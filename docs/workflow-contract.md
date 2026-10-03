# Workflow Contract

Serel Memory workflows should be small, explicit, and portable across agents. Use this
contract when adding or revising a Claude command, Codex skill, or future adapter.

## Required sections

Every workflow should make these things clear:

- **Trigger**: when to use it and when not to use it.
- **Required reads**: files, diffs, logs, or docs the agent must inspect first.
- **Allowed writes**: files the workflow may edit, and whether confirmation is required.
- **Output contract**: the exact shape users should expect back.
- **Stop conditions**: when the agent must pause for user input instead of guessing.

## Resolving scope

By default a repo has one bank at its root and every workflow targets it —
nothing below applies. A repo that hosts several initiatives can opt in to
**scoped banks**: one root bank for portfolio state plus one full bank per
project folder, each with the standard seven files and its own `.rules`.

Opt in by listing the parent folders that hold projects in
`.serel-memory.json` (any other key is left alone):

```json
{ "upstream": "madeordinary/serel-memory", "ref": "v0.4.0", "linked": false,
  "scopes": ["projects/running", "projects/watching"] }
```

Every immediate child folder of a scope root is a **project root**. Its bank
is `<project root>/memory-bank/`; a project root without one is valid but
*uninitialized* — `/init-memory`, `/from-prd`, and `/discover` may create it;
every other workflow stops with the usual uninitialized message.

**One rule, everywhere.** Each invocation resolves exactly one scope, and it
never remembers a previous choice:

1. `--scope <path>` — `.` selects the root; a path equal to a project root
   selects that project; anything else stops and lists the valid selectors.
   Paths, never bare names: they cannot collide with mode words or with other
   workflows' arguments.
2. Otherwise, if the current directory is inside a project root, that project.
3. Otherwise, the root.

`hooks/lib/resolve-scope.sh` implements this rule for the hooks and the
tests; workflow prompts describe the same rule. The maintainer overlay
(below) is then applied *inside* the selected scope root.

**Rules files.** Writes go to the selected scope's own `.rules` (the overlay's
when the overlay is selected, even if it does not exist yet — never the
tracked root `.rules`). Reads use the first existing of the scope's write
target and the scope's plain `.rules`; at project scope the repo's effective
`.rules` is read too, as inherited guidance — local entries win on conflict,
and it is never written from a project scope.

**One bank per invocation.** A workflow reads one bank and writes one bank.
The only exception is enumeration: at the root, `/start` and the SessionStart
hook list project roots as usable selectors with an `initialized` /
`uninitialized` marker — no project bank content is read. If a learning
belongs to another scope, say so and offer to re-run with that selector;
never write outside the resolved scope.

**Scope-relative artifacts.** `/init-memory` inspects the scope root;
`/handoff` writes `<scope root>/docs/handoff.md`; `/decision-log` writes
`<scope root>/docs/decisions/`; `/retro` and `/runbook` write under
`<scope root>/docs/`. Archives rotate under the selected effective bank.

**Exceptions.** The SessionStart hook runs from the repo root and always
loads the root scope (plus the enumeration). `sync-upstream` is repo-root
anchored regardless of scope: framework files and the anchor live at the
root only. Malformed or overlapping `scopes`, or a missing `jq`, disable
scopes with one warning — the repo behaves as single-bank rather than
guessing.

**Non-code workspaces.** The bank shape is domain-neutral. For a portfolio
or product-management workspace, `systemPatterns.md` describes how the work
gets done (systems of record, rituals, who decides) and `techContext.md`
lists tools, data sources, and access. A project whose spec lives in an
external system of record keeps `projectbrief.md` as a declared mirror.
Project-specific preflights (a warehouse connectivity probe, say) belong in a
project-local command, never in `start.md`, so `sync-upstream` stays clean.

## Resolving the effective bank

Every reference to "the memory bank" or `.rules` in a workflow means the
**effective bank** within the resolved scope:

