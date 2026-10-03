---
description: Review the current branch or uncommitted diff
---

# /review

Review the code currently on this branch (or the uncommitted diff if there's nothing branch-specific). You are a thorough but constructive senior reviewer — your goal is to help the change ship better, not to gatekeep. Take a read-only stance: **do not edit files** during a review.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Steps:

1. Read relevant project context: `memory-bank/projectbrief.md`, `systemPatterns.md`, `techContext.md`, `decisionLog.md`, `activeContext.md`, and `.rules`.
2. Run `git diff main...HEAD` (or `git diff` for uncommitted changes) to see what changed. If `main` doesn't exist, find the likely base branch or state the fallback.
3. Launch the cross-agent pass in the background if it qualifies (see below) — before drafting any findings of your own.
4. Read modified files in full when context matters — not just the diff.
5. Check the change against the memory bank: does it match `projectbrief.md` goals, `systemPatterns.md` architecture, and `decisionLog.md` decisions?

## Cross-agent pass (opportunistic)

The diff under review is often authored by the same model now reviewing it — a
single-model review grades its own homework. If `codex --version` succeeds and
the diff is non-trivial (≥ 20 changed lines), get an independent Codex review
of the same diff, merged with provenance:

1. Right after computing the diff (step 2), write a prompt file containing:
   - the diff range (e.g. `git diff main...HEAD`)
   - the review checklist below, plus the memory-bank alignment check from step 5
   - the findings format — without the provenance tags or the dual/single-model
     label line; you add those at merge
   - a read-only instruction: do not edit files or run write operations

   **Not your own findings** — Codex must review blind, or it will anchor on
   your framing. Launch it in the background, capturing output to a file
   (`docs/cross-agent-review.md` has the canonical background form; prefer
   your harness's background facility over bare `&` if it has one):

   ```bash
   codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE" > "$OUT_FILE" 2>&1 &
   ```

2. Do your own full review and **draft your own findings before reading
   Codex's output** — independence matters more than speed.
3. After your draft is done, wait up to ~90 seconds for Codex. If it hasn't
   returned, proceed single-model and say so.
4. Merge: tag every finding `[both]`, `[claude]`, or `[codex]`. Verify
   `[codex]`-only findings against the actual code before including them —
   drop what you can't confirm and note it under QUESTIONS instead. Then add one `DISAGREEMENTS:` line per explicit contradiction (one model says X, the other says not-X); silence from a model is not disagreement. Agreement is confidence, not priority — a single verified correctness or security finding outranks two matching style notes.

This pass never blocks the review: if Codex is missing, slow, or the diff is
trivial, complete single-model and label the SUMMARY accordingly.

Then produce findings in this exact format:

```text
SUMMARY: [one sentence — what this change does and your overall take]
[dual-model review (Claude + Codex) | single-model review (reason: Codex unavailable / timed out / trivial diff)]

HIGH (must fix before merge):
- [both|claude|codex] [file:line] [issue] → [suggested fix]

MEDIUM (should fix before merge):
- [both|claude|codex] [file:line] [issue] → [suggested fix]

LOW (nice to have):
- [both|claude|codex] [file:line] [issue] → [suggested fix]

QUESTIONS:
- [anything you couldn't determine from the code]
```

Omit the provenance tags when the review was single-model.

At minimum, check for:

- **Correctness** — does it do what the diff/commit claims?
- **Tests** — do tests exist for new behavior; are edge cases covered?
- **Naming & clarity** — are names accurate; could a new reader follow this?
- **Error handling** — are failure paths handled or documented?
- **Side effects** — unintended changes, leftover `console.log` / debug prints?
- **Scope discipline** — does every changed line trace to the task? Any drive-by refactors, reformatting, or deletion of code the change didn't require?
- **Simplicity** — overcomplication, speculative abstractions, unrequested config/flexibility, or error handling for impossible cases? Could it be substantially smaller?
- **Security** — input validation, secrets in code, auth bypasses?
- **Performance** — obvious O(n²), N+1, or unbounded growth?

Always include a SUMMARY line, even if there are no HIGH findings. If everything looks good, say so clearly — false positives waste trust.
