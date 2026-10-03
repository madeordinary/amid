#!/usr/bin/env bash
# Serel Memory PreCompact hook
#
# Fires before Claude Code compacts session context. Reminds the agent to
# update the memory bank so this session's work isn't lost when older context
# is summarized away.
#
# To disable temporarily: export SEREL_MEMORY_HOOKS=off
# To disable permanently: remove from .claude/settings.json

set -euo pipefail

if [ "${SEREL_MEMORY_HOOKS:-}" = "off" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# If Serel Memory isn't installed here, do nothing
if [ ! -d "$ROOT/memory-bank" ] && [ ! -d "$ROOT/memory-bank.local" ]; then
  exit 0
fi

# Scoped banks (opt-in): resolve by cwd through the shared resolver so the
# reminder names the right bank. Single-bank repos print nothing extra.
LIB="$(dirname "${BASH_SOURCE[0]}")/lib/resolve-scope.sh"
SCOPE_NOTE=""
RESOLVER_WARNINGS="$(bash "$LIB" --root "$ROOT" --cwd "$PWD" 2>&1 >/dev/null || true)"
if [ "$(bash "$LIB" --root "$ROOT" --list 2>/dev/null || echo "SCOPES: none")" != "SCOPES: none" ]; then
  IFS=$'\t' read -r SCOPE_ROOT BANK_REL RULES_WRITE _ _ _ < <(bash "$LIB" --root "$ROOT" --cwd "$PWD" 2>/dev/null)
  SCOPE_NOTE="Scope resolved by cwd: \`$SCOPE_ROOT\` — effective bank \`$BANK_REL\`, rules \`$RULES_WRITE\`. Apply the updates there. To target another bank, run \`/update-memory --scope <path>\` explicitly — a scope chosen earlier in the session is never remembered."
fi

cat <<'EOF'
## Serel Memory: pre-compact memory bank refresh

Context is about to be compacted. Earlier conversation history will be summarized
and details may be lost. Before that happens, refresh the memory bank so this
session's work is preserved:

Note: if `memory-bank.local/` exists (upstream Serel Memory development), it is the
effective bank — apply all of the updates below to `memory-bank.local/` and its
`.rules`, never to the tracked starter templates.

1. Update `memory-bank/activeContext.md` to reflect:
   - Current focus
   - Recent changes (top of the list, most recent first)
   - Next steps
   - If multi-session work is underway, the `## Checkpoint` section — one
     resumable state (branch and HEAD, what is uncommitted, what is
     verified, first action on resume), overwritten in place. Do not
     commit a `wip:` on compaction (contract "Clean stop").
   - Any new open questions

2. Update `memory-bank/progress.md`:
   - Move items from "in progress" to "what works" if they shipped
   - Add new known issues
   - Update the phase if it changed

3. Update `memory-bank/decisionLog.md` if a durable architectural, product,
   workflow, or operational decision was made.

4. If anything non-obvious was learned this session — a user preference, a
   gotcha, a rejected approach worth remembering — append it to `.rules`.

5. Apply the update-memory retention step: run
   `hooks/lib/rotate-check.sh` on the proposed `activeContext.md` and
   `progress.md`, and include any `ROTATE n` archive moves in the same diffs
   (see `docs/workflow-contract.md` "Retention"). Skip `memory-bank/archive/`
   when reading.

Show the diffs to the user and ask for confirmation before writing. Then proceed
with the compaction.
EOF
if [ -n "$RESOLVER_WARNINGS" ]; then
  echo ""
  echo "Serel Memory notice: $RESOLVER_WARNINGS"
fi
if [ -n "$SCOPE_NOTE" ]; then
  echo ""
  echo "$SCOPE_NOTE"
fi
