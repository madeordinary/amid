# Approved Serel setup write plan

Historical installation record: the original setup and bank seeding completed locally. The later owner-approved privacy policy keeps all `memory-bank/` files and seed proposals local and ignored; those paths in the original write list below are not included in public clones. Reusable workflows remain tracked. `AGENTS.md` now includes a project-specific public-checkout fallback; upstream skill/command payloads and installer receipts remain unchanged. See [repository hygiene](repository-hygiene.md).

Scope: project root. Stage: PRD, no code. Bank: absent. Memory v0.6.0, Kit v0.2.0 writing and verify; shared Git-visible files; native Claude and Codex adapters; hooks off. User advance authorization: GOAL.md. No existing project workflows or same-path collisions. Preserve all five input documents.

Installed specialized security workflows are complementary to general Serel reviews; keep both and preserve stricter safety constraints. Project-local Serel is primary for memory and feature verification. No global workflow changes.

Guide: Memory a407c994355cec892c061ceb9f247d359aae0a57; installed release: 5f99244d648735db94429bf4e77571325160e5ec. Kit guide: 0cb870dfe76489717a50353ddf898f33bfba73c1; installed release: a4b7b29b9b80e72294e601da2c264f8a9082a795. Unreleased guided routing/local installer are not installed.

## Exact expected writes (all Git-visible except .git)

- `.agents/skills/analyze/SKILL.md`
- `.agents/skills/analyze/agents/openai.yaml`
- `.agents/skills/ask-claude/SKILL.md`
- `.agents/skills/ask-claude/agents/openai.yaml`
- `.agents/skills/breakdown/SKILL.md`
- `.agents/skills/breakdown/agents/openai.yaml`
- `.agents/skills/decision-log/SKILL.md`
- `.agents/skills/decision-log/agents/openai.yaml`
- `.agents/skills/discover/SKILL.md`
- `.agents/skills/discover/agents/openai.yaml`
- `.agents/skills/from-prd/SKILL.md`
- `.agents/skills/from-prd/agents/openai.yaml`
- `.agents/skills/handoff/SKILL.md`
- `.agents/skills/handoff/agents/openai.yaml`
- `.agents/skills/init-memory/SKILL.md`
- `.agents/skills/init-memory/agents/openai.yaml`
- `.agents/skills/polish/RULES.md`
- `.agents/skills/polish/SKILL.md`
- `.agents/skills/polish/agents/openai.yaml`
- `.agents/skills/retro/SKILL.md`
- `.agents/skills/retro/agents/openai.yaml`
- `.agents/skills/review/SKILL.md`
- `.agents/skills/review/agents/openai.yaml`
- `.agents/skills/risk-review/SKILL.md`
- `.agents/skills/risk-review/agents/openai.yaml`
- `.agents/skills/runbook/SKILL.md`
- `.agents/skills/runbook/agents/openai.yaml`
- `.agents/skills/security-check/SKILL.md`
- `.agents/skills/security-check/agents/openai.yaml`
- `.agents/skills/ship/SKILL.md`
- `.agents/skills/ship/agents/openai.yaml`
- `.agents/skills/start/SKILL.md`
- `.agents/skills/start/agents/openai.yaml`
- `.agents/skills/sync-upstream/SKILL.md`
- `.agents/skills/sync-upstream/agents/openai.yaml`
- `.agents/skills/update-memory/SKILL.md`
- `.agents/skills/update-memory/agents/openai.yaml`
- `.agents/skills/verify-map/SKILL.md`
- `.agents/skills/verify-map/TEMPLATE.md`
- `.agents/skills/verify-map/agents/openai.yaml`
- `.agents/skills/weekly-update/SKILL.md`
- `.agents/skills/weekly-update/agents/openai.yaml`
- `.claude/commands/analyze.md`
- `.claude/commands/ask-codex.md`
- `.claude/commands/breakdown.md`
- `.claude/commands/decision-log.md`
- `.claude/commands/discover.md`
- `.claude/commands/from-prd.md`
- `.claude/commands/handoff.md`
- `.claude/commands/init-memory.md`
- `.claude/commands/polish.md`
- `.claude/commands/retro.md`
- `.claude/commands/review.md`
- `.claude/commands/risk-review.md`
- `.claude/commands/runbook.md`
- `.claude/commands/security-check.md`
- `.claude/commands/ship.md`
- `.claude/commands/start.md`
- `.claude/commands/sync-upstream.md`
- `.claude/commands/update-memory.md`
- `.claude/commands/verify-map.md`
- `.claude/commands/weekly-update.md`
- `.git/ (local Git metadata only)`
- `.rules`
- `.serel-kit.json`
- `.serel-memory.json`
- `AGENTS.md`
- `LICENSES/Serel-Kit.txt`
- `LICENSES/Serel-Memory.txt`
- `bin/serel-memory`
- `docs/cross-agent-review.md`
- `docs/implementation-plan.md`
- `docs/serel-installation.md`
- `docs/serel-seed-proposal.md`
- `docs/workflow-contract.md`
- `hooks/README.md`
- `hooks/enable-codex-hooks.sh`
- `hooks/enable-hooks.sh`
- `hooks/lib/resolve-scope.sh`
- `hooks/lib/rotate-check.sh`
- `hooks/pre-compact.sh`
- `hooks/session-start.sh`
- `memory-bank/activeContext.md`
- `memory-bank/decisionLog.md`
- `memory-bank/productContext.md`
- `memory-bank/progress.md`
- `memory-bank/projectbrief.md`
- `memory-bank/systemPatterns.md`
- `memory-bank/techContext.md`
