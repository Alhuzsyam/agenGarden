#!/usr/bin/env bash
# Spawn a *detached* Claude Code session + phone bridge for a new project, so the
# GardenServer can start agents remotely (POST /new-project). Unlike
# garden-claude.sh this never `exec`s `tmux attach` — it just creates the session
# and the mirror, then prints the tmux session name and returns.
#
#   garden-spawn.sh <name> [dir]
#
# <name>  becomes the agent id shown in the dashboard/watch.
# [dir]   working directory for the session (default: ~/<name>, created if new).
set -u

NAME="${1:?usage: garden-spawn.sh <name> [dir]}"
DIR="${2:-$HOME/$NAME}"
mkdir -p "$DIR" 2>/dev/null || true

SESSION="garden_$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9_' '_')"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Already running? Just report it — the bridge is still attached.
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "$SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" -x 120 -y 40 -c "$DIR" "claude"

GARDEN_AGENT="$NAME" GARDEN_TMUX="$SESSION" \
  nohup "$SCRIPT_DIR/agent-garden-tmux-bridge.sh" \
  >"/tmp/garden-bridge-$SESSION.log" 2>&1 &

echo "$SESSION"
