---
name: decision-log
description: "Record an architectural, product, workflow, or operational decision. Use when the user asks to log a decision, create an ADR, or preserve decision rationale."
---

# Decision Log

Use this skill to record a durable decision. Significant decisions should get an ADR in `docs/decisions/` and a short index entry in `memory-bank/decisionLog.md`.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), all memory-bank reads and writes below target it instead of the tracked templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. If the decision is not clear, ask: **"What's the decision you want to record?"**
2. Read:
   - `memory-bank/systemPatterns.md`
   - `memory-bank/techContext.md`
   - `memory-bank/decisionLog.md`
   - `.rules`
3. Check `docs/decisions/` for existing ADRs and determine the next sequential number. If the directory is missing, plan to create it.
4. Draft an ADR:

```text
# [NNN]. [Short imperative title]

## Status

Proposed | Accepted | Deprecated | Superseded by [NNN]

## Context

[Situation, constraints, and why this decision exists.]

## Decision

[The decision in definitive language.]

## Alternatives considered

- **[Alternative A]**: [why rejected]
- **[Alternative B]**: [why rejected]

## Consequences

**Positive**:
- [benefit]

**Negative**:
- [cost or tradeoff]

**Neutral**:
- [side effect]

## References

- [link to code, doc, discussion, ticket]
```

5. Show the proposed ADR and the proposed `memory-bank/decisionLog.md` index entry.
6. Wait for confirmation before writing.
7. When approved, write:
   - `docs/decisions/NNN-<slug>.md`
   - an entry in `memory-bank/decisionLog.md`
8. Ask whether `memory-bank/systemPatterns.md` should reference the decision under "Key decisions."

## Rules

- ADRs are for decisions with meaningful alternatives or future consequences.
- Use `Proposed` unless the decision is already in effect.
- Consequences should be balanced.
- Do not silently overwrite existing ADRs.
