#!/usr/bin/env bash
# Serel Memory enable-hooks
#
# Registers Serel Memory's SessionStart and PreCompact hooks in .claude/settings.json.
# Re-run this any time — it's idempotent (won't double-register).
#
# To disable, either:
#   - export SEREL_MEMORY_HOOKS=off  (temporary, current session only)
#   - remove the entries from .claude/settings.json  (permanent)

set -euo pipefail

SETTINGS=".claude/settings.json"
mkdir -p .claude

SESSION_START_CMD="bash hooks/session-start.sh"
PRE_COMPACT_CMD="bash hooks/pre-compact.sh"

# Prefer jq for safe JSON manipulation
if command -v jq >/dev/null 2>&1; then
  # Initialize settings.json if it doesn't exist
  if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
  fi

  tmp=$(mktemp)
  jq \
    --arg ss_cmd "$SESSION_START_CMD" \
    --arg pc_cmd "$PRE_COMPACT_CMD" \
    '
      .hooks = (.hooks // {})
      | .hooks.SessionStart = (.hooks.SessionStart // [])
      | .hooks.PreCompact   = (.hooks.PreCompact // [])
      | if any(.hooks.SessionStart[]?.hooks[]?; .command == $ss_cmd) then .
        else .hooks.SessionStart += [{matcher: "", hooks: [{type: "command", command: $ss_cmd}]}]
        end
      | if any(.hooks.PreCompact[]?.hooks[]?; .command == $pc_cmd) then .
        else .hooks.PreCompact += [{matcher: "", hooks: [{type: "command", command: $pc_cmd}]}]
        end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  # Make hook scripts executable
  chmod +x hooks/session-start.sh hooks/pre-compact.sh 2>/dev/null || true

  echo "✓ Serel Memory hooks registered in $SETTINGS"
  echo "  SessionStart → $SESSION_START_CMD"
  echo "  PreCompact   → $PRE_COMPACT_CMD"
  echo ""
  echo "  To disable temporarily: export SEREL_MEMORY_HOOKS=off"
  echo "  To disable permanently: remove the entries from $SETTINGS"
else
  echo "jq is not installed. Either install it (brew install jq) and re-run,"
  echo "or add the following to $SETTINGS manually:"
  echo ""
  cat <<JSON
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$SESSION_START_CMD" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$PRE_COMPACT_CMD" }
        ]
      }
    ]
  }
}
JSON
  exit 1
fi
