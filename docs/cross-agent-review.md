# Cross-Agent Review

Serel Memory supports optional second opinions between Claude Code and Codex through
their CLIs. This is intentionally a thin workflow, not a full orchestrator.

## Policy

- Reach for a review on high-impact or hard-to-reverse plans (architecture, security/auth, data migrations, public API or schema, dependency choices). For routine changes it's optional — it's a tool, not a tax.
- Check the other CLI exists first; if it doesn't, do a labeled local self-critique rather than blocking.
- Default to one read-only review.
- Don't pin the secondary CLI's model or effort flags, and don't hardcode model names in prompts or docs — inherit that CLI's own defaults so upgrades flow through without leaving stale claims behind.
- Use a loop only when the user explicitly asks for debate, back-and-forth, or a loop.
- Cap loops at 2 rounds by default.
- Cap at 3 rounds only when the user explicitly asks.
- The current agent owns synthesis and next steps.
- Never ask the secondary CLI to call back into the primary CLI.
- Do not edit files during the review loop.
- Do not pass secrets, credentials, private production data, or sensitive customer data.

## Output contract

When the secondary critiques a plan or proposal (an anchored review), it
should use:

```text
AGREEMENTS:
DISAGREEMENTS:
RISKS:
SUGGESTED CHANGES:
QUESTIONS:
VERDICT: APPROVE | REVISE | RETHINK
```

Pick exactly one. APPROVE means the plan is sound to proceed as written;
REVISE means there are fixable issues to address before proceeding; RETHINK
means the approach itself is wrong. The one-line verdict makes review
outcomes greppable and comparable across rounds. It describes this review
round only — it is not a plan lifecycle status, and it never overrides the
user's decision.

Blind generative touchpoints (a parallel code review, security pass, or bank
audit) return the calling workflow's own findings format instead — there is
nothing to agree or disagree with.

Loop synthesis should end with:

```text
FINAL SYNTHESIS:
- What both agents agree on
- What changed in the plan
- Remaining disagreements
- User decisions needed
- Recommended next step
```

## CLI preflight

Before shelling out, verify the target CLI exists and is authenticated enough to run:

- Claude: `claude --version` and, when useful, `claude auth status`
- Codex: `codex --version` and, when useful, `codex exec --help`

If the CLI is missing, blocked, or unauthenticated, say so and perform a local
critique instead. Do not pretend another model reviewed the work.

## Runtime stance

- Claude review from Codex: prefer `claude -p --permission-mode plan < prompt-file`.
- Codex review from Claude: prefer `codex exec --cd "$PWD" --sandbox read-only -` (prompt via stdin — see Canonical invocation below).
- Treat sandboxing and plan mode as defense in depth. The prompt still must say
  not to edit files or run write operations.

## Claude Code Web branch fallback

When the local Claude invocation is unavailable, an owner-authorized Claude
Code Web session can perform the independent review if organizational policy
permits cloud sessions and the repository is already authorized through
GitHub. This is an explicit fallback, not a way to route around a tenant or
data-handling restriction.

Web sessions start from a fresh clone, so they can see committed and pushed
repository state, not a local working tree. The safe review flow is:

1. Put the exact review state on a dedicated branch and push it.
2. Record the branch name, expected HEAD SHA, and exact diff base or range.
3. Start a **fresh** Claude Code Web session and select that repository and
   branch. Fresh context preserves the independence of the review.
4. Tell Claude to run `git rev-parse HEAD` first and stop if it does not match
   the expected SHA.
5. Make the boundary explicit: read-only review; no edits, commits, pushes,
   PRs, deployments, secrets, environment files, production data, or customer
   data. Give it the relevant artifact paths and the expected output contract.
6. Bring the result back to the primary agent. Verify every proposed finding
   against the repository before folding it in.
7. If the reviewed state changes, push the new SHA and review that final state;
   a verdict for an older SHA does not cover the new diff.

A compact starting prompt is:

```text
Perform a fresh, independent, read-only review.

Repository: <owner/repo>
Branch: <review-branch>
Expected HEAD: <full-sha>
Review range: <base>..<head>

First confirm git rev-parse HEAD matches Expected HEAD. Stop on a mismatch.
Do not edit files, commit, push, open a PR, deploy, or access secrets,
environment files, production systems, logs, or customer data.

Independently verify the artifact against repository source. Treat prior
reviews as claims, not evidence. Return the workflow's normal findings format
and verdict, then state explicitly that you made no edits, commits, or pushes.
```

