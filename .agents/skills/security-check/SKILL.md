---
name: security-check
description: "Lightweight OWASP Top 10 + STRIDE security pass on the current change. Use when the user asks for a security review, security check, threat model, or vulnerability scan of the current diff."
---

# Security Check

Review the current change for security issues. Be thorough but pragmatic — focus on real risks, not theoretical edge cases. Do not edit files.

## Workflow

1. Run `git diff main...HEAD` (or `git diff` for uncommitted) to see what changed.
2. Launch the cross-agent pass in the background if it qualifies (see below) — before forming any findings of your own.
3. Read modified files in full where context matters.
4. Check against OWASP Top 10 + STRIDE.

## Cross-agent pass (opportunistic)

Security is exactly the category where a second model pays for itself — and
the diff is often authored by the model now checking it. If `claude --version`
succeeds and the diff is non-trivial (≥ 20 changed lines):

1. Right after computing the diff (step 1), write a prompt file containing:
   - the diff range
   - the full OWASP + STRIDE checklist below
   - the findings format — without the provenance tags or the dual/single-model
     label line; you add those at merge
   - a read-only instruction: do not edit files or run write operations

   **Not your own findings** — Claude must check blind, or it will anchor on
   your framing. Launch it in the background, capturing output to a file
   (`docs/cross-agent-review.md` has the canonical background form; prefer
   your harness's background facility over bare `&` if it has one):

   ```bash
   claude -p --permission-mode plan < "$PROMPT_FILE" > "$OUT_FILE" 2>&1 &
   ```

2. Do your own full pass and **draft your own findings before reading Claude's
   output**.
3. After your draft is done, wait up to ~90 seconds for Claude; if it hasn't
   returned, proceed single-model and say so.
4. Merge with provenance: tag every finding `[both]`, `[codex]`, or
   `[claude]`. Verify `[claude]`-only findings against the actual code before
   including them. Findings tagged `[both]` carry the most confidence, but confidence
   is not priority: a single verified vulnerability outranks two matching
   low-severity notes. Add one `DISAGREEMENTS:` line per explicit
   contradiction; silence from a model is not disagreement.

This pass never blocks the check: if Claude is missing or slow, complete
single-model and say so in the SECURITY SUMMARY.

## OWASP Top 10 pass

For each, note: present / not applicable / concern.

1. **Broken access control** — anyone able to access something they shouldn't?
2. **Cryptographic failures** — sensitive data in the clear; weak algorithms; hardcoded keys?
3. **Injection** — SQL, command, LDAP, OS, prompt injection?
4. **Insecure design** — missing rate limits, no auth where needed, trust boundaries violated?
5. **Security misconfiguration** — overly permissive CORS, verbose errors, default creds?
6. **Vulnerable & outdated components** — new deps with known CVEs?
7. **Identification & authentication failures** — weak sessions, missing MFA, token leakage?
8. **Software & data integrity failures** — unsigned updates, deserialization, dependency tampering?
9. **Security logging & monitoring failures** — enough audit trail for what was added?
10. **Server-side request forgery** — user-controlled URLs fetched server-side?

## STRIDE pass

- **Spoofing** — can someone impersonate a user or service?
- **Tampering** — can data in transit or at rest be modified undetected?
- **Repudiation** — can a user deny doing something we'd need to prove?
- **Information disclosure** — anything leaked through errors, logs, response bodies?
- **Denial of service** — unbounded loops, unrate-limited endpoints, resource exhaustion?
- **Elevation of privilege** — can a low-privilege actor get higher access?

## Output

```text
SECURITY SUMMARY: [one line — overall risk read]
[dual-model check (Codex + Claude) | single-model check (reason)]

HIGH RISK (block merge):
- [both|codex|claude] [file:line] [issue] → [fix]

MEDIUM RISK (fix before prod):
- [both|codex|claude] [file:line] [issue] → [fix]

LOW / NIT (track for later):
- [both|codex|claude] [file:line] [issue] → [fix]

CHECKED & CLEAN: [list of categories checked and clean — to show coverage]
```

Omit the provenance tags when the check was single-model.

## Rules

- Don't cry wolf. A theoretical attack with no realistic path doesn't belong in HIGH RISK.
- For each finding, the fix matters as much as the identification.
- If you didn't check something (e.g., infra not in scope), say so — don't claim coverage you don't have.
