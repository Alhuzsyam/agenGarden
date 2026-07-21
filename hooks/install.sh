#!/bin/bash
#
# One-shot AgentGarden setup:
#   - checks required tools (curl, jq, tmux)
#   - adds a `garden` alias to your shell rc (idempotent)
#   - reminds you to merge the hooks into ~/.claude/settings.json
#
#   hooks/install.sh
#
# Safe to re-run: the alias is only appended if it isn't already present.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$SCRIPT_DIR/garden-claude.sh"
ALIAS_LINE="alias garden='$LAUNCHER'"

echo "AgentGarden install"
echo "  repo: $SCRIPT_DIR"
echo

# 1. Dependency check ---------------------------------------------------------
missing=""
for tool in curl jq tmux; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "⚠ Missing tools:$missing"
  echo "  Install with: brew install$missing"
  echo
fi

# 2. Alias (idempotent) -------------------------------------------------------
# Pick the rc file for the user's current login shell.
case "${SHELL##*/}" in
  zsh)  RC="$HOME/.zshrc" ;;
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="$HOME/.zshrc" ;;   # sensible default on macOS
esac

if [ -f "$RC" ] && grep -qxF "$ALIAS_LINE" "$RC"; then
  echo "✓ garden alias already in $RC (unchanged)"
else
  if [ -f "$RC" ] && grep -qE "^alias garden=" "$RC"; then
    # A garden alias exists but points elsewhere (repo moved?). Drop the stale
    # line (and our comment) so we don't leave duplicates, then re-add.
    tmp="$(mktemp)"
    grep -vE "^alias garden=|^# AgentGarden — launch a phone-drivable Claude session$" \
      "$RC" > "$tmp" && cat "$tmp" > "$RC"
    rm -f "$tmp"
    echo "✓ Replaced stale garden alias in $RC"
  else
    echo "✓ Added garden alias to $RC"
  fi
  printf '\n# AgentGarden — launch a phone-drivable Claude session\n%s\n' \
    "$ALIAS_LINE" >> "$RC"
  echo "  Run:  source $RC   (or open a new terminal)"
fi
echo

# 3. Hooks reminder -----------------------------------------------------------
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "agent-garden-hook.sh" "$SETTINGS"; then
  echo "✓ Hooks already wired in $SETTINGS"
else
  echo "→ Next: merge $SCRIPT_DIR/settings-snippet.json's \"hooks\" block"
  echo "  into $SETTINGS (global, so every project reports)."
fi
echo
echo "Done. Start a phone-drivable session anywhere with:  garden [name]"
