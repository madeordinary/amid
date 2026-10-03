---
description: Break a task into steps before executing
---

# /breakdown

For the task the user just described, do NOT take any action yet. Produce a plan first.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

First, read for project intent so the plan is grounded, not guessed:

- The relevant `memory-bank/` files (`projectbrief.md`, `productContext.md`, `systemPatterns.md`, `techContext.md`, `decisionLog.md`, `activeContext.md`, `progress.md`) and `.rules`.
- Only the source files you need to make the plan concrete.

Then produce a plan that contains, in this order:

1. **Goal** — one sentence; what success looks like.
2. **Scope** — which files, components, or areas you'll touch. Be specific (paths, function names).
3. **Steps** — 3–7 concrete steps, each starting with a verb (add, refactor, test, document, deploy) and ending with `→ verify: [how you'll know it worked]`. Reframe imperative steps as verifiable goals — "add validation" becomes "write tests for invalid inputs, then make them pass".
4. **Risks & unknowns** — what could go wrong, what you'd need to verify first, what assumptions you're making.
5. **Out of scope** — things you'll deliberately NOT do, in case the user wants them too.

## Cross-agent review (recommended for high-impact plans)

For high-impact or hard-to-reverse plans (architecture, security/auth, data migrations, public API or schema, dependency choices), get a Codex second opinion before presenting to the user. For routine changes it's optional — use judgment.

1. Check whether Codex is available: `codex --version`
2. If it is, build a concise prompt with the plan, the goal, and enough project context for a meaningful review, asking it to end with a one-line verdict (`VERDICT: APPROVE | REVISE | RETHINK`, pick exactly one), then run Codex in read-only mode. Write the prompt to a temp file and pipe it — long inline prompts can hang `codex exec` — in a single shell invocation (shell state doesn't survive across tool calls):

   ```bash
   PROMPT_FILE="$(mktemp)"
   cat > "$PROMPT_FILE" <<'EOF'
   ...the full prompt...
   EOF
   codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE"
   rm -f "$PROMPT_FILE"
   ```

3. Append a **Second Opinion (Codex)** section to the plan output:
   - Verdict (APPROVE / REVISE / RETHINK)
   - Agreements
   - Disagreements or gaps
   - Suggested changes worth adopting
   - Questions to resolve before proceeding

If `codex` is not installed or not authenticated, don't block — perform a local self-critique instead and label it **Self-Critique (Codex unavailable)** so the user knows no independent review happened. Never pretend Codex reviewed it.

Then end with: **"Want me to proceed, or change something first?"**

Wait. Do not start executing until the user confirms.

Rules:

- If the plan is longer than 7 steps, the task is too big — recommend splitting it.
- If you have to assume something material, say so explicitly. Don't bury assumptions inside step descriptions.
- If the request has more than one reasonable interpretation, lay them out and ask which one — don't silently pick.
- If the memory bank, including `decisionLog.md`, doesn't have enough context for the plan, say what's missing and ask before guessing.
