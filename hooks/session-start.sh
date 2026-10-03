#!/usr/bin/env bash
# Serel Memory SessionStart hook
#
# Auto-loads the memory bank as session context so you don't need to type /start.
# Registered via hooks/enable-hooks.sh. Off by default.
#
# To disable temporarily for one session: export SEREL_MEMORY_HOOKS=off
# To disable permanently: remove the entries from .claude/settings.json

set -euo pipefail

# Honor the kill switch.
if [ "${SEREL_MEMORY_HOOKS:-}" = "off" ]; then
  exit 0
fi

# Anchor to the project root (where this hook was registered)
# Claude Code runs hooks from the project root, but be defensive.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Bail quietly if there's no memory bank — Serel Memory isn't installed here
if [ ! -d "$ROOT/memory-bank" ] && [ ! -d "$ROOT/memory-bank.local" ]; then
  exit 0
fi

# Resolve the effective bank through the shared resolver (maintainer overlay
# aware). SessionStart runs from the repo root, so it always loads the ROOT
# scope — the documented exception in docs/workflow-contract.md "Resolving
# scope". Project banks (if the repo configures "scopes") are only listed.
LIB="$(dirname "${BASH_SOURCE[0]}")/lib/resolve-scope.sh"
RESOLVER_WARNINGS="$(bash "$LIB" --root "$ROOT" --scope . 2>&1 >/dev/null || true)"
IFS=$'\t' read -r _ BANK_REL _ RULES_REL _ _ < <(bash "$LIB" --root "$ROOT" --scope . 2>/dev/null)
BANK_DIR="$ROOT/$BANK_REL"
BANK_LABEL="$BANK_REL"
RULES_FILE=""
RULES_LABEL=""
if [ "$RULES_REL" != "-" ]; then
  RULES_FILE="$ROOT/$RULES_REL"
  RULES_LABEL="$RULES_REL"
fi

cat <<'HEADER'
## Project context (auto-loaded by Serel Memory)

You are starting a session on a project using the Serel Memory bank pattern.
The contents below were read automatically at session start. Treat the memory
bank as the source of truth for project intent. If it conflicts with the actual
code, the code is correct and the bank needs updating — flag this to the user.

HEADER

for f in projectbrief productContext systemPatterns techContext decisionLog activeContext progress; do
  file="$BANK_DIR/$f.md"
  if [ -f "$file" ]; then
    echo "### $BANK_LABEL/$f.md"
    echo ""
    cat "$file"
    echo ""
    echo ""
  fi
done

if [ -n "$RULES_FILE" ] && [ -f "$RULES_FILE" ]; then
  echo "### $RULES_LABEL"
  echo ""
  cat "$RULES_FILE"
  echo ""
fi

# Scoped banks (opt-in): list project banks by selector only. Nothing from a
# project bank is read here — one bank per invocation.
SCOPE_LIST="$(bash "$LIB" --root "$ROOT" --list 2>/dev/null || echo "SCOPES: none")"
if [ -n "$RESOLVER_WARNINGS" ]; then
  echo "### Serel Memory notice"
  echo ""
  printf '%s\n' "$RESOLVER_WARNINGS"
  echo ""
fi
if [ "$SCOPE_LIST" != "SCOPES: none" ]; then
  echo "### Scopes (project banks in this repo)"
  echo ""
  echo "Only the ROOT bank above was loaded. Each project below has its own bank;"
  echo "select one with \`--scope <path>\` (for example \`/start --scope <path>\`)."
  echo "Nothing from these banks was read."
  echo ""
  printf '%s\n' "$SCOPE_LIST" | awk -F'\t' '$1=="P"{printf "- --scope %s [%s]\n", $2, $3}'
  echo ""
fi

# Recent git activity, best-effort
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "### Recent activity"
  echo ""
  echo "Last 10 commits:"
  git -C "$ROOT" log --oneline -10 2>/dev/null || true
  echo ""
  echo "Working tree:"
  status=$(git -C "$ROOT" status --short 2>/dev/null | head -20)
  if [ -n "$status" ]; then
    echo "$status"
  else
    echo "(clean)"
  fi
  echo ""
fi

echo "---"
echo ""
echo "End of auto-loaded context. Continue with the user's request."
