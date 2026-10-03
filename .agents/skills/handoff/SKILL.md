---
name: handoff
description: "Generate a handoff document from a project. Use when the user asks for a handoff, onboarding summary, transfer doc, or context package for someone new."
---

# Handoff

Use this skill to create a concise handoff for a smart engineer or PM picking up the project cold.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Read every file in `memory-bank/`, including `decisionLog.md` (skip `memory-bank/archive/` unless the handoff needs that history).
2. Read `.rules`.
3. Read the project `README.md` if present.
4. Scan `docs/`, especially `docs/decisions/` and `docs/runbooks/`.
5. Run `git log --oneline -30`.
6. Look for open TODOs, FIXMEs, or active branches when relevant.
7. Produce `docs/handoff.md` with this structure:

```text
# [Project name] - Handoff

> Generated [DATE]. If you're reading this, someone is handing this project to you.

## TL;DR

[Three sentences: what this is, state, first next action.]

## What this is and why it exists

[Project purpose.]

## How it works

[Architecture and data flow.]

## Where we are right now

[Current focus, what works, what's broken, what's stuck.]

## How to run it

[Setup, env vars, tests, deploy.]

## Conventions and gotchas

[Non-obvious rules and known traps.]

## Key decisions and why

[Important entries from decisionLog.md and docs/decisions/.]

## Open questions and risks

[Unresolved questions and risks.]

## First things to do

[Concrete first actions.]

## Where to find things

[Quick map.]

## Who knows what

[Context owners, or note that it is solo.]
```

8. Show the proposed content before overwriting an existing `docs/handoff.md`.

## Rules

- Be honest about rough edges.
- Link to deeper docs instead of copying long explanations.
- The handoff is a map, not the territory.
- After writing, ask what context is still only in the user's head.
