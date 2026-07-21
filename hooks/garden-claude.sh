#!/bin/bash
#
# Launch a Claude Code session that the phone can drive. Creates (or reattaches
# to) a tmux session, starts the AgentGarden tmux bridge for it, then attaches.
#
#   garden-claude.sh [name]     # name defaults to the current directory
#
# From the phone you then see the live terminal and can type / answer prompts.

set -u

NAME="${1:-$(basename "$PWD")}"
SESSION="garden_$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9_' '_')"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Reattaching to $SESSION…"
  exec tmux attach -t "$SESSION"
fi

# Fixed pane size so the phone mirror is stable regardless of your window.
tmux new-session -d -s "$SESSION" -x 120 -y 40 "claude"

GARDEN_AGENT="$NAME" GARDEN_TMUX="$SESSION" \
  nohup "$SCRIPT_DIR/agent-garden-tmux-bridge.sh" \
  >"/tmp/garden-bridge-$SESSION.log" 2>&1 &

echo "Started $SESSION with phone bridge (agent: $NAME). Attaching…"
exec tmux attach -t "$SESSION"