- If `memory-bank.local/` exists (upstream Serel Memory development only — it is
  gitignored and never ships), it is the effective bank: read and write its
  files instead of the tracked `memory-bank/`, and `memory-bank.local/.rules`
  instead of root `.rules`. It is partial by design; for core files it lacks,
  `README.md` and `docs/` carry intent — don't flag the blank tracked
  templates as uninitialized, and never write maintainer state to them.
- Otherwise (every downstream project), the effective bank is `memory-bank/`
  and root `.rules`.

## Defaults

- Read `AGENTS.md`, the relevant memory-bank files, `.rules`, and recent git history when project intent matters.
- Treat code as source of truth for current behavior.
- Treat the memory bank as source of truth for intended behavior once initialized.
- Show diffs before writing memory-bank files.
- Ask before changing product scope, architecture, dependencies, security posture, or public behavior.
- Prefer one focused workflow over a broad persona.
- Read optional `memory-bank/` docs only when the current task clearly touches that topic.

## Optional memory docs

Keep the core memory bank small. When a topic outgrows the core files, add focused
optional docs under `memory-bank/`, for example:

- `memory-bank/features/<feature>.md`
- `memory-bank/integrations/<service>.md`
- `memory-bank/ops/<runbook-context>.md`
- `memory-bank/testing.md`

Optional docs are not part of the required startup read. Agents should find and
read them only when relevant to the task.

## Memory writes

Use this promotion path:

1. Current task details go in the conversation or temporary plan.
2. Current session state goes in `memory-bank/activeContext.md`.
3. Completed status goes in `memory-bank/progress.md`.
4. Durable decisions go in `memory-bank/decisionLog.md` and, when useful, `docs/decisions/`.
   An entry says *decision / why / evidence / result* and keeps its date,
   status, and supersession link; an accepted-but-unbuilt decision records
   `result: pending`. ADRs still carry alternatives and consequences.
5. Reusable patterns and gotchas go in `.rules`. When a `.rules` entry is
   about to be written a second time, or a correction recurs, first ask why
   the existing guidance did not take (did it trigger? was it already there?
   wording or placement?), then propose the structural form — a test, a hook
   check, a CI step. Keep the prose rule until the mechanism exists and works;
   judgment rules stay prose with a concrete failure example.
6. Stable architecture goes in `memory-bank/systemPatterns.md`.

Do not turn the memory bank into a journal. A line should survive because it helps
the next session make a better decision.

## Memory accuracy

Every `/update-memory` or `$update-memory` proposal includes two passes over
the selected effective bank, bounded to subjects changed or discovered in the
session. This is routine reconciliation, not a full repository audit.

- **Capture:** compare session decisions and observations with relevant git
  history, staged and unstaged diffs, and relevant new files. Identify durable
  changes missing from the bank: completed work, changed constraints, accepted
  or superseded decisions, reusable learnings, unresolved problems, and the
  next action. A decision may have no code diff. Do not claim a test or manual
  verification ran without an observed result; distinguish committed work,
  uncommitted work, and released behavior.
- **Reconcile:** search the live bank and its own `.rules` for existing claims
  about those subjects. Read optional docs only when they match. Update current
  status, next steps, and obsolete blockers together; completing a feature also
  retires its pending task. Correct or remove stale facts in stable files even
  when product intent has not changed. Prefer one authoritative home for a
  volatile fact (release/completion status in `progress.md`, immediate work in
  `activeContext.md`) and references elsewhere over repeated status claims.

Classify discrepancies before proposing a correction: **current fact**,
**durable decision**, **intended future**, or **open question**. Code and
observed results establish current behavior; they do not supersede accepted
intent. If behavior violates a decision, report a possible regression for the
owner to resolve. Missing evidence means unassessed or unresolved, not false.
For external capability claims, record the source and applicable version or
verification date; re-check the source when relying on a changeable claim, or
say it could not be checked. The offline drift checker cannot do this.

Decisions are superseded with links, never silently deleted. Dated historical
entries, including recent changes and milestones, stay verbatim and rotate
under Retention; an old release mentioned as history is not a stale claim.
Never cross scopes to reconcile another bank or write inherited root rules.

