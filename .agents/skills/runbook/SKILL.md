---
name: runbook
description: "Generate or update an operational runbook for a service or change. Use when the user asks for a runbook, ops doc, on-call guide, or deployment documentation."
---

# Runbook

Produce an operational runbook entry for the service or change being made. This is for the person on-call at 3am, not the developer who already knows the codebase.

**Scope:** resolve which bank this targets per "Resolving scope" in `docs/workflow-contract.md` — an optional `--scope <path>` argument selects a project bank when the repo configures `scopes`; otherwise the root bank, as always.

## Workflow

1. Determine the target:
   - If the user named a specific service, use that.
   - Otherwise, infer from the current branch or changes — what's being deployed?
2. Read relevant code, deploy config, and `memory-bank/techContext.md` for stack/hosting context.
3. If a runbook already exists at `docs/runbooks/<service>.md`, read it and propose updates as a diff.

## Output

```text
# Runbook: [service name]

## What this is
[one paragraph — what does this service do, who depends on it]

## Where it runs
- Hosting: [e.g., AWS App Runner, Render, ECS]
- Region(s):
- Deploy method: [e.g., GitHub Actions → ECR → App Runner]
- Repo / branch:

## How to run it locally
[clone, install, env, start — exact commands]

## How to deploy
[steps, prerequisites, who can press the button]

## Health & monitoring
- Healthcheck URL:
- Logs: [where, how to tail — exact commands]
- Metrics dashboard:
- Alerts: [what fires, where it goes]

## Common failure modes
| Symptom | Likely cause | Diagnose | Fix |
|---------|--------------|----------|-----|
|         |              |          |     |

## Rollback procedure
[exact steps to roll back the last deploy, with commands]

## Who to page
[on-call rotation or contact for ownership questions]

## Recent changes
[link to last few deploys / changelog entries]
```

Save to `docs/runbooks/<service>.md`. Create the directory if needed.

## Rules

- Be specific. "Check the logs" is useless. `aws logs tail /aws/apprunner/foo --follow | grep ERROR_TIMEOUT` is a runbook.
- Don't invent details. If you don't know the on-call rotation, write `<TBD>` rather than guessing.
- Failure modes need a real diagnose step, not just "investigate."
