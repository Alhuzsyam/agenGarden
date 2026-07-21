#!/bin/bash
#
# AgentGarden tmux bridge — the piece that makes the phone a real remote
# terminal. It runs alongside a Claude Code session living in a tmux pane and,
# on a ~1s loop:
#
#   1. captures the pane and POSTs it to /terminal so the phone can SEE the
#      screen (including "Do you want to proceed? 1.Yes 2.No" menus);
#   2. drains /keys and replays each keystroke into the pane with
#      `tmux send-keys`, so typing / choosing on the phone lands in the session.
#
# Usage:
#   GARDEN_AGENT=<name> GARDEN_TMUX=<session-or-pane> agent-garden-tmux-bridge.sh
#
# Normally you don't call this directly — `garden-claude.sh` sets it up. It
# exits automatically when the tmux target goes away.
#
# Dependencies: tmux + curl + jq.

set -u

GARDEN_URL="${GARDEN_URL:-http://127.0.0.1:4141}"
AGENT="${GARDEN_AGENT:-$(basename "$PWD")}"
TARGET="${GARDEN_TMUX:?set GARDEN_TMUX to the tmux session/pane}"
INTERVAL="${GARDEN_BRIDGE_INTERVAL:-1}"

TOKEN="$(cat "$HOME/.agent-garden-token" 2>/dev/null)"
AUTH=(-H "Authorization: Bearer ${TOKEN}")
enc_agent="$(printf '%s' "$AGENT" | jq -sRr @uri)"

# tmux key names we pass through as-is; everything else is typed literally.
is_named_key() {
  case "$1" in
    Enter|Escape|Up|Down|Left|Right|Tab|BTab|Space|BSpace|Home|End|PageUp|PageDown|Delete|Insert|C-*|M-*|F[0-9]*)
      return 0 ;;
    *) return 1 ;;
  esac
}

send_key() {
  if is_named_key "$1"; then
    tmux send-keys -t "$TARGET" "$1"
  else
    tmux send-keys -t "$TARGET" -l "$1"   # -l = literal, type the characters
  fi
}

while true; do
  tmux has-session -t "$TARGET" 2>/dev/null || { echo "bridge: tmux target gone, exiting"; break; }

  # 1) mirror the pane up to the server
  screen="$(tmux capture-pane -p -t "$TARGET" 2>/dev/null)"
  if [ -n "$screen" ]; then
    body="$(jq -nc --arg a "$AGENT" --arg s "$screen" '{agent:$a, screen:$s}')"
    curl -s --max-time 3 "${AUTH[@]}" -X POST "$GARDEN_URL/terminal" \
      -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 || true
  fi

  # 2) replay any keys queued from the phone
  keys_json="$(curl -s --max-time 3 "${AUTH[@]}" "$GARDEN_URL/keys/$enc_agent" 2>/dev/null)"
  count="$(printf '%s' "$keys_json" | jq '.keys | length' 2>/dev/null || echo 0)"
  if [ "${count:-0}" -gt 0 ]; then
    for i in $(seq 0 $((count - 1))); do
      key="$(printf '%s' "$keys_json" | jq -r ".keys[$i]" 2>/dev/null)"
      [ -n "$key" ] && send_key "$key"
    done
  fi

  sleep "$INTERVAL"
done
