---
name: ship
description: "Run a pre-merge ship readiness checklist. Use when the user asks whether a branch/change is ready to merge, ship, release, or needs final checks."
---

# Ship

Use this skill to decide whether the current branch or change is ready to merge.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Checklist

1. Tests pass. Run the project test suite if discoverable.
2. New behavior has tests.
3. Documentation is updated.
4. New environment variables are documented.
5. Changelog is updated when the project has one.
6. Memory bank is updated, especially `progress.md`, `activeContext.md`, and `decisionLog.md` when decisions changed.
7. No leftover debug code such as `console.log`, `print(`, `debugger`, untracked TODOs, or commented-out blocks.
8. No leaked secrets in the diff.
9. Commit history is reasonable, or there is a sensible squash plan.

## Output

```text
SHIP READINESS: [READY / NOT READY / READY WITH CAVEATS]

CHECKLIST:
[pass/fail] 1. Tests pass - [detail]
[pass/fail] 2. New behavior has tests - [detail]
[pass/fail] 3. Documentation updated - [detail]
[pass/fail] 4. Env vars documented - [detail]
[pass/fail] 5. CHANGELOG updated - [detail]
[pass/fail] 6. Memory bank updated - [detail]
[pass/fail] 7. No leftover debug code - [detail]
[pass/fail] 8. No secrets leaked - [detail]
[pass/fail] 9. Commit history reasonable - [detail]

BLOCKERS (must fix):
-

CAVEATS (should fix but not blocking):
-

RECOMMENDATION: [one sentence]
```

If something is ambiguous, ask before declaring the change not ready.
