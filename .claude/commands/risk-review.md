---
description: Surface risks not yet documented in the memory bank
---

# /risk-review

Surface risks and unknowns that aren't already captured in the memory bank. The goal is to find what could derail this project that nobody's named yet.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), all memory-bank and `.rules` reads and writes below target it instead of the tracked templates; skip files it doesn't contain. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Steps:

1. Read `memory-bank/projectbrief.md` for goals and success criteria.
2. Read `memory-bank/productContext.md` for user/UX context.
3. Read `memory-bank/systemPatterns.md` for architectural decisions and assumptions.
4. Read `memory-bank/techContext.md` for stack, dependencies, constraints.
5. Read `memory-bank/decisionLog.md` for durable decisions and ADR references.
6. Read `memory-bank/activeContext.md` for current focus.
7. Read `memory-bank/progress.md` for status and known issues.
8. Read `.rules` for any documented gotchas or rejected approaches.

Then identify risks across these categories:

- **Technical**: dependencies, scaling, architecture decisions that might not survive contact with reality
- **Schedule**: dates, milestones, anything time-bound
- **External**: vendors, APIs, integrations, anything outside the team's control
- **Resource**: people, budget, capacity
- **Scope**: ambiguity in requirements, scope creep, feature inflation
- **Operational**: deployment, monitoring, on-call coverage, security
- **Assumptions**: things the project assumes are true that might not be

For each risk, produce:

~~~markdown
## [Short name]
- **Category**: [from above]
- **What could go wrong**: [specific failure mode]
- **Likelihood**: high / medium / low
- **Impact if it hits**: [concrete consequences]
- **Mitigation**: [what we could do now to reduce likelihood or impact]
- **Status**: undocumented / partially documented / documented but stale
~~~

Output a ranked list, highest combined likelihood × impact first.

Rules:

- Surface NEW risks. Don't just restate what's already in `progress.md` under "known issues."
- Be specific. "API might be slow" is not a risk; "Vendor X's rate limit is 100 req/min and we're projecting 300 req/min at launch" is.
- Don't manufacture risks. If a category has nothing real, say so explicitly.
- If a risk is genuinely "out of our control," still name it — visibility matters even when action doesn't.

After the review, ask the user which risks belong in `memory-bank/activeContext.md`, `memory-bank/progress.md`, or `memory-bank/decisionLog.md`, and add them with confirmation.
