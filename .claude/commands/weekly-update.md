---
description: Draft a stakeholder-ready weekly update from the memory bank and recent activity
---

# /weekly-update

Draft a weekly update suitable for stakeholders, pulling from the memory bank and recent git activity. The output should be skimmable in 30 seconds.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Steps:

1. Read `memory-bank/projectbrief.md` for what this project is.
2. Read `memory-bank/activeContext.md` for current focus and open questions.
3. Read `memory-bank/progress.md` for what works and what's in progress.
4. Read `memory-bank/decisionLog.md` for decisions made or changed this week.
5. Run `git log --since="1 week ago" --oneline --all` for recent activity.
6. Run `git status` to see current uncommitted work.

Then produce an update in this structure:

~~~markdown
# [Project name] — Week of [Mon DD, YYYY]

## Headline
[One sentence — the most important thing a stakeholder should know about this week.]

## Shipped this week
- [completed item — what it does, why it matters]
- [completed item]

## In progress
- [active work — what's being built, expected completion if known]
- [active work]

## Up next
- [planned next — what we're picking up next, why]
- [planned next]

## Risks and open questions
- [risk or unresolved decision — impact, what's needed to resolve]
- [risk]

## Decisions
- [decision made or changed this week — why it matters]
- (or write "None this week")

## Asks
- [anything needed from stakeholders — decisions, resources, feedback]
- (or write "None this week")
~~~

Rules:

- Keep each bullet to one line. If something needs more, it belongs in a separate doc with a link from the update.
- "Shipped" means done and verifiable. Don't conflate intent with completion.
- "Risks" should be specific. "Things might be hard" is not a risk. "External API rate limits could block X by Y date unless we get a quota increase" is.
- "Decisions" should be durable choices, not normal task progress.
- If a section has nothing to report, write "(none)" rather than omitting the section. Empty sections are signal too — they tell the reader you considered it.
- This is a stakeholder document, not an engineering log. Skip technical detail unless a stakeholder needs to know it. If a teammate would need more detail, mention there's a longer doc available.

After generating the draft, ask the user:

- Is the headline the right one for this audience?
- Tighter, longer, or about right?
- Format for a specific channel (Slack, email, Confluence) or keep generic?

Revise based on their answer. Then stop.
