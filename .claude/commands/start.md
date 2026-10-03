---
description: "Read the memory bank, summarize state, ask where to pick up. Use: /start (quick) or /start full (rich dashboard)"
---

# /start

You are starting a new session on this project. Your memory has reset; the memory bank is your only continuity.

**Mode:** Check `$ARGUMENTS` for a mode keyword.

- If empty, `quick`, or `brief` → use **Quick mode** (compact output; both modes read the same inputs).
- If `full`, `onboard`, or `dashboard` → use **Full mode** (rich onboarding dashboard).

Also check `$ARGUMENTS` for `--scope <path>` (scoped banks only — see "Resolving scope" in `docs/workflow-contract.md`). `--scope .` is the root; a path equal to a project root selects that project's bank; anything else: stop and list the valid selectors (`hooks/lib/resolve-scope.sh --list`). Without it, resolve by the current directory, then the root. Never read more than one bank in a pass.

---

## Step 1 — Read the memory bank (both modes)

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), it is the working bank — read its files and its `.rules` instead of the tracked ones, skip files it doesn't contain (intent lives in `README.md`/`docs/`), and don't report the blank tracked templates as uninitialized. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

Do these in order, before anything else:

1. Read every file in `memory-bank/` in this order:
   - `projectbrief.md`
   - `productContext.md`
   - `systemPatterns.md`
   - `techContext.md`
   - `decisionLog.md`
   - `activeContext.md`
   - `progress.md`
2. Read `.rules`.
3. Look for optional docs under `memory-bank/` that clearly match the user's task or active context, and read only the relevant ones. Never read `memory-bank/archive/` at startup.
4. Run `git log --oneline -10` to see recent activity.
5. Run `git status` to see uncommitted changes.
6. If `bin/serel-memory` exists, run the read-only drift check on the resolved scope and keep its summary line for the audit:

   ```bash
   "$(git rev-parse --show-toplevel)/bin/serel-memory" check --scope <resolved scope>
   ```

   Report its findings and summary line as they are — it never blocks the session. If the file is absent, say `checker absent`.

If any memory bank file is empty, missing, or still only template placeholders, surface it as `BLANK` or `UNINITIALIZED` and ask the user whether to initialize it before proceeding.

---

## Step 2 — Produce the output

### Quick mode (default)

Produce a context audit and session summary in this exact format:

```text
CONTEXT AUDIT:
- Read: [memory-bank files and .rules]
- Optional docs read: [paths or "(none)"]
- Scope: [only when the repo configures `scopes`: `.` or the selected project root]
- Uninitialized: [missing, empty, or template-only files]
- Recent commits not reflected in memory: [yes/no/unknown]
- Working tree: [clean / dirty summary]
- Drift: [the drift checker's summary line, or "checker absent"]

PROJECT: [one sentence — what we're building]
PHASE: [from progress.md]
LAST SESSION: [from activeContext.md — what was being worked on]
CURRENT STATE: [what works / what's in progress / known issues — 2 lines max]
NEXT STEPS: [from activeContext.md — top 1–3]
OPEN QUESTIONS: [anything blocking or unresolved]
```

If the repo configures `scopes` and the scope resolved to the root, add an **Active scopes** list before the closing question — one line per project root from `hooks/lib/resolve-scope.sh --list`, as `--scope <path> [initialized|uninitialized]`. Read nothing from those banks. Then end with: **"Which scope, or stay at the root?"** Otherwise end with: **"Where do you want to pick up?"** Then wait.

### Full mode (`/start full`)

Produce the full context audit (same as quick mode), then continue with all of the sections below.

#### Recent Progress (last 2–3 sessions)

Extract from `progress.md` recent milestones and `activeContext.md` recent changes:

- Session achievements with dates
- Key technical discoveries or architectural changes
- Milestones reached

#### Current State Analysis

**What Works**

- Pull from `progress.md` "What works" section — list each capability

**In Progress**

- Pull from `progress.md` "In progress" section
- Cross-reference with `activeContext.md` current focus

**Known Issues**

- Pull from `progress.md` "Known issues" section

**What's Left to Build**

- Pull from `progress.md` "What's left to build" section
- Include estimates where you can reasonably infer them

#### Open Decisions & Blockers

- Pull from `activeContext.md` open questions
- Pull from `decisionLog.md` any pending/draft decisions
- Flag any memory bank staleness (commits not reflected, files out of date)

#### Git Status

- Uncommitted changes that should be addressed
- Commits ahead/behind of remote
- Current branch info

#### Suggested Next Steps

Provide 3–5 specific, actionable recommendations organized by urgency:

🔴 **URGENT** — blocking progress or stale/broken
🟡 **HIGH-VALUE** — best use of this session based on momentum and impact
🟢 **STRATEGIC** — important but can wait

For each, include: clear action item, rough time estimate, expected outcome.

#### Direction Options

Present 3–4 options clearly:

- **Option A:** Continue recent momentum — [describe based on activeContext]
- **Option B:** Address top priority — [from what's left to build]
- **Option C:** Start next feature/initiative — [from what's left or open questions]
- **Option D:** Something else

End with: **"Which direction would you like to take for this session?"** Then wait.

---

Do not start working on anything until the user answers.
