---
description: Seed the memory bank from an existing PRD or product brief
---

# /from-prd

Use this when a new project has a PRD, product brief, strategy doc, or similar source document, but little or no code yet. You'll read the document, ask only for important gaps, then propose initial memory bank contents.

This sits between `/discover` and `/init-memory`:

- `/discover` is for rough ideas with no source document.
- `/from-prd` is for a project with a PRD or brief but no meaningful code yet.
- `/init-memory` is for an existing codebase.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), it is the working bank — the substantive-content check and any proposed writes target it, not the tracked starter templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Steps

1. Determine the PRD path.
   - If the user provided a path, use it.
   - If not, look for likely files in `docs/`, the repo root, or filenames containing `prd`, `brief`, `spec`, `requirements`, or `product`.
   - If there are multiple plausible files, ask which one to use.
2. Read the PRD in full.
3. Check whether the memory bank already has substantive content. If it does, ask whether to merge from the PRD or stop.
4. Extract what the PRD clearly says about:
   - Problem
   - User
   - Current workaround or status quo
   - Goals and success criteria
   - Minimum scope
   - Anti-scope
   - Constraints
   - Stack, platform, or architecture hints
   - Risks, open questions, and unresolved decisions
5. Before proposing memory-bank contents, present a clarifications checkpoint:

   ```text
   CLARIFYING QUESTIONS:
   - [question] or "(none - PRD is sufficient for initial seeding)"
   ```

   Ask at most 3 targeted follow-up questions for material gaps that would make the memory bank misleading if guessed. Skip questions where `TBD` is acceptable.
6. If there are clarifying questions, stop and wait for the user's answers before synthesis. If there are none, say so and proceed.
7. Propose contents for every memory bank file:
   - `memory-bank/projectbrief.md`
   - `memory-bank/productContext.md`
   - `memory-bank/systemPatterns.md`
   - `memory-bank/techContext.md`
   - `memory-bank/decisionLog.md`
   - `memory-bank/activeContext.md`
   - `memory-bank/progress.md`

Use this format for each proposal:

```text
FILE: memory-bank/<name>.md
PROPOSAL:
<proposed contents, preserving the file's heading structure>

CONFIDENCE: high / medium / low
SOURCE: <PRD section or evidence used>
QUESTIONS / ASSUMPTIONS: <only if needed>
```

After all proposals, stop and wait. Do not write anything until the user approves or revises.

## Output quality

- Do not wrap an entire file proposal in a Markdown code fence if the proposed file itself contains fenced code blocks.
- If a proposal includes a code block, close the fence before continuing with the next heading or metadata line.
- Keep architecture sketches simple unless a code fence is genuinely useful.
- Keep `CONFIDENCE`, `SOURCE`, and `QUESTIONS / ASSUMPTIONS` outside the proposed file body.
- End by asking whether the user wants to approve, revise, or inspect a specific file first.

## Rules

- Treat the PRD as source material, not absolute truth.
- Do not invent details to fill empty sections. Use `<TBD>` or ask.
- Keep `systemPatterns.md` and `techContext.md` light unless the PRD states real technical decisions.
- Use `decisionLog.md` only for explicit decisions in the PRD; otherwise state that no durable decisions have been recorded yet.
- Use `activeContext.md` to capture the immediate next focus after seeding the bank.
- Use `progress.md` to reflect that the project is initialized/planning unless code already exists.
- Do not overwrite the PRD.
- Do not bloat the bank; preserve signal.

## Handoff

When approved files are written, end with:

> "Memory bank seeded from the PRD. Run `/start` to verify the bootstrap, or `/breakdown` to break the first implementation chunk into steps."
