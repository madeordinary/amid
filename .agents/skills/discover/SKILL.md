---
name: discover
description: "Shape a brand-new project from a rough idea and seed memory-bank files. Use when there is no code yet, the project brief is blank/template-only, or the user asks to discover, define, clarify, or scope a new project."
---

# Discover

Use this skill at the start of a new project when the user has an idea but has not articulated it as a brief. This is the inverse of `$init-memory`, which analyzes existing code.

First check whether `memory-bank/projectbrief.md` already has substantive content beyond template placeholders. If it does, point the user toward `$start` or planning instead.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), it is the working bank — the check above and any proposed writes target it, not the tracked starter templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Phase 1 - Open Prompt

Ask:

> Tell me what you want to build. Don't worry about structure - just what's in your head right now. A sentence is fine; a paragraph is fine; a rambling explanation is fine.

Listen to the answer before restructuring it.

## Phase 2 - Map And Ask

Classify these items as clear, partial, or missing:

1. Problem - what pain or opportunity drives this
2. User - who specifically has this need
3. Today's solution - what they do now and why it falls short
4. Success - what "this worked" looks like concretely
5. Minimum scope - smallest useful version
6. Anti-scope - what this explicitly does not do
7. Constraints - time, budget, tech, compliance, anything binding
8. Stack hints - tech they want or have ruled out

Skip clear items. For partial and missing items, ask one targeted question at a time. Aim for 3-5 high-value questions total.

Prefer concrete questions, for example:

- "Is this for you only, for a specific team of 5-50 people, or for thousands of strangers?"
- "Six months from now, if this is working, what would specifically be different?"
- "If you could ship only one feature on day one and skip everything else, which one is it?"

## Phase 3 - Synthesize

Once there is enough material, draft proposals for:

- `memory-bank/projectbrief.md`
- `memory-bank/productContext.md`
- `memory-bank/systemPatterns.md`
- `memory-bank/techContext.md`
- `memory-bank/decisionLog.md`
- `memory-bank/activeContext.md`
- `memory-bank/progress.md`

Show proposals one file at a time. After each proposal, wait for approval, revision, or pushback before writing.

## Rules

- Do not pretend to know things the user has not said.
- Push back gently when the answer is too vague to create useful memory-bank content.
- Resist adding scope.
- Do not validate or endorse the idea; document and clarify it.
- Use `decisionLog.md` only for explicit decisions made during discovery; otherwise keep it empty/template-light.
- After all approved files are written, end with: **"Memory bank seeded. Use `$start` to verify the bootstrap, or ask me to plan the first chunk of work."**