Before the proposed diffs, give a compact coverage summary: **Captured** (new
durable information and its evidence), **Reconciled** (old claims corrected
and their locations), and **Unresolved** (missing evidence or owner decisions;
say none when there are none). This summary describes the subjects checked,
not a certification of the whole bank. Show diffs and use the existing
confirmation gate; reconciliation adds no separate approval step.

## Accuracy audit

`/analyze` and `$analyze` apply Memory accuracy as a read-only, on-demand
audit of one effective bank. They do not replace update-memory's routine
capture/reconciliation or the deterministic checker.

An explicit topic selects its claims across the live bank and matching optional
docs. Without a topic, coverage is current progress status, active focus,
checkpoint and next steps, pending/accepted decisions, and current setup facts.
Other core files supply intent; other claims remain unassessed. At a scoped
repo's root, audit only its root bank. Never silently inspect every project.

Every finding cites the bank claim or evidenced omission, its classification,
repository or external evidence, an action, and the evidence's limits. Separate
**documentation drift**, **possible regression**, **missing evidence**, and
**missing durable information**. Missing proof is not a proven falsehood.
Old verification records and source-level tests do not prove a fresh test pass.
Keep unsupported claims unverified; turning one into a target requires owner
intent. Implementation or commit evidence alone does not establish a release.

The workflow writes nothing and runs no tests, builds, recipes or secondary
agents. It may run the read-only checker, reporting its exit code and summary
separately; unavailable/dirty evidence stays incomplete. It reports coverage
and unresolved decisions, never a whole-bank truth score or semantic CI gate.
Corrections are suggestions for a separate reviewed update-memory invocation;
possible regressions stay owner decisions rather than automatic bank rewrites.

## Clean stop

When a session ends or context is about to compact, leave a state a
cold-start agent can resume from without redoing work:

- Finish or back out of the current atomic step. Never stop mid-edit in a
  known-broken state.
- The `## Checkpoint` records the branch and HEAD, what is uncommitted, what
  is verified (and how), and the first action on resume. That is the resume
  note; nothing else needs writing.
- Commit a `wip:` only when the user asked for a pause and only over changes
  this session authored. Never on compaction, never on "keep going", never
  over someone else's dirty files.
- On resume, the prior trail is authoritative for reasoning and completed
  investigation; inherited *completion claims* are re-verified on the real
  artifact before being relied on.

## Retention

Bank files are read every session, so their size is the framework's context
budget. Retention keeps the two volatile files bounded without losing history.

**Soft targets, per effective bank:**

- `activeContext.md`: at most 200 lines and 12,000 bytes.
- `progress.md`: `## Recent milestones` keeps its 10 newest entries.
- `.rules`: about 40 lines (existing rule; pruned, not rotated).

**Protected sections are never rotated** — they are current state, rewritten
in place by the normal update:

- activeContext: `## Current focus`, `## Checkpoint`, `## Next steps`,
  `## Open questions`, `## Notes for next session`. Move a note into
  `Recent changes` once it is done; age alone does not make it history.
- progress: `## Status`, `## What works`, `## In progress`,
  `## What's left to build`, `## Known issues`.

**Rotatable units**, oldest first (banks are newest-first, so oldest is last):

- activeContext: an entire `## Recent changes (<suffix>)` section — the
  heading travels with its body — or a top-level bullet (a line starting
  with `-`) with its continuation lines under an unsuffixed `## Recent changes`.
  The newest dated section is the exception: its heading stays live as the
  pointer's home and is *copied* into the archive (the helper reports it
  as `ARCHIVE-PREFIX`).
- progress: a top-level bullet under `## Recent milestones`.
- Any other structure is left untouched and reported as remaining overage.

**Rotation is lossless.** Selected units move verbatim to
`<effective bank>/archive/<file>-<YYYY-MM>.md` (append, or create with a
one-line header), and the live file keeps one pointer line,
`Older entries: archive/<file>-*.md`, directly under the first
`## Recent ...` heading. If protected content alone exceeds the target,
report it and rotate nothing further — never truncate current state.
Rotating again with nothing rotatable is a no-op.

