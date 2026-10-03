# Project Agent Instructions

Amid uses Serel Memory for private local continuity. The entire `memory-bank/` directory is gitignored and is intentionally absent from public clones. Keep session checkpoints, coordination notes and working verification maps local. Publish reusable architecture, decisions and testing guidance in reviewed `docs/` files; do not copy the working bank into public docs. `PRD.md` defines product scope, and code plus observed evidence define what currently works.

## At the start of every session

If a local memory bank exists, read these files in order before work:

1. `memory-bank/projectbrief.md` — what we're building and why
2. `memory-bank/productContext.md` — the user problem and UX goals
3. `memory-bank/systemPatterns.md` — architecture and design decisions
4. `memory-bank/techContext.md` — stack, constraints, dependencies
5. `memory-bank/decisionLog.md` — durable decisions and ADR index
6. `memory-bank/activeContext.md` — current focus (most important)
7. `memory-bank/progress.md` — what works, what's broken
8. `.rules` — project-specific patterns and preferences

For a public clone without a bank, read `README.md`, `PRD.md`, `GOAL.md`, `.rules`, `docs/requirements.md` and the relevant architecture or testing docs instead. Use `docs/storage-design.md`, `docs/action-safety.md`, `docs/phase0-collectors.md` and `docs/release-gates.md` as applicable. No private bank is required to build, test or contribute.

Then read the last 5–10 git commits for recent context (or all available commits in a shorter history).

If the task clearly touches a specific feature, integration, deployment path, testing strategy, or API, look for relevant optional docs under `memory-bank/` and read only the ones that apply. `memory-bank/archive/` holds rotated history — never part of the session read; open it only when a task needs that history.

If an existing local bank is incomplete or contains only placeholders, note that before relying on it and use the public documents for unaffected work. Before invoking a workflow that requires a complete bank, resolve the missing context or initialize it under the user’s approved scope with `/init-memory` (code exists) or `/from-prd` (a spec exists). Do not treat the deliberately absent bank in a public clone as an error or require contributors to retrieve private files. Keep any new bank gitignored.

Tip: `bash hooks/enable-hooks.sh` registers an optional SessionStart hook that auto-loads the bank so you don't need `/start` every session (see `hooks/README.md`).

### Scoped banks (optional)

A repo that hosts several initiatives may list project folders under `"scopes"` in `.serel-memory.json`. Then each project root carries its own full bank and `.rules`, and every workflow resolves exactly one scope per invocation: `--scope <path>` (`.` = root), else the current directory, else the root — never a remembered choice. Read one bank, write one bank; at the root, only list the project selectors. Rules: "Resolving scope" in `docs/workflow-contract.md`. Without `scopes`, nothing changes.

### Maintainer overlay (upstream Serel Memory development only)

If a `memory-bank.local/` directory exists, you are working on the upstream Serel Memory repo itself. That directory is the real working bank (gitignored, never shipped), and it **is** the effective bank:

- Read files from `memory-bank.local/` instead of `memory-bank/`, and `memory-bank.local/.rules` instead of root `.rules`.
- The overlay is partial by design. For core files it doesn't contain (projectbrief, productContext, systemPatterns, techContext), `README.md` and `docs/` carry project intent — do not flag the blank tracked templates as uninitialized.
- Write session state (activeContext, progress, decisionLog, rules) only to the overlay. The tracked `memory-bank/` and `.rules` are clean starter templates shipped downstream and are guarded by tests — never write maintainer state to them.

Downstream projects never have this directory; everything else in this file refers to the effective bank.

## While working

The bank maintenance rules below apply when a local bank is in use. Public contributions must remain understandable from tracked source and curated documentation.

