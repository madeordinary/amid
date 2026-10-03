---
name: update-memory
description: "Refresh memory-bank files after a work session. Use when the user asks to update memory, preserve session context, refresh activeContext/progress, or capture new project learnings."
---

# Update Memory

Use this skill to update the memory bank from the current session. Always show proposed diffs before writing.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), all reads and writes below target it and its `.rules` — never the tracked starter templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Read the seven core files in the effective bank, its `.rules`, and the
   contract's **Memory accuracy** section. Read optional docs only for relevant
   subjects; skip `archive/` unless this task needs that history.
2. **Capture and reconcile (required).** Follow both passes in "Memory accuracy":
   compare session decisions and observed results with relevant git history,
   staged/unstaged changes, and new files for missing durable information;
   search the live bank and its rules for old claims about changed subjects.
   Reconcile current status, next steps, and blockers together. Preserve dated
   history and accepted intent; flag possible regressions and missing evidence.
   Before the diffs, summarize **Captured**, **Reconciled**, and **Unresolved**
   with evidence/locations and the bounds of what was checked.
3. Propose updates, focusing on:
   - `memory-bank/activeContext.md` - current focus, recent changes, next steps, open questions
   - `memory-bank/progress.md` - what works, in progress, known issues, phase
4. Touch other files only if needed, including correcting or removing stale
   current-fact claims even when intent has not changed. Keep volatile status
   in its owning file rather than duplicating it across the bank:
   - `systemPatterns.md` — architectural changes or evidenced corrections to
     the description of current architecture
   - `techContext.md` — stack, environment, or operational changes, including
     evidenced corrections to existing setup instructions and factual claims
   - `decisionLog.md` — durable decisions or dated factual annotations to
     existing entries. Preserve the original rationale and history. If a past
     decision changed, **supersede, don't delete**: append "SUPERSEDED by …
     (date)" and move it to the Superseded section.
   - `productContext.md` or `projectbrief.md` for changed intent or obsolete
     factual content; preserve still-valid goals and user needs
5. Append to `.rules` only for non-obvious reusable learnings. If the entry is a repeat, or the same correction has recurred, first ask why the existing guidance did not take, then propose a test or hook check instead of a second line (contract "Memory writes" item 5). Then **prune** it: if it's over ~40 lines or holds stale lines, drop what's no longer true and promote stabilized conventions into `systemPatterns.md`.
6. **Retention (required).** Write the proposed `activeContext.md` and `progress.md` to a temp location and run the read-only helper on each - it measures the file *as it would be after this update*:

   ```bash
   hooks/lib/rotate-check.sh "$TMP/activeContext.md" activeContext
   hooks/lib/rotate-check.sh "$TMP/progress.md" progress
   ```

   - `RESULT: NO-OP` - nothing to do.
   - `RESULT: ROTATE n` - add to the proposal, for each selected line range: an append of those lines verbatim to the named `memory-bank/archive/<file>-<YYYY-MM>.md` (create it with a one-line header if missing), their removal from the live file, the heading named by any `ARCHIVE-PREFIX` line copied into the archive ahead of its span (it stays live), and - if `POINTER: missing` - one line `Older entries: archive/<file>-*.md` directly under the first `## Recent ...` heading. Never rotate a protected section; never paraphrase what moves.
   - `RESULT: OVERAGE-REMAINS` - rotate what it selected (if anything) and say plainly that current-state content alone is over the target; the user decides whether to trim it.

   After the user confirms and the files are written, run the helper again on the live files and report its `RESULT` lines. Targets and rules: `docs/workflow-contract.md` "Retention".

7. **Drift check (after writing).** If `bin/serel-memory` exists, run it on the resolved scope and report its summary line:

   ```bash
   "$(git rev-parse --show-toplevel)/bin/serel-memory" check --scope <resolved scope>
   ```

   It is read-only and never blocks the update. If it reports `DRIFT` or `STALE`, say what it found and offer to fix the bank in this pass.

For each proposed change, show:

```text
FILE: [path]
CHANGE: [add / update / remove]
DIFF:
[actual before/after for the affected section]
```

## Bank-vs-reality audit (offered)

The bank update is the agent writing the durable record of its own session —
the purest self-grading moment in the framework. After showing the proposed
diffs and before asking for confirmation, if `claude --version` succeeds and
the session wasn't trivial (docs-only or a tiny diff), offer once:

> Want Claude to verify these updates against the actual repo? (~30–90s, read-only)

If accepted:

1. Write a prompt file containing the proposed diff blocks, the coverage
   summary and relevant evidence, the selected effective bank path, the
   instructions below, and a read-only instruction (do not edit
   files or run write operations), then run Claude read-only — synchronous
   form, `docs/cross-agent-review.md` has the canonical invocation:

   ```bash
   claude -p --permission-mode plan < "$PROMPT_FILE"
   ```

2. Ask Claude to read the relevant live bank sections alongside the proposed
   diffs, looking for old claims about the changed subjects that the proposal
   leaves behind. Classify claims as **current fact**, **durable decision**,
   **intended future**, or **open question**. Flag only *current-fact* claims
   the code, tests, or git history
   don't support. Intent is allowed to lead the code; facts are not. When a
   claim is ambiguous between fact and intent (present-tense statements in
   `projectbrief.md`, `productContext.md`, or `systemPatterns.md` often
   describe planned state), classify it as intent unless it asserts
   observable build/test/runtime status.
3. Also ask it to compare session decisions and observed results with the
   relevant diff/log for durable changes the draft missed — including decisions
   without code changes. Preserve historical entries and accepted intent; flag
   possible regressions rather than rewriting goals to match implementation.
4. Fold accepted findings into the proposed diffs, mark which lines changed
   because of the audit, and show the revised diffs.

If Claude is unavailable or the user declines, continue single-model — the
audit never blocks a bank update.

Wait for confirmation before writing.

## Rules

- Do not bloat the bank.
- The `## Checkpoint` is the resume note (branch and HEAD, uncommitted, verified, first action). No `wip:` commit unless the user asked for a pause (contract "Clean stop").
- Do not journal one-off events.
- Never write to two scopes in one pass. If a learning clearly belongs to another project bank or to the root, say so and offer to run this workflow again with that `--scope`, rather than writing outside the resolved scope.
- If `.rules` already covers a learning, refine the existing entry instead of duplicating it.
- Keep `activeContext.md` current: current-state sections (`Current focus`, `Checkpoint`, `Next steps`, `Open questions`, `Notes for next session`) are rewritten in place; historical entries rotate losslessly to `archive/` per step 6, never deleted, never paraphrased.
- Promote information according to `docs/workflow-contract.md`: session state to `activeContext.md`, completed status to `progress.md`, durable decisions to `decisionLog.md`, reusable gotchas to `.rules`.
