---
description: Record an architectural decision in ADR format
---

# /decision-log

Record an architectural or design decision in standard ADR (Architecture Decision Record) format. Use this when a decision is significant enough that future-you (or a future teammate) will want to know why it was made.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), all memory-bank reads and writes below target it instead of the tracked templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Steps:

1. If the user hasn't already stated the decision, ask: "What's the decision you want to record?"
2. Read `memory-bank/systemPatterns.md`, `memory-bank/techContext.md`, and `memory-bank/decisionLog.md` for related context.
3. Check `docs/decisions/` for existing ADRs to determine the next number. If the directory is missing, create it when the ADR is approved.
4. Draft the ADR and a short `memory-bank/decisionLog.md` entry.

Use this structure:

~~~markdown
# [NNN]. [Short imperative title — e.g., "Use Postgres for state, not SQLite"]

## Status

Proposed | Accepted | Deprecated | Superseded by [NNN]

## Context

[What's the situation that's forcing this decision? What constraints are in play? Be specific about what's actually true today.]

## Decision

[What did we decide? Be definitive. "We will use X" not "We're considering X."]

## Alternatives considered

- **[Alternative A]**: [brief description and why it was rejected]
- **[Alternative B]**: [brief description and why it was rejected]

## Consequences

**Positive**:
- [what this decision enables or makes easier]

**Negative**:
- [what this decision costs us or makes harder]

**Neutral**:
- [side effects that aren't clearly good or bad but should be known]

## References

- [link to relevant code, doc, discussion, ticket]
~~~

Show the proposed ADR and memory-bank entry, then wait for confirmation before writing.

When approved, save the ADR to `docs/decisions/NNN-<slug>.md`, where NNN is the next sequential number padded to 3 digits (e.g., `001-use-postgres-for-state.md`). Add the short entry to `memory-bank/decisionLog.md`.

After writing, ask the user whether `memory-bank/systemPatterns.md` should be updated to reference this decision under "Key decisions."

Rules:

- ADRs are for *real* decisions — ones with alternatives that were genuinely considered. Don't ADR trivial things ("we use 2-space indents").
- Status starts as "Proposed" unless the decision is already in effect. The user updates to "Accepted" when they're confident.
- Alternatives section should be honest. If you didn't seriously consider others, say so — that's also useful context.
- Consequences should be balanced. If you can't think of negatives, you probably haven't thought hard enough about the decision.
- Do not silently overwrite an existing ADR or decision-log entry.
