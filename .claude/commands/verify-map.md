---
description: Create or refresh a feature's verification map in the memory bank — how to see the feature work, and what someone last saw.
---

# /verify-map

Write down how to see one feature work with your own eyes, and what happened
the last time someone did. The result is a file in the memory bank that the
next session can follow.

Usage:

```text
/verify-map checkout
/verify-map "reset a forgotten password"
/verify-map checkout --scope projects/storefront
/verify-map                              # lists existing maps and asks
```

## Trigger

Use it when a feature has no scripted way to prove it behaves — a UI flow, a
job that has to actually run, an integration you can only watch. Use it again
after verifying by hand, to record what you saw.

Do not use it as a substitute for a test. If the behavior can be asserted in
code, write the test instead. A map is for what a test cannot reach.

## Required reads

1. Resolve the scope, then the effective bank (below). Everything else is
   relative to that bank.
2. `.agents/skills/verify-map/TEMPLATE.md` — the file shape. Read it every
   time; do not reproduce it from memory.
3. The existing `<effective bank>/verification/<feature>.md`, if there is one.
   A refresh edits that file; it does not start over.
4. `memory-bank/activeContext.md` and `memory-bank/progress.md` in the
   effective bank, for what the feature is and whether it currently works.
5. The code paths the feature lives in, enough to write a Launch section that
   runs. Read the project README and any run scripts before inventing a
   command.

### Resolving scope

Follow "Resolving scope" in `docs/workflow-contract.md`. In short: one scope
per invocation, never a remembered one.

1. `--scope <path>` selects it. `.` is the repo root. A path that is not a
   project root stops the workflow and lists the valid selectors.
2. Otherwise, if the current directory is inside a project root, that project.
3. Otherwise, the repo root.

A repo with no `scopes` key in `.serel-memory.json` has one bank at the root,
and none of this applies.

### Resolving the effective bank

Follow "Resolving the effective bank" in `docs/workflow-contract.md`. Inside
the selected scope root: if `memory-bank.local/` exists it is the effective
bank; otherwise `memory-bank/` is. Write only to the effective bank.

## Stop conditions

Stop before writing anything when:

- **There is no `.serel-memory.json`.** This workflow targets a Serel Memory
  bank. Say so and stop.
- **The bank is uninitialized** — a plain `memory-bank/` whose core files are
  missing, empty, or still only template placeholders. Say which files, and ask
  the user to seed the bank first: `/discover` if there is no code yet,
  `/init-memory` if there is, `/from-prd` if a spec exists. Do not create the
  bank yourself. One exception, straight from Memory's contract: a
  `memory-bank.local/` overlay is **partial by design**. Core files it does not
  carry are not an uninitialized bank — read `README.md` and `docs/` for the
  intent they would have held, do not flag the tracked templates behind them,
  and carry on.
- **`--scope` names something that is not a project root.** List the valid
  selectors and stop.
- **No feature was named.** List the maps already in
  `<effective bank>/verification/`, suggest candidates from the bank, and ask
  which one. Never pick for the user.
- **You cannot tell how to launch the thing.** Ask. A Launch section with a
  guessed command is worse than no map, because the next person will trust it.
- **The user is asking you to record a run you did not observe.** Say what you
  can and cannot attest to, then ask them for the observation.

## Allowed writes

Exactly one file: `<effective bank>/verification/<feature>.md`.

Nothing else. Not `activeContext.md`, not `progress.md`, not `.rules`, not the
anchor. If the map surfaces something those files should say, mention it and
let `/update-memory` handle it.

Serel Memory's rule applies: show the diff and wait for confirmation before
writing. A new file is shown as an **added-file diff** — the
`--- /dev/null` / `+++ b/<path>` header and every line prefixed with `+` — not
as a bare document body. The proposal then reads the same way whether the file
is new or being refreshed, and there is no way to mistake it for a file that
already exists.

## Steps

1. Resolve scope and effective bank. Run the stop conditions.
2. Pick the filename: lowercase, hyphens, no spaces —
   `reset a forgotten password` becomes `reset-password.md`. Keep the human
   name inside the file as the heading.
3. Read `TEMPLATE.md`, then the existing map if there is one.
4. Fill in the **Recipe**: Launch, Drive, Observe, Clean up. Every command
   must be one you found in the repo or one the user gave you. Every input
   must be concrete.
5. Fill in **Records** only from what was actually observed. If this run is
   documentation only, leave the records as they are and say the feature is
   unverified.
6. Refresh, don't rewrite: keep older records verbatim, add the new one on
   top, and update Status and Paths if they changed.
7. Show the diff — added-file form when the file is new — and ask for
   confirmation.
8. Write only after the user confirms. Then print the path and stop.

## Output contract

```text
VERIFY-MAP: <feature> — <new | refreshed>
BANK: <effective bank path>
FILE: <effective bank>/verification/<feature>.md

<the diff: an added-file diff when the file is new, a unified diff on refresh>

RECORDS: <n> (newest <date>) | none — this feature is unverified
UNVERIFIED CLAIMS: <anything in the Recipe you could not confirm yourself>
```

Then ask: "Write this file?" and stop until answered.

## What this is not

- A map is not a test. It never replaces running the tests, and a green map
  is not a green build.
- A missing map is not a product failure. It means nobody has written down how
  to check that feature yet.
- An empty Records section is not a bug. It is an honest "nobody has verified
  this."
