---
name: ask-claude
description: "Ask Claude Code CLI for an independent second opinion while working in Codex. Use when the user wants Claude to review a plan, architecture decision, PRD interpretation, implementation approach, or risk assessment. Supports optional bounded loop mode when explicitly requested."
---

# Ask Claude

Use this skill when the user wants an independent Claude Code review while working in Codex. This shells out to the Claude CLI and does not require MCP.

## Preconditions

- `claude` should be installed and authenticated. If it isn't, don't block — use the Fallback at the end.
- The user must approve shell execution when required by the environment.
- Do not pass secrets, credentials, private production data, or sensitive customer data into the prompt.
- Follow `docs/cross-agent-review.md` when present.

## Default: Single-Pass Review

1. Identify the artifact to review:
   - A plan from the current conversation
   - A file path
   - A diff
   - A proposed architecture or decision
2. Build a concise prompt for Claude:

   ```text
   You are an independent engineering reviewer.
   Do not edit files.
   Do not run write operations.
   Review the plan/artifact below for:
   - incorrect assumptions
   - missing risks
   - simpler alternatives
   - validation gaps
   - questions the primary agent should ask the user

   Return:
   AGREEMENTS:
   DISAGREEMENTS:
   RISKS:
   SUGGESTED CHANGES:
   QUESTIONS:
   VERDICT: APPROVE | REVISE | RETHINK

   <plan/artifact/context>
   ```

3. Verify Claude CLI is available when practical:

   ```bash
   claude --version
   ```

4. Run Claude in print/plan mode. Write the prompt to a temp file and pipe it
   via stdin — long inline prompts are unreliable as CLI arguments — in a
   single shell invocation (shell state doesn't survive across tool calls):

   ```bash
   PROMPT_FILE="$(mktemp)"
   cat > "$PROMPT_FILE" <<'EOF'
   ...the full prompt...
   EOF
   claude -p --permission-mode plan < "$PROMPT_FILE"
   rm -f "$PROMPT_FILE"
   ```

5. Summarize Claude's response for the user:
   - Verdict (APPROVE / REVISE / RETHINK)
   - Agreements
   - Gaps or disagreements
   - Plan changes worth adopting
   - Questions to ask before proceeding
6. Stop and wait for the user.

## Advanced: Bounded Loop

Use loop mode only when the user explicitly asks for a loop, debate, back-and-forth, or "have Codex and Claude work it out."

Rules:

- Maximum 2 rounds by default.
- Maximum 3 rounds only if the user explicitly asks.
- No file edits during the loop.
- Each round must get shorter and more specific.
- Stop early when the remaining disagreement is a product judgment, user preference, or low-impact implementation detail.
- Never ask Claude to call Codex back. The current Codex session owns the loop.

Loop structure:

1. Round 1: Ask Claude for broad critique.
2. Codex summarizes what it accepts, rejects, and wants challenged.
3. Round 2: Ask Claude only about unresolved disagreements or high-risk gaps.
4. Produce final synthesis:

   ```text
   FINAL SYNTHESIS:
   - What both agents agree on
   - What changed in the plan
   - Remaining disagreements
   - User decisions needed
   - Recommended next step
   ```

Then stop and wait.

## Fallback

If `claude` is missing, not authenticated, or blocked, say so and perform a local critique instead. Do not pretend Claude reviewed it.