- Keep `activeContext.md` honest as the focus shifts during the session.
- For work that spans sessions, keep a `## Checkpoint` section in `activeContext.md` current: one resumable state (branch, what's done, the exact next step). Overwrite it, don't append; clear it when the work ships.
- When you discover a non-obvious pattern or user preference, append it to `.rules`.
- Before significant work, propose a plan and wait for confirmation. Once a plan or scope is approved, work autonomously inside that lane — no per-file re-asking; still stop for destructive actions, scope changes, outward-facing actions, and any approval gate a workflow itself defines (show-diffs-before-writing, per-file proposals).
- The memory bank is the source of truth for intent. If it conflicts with the actual code, the code is correct and the bank needs updating — flag this so the user can decide.

## Making changes

How code gets written in a session, not just how the bank is kept. For non-trivial changes — use judgment on obvious one-liners. (Inspired by Andrej Karpathy's observations on LLM coding pitfalls and `multica-ai/andrej-karpathy-skills`, MIT.)

- **Think before coding.** Don't assume — surface assumptions; if a request has more than one reasonable interpretation, present them instead of silently picking; push back when a simpler path exists; stop and ask when something is unclear.
- **Simplicity first.** Write the minimum that solves the problem — no speculative features, abstractions for single-use code, unrequested config, or error handling for impossible cases. Test: would a senior engineer call this overcomplicated?
- **Surgical changes.** Touch only what the task needs; don't refactor or reformat adjacent code; match existing style even if you'd do it differently; mention unrelated dead code rather than deleting it. Test: every changed line traces to the request. One exception — fix the class, not just the instance: when your fix repairs one occurrence of a defect that repeats at sibling sites, sweep for the siblings and fix or explicitly rule out each, bounded to the same demonstrated root cause and the same safe fix; anything broader is a scope change to surface first.
- **Goal-driven execution.** Turn the task into a verifiable goal and loop until it's met — e.g. "fix the bug" → "write a failing test, then make it pass." Strong success criteria let you work independently; weak ones ("make it work") force constant clarification. Judge gates (tests, typecheck, lint, build) by exit code, not by scanning their output for success strings — grepping can pass a failing check.

## When the user says "update memory bank"

Refresh every file in `memory-bank/`. Focus especially on `activeContext.md`, `progress.md`, and `decisionLog.md` when decisions changed. Show diffs before writing.

## Available workflows

The `.claude/commands/` directory contains Claude Code slash commands, and `.agents/skills/` contains Codex-native skills for core Serel Memory workflows:

- `/start` / `$start` — read the bank, summarize state, ask where to pick up (compact; use `/start full` for rich onboarding dashboard)
- `/discover` / `$discover` — help the user define a project from a rough idea; produces initial memory bank (use when starting fresh with no code yet)
- `/from-prd` / `$from-prd` — seed the memory bank from an existing PRD, product brief, spec, or requirements doc
- `/init-memory` / `$init-memory` — analyze the codebase and propose initial memory bank contents (use when bank is empty but code already exists)
- `/breakdown` / `$breakdown` — break a task into steps before executing
- `/review` / `$review` — code review the current branch or diff
- `/update-memory` / `$update-memory` — refresh the memory bank from this session's work
- `/analyze` / `$analyze` — read-only audit of memory claims against code and evidence
- `/weekly-update` / `$weekly-update` — stakeholder-ready weekly update from the bank and recent activity
- `/retro` / `$retro` — sprint or weekly retrospective drawing from progress and git log
- `/risk-review` / `$risk-review` — surface risks not yet documented in the bank
- `/decision-log` / `$decision-log` — record an architectural decision in ADR format
- `/handoff` / `$handoff` — generate a handoff doc for someone picking up the project cold
- `/ask-codex` / `$ask-claude` — ask the other CLI for an optional second opinion on plans, risks, and decisions
- `/ship` / `$ship` — pre-merge checklist
- `/sync-upstream` / `$sync-upstream` — check the upstream Serel Memory repo for framework updates and selectively pull changes
- `/runbook` / `$runbook` — generate or update an operational runbook
- `/security-check` / `$security-check` — OWASP + STRIDE pass on the current change

If a workflow does not yet have a Codex skill, read the corresponding `.claude/commands/<name>.md` file as guidance for the action.

## Cross-agent planning

For **high-impact or hard-to-reverse plans** — architecture changes, security or auth, data migrations, public API or schema changes, dependency choices — a second opinion from the other agent CLI is recommended before you implement:

- **In Claude Code**: shell out to `codex exec --cd "$PWD" --sandbox read-only - < prompt-file` for a read-only Codex review.
- **In Codex**: shell out to `claude -p --permission-mode plan < prompt-file` for a read-only Claude review.
- Write the prompt to a temp file first and pipe it via stdin — long inline prompts can hang `codex exec`.

First check whether the other CLI is installed (`codex --version` / `claude --version`). If it is, get the review and present both the plan and the second opinion to the user. If it isn't, don't block — do a local self-critique instead and label it clearly (e.g. "Self-Critique — Codex unavailable") so the user knows no independent review happened. Never pretend the other agent reviewed it.

For routine multi-file changes the review is optional — use judgment; it's a tool, not a tax. The `/breakdown` and `$breakdown` workflows offer it automatically.

See `docs/cross-agent-review.md` for the output contract, loop policy, and CLI preflight.

## Ground rules

- Don't assume project context unsupported by the PRD, public documentation or an initialized local bank. Ask when a material ambiguity remains.
- Don't overwrite memory bank files silently. Show diffs first.
- Don't bloat the bank — it's signal, not journal. One-offs don't belong.
- Code is the source of truth for what currently works. The bank is the source of truth for what we *meant* to build.
- For high-impact or hard-to-reverse work, consider a cross-agent second opinion on the plan (see above).
