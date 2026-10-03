---
description: Generate a handoff document for someone picking up this project cold
---

# /handoff

Produce a handoff document for someone who's never seen this project before. The audience is a smart engineer or PM who needs to be able to take this over within a few days.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Steps:

1. Read every file in `memory-bank/` for full project context (skip `memory-bank/archive/` unless the handoff needs that history).
2. Read `.rules` for non-obvious patterns and preferences.
3. Read the project's `README.md` (the user-facing one, not Serel Memory's).
4. Scan `docs/` if it exists, especially `docs/decisions/` and `docs/runbooks/`.
5. Run `git log --oneline -30` for recent history.
6. Note any open TODOs, FIXMEs, or in-progress branches.

Then produce a handoff doc in this structure:

~~~markdown
# [Project name] — Handoff

> Generated [DATE]. If you're reading this, someone is handing this project to you. This document is your starting point.

## TL;DR

[Three sentences: what this project is, what state it's in, what the next person should do first.]

## What this is and why it exists

[From projectbrief.md — what we're building and why. Don't just copy; summarize for an outsider.]

## How it works

[From systemPatterns.md and techContext.md — the architecture at a level a new engineer can absorb. Include a sketch or describe the data flow if relevant.]

## Where we are right now

[From activeContext.md and progress.md — current focus, what works, what's broken, what's stuck.]

## How to run it

[Setup commands, env vars, where to deploy, how to test. From techContext.md and any READMEs.]

## Conventions and gotchas

[From .rules — non-obvious patterns, things that have bitten us, preferences worth knowing.]

## Key decisions and why

[Summary of the most important entries from decisionLog.md and ADRs from docs/decisions/, with links to full versions.]

## Open questions and risks

[From activeContext.md — things that aren't decided yet, plus any risks worth flagging.]

## First things to do

[1. Get the project running locally. 2. Read [these specific files]. 3. Talk to [these people if anyone]. 4. Pick up [this specific in-progress thing] or [this open question].]

## Where to find things

[Quick map: code in src/, docs in docs/, decisions in docs/decisions/, etc.]

## Who knows what

[If the project has had multiple contributors, mention who has context on what. If solo, just say so.]
~~~

Save to `docs/handoff.md` (overwrite if it exists — handoffs are point-in-time snapshots, not version-controlled history).

Rules:

- Write for someone who is *smart and skeptical*, not someone who needs hand-holding. Don't over-explain.
- Be honest about what's broken or unfinished. The handoff is more valuable when it surfaces the rough edges than when it papers over them.
- "First things to do" should be concrete — not "read the codebase" but "read `src/api/` first, then `src/workers/`."
- If something would take longer than a paragraph to explain, link to the file or doc that explains it. The handoff is a map, not the territory.

After writing, ask the user: "Is there context that's in your head but not in the memory bank? Anything I should add before this gets passed on?"
