---
name: polish
description: "Rewrite text to the project's house rules and show the diff, without writing anything. Use when the user asks to polish, tighten, clean up, de-slop, or plain-language a file, a section, a PR description, release notes, or pasted prose."
---

# Polish

Rewrite prose so a reader gets the facts faster. This skill proposes a rewrite
and stops. It writes no files.

Invoke it as `$polish <target>`, where the target is a path, a path plus a
heading, or text the user pastes. `--scope <path>` selects which bank the
target lives in, when the target is bank content.

## Trigger

Use it on prose someone has to act on: a memory bank entry, a PR description,
a README section, release notes, a handoff, a decision record, a commit body.

Do not use it on code, on generated files, or on text the user cannot change.
It is not a review: it changes how a claim reads, never whether it is true.

## Required reads

1. `RULES.md` next to this skill (`.agents/skills/polish/RULES.md`) — the
   house rules. Read the whole file on every run, not from memory.
2. The target. If the user named a heading, read the whole file first so you
   can see what that section is allowed to assume.
3. For a memory bank file, read `docs/workflow-contract.md` "Retention" when
   the repo has it. It names the structure that is load-bearing.

## When the target is memory bank content

`$polish` works on any prose, with or without Serel Memory. But when the
target is bank content — a file under `memory-bank/` or `memory-bank.local/`,
`.rules`, or a bare name that matches one of them — work out *which* bank
first, exactly as `docs/workflow-contract.md` says. Polishing the wrong copy
of `activeContext.md` is worse than not polishing it.

1. **Resolve the scope** ("Resolving scope"). `--scope <path>` selects it and
   `.` is the repo root; otherwise the project root the current directory sits
   in; otherwise the repo root. Exactly one scope per invocation, never a
   remembered one. A `--scope` that is not a project root stops the skill with
   the list of valid selectors.
2. **Resolve the effective bank** ("Resolving the effective bank"). Inside
   that scope root, `memory-bank.local/` is the effective bank when it exists,
   otherwise `memory-bank/`. Read and diff the file in the effective bank, not
   its counterpart in the other one.
3. **Stop if the target is not there to polish.** When the effective bank is
   a `memory-bank.local/` overlay and the requested file is not in it, stop and
   say the file is not in the overlay. The overlay is partial by design, so
   that is not an uninitialized bank — and the tracked starter template behind
   it is not the file you were asked to polish, so never fall back to it. When
   the effective bank is a plain `memory-bank/` and the requested file is
   missing, empty, or still only template placeholders, stop, name it, and
   point at `$discover` (no code yet), `$init-memory` (code exists), or `$from-prd`
   (a spec exists). Never create or seed a bank.

Ordinary prose — a PR body, a README, release notes, pasted text — skips all
of this, and so does a repo with no `.serel-memory.json`. The rest of the
workflow is identical either way.

## Allowed writes

None. The skill ends after it prints the diff. Applying the rewrite is a
separate request the user makes afterwards.

## Preserve

A rewrite that drops any of these has failed, however much shorter it is:

- Meaning, and every qualification the author put there ("on macOS only",
  "we think", "not yet measured").
- Unresolved questions. They stay open and stay questions.
- Decision status and supersession links — `Accepted`, `Superseded by
  ADR-014`, dates, `result: pending`.
- Evidence pointers: paths, line numbers, commit SHAs, ticket ids, links.
- Literal commands, paths, code, error strings, and every fenced code block.
  Fences pass through untouched.
- Retention-significant structure in memory bank files: `## Recent changes`
  headings with their dated suffixes, `## Recent milestones`, the
  `Older entries: archive/...` pointer lines, and entry order. Serel Memory's
  retention step reads these.
- Headings, list nesting, and anchors other files link to.

## Workflow

1. Resolve the target. If it is bank content, resolve the scope and the
   effective bank first (above). If the name matches more than one file, stop
   and list the matches.
2. Read the rules, then the target.
3. Rewrite. Apply the rules in order; skip any rule that would cost a fact.
4. Diff your rewrite against the original.
5. Print the output below and stop.

## Output contract

```text
POLISH: <target> - <n> change(s)

<a unified diff of the proposed rewrite>

WHY: <one line per change, keyed to a rule number>
KEPT: <one line per thing deliberately left alone, and why>
```

- The diff is the proposal: real hunks with context, not a retyped file.
- `WHY` cites rule numbers, for example `3, 6 - split the compound sentence,
  cut "it is worth noting"`.
- `KEPT` is required. It is how the user checks that no qualification was
  quietly dropped. Write `KEPT: nothing notable` if that is the truth.
- End with the line `Nothing was written.` and stop. Do not offer to apply
  it, ask a follow-up, or summarize the file.

If the text already follows the rules, print `POLISH: <target> - 0 changes`
plus one line on why it is fine. No change is a real answer.

## Stop conditions

Stop and ask before producing a diff when:

- The named file or heading does not exist.
- The name matches several files.
- A faithful rewrite would need a fact you cannot check. Quote the sentence
  and ask.
- `--scope` was given and does not name a project root. List the valid
  selectors and stop; never fall back to a different bank.
- The rewrite would change what the text claims. That needs the author.