This fallback changes what must be remote, not what counts as approved. A
review-only commit is not authorization to merge or release. If a project's
policy literally requires review before *any* commit, the owner must explicitly
allow a review-only branch commit or use the local CLI path instead. Anthropic's
[Claude Code Web documentation](https://code.claude.com/docs/en/claude-code-on-the-web)
describes the fresh-clone and pushed-branch behavior.

## Canonical invocation

Real review prompts (a plan plus context) are long, and `codex exec` can hang
when a long prompt is passed inline as an argument. Always pass the prompt via
a temp file and stdin.

Shell state (variables, traps) does not survive across separate agent tool
calls — write the prompt file and launch the CLI in a **single shell
invocation**, and clean up explicitly afterwards. An `EXIT` trap is safe only
when set in the same invocation that runs the CLI; set in an earlier call it
fires before the CLI ever runs and deletes the prompt file.

Synchronous form (plan reviews — ask-codex, ask-claude, breakdown):

```bash
PROMPT_FILE="$(mktemp)"
cat > "$PROMPT_FILE" <<'EOF'
...the full prompt...
EOF

# Codex review from Claude:
codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE"
# Claude review from Codex:
claude -p --permission-mode plan < "$PROMPT_FILE"

rm -f "$PROMPT_FILE"
```

Background form (parallel touchpoints — review, security-check): stdout of a
bare `&` job is lost, so capture it to a second temp file and read that file
at merge time:

```bash
PROMPT_FILE="$(mktemp)"; OUT_FILE="$(mktemp)"
cat > "$PROMPT_FILE" <<'EOF'
...the full prompt...
EOF
codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE" > "$OUT_FILE" 2>&1 &
XAGENT_PID=$!
rm -f "$PROMPT_FILE"          # safe — the launched process already holds the file open
echo "$XAGENT_PID $OUT_FILE"  # note these — kill/read at merge time
```

If your harness has a native background-execution facility on its shell tool,
prefer it over bare `&` — it tracks completion for you. At merge time read
`$OUT_FILE`; if it's empty or incomplete after the timeout, proceed
single-model and kill the straggler (`kill "$XAGENT_PID"`). Clean up
`$OUT_FILE` after the merge.

For a lighter capture, `codex exec` also accepts
`--output-last-message <file>`, which writes only the final message. The
stdout redirect above remains the canonical capture — it preserves the run's
diagnostics for the case where the review fails or comes back empty.

The prompt file lives in the shared temp dir until cleanup — never write
secrets, credentials, or private data into it.

## Diff reviews: `codex review`

For reviewing a git diff (as opposed to a plan or prompt), Codex ships a
diff-native subcommand that needs no prompt file:

```bash
codex review --uncommitted   # working tree: staged + unstaged + untracked
codex review --base main     # everything on the branch vs a base branch
codex review --commit <sha>  # a single commit
```

- `--uncommitted` reviews staged, unstaged, **and** untracked changes
  together — there is no staged-only mode. A workflow that must review
  exactly what is staged still composes its own prompt over an explicit
  `git diff --staged` instead.
- Preflight with `codex review --help`, the same way `codex exec` is
  preflighted.
- Serel Memory's own `review` and `security-check` workflows keep the
  prompt-file form — they need a custom checklist, a blind independent
  pass, and their own output contract. `codex review` is the direct path
  for ad-hoc diff reviews outside those workflows.
- There is no local `claude review` twin (`claude ultrareview` exists but
  is a cloud-hosted multi-agent review, not a quick local gate); diff
  reviews in the reverse direction keep using
  `claude -p --permission-mode plan < prompt-file` with the diff included
  in the prompt file.

## Touchpoint patterns

Cross-agent calls aren't limited to plan review. When a workflow adds a
secondary-CLI touchpoint, follow these rules:

- **Blind over anchored.** When the secondary agent generates findings (a
  review, a risk list, an audit), give it the same inputs as the primary — not
  the primary's conclusions. Anchored critique tends to validate framing;
  independent generation surfaces blind spots.
- **Provenance tags.** Merged findings are tagged `[both]`, `[claude]`, or
  `[codex]` so agreement and disagreement stay auditable. The primary agent
  verifies secondary-only findings against the code before including them.
- **Hide the latency.** Launch the secondary CLI in the background while the
  primary does its own pass; merge at the end.
- **Offered vs. default-on.** Ambient touchpoints (e.g. the bank audit in
  update-memory) are offers the user can decline. Default-on is reserved for
  explicitly invoked scrutiny rituals (a code review or security check the
  user asked for) and the high-impact plan reviews recommended in `AGENTS.md`
  — and even then it is opportunistic: bounded timeout, skip on trivial
  input, never wait indefinitely.
- **Concentrate where self-grading is weakest.** Clean self-reviews, READY
  verdicts, empty risk sections, and the agent summarizing its own session are
  where a second model earns its cost.
- **Never block, never pretend.** If the secondary CLI is missing, slow, or
  unauthenticated, complete single-model and label the output accordingly.
- **Patience scales with intent.** The bounded-timeout-and-kill rule above is
  for opportunistic background passes. When the user explicitly asked for the
  review, a long run is usually thoroughness, not a hang — high-effort
  configurations legitimately take minutes, and web search runs server-side,
  unaffected by the local sandbox. Before killing a requested review, check
  the captured output file: if it is still growing, let it finish. Don't
  lower the secondary CLI's reasoning effort to make reviews faster — that
  trades away the judgment the review exists to provide.

## Optional preset: mandatory review gate

The shipped default stays "recommended for high-impact plans" — review is a
tool, not a tax. Teams that want a hard gate instead can adopt this policy as
a working agreement for their agents (it is prose policy, not a git hook):

```text
Cross-agent review is a mandatory gate: every plan and every non-trivial
code diff gets a second-CLI review before commit.
- Exemptions: typo/comment-only edits and memory-bank docs commits.
- Every finding is folded in or explicitly disposed of before committing.
  A fix for a failed check is still a diff, so it gets reviewed too — "it's
  only a CI fix" is not an exemption.
- Re-review converges like a loop: after two rounds on the same change,
  stop and escalate the remaining disagreement to the user instead of
  iterating.
- If the secondary CLI is missing or errors, the gate does not silently
  pass: do a labeled self-critique, ask the user for an explicit waiver,
  and record the waiver in the commit body.
- Plan reviews come before implementation; diff reviews come before
  commit. The diff gate blocks the commit, not the work: launch the
  review in the background and keep working while it runs.
```

Where to put it: the effective `.rules` file is the drift-free home — it is
never in sync scope. `AGENTS.md` also works (both CLIs read it), but it is
in the sync-upstream allowlist: template-mode syncs will list your addition
as a local difference to review on each run, and fork-mode syncs can
conflict when upstream changes the same file. Adopting the preset does not
change Serel Memory's shipped default.
