#!/bin/bash
#
# AgentGarden bridge hook for Claude Code.
#
# One script wired to several Claude Code hook events. It reads the hook's
# JSON payload on stdin, figures out which event fired, and reports it to the
# local GardenServer so the Dynamic Island and the phone dashboard light up.
#
# It also implements the remote-approval flow: when PreToolUse fires *and*
# remote approval is armed (~/.agent-garden-remote-approval exists), it asks
# the phone to allow/deny and blocks until you answer (or it times out and
# falls back to the normal terminal prompt).
#
# Dependencies: curl + jq (both ship at /usr/bin on macOS).
#
# Never let a hook failure disturb the agent: every network call is capped
# with --max-time and the script always exits 0 unless it is deliberately
# denying a tool. If the Mac app is not running, calls fail fast and the
# session behaves exactly as if this hook were absent.

set -u

GARDEN_URL="${GARDEN_URL:-http://127.0.0.1:4141}"
# Armed = gate non-read-only tools for allow/deny (from the phone OR the
# terminal — see PreToolUse). Away = additionally park a finished turn to wait
# for a prompt from the phone. Keeping them separate means that while you are AT
# the laptop (armed but not away) a finished turn ends immediately, so you can
# just type your reply — no ESC to break out of a park.
ARM_MARKER="$HOME/.agent-garden-remote-approval"
AWAY_MARKER="$HOME/.agent-garden-away"

# Shared token the app mints in ~/.agent-garden-token; sent on every call so
# the server accepts us. Empty (app never ran) just means calls 401 and the
# session degrades exactly as if the app were down.
TOKEN="$(cat "$HOME/.agent-garden-token" 2>/dev/null)"
AUTH=(-H "Authorization: Bearer ${TOKEN}")

# Tools that never need remote approval — read-only, no side effects.
# Everything else is gated to the phone while remote approval is armed.
READONLY_TOOLS="Read Grep Glob LS NotebookRead TodoWrite WebFetch WebSearch Task"

# How long to wait for a decision from the phone before giving up and letting
# the terminal prompt take over. Keep this under the hook `timeout` in
# settings.json (we ship 300s there, poll for ~280s here).
APPROVAL_TIMEOUT="${GARDEN_APPROVAL_TIMEOUT:-280}"
# While armed, how long a finished turn parks waiting for a prompt from the
# phone before it gives up and lets the session stop. Keep under the Stop hook
# `timeout` in settings.json (we ship 300s there).
PROMPT_TIMEOUT="${GARDEN_PROMPT_TIMEOUT:-280}"
POLL_INTERVAL="${GARDEN_POLL_INTERVAL:-2}"

payload="$(cat)"

jqget() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

event_name="$(jqget '.hook_event_name')"
cwd="$(jqget '.cwd')"
[ -z "$cwd" ] && cwd="$PWD"

# One garden plot per project directory.
agent="$(basename "$cwd")"
[ -z "$agent" ] && agent="agent"

# POST a garden event; never blocks the agent for more than a moment.
post_event() {
  local body="$1"
  curl -s --max-time 3 "${AUTH[@]}" -X POST "$GARDEN_URL/event" \
    -H 'Content-Type: application/json' \
    -d "$body" >/dev/null 2>&1 || true
}

emit() { # emit <event> [extra-json-fields]
  local event="$1"; local extra="${2:-}"
  local body
  body="$(jq -nc --arg agent "$agent" --arg event "$event" \
    '{agent:$agent, event:$event}')"
  if [ -n "$extra" ]; then
    body="$(printf '%s' "$body" | jq -c ". + $extra")"
  fi
  post_event "$body"
}

