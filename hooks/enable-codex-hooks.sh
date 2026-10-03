#!/usr/bin/env bash
# Serel Memory enable-codex-hooks
#
# Registers Serel Memory's Codex SessionStart hook in .codex/hooks.json.
# Re-run this any time - it's idempotent.
#
# To disable, remove the Serel Memory entry from .codex/hooks.json.

set -euo pipefail

SETTINGS=".codex/hooks.json"
mkdir -p .codex

SESSION_START_CMD="cd \"\$(git rev-parse --show-toplevel)\" && bash hooks/session-start.sh"

if command -v jq >/dev/null 2>&1; then
  if [ ! -f "$SETTINGS" ]; then
    echo '{"hooks":{}}' > "$SETTINGS"
  fi

  tmp=$(mktemp)
  jq \
    --arg ss_cmd "$SESSION_START_CMD" \
    '
      .hooks = (.hooks // {})
      | .hooks.SessionStart = (.hooks.SessionStart // [])
      | if any(.hooks.SessionStart[]?.hooks[]?; .command == $ss_cmd) then .
        else .hooks.SessionStart += [{
          matcher: "startup|resume",
          hooks: [{
            type: "command",
            command: $ss_cmd,
            statusMessage: "Loading Serel Memory bank"
          }]
        }]
        end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  chmod +x hooks/session-start.sh 2>/dev/null || true

  echo "Serel Memory Codex hook registered in $SETTINGS"
  echo "  SessionStart -> $SESSION_START_CMD"
  echo ""
  echo "Open /hooks in Codex to review and trust the project hook."
else
  echo "jq is not installed. Either install it and re-run, or add this to $SETTINGS manually:"
  echo ""
  cat <<JSON
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "$SESSION_START_CMD",
            "statusMessage": "Loading Serel Memory bank"
          }
        ]
      }
    ]
  }
}
JSON
  exit 1
fi
