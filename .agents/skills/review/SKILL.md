---
name: review
description: "Review the current branch, diff, or proposed change in Codex. Use when the user asks for a code review, branch review, diff review, or quality/risk pass."
---

# Review

Use this skill to review code or a proposed change. Take a code-review stance: findings first, grounded in file and line references when possible. Do not edit files.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Read relevant project context:
   - `memory-bank/projectbrief.md`
   - `memory-bank/systemPatterns.md`
   - `memory-bank/techContext.md`
   - `memory-bank/decisionLog.md`
   - `memory-bank/activeContext.md`
   - `.rules`
2. Inspect the change:
   - Prefer `git diff main...HEAD` for branch changes.
   - Use `git diff` for uncommitted changes.
   - If `main` does not exist, find the likely base branch or state the fallback.
3. Launch the cross-agent pass in the background if it qualifies (see below) — before drafting any findings of your own.
4. Read modified files in full when the diff alone is not enough.
5. Check at minimum:
   - Correctness and edge cases
   - Tests for new behavior
   - Naming and clarity
   - Error handling
   - Side effects and leftover debug code
   - Scope discipline — does every changed line trace to the task; any drive-by refactors or unrequested deletions
   - Simplicity — overcomplication, speculative abstractions, or config that was not requested
   - Security and secret leakage
   - Performance pitfalls
   - Alignment with memory-bank intent and decisions

## Cross-agent pass (opportunistic)

The diff under review is often authored by the same model now reviewing it — a
single-model review grades its own homework. If `claude --version` succeeds and
the diff is non-trivial (≥ 20 changed lines), get an independent Claude review
of the same diff, merged with provenance:

1. Right after computing the diff (step 2), write a prompt file containing:
   - the diff range (e.g. `git diff main...HEAD`)
   - the review checklist above (step 5, including memory-bank alignment)
   - the findings format — without the provenance tags or the dual/single-model
     label line; you add those at merge
   - a read-only instruction: do not edit files or run write operations

   **Not your own findings** — Claude must review blind, or it will anchor on
   your framing. Launch it in the background, capturing output to a file
   (`docs/cross-agent-review.md` has the canonical background form; prefer
   your harness's background facility over bare `&` if it has one):

   ```bash
   claude -p --permission-mode plan < "$PROMPT_FILE" > "$OUT_FILE" 2>&1 &
   ```

2. Do your own full review and **draft your own findings before reading
   Claude's output** — independence matters more than speed.
3. After your draft is done, wait up to ~90 seconds for Claude. If it hasn't
   returned, proceed single-model and say so.
4. Merge: tag every finding `[both]`, `[codex]`, or `[claude]`. Verify
   `[claude]`-only findings against the actual code before including them —
   drop what you can't confirm and note it under QUESTIONS instead. Then add one `DISAGREEMENTS:` line per explicit contradiction (one model says X, the other says not-X); silence from a model is not disagreement. Agreement is confidence, not priority — a single verified correctness or security finding outranks two matching style notes.

This pass never blocks the review: if Claude is missing, slow, or the diff is
trivial, complete single-model and label the SUMMARY accordingly.

## Output

```text
SUMMARY: [one sentence - what changed and overall take]
[dual-model review (Codex + Claude) | single-model review (reason: Claude unavailable / timed out / trivial diff)]

HIGH (must fix before merge):
- [both|codex|claude] [file:line] [issue] -> [suggested fix]

MEDIUM (should fix before merge):
- [both|codex|claude] [file:line] [issue] -> [suggested fix]

LOW (nice to have):
- [both|codex|claude] [file:line] [issue] -> [suggested fix]

QUESTIONS:
- [anything you could not determine from code]
```

Omit the provenance tags when the review was single-model.

If there are no findings, say so clearly and mention any remaining test gaps or residual risk.