case "$event_name" in
  SessionStart)
    emit start
    ;;

  UserPromptSubmit)
    prompt="$(jqget '.prompt')"
    task="$(printf '%s' "$prompt" | tr '\n' ' ' | cut -c1-80)"
    emit resume "$(jq -nc --arg t "$task" '{task:$t}')"
    ;;

  PostToolUse)
    tool="$(jqget '.tool_name')"
    emit tool "$(jq -nc --arg t "$tool" '{tool:$t}')"
    ;;

  Notification)
    emit attention
    ;;

  Stop)
    # Only park when AWAY. Parking holds a finished turn open (up to
    # PROMPT_TIMEOUT) polling the phone for a prompt, so you can keep steering
    # the agent from your phone after you have left the desk. While you are at
    # the laptop (armed but not away) we never park — the turn ends at once so
    # you can just type your reply. A queued prompt is fed back via the Stop
    # hook's block+reason, which makes Claude Code continue instead of stopping.
    if [ -f "$AWAY_MARKER" ]; then
      enc_agent="$(printf '%s' "$agent" | jq -sRr @uri)"
      emit attention
      waited=0
      while [ "$waited" -lt "$PROMPT_TIMEOUT" ]; do
        [ -f "$AWAY_MARKER" ] || break   # coming back (rm away) releases the turn
        p="$(curl -s --max-time 3 "${AUTH[@]}" "$GARDEN_URL/prompt/$enc_agent" 2>/dev/null | jq -r '.prompt // empty' 2>/dev/null)"
        if [ -n "$p" ]; then
          task="$(printf '%s' "$p" | tr '\n' ' ' | cut -c1-80)"
          emit resume "$(jq -nc --arg t "$task" '{task:$t}')"
          jq -nc --arg r "$p" '{decision:"block", reason:$r}'
          exit 0
        fi
        sleep "$POLL_INTERVAL"
        waited=$((waited + POLL_INTERVAL))
      done
    fi
    emit done
    ;;

  PreToolUse)
    # Approval flow only matters when armed; otherwise behave transparently.
    [ -f "$ARM_MARKER" ] || exit 0

    tool="$(jqget '.tool_name')"
    for ro in $READONLY_TOOLS; do
      [ "$tool" = "$ro" ] && exit 0
    done

    # Human-readable detail for the phone card.
    case "$tool" in
      Bash)        detail="$(jqget '.tool_input.command')" ;;
      Edit|Write|MultiEdit|NotebookEdit)
                   detail="$(jqget '.tool_input.file_path')" ;;
      *)           detail="$(printf '%s' "$payload" | jq -c '.tool_input // {}' 2>/dev/null)" ;;
    esac
    [ -z "$detail" ] && detail="$tool"

    id="$(uuidgen)"
    req="$(jq -nc --arg id "$id" --arg agent "$agent" --arg tool "$tool" --arg detail "$detail" \
      '{id:$id, agent:$agent, tool:$tool, detail:$detail}')"
    if ! curl -sf --max-time 3 "${AUTH[@]}" -X POST "$GARDEN_URL/approval/request" \
        -H 'Content-Type: application/json' -d "$req" >/dev/null 2>&1; then
      # App unreachable or rejected us (401) — fall back to the terminal prompt.
      exit 0
    fi

    # Decide from EITHER side, whichever answers first: press y/n at the laptop,
    # or tap allow/deny on the phone card. The terminal prompt (fd 9 -> /dev/tty)
    # is written/read directly so it never touches stdout, which must carry only
    # the hook's JSON decision. No controlling TTY (headless) -> phone-only, as
    # before. The keystroke is meant to be consumed here, so bash 3.2's
    # `read -t <n> -n1` is exactly right.
    emit_decision() { # emit_decision allow|deny  reason
      emit resume
      jq -nc --arg d "$1" --arg why "$2" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$why}}'
      exit 0
    }

    have_tty=0
    # Group-wrap so a failed open (headless / no controlling TTY) is silenced —
    # a bare `exec 9<>/dev/tty 2>/dev/null` still leaks the error to stderr.
    if { exec 9<>/dev/tty; } 2>/dev/null; then
      have_tty=1
      printf '\n🌱 AgentGarden: allow %s (%s)?  [y]es / [n]o  — or decide on phone\n' \
        "$tool" "$detail" >&9
    fi

    waited=0
    while [ "$waited" -lt "$APPROVAL_TIMEOUT" ]; do
      # Phone side.
      resp="$(curl -s --max-time 3 "${AUTH[@]}" "$GARDEN_URL/approval/$id" 2>/dev/null)"
      case "$(printf '%s' "$resp" | jq -r '.decision // empty' 2>/dev/null)" in
        allow) emit_decision allow "Approved from phone (AgentGarden)" ;;
        deny)  emit_decision deny  "Denied from phone (AgentGarden)" ;;
      esac
      # Laptop side — one keypress, also paces the loop (times out after POLL).
      if [ "$have_tty" = 1 ]; then
        if read -t "$POLL_INTERVAL" -n1 -u 9 -r key 2>/dev/null; then
          case "$key" in
            y|Y|a|A) emit_decision allow "Approved from terminal (AgentGarden)" ;;
            n|N|d|D) emit_decision deny  "Denied from terminal (AgentGarden)" ;;
          esac
        fi
      else
        sleep "$POLL_INTERVAL"
      fi
      waited=$((waited + POLL_INTERVAL))
    done

    # Timed out — hand control back to the terminal prompt.
    emit resume
    exit 0
    ;;

  *)
    ;;
esac

exit 0
