---
name: risk-review
description: "Surface project risks not yet captured in the memory bank. Use when the user asks for risk review, hidden risks, assumptions, unknowns, or pre-planning risk assessment."
---

# Risk Review

Use this skill to find risks and assumptions that are not already captured in the memory bank. Do not invent risks just to fill categories.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), all memory-bank and `.rules` reads and writes below target it instead of the tracked templates; skip files it doesn't contain. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Read:
   - `memory-bank/projectbrief.md`
   - `memory-bank/productContext.md`
   - `memory-bank/systemPatterns.md`
   - `memory-bank/techContext.md`
   - `memory-bank/decisionLog.md`
   - `memory-bank/activeContext.md`
   - `memory-bank/progress.md`
   - `.rules`
2. Inspect relevant code, docs, dependency manifests, recent commits, or open diffs when needed.
3. Identify risks across:
   - Technical
   - Schedule
   - External/vendor
   - Resource/capacity
   - Scope
   - Operational/security
   - Assumptions
4. Rank by likelihood times impact.

## Output

For each risk:

```text
## [Short name]
- Category: [category]
- What could go wrong: [specific failure mode]
- Likelihood: high / medium / low
- Impact if it hits: [concrete consequence]
- Mitigation: [what to do now]
- Status: undocumented / partially documented / documented but stale
```

End by asking which risks should be added to `memory-bank/activeContext.md`, `memory-bank/progress.md`, or `memory-bank/decisionLog.md`. Do not write memory updates without confirmation.
