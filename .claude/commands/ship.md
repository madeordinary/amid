---
description: Pre-merge checklist — ship or don't ship
---

# /ship

You're being asked whether the current branch is ready to merge. Run through the checklist and produce a clear ship/don't-ship recommendation.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Checklist:

1. **Tests pass.** Run the test suite. If there are no tests for a project that should have them, flag it.
2. **New behavior has tests.** Look at the diff — anything new without a corresponding test?
3. **Documentation updated.** README, docs/, comments on non-obvious code, anywhere users would look.
4. **Env vars documented.** If new env vars were added, are they in README and/or `.env.example`?
5. **CHANGELOG updated.** If the project has one, does this change appear in it?
6. **Memory bank updated.** Does `progress.md` reflect what changed? Is `activeContext.md` current? Does `decisionLog.md` reflect any durable decisions?
7. **No leftover debug code.** Search for `console.log`, `print(`, `debugger`, TODOs without a tracking link, commented-out blocks.
8. **No secrets leaked.** Scan diff for API keys, tokens, passwords, internal URLs.
9. **Commit history is reasonable.** Either clean commits or a sensible squash plan.

Output format:

```text
SHIP READINESS: [READY / NOT READY / READY WITH CAVEATS]

CHECKLIST:
[✓ or ✗] 1. Tests pass — [detail]
[✓ or ✗] 2. New behavior has tests — [detail]
[✓ or ✗] 3. Documentation updated — [detail]
[✓ or ✗] 4. Env vars documented — [detail]
[✓ or ✗] 5. CHANGELOG updated — [detail]
[✓ or ✗] 6. Memory bank updated — [detail]
[✓ or ✗] 7. No leftover debug code — [detail]
[✓ or ✗] 8. No secrets leaked — [detail]
[✓ or ✗] 9. Commit history reasonable — [detail]

BLOCKERS (must fix):
- 

CAVEATS (should fix but not blocking):
- 

RECOMMENDATION: [one sentence]
```

If something is ambiguous, ask before declaring NOT READY — don't fail someone on something you misread.
