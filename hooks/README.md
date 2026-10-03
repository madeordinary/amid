# Serel Memory hooks

These hooks automate part of Serel Memory's workflow. They're **off by default** — you opt in per project.

## What's here

| File | Event | What it does |
|------|-------|--------------|
| `session-start.sh` | `SessionStart` | Reads the memory bank + `.rules` + recent git activity and injects it as session context. Replaces typing `/start`. |
| `pre-compact.sh` | `PreCompact` | Reminds the agent to refresh `activeContext.md`, `progress.md`, and `decisionLog.md` before Claude Code compacts context. Replaces remembering `/update-memory`. |
| `enable-hooks.sh` | n/a | One-shot script that registers Claude Code hooks in `.claude/settings.json`. |
| `enable-codex-hooks.sh` | n/a | One-shot script that registers the Codex `SessionStart` hook in `.codex/hooks.json`. |
| `lib/resolve-scope.sh` | n/a | Read-only scope resolver shared by both hooks and the tests: picks the one bank an invocation targets (`--scope <path>`, else cwd, else root) and lists project banks. Single-bank repos always resolve to the root. |
| `lib/rotate-check.sh` | n/a | Read-only retention helper used by `/update-memory` and the pre-compact reminder: measures `activeContext.md` / `progress.md` against the contract targets and lists which old entries would rotate to `memory-bank/archive/`. It never writes. |

## Enable Claude Code Hooks

```bash
bash hooks/enable-hooks.sh
```

Idempotent — safe to re-run. Requires `jq` for the JSON manipulation; if jq isn't installed, the script prints the settings.json block for you to paste manually.

After enabling, hooks fire on every Claude Code session in this project. No extra steps.

## Enable Codex Hooks

```bash
bash hooks/enable-codex-hooks.sh
```

This writes `.codex/hooks.json` with a `SessionStart` hook that runs `hooks/session-start.sh`. Codex project hooks require review; open `/hooks` in Codex to inspect and trust the hook.

## Disable

**Temporarily** (current shell only):

```bash
export SEREL_MEMORY_HOOKS=off
```

Both scripts exit early when `SEREL_MEMORY_HOOKS` is `off`.

**Permanently**: remove the Serel Memory entries from `.claude/settings.json` or `.codex/hooks.json`. Or delete the whole `hooks` object if you don't use any other hooks.

## When to enable

Enable on projects where:

- You come back to the project across many sessions
- Memory continuity matters more than ceremony
- You'd rather not type `/start` and `/update-memory` every time

Keep them off for:

- Quick exploratory hacking where the bank is overhead
- Throwaway scripts
- Projects where you specifically want the discipline of running the commands manually

## How they work

Claude Code and Codex both let you run shell commands at specific lifecycle events. Output from the session-start hook is added to the model's context.

- `session-start.sh` runs once per Claude Code session, just after the agent boots. Its stdout becomes additional context alongside the project's agent instructions (`AGENTS.md`, or a compatibility import; see the root README).
- `pre-compact.sh` runs before context compaction (which happens automatically when context fills up or when the user runs `/compact`). Its stdout becomes the instruction the agent acts on during compaction.

The scripts read `$CLAUDE_PROJECT_DIR` when Claude Code sets it. If it's not set, they fall back to `$PWD`; the Codex installer runs the hook from the git root so the same script works there too.

## Codex CLI

Codex uses its own hook system. `enable-codex-hooks.sh` registers only `SessionStart`, because Codex does not have Claude Code's `PreCompact` event. For memory refreshes, use the `$update-memory` skill manually before ending long sessions.

## Customizing

These are bash scripts. Open them, change them. Add your own hooks. If you write a hook that's useful enough that it belongs in Serel Memory, send a PR.
