---
name: weekly-update
description: "Draft a stakeholder-ready weekly update from the memory bank and recent activity. Use when the user asks for a weekly update, status report, stakeholder summary, or progress email."
---

# Weekly Update

Draft a weekly update suitable for stakeholders, pulling from the memory bank and recent git activity. The output should be skimmable in 30 seconds.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Read:
   - `memory-bank/projectbrief.md` — what this project is
   - `memory-bank/activeContext.md` — current focus and open questions
   - `memory-bank/progress.md` — what works and what's in progress
   - `memory-bank/decisionLog.md` — decisions made or changed this week
2. Run `git log --since="1 week ago" --oneline --all` for recent activity.
3. Run `git status` to see current uncommitted work.

## Output

```text
# [Project name] — Week of [Mon DD, YYYY]

## Headline
[One sentence — the most important thing a stakeholder should know.]

## Shipped this week
- [completed item — what it does, why it matters]

## In progress
- [active work — what's being built, expected completion if known]

## Up next
- [planned next — what we're picking up, why]

## Risks and open questions
- [risk or unresolved decision — impact, what's needed to resolve]

## Decisions
- [decision made or changed this week — why it matters]
- (or "None this week")

## Asks
- [anything needed from stakeholders — decisions, resources, feedback]
- (or "None this week")
```

## Rules

- Keep each bullet to one line. Longer items belong in a separate doc.
- "Shipped" means done and verifiable. Don't conflate intent with completion.
- "Risks" should be specific, not vague concerns.
- If a section has nothing, write "(none)" — empty sections are signal too.
- This is for stakeholders, not engineers. Skip technical detail unless they need it.

After generating, ask:

- Is the headline right for this audience?
- Tighter, longer, or about right?
- Format for a specific channel (Slack, email, Confluence) or keep generic?

Revise based on their answer. Then stop.
