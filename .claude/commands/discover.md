---
description: Help the user define a project from a rough idea (no code yet); produces initial memory bank
---

# /discover

Use this at the start of a brand-new project, when the user has an idea but hasn't yet articulated it as a brief. You'll guide them through structured discovery, then propose memory bank contents based on the dialogue.

This is the inverse of `/init-memory`. That command analyzes existing code. This one helps shape a project that doesn't exist yet.

First, check whether the project already has substantive memory bank content. If `memory-bank/projectbrief.md` has real content beyond the template placeholders, this is the wrong command — point the user toward `/breakdown` or `/start` instead. Otherwise, proceed.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), it is the working bank — the check above and any proposed writes target it, not the tracked starter templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Phase 1 — Open prompt

Start with this, more or less verbatim:

> "Tell me what you want to build. Don't worry about structure — just what's in your head right now. A sentence is fine; a paragraph is fine; a rambling explanation is fine."

Listen to whatever the user gives. Don't interrupt. Don't restructure. Just take it in.

## Phase 2 — Map and ask

From the user's initial answer, identify which of these are **clear**, **partial**, or **missing**:

1. **Problem** — what pain or opportunity drives this
2. **User** — who specifically has this need
3. **Today's solution** — what they do now and why it falls short
4. **Success** — what "this worked" looks like concretely
5. **Scope (minimum)** — smallest version that would be useful
6. **Anti-scope** — what this explicitly does NOT do
7. **Constraints** — time, budget, tech, compliance, anything binding
8. **Stack hints** — tech they want or have ruled out

Skip CLEAR items. For PARTIAL and MISSING items, ask **one targeted question at a time**. Wait for the answer before asking the next. Aim for 3–5 well-chosen questions total. Not eight.

Good questions are CONCRETE. Examples:

- Bad: "Who's the user?"
- Good: "Is this for you only, for a specific team of 5–50 people, or for thousands of strangers? Each one changes how this would look."

- Bad: "What does success look like?"
- Good: "Six months from now, if this is working, what would specifically be different in your day or in the world?"

- Bad: "What's the scope?"
- Good: "If you could ship only one feature on day one and skip everything else, which one is it?"

## Phase 3 — Synthesize

Once you have enough, draft proposals for:

- `memory-bank/projectbrief.md` — what, why, success, anti-scope, constraints
- `memory-bank/productContext.md` — user, job, today's solution, UX principles
- `memory-bank/systemPatterns.md` — keep light. Architecture often emerges later. Only capture what the user has clear opinions on.
- `memory-bank/techContext.md` — keep light. Stack often emerges as the project takes shape.
- `memory-bank/decisionLog.md` — only explicit decisions made during discovery; otherwise keep template-light.
- `memory-bank/activeContext.md` — immediate next focus and open questions.
- `memory-bank/progress.md` — planning status and what exists so far.

Show proposals **one file at a time**. After each, wait for the user to approve, revise, or push back before moving to the next.

## Rules

- Don't pretend to know things the user hasn't told you.
- If the user gives a weak answer ("idk, just kind of an AI thing"), push back gently: "I don't have enough yet to write a brief that's actually useful. Can you tell me more about [specific thing]?"
- Resist adding scope. Users usually come in wanting to do too much for v1. Help them carve back to a minimum useful version.
- Don't validate the idea itself. Your job is to help them articulate it, not endorse it.
- Don't synthesize until you have real material. Better to ask one more question than to fabricate.
- After synthesis, the project is still in their hands. You've documented what they said; you haven't blessed it.

## Handoff

When the files are approved and written, end with:

> "Memory bank seeded. Run `/start` to verify the bootstrap, or `/breakdown` if you want to break the first chunk of work into steps."
