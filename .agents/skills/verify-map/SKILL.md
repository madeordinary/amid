---
name: verify-map
description: "Create or refresh a feature's verification map in the memory bank: how to see the feature work by hand, and what someone actually saw. Use when the user asks for a verification map, a manual test recipe, a feature map, or how to prove a feature works."
---

# Verify map

Write down how to see one feature work with your own eyes, and what happened
the last time someone did. The result is one file in the memory bank that the
next session can follow.

Invoke it as `$verify-map <feature>`, optionally with `--scope <path>`.

## Trigger

Use it when a feature has no scripted way to prove it behaves — a UI flow, a
job that has to actually run, an integration you can only watch. Use it again
after verifying by hand, to record what was seen.

Do not use it instead of a test. If the behavior can be asserted in code,
write the test. A map is for what a test cannot reach.

## Required reads

1. Resolve the scope, then the effective bank (below). Everything else is
   relative to that bank.
2. `TEMPLATE.md` next to this skill
   (`.agents/skills/verify-map/TEMPLATE.md`) — the file shape. Read it every
   run; do not reproduce it from memory.
3. The existing `<effective bank>/verification/<feature>.md`, if any. A
   refresh edits that file; it does not start over.
4. `activeContext.md` and `progress.md` in the effective bank, for what the
   feature is and whether it currently works.
5. The code paths the feature lives in, plus the project README and any run
   scripts, so the Launch section contains commands that exist.

### Resolving scope

Follow "Resolving scope" in `docs/workflow-contract.md`: exactly one scope per
invocation, never a remembered one.

1. `--scope <path>` selects it. `.` is the repo root. A path that is not a
   project root stops the skill and lists the valid selectors.
2. Otherwise, if the current directory is inside a project root, that project.
3. Otherwise, the repo root.

A repo with no `scopes` key in `.serel-memory.json` has one bank at the root
and none of this applies.

### Resolving the effective bank

Follow "Resolving the effective bank" in `docs/workflow-contract.md`. Inside
the selected scope root: `memory-bank.local/` is the effective bank when it
exists, otherwise `memory-bank/`. Write only to the effective bank.

## Stop conditions

Stop before writing anything when:

- **There is no `.serel-memory.json`.** This skill targets a Serel Memory
  bank. Say so and stop.
- **The bank is uninitialized** — a plain `memory-bank/` whose core files are
  missing, empty, or still only template placeholders. Name the files and ask
  the user to seed the bank first: `$discover` with no code yet, `$init-memory`
  with code, `$from-prd` with a spec. Do not create the bank. One exception,
  straight from Memory's contract: a `memory-bank.local/` overlay is **partial
  by design**. Core files it does not carry are not an uninitialized bank —
  read `README.md` and `docs/` for the intent they would have held, do not flag
  the tracked templates behind them, and carry on.
- **`--scope` names something that is not a project root.** List the valid
  selectors and stop.
- **No feature was named.** List the maps already in
  `<effective bank>/verification/`, suggest candidates from the bank, and ask
  which. Never choose for the user.
- **The launch procedure is a guess.** Ask. A guessed command is worse than no
  map, because the next person will trust it.
- **You are being asked to record a run you did not observe.** Say what you
  can and cannot attest to, then ask for the observation.

## Allowed writes

Exactly one file: `<effective bank>/verification/<feature>.md`.

Nothing else — not `activeContext.md`, not `progress.md`, not `.rules`, not
the anchor. If the map turns up something those files should say, mention it
and leave it to `$update-memory`.

Serel Memory's rule applies: show the diff and wait for confirmation before
writing. A new file is shown as an **added-file diff** — the
`--- /dev/null` / `+++ b/<path>` header and every line prefixed with `+` — not
as a bare document body. The proposal then reads the same way whether the file
is new or being refreshed, and there is no way to mistake it for a file that
already exists.

## Workflow

1. Resolve scope and effective bank. Run the stop conditions.
2. Choose the filename: lowercase, hyphens, no spaces. "reset a forgotten
   password" becomes `reset-password.md`; the human name stays as the heading
   inside the file.
3. Read `TEMPLATE.md`, then the existing map if there is one.
4. Fill in the **Recipe**: Launch, Drive, Observe, Clean up. Every command
   comes from the repo or from the user. Every input is concrete.
5. Fill in **Records** only from what was actually observed. If this run is
   documentation only, leave the records alone and report the feature as
   unverified.
6. Refresh, do not rewrite: older records stay verbatim, the new one goes on
   top, Status and Paths update if they changed.
7. Show the diff — added-file form when the file is new — and ask for
   confirmation.
8. Write only after the user confirms, then print the path and stop.

## Output contract

```text
VERIFY-MAP: <feature> - <new | refreshed>
BANK: <effective bank path>
FILE: <effective bank>/verification/<feature>.md

<the diff: an added-file diff when the file is new, a unified diff on refresh>

RECORDS: <n> (newest <date>) | none - this feature is unverified
UNVERIFIED CLAIMS: <anything in the Recipe you could not confirm yourself>
```

Then ask "Write this file?" and stop until answered.

## What this is not

- A map is not a test. It never replaces running the tests, and a green map is
  not a green build.
- A missing map is not a product failure. It means nobody has written down how
  to check that feature yet.
- An empty Records section is not a bug. It is an honest "nobody has verified
  this."
