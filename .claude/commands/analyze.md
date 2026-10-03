---
description: Audit memory accuracy against repository evidence without editing files
---

# /analyze

Audit the selected memory bank against repository evidence. This is an
on-demand accuracy review; routine `update-memory` captures and reconciles
subjects changed during a session. Use this workflow when asked whether
existing memory is accurate, stale, unsupported, or missing durable facts.

Invoke as `/analyze [topic] [--scope <path>]`.

## Scope and required reads

Resolve exactly one scope per **Resolving scope** in
`docs/workflow-contract.md`: explicit `--scope` (`.` is root), else cwd,
else root. Invalid selectors stop and list valid selectors. At root, audit
the root bank only; do not open child banks. Read inherited root rules at a
project scope without auditing or changing another scope's bank.

**Effective bank:** within that scope use `memory-bank.local/` and its
`.rules` when present; otherwise use `memory-bank/` and the scope's `.rules`.
A maintainer overlay is partial: missing core files get intent from
`README.md`/`docs/`, never from the blank tracked templates behind it.

1. Read the contract's **Memory accuracy** and **Accuracy audit** sections.
2. Read the effective bank's `projectbrief.md`, `productContext.md`,
   `systemPatterns.md`, `techContext.md`, `decisionLog.md`, `activeContext.md`,
   `progress.md`, then its rules. A normal bank with missing, empty, or
   template-only core files is uninitialized: name them and stop; suggest
   discover, init-memory, or from-prd as appropriate. Do not seed it here.
3. Inspect recent git history and working-tree status, including staged,
   unstaged and relevant untracked files. Inspect source, manifests and test
   definitions needed to assess the selected subjects. Do not assume an
   implementation is committed, released or tested because it exists locally.
4. With a topic, inspect claims about that topic across the live bank and
   relevant optional docs. Without one, bound the audit to current status in
   `progress.md`, focus/checkpoint/next steps in `activeContext.md`, pending
   or accepted decisions, and current setup facts in `techContext.md`.
   Other files supply intent; report other claims as outside coverage.
   Skip archives unless a specific finding needs historical evidence.
5. Read optional docs only for those subjects. A verification map's Recipe
   is a procedure, not a result. Records describe a particular revision and
   environment; changed paths or missing artifacts limit their relevance.
   Never execute a recipe or infer a fresh pass from an old record.
6. If the checker exists, run it for this scope and retain its exit code and
   summary separately from semantic findings:

   ```bash
   "$(git rev-parse --show-toplevel)/bin/serel-memory" check --scope <resolved scope>
   ```

   Report an absent checker or failed assessment explicitly. Exit 2, including
   dirty evidence paths, means incomplete assessment, not proven drift. Do not
   stash or edit files to make the checker pass. Its exit 0 does not certify
   the accuracy of prose.

## Assessment

Apply **Memory accuracy**: classify each disputed claim as current fact,
durable decision, intended future, or open question before recommending action.
Code can establish a current implementation without overruling accepted intent.
An unbuilt plan and a dated historical statement are not stale current facts.

Report evidence-backed findings as **documentation drift**, **possible
regression**, **missing evidence**, or **missing durable information**.
Missing code alone does not prove a claim false; narrow the conclusion to what
was inspected. Recheck in-scope external capability claims against a primary
source with version/date, or mark them unassessed. Do not invent missing work
or decisions, erase history, or recommend making intent match a possible bug.
Keep unsupported claims unverified or request evidence; do not convert them
into targets or decisions without owner intent. Say implemented or committed
when that is all the evidence shows; reserve released/shipped for release evidence.

## Allowed writes and stop conditions

None. Do not edit bank, code, rules, evidence markers, or checkpoints; do not
run tests, builds, verification recipes, installs, fetches, or another agent.
Read-only source inspection is not a test run. Report access failures,
conflicting evidence, and owner decisions needed; do not guess to finish.

## Output

Start with the scope, effective bank, inspected subjects, HEAD and working-tree
state, then the deterministic check's exit code and summary (or unavailable).

For each finding, give:

- **Kind and impact:** one of the four finding kinds, and why it matters.
- **Claim:** exact bank path/line or section and a short quotation, plus its
  fact/decision/intent/question classification. For missing information, name
  the owning bank section and the evidenced omission instead of inventing a quote.
- **Evidence:** source path/line, commit/diff, observed result, or primary-source
  link with version/date. Distinguish inspected tests from tests actually run.
- **Recommended action:** a proposed factual correction, a missing entry, a
  verification step, or an owner decision about a possible regression.
- **Limits:** what the evidence cannot establish.

End with **Coverage and unassessed areas**, including unresolved evidence and
decisions. If there are no findings, say "No discrepancies found within the
inspected subjects," not "the bank is accurate." No score or semantic CI verdict.
Offer `/update-memory` for a separate, reviewed bank update; do not invoke it or
write the corrections automatically. Possible regressions need an owner
decision before intent or code changes.
