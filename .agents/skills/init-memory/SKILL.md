---
name: init-memory
description: "Initialize memory-bank files by analyzing an existing codebase. Use when the memory bank has been added to a repo with code already present and the memory-bank files are blank or template-only."
---

# Init Memory

Use this skill when Serel Memory has been dropped into an existing project and the memory bank is still uninitialized.

**Effective bank:** if `memory-bank.local/` exists (upstream Serel Memory development only), it is the working bank — the uninitialized check and any proposed writes target it, not the tracked starter templates. See "Resolving the effective bank" in `docs/workflow-contract.md`.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Map the repo structure with fast shell tools. Skip `node_modules/`, `.git/`, `dist/`, and `build/`.
2. Read `README.md` and relevant docs for stated purpose, setup, and architecture.
3. Read package manifests such as `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or `Gemfile`.
4. Skim the source tree enough to understand component boundaries. Do not read every file unless needed.
5. Run `git log --oneline -20` and `git branch -a`.
6. Propose contents for each memory-bank file in this order:
   - `projectbrief.md`
   - `productContext.md`
   - `systemPatterns.md`
   - `techContext.md`
   - `decisionLog.md`
   - `activeContext.md`
   - `progress.md`

For each file, use this format:

```text
FILE: memory-bank/<name>.md
PROPOSAL:
<proposed contents, preserving the file's heading structure>

CONFIDENCE: high / medium / low
REASONING: <one or two lines on evidence>
QUESTIONS FOR USER: <anything that cannot be inferred>
```

After all proposals, stop and wait. Do not write anything until the user approves or revises.

## Rules

- If something cannot be inferred from code/docs/history, say so.
- Prefer terse and accurate over comprehensive and speculative.
- Treat code as the source of truth for current behavior.
- Treat the memory bank as the source of truth for intended behavior once initialized.