**Mechanism.** `hooks/lib/rotate-check.sh <file> <activeContext|progress>`
is read-only: it measures a file, lists rotatable units as line ranges,
predicts the result of rotating the fewest oldest units that meet the
target, and ends with `RESULT: NO-OP`, `RESULT: ROTATE n`, or
`RESULT: OVERAGE-REMAINS`. `/update-memory` and `$update-memory` must run it
on the *proposed* files, fold any `ROTATE n` into the same confirmation as
the content diffs, and re-run it after writing. The approval gate is
unchanged — the helper selects, the user approves, the agent writes.

**Archives are not routine reads.** `archive/` is excluded from the session
read list, `/start`, `/update-memory`, `/handoff`, and both hooks. Read an
archive only when the task needs that history.

## Drift check

`bin/serel-memory check [--scope <path>] [--root <repo_root>]` is a read-only,
offline pass over the effective bank in the resolved scope. It exists because
"is the bank still true?" is the one question an agent should never answer
about its own writing. The checker answers only the part a machine can settle,
and says plainly which part it left alone.

**Findings.** One line each, `<KIND> <location> <message>`. The location is a
repo-relative path — `<file>:<line>` when the finding is about one line, plain
`<file>` when it is about the whole file — or `repo` for a repository-wide
finding:

- `DRIFT` — the repo contradicts the bank: a missing core file, a file that
  still holds only template placeholders, a framework file present in the
  anchor baseline but absent here, a leftover pre-0.3.0 anchor.
- `STALE` — a bank line declared evidence and that evidence has moved.
- `INCOMPLETE` — an assessment could not be made: no `jq`, an anchor that does
  not parse, a marker naming an unknown revision or a path that is not at
  `HEAD`, evidence dirty in the worktree, a degraded scope resolver.
- `WARN` — a soft target is exceeded (retention). Exit-neutral.
- `INFO` — context, never a verdict: overlay gaps, unmarked bullets, framework
  files that differ from the baseline, no local baseline to compare against.

Then exactly one summary line:
`serel-memory check: <d> drift, <s> stale, <i> incomplete, <w> warn, <f> fresh,
<u> unmarked, baseline: <ref|unavailable> — exit <code>`.

**Exit contract.** Any `INCOMPLETE` → 2; else any `DRIFT` or `STALE` → 1; else
0. `WARN` and `INFO` never change the exit code. An assessment that could not
finish outranks one that finished badly: a checker that cannot see is more
dangerous than one that reports drift.

**Evidence markers.** A bank line may declare what it rests on:

```text
- The renderer renders widgets (verified: <sha> <path> [<path>...])
```

One line, outside fenced code, optionally wrapped in parentheses. Every marker
on a line is read. A revision written as a placeholder in angle brackets —
`verified: <sha> <path>` — is the syntax being described rather than a claim
being made, and is skipped: a bank is free to document this feature. Paths are whitespace-separated and resolve against the scope
root first, then the repo root; a tracked directory is valid evidence. The
syntax has no quoting or escaping, so a path cannot contain a space, and `)`
always ends the marker — rename such a path or leave the claim unmarked rather
than trying to escape it. The checker reports `declared evidence unchanged` or
`declared evidence differs since <sha>` — never "verified" or "true". A marker
inside a fenced block is documentation, not a claim.

**What is NOT assessed.** Whether a bank line is *true*; whether an unmarked
bullet is still accurate. Unmarked bullets are counted — top-level `-`, `*`, or
`+` bullets under `## What works` and `## Recent milestones` in `progress.md`,
the two recognized sections, not the whole bank — and that count is the honest
measure of what the check does not cover. Nothing requiring the network is
assessed: the framework baseline is compared only when the anchor's `ref`
already resolves locally (a clone or fork carrying the upstream tags, or a
private `refs/serel-memory/anchor` left behind by an interrupted sync — a
completed `sync-upstream` deletes that ref). Otherwise the summary says
`baseline: unavailable` rather than quietly skipping the comparison.

**A failed check is never a clean one.** Every subprocess status is checked; a
command that fails becomes `INCOMPLETE`, and the summary line prints even when
the run aborts.

`/start` and `/update-memory` run the checker when it is present and report its
summary line. It never blocks either workflow.
