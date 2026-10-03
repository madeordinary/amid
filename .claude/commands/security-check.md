---
description: Lightweight OWASP + STRIDE pass on the current change
---

# /security-check

Review the current change for security issues. You are a thorough but pragmatic reviewer — focus on real risks, not theoretical edge cases.

Steps:

1. Run `git diff main...HEAD` (or `git diff` for uncommitted) to see what changed.
2. Launch the cross-agent pass in the background if it qualifies (see below) — before forming any findings of your own.
3. Read modified files in full where context matters.
4. Check against OWASP Top 10 + STRIDE.

## Cross-agent pass (opportunistic)

Security is exactly the category where a second model pays for itself — and
the diff is often authored by the model now checking it. If `codex --version`
succeeds and the diff is non-trivial (≥ 20 changed lines):

1. Right after computing the diff (step 1), write a prompt file containing:
   - the diff range
   - the full OWASP + STRIDE checklist below
   - the findings format — without the provenance tags or the dual/single-model
     label line; you add those at merge
   - a read-only instruction: do not edit files or run write operations

   **Not your own findings** — Codex must check blind, or it will anchor on
   your framing. Launch it in the background, capturing output to a file
   (`docs/cross-agent-review.md` has the canonical background form; prefer
   your harness's background facility over bare `&` if it has one):

   ```bash
   codex exec --cd "$PWD" --sandbox read-only - < "$PROMPT_FILE" > "$OUT_FILE" 2>&1 &
   ```

2. Do your own full pass and **draft your own findings before reading Codex's
   output**.
3. After your draft is done, wait up to ~90 seconds for Codex; if it hasn't
   returned, proceed single-model and say so.
4. Merge with provenance: tag every finding `[both]`, `[claude]`, or
   `[codex]`. Verify `[codex]`-only findings against the actual code before
   including them. Findings tagged `[both]` carry the most confidence, but confidence
   is not priority: a single verified vulnerability outranks two matching
   low-severity notes. Add one `DISAGREEMENTS:` line per explicit
   contradiction; silence from a model is not disagreement.

This pass never blocks the check: if Codex is missing or slow, complete
single-model and say so in the SECURITY SUMMARY.

## OWASP Top 10 pass

For each, note: present / not applicable / concern.

1. **Broken access control** — anyone able to access something they shouldn't?
2. **Cryptographic failures** — anything sensitive transmitted or stored in the clear; weak algorithms; hardcoded keys?
3. **Injection** — SQL, command, LDAP, OS, prompt injection?
4. **Insecure design** — missing rate limits, no auth where needed, trust boundaries violated?
5. **Security misconfiguration** — overly permissive CORS, verbose error messages, default creds?
6. **Vulnerable & outdated components** — new deps; any with known CVEs?
7. **Identification & authentication failures** — weak session handling, missing MFA, token leakage?
8. **Software & data integrity failures** — unsigned updates, deserialization issues, dependency tampering risk?
9. **Security logging & monitoring failures** — enough audit trail for what was added?
10. **Server-side request forgery** — user-controlled URLs being fetched server-side?

## STRIDE pass

- **Spoofing** — can someone impersonate a user or service?
- **Tampering** — can data in transit or at rest be modified undetected?
- **Repudiation** — can a user deny doing something we'd need to prove?
- **Information disclosure** — anything leaked through errors, logs, response bodies?
- **Denial of service** — unbounded loops, unrate-limited endpoints, easy resource exhaustion?
- **Elevation of privilege** — can a low-privilege actor get higher access?

## Output

```text
SECURITY SUMMARY: [one line — overall risk read]
[dual-model check (Claude + Codex) | single-model check (reason)]

HIGH RISK (block merge):
- [both|claude|codex] [file:line] [issue] → [fix]

MEDIUM RISK (fix before prod):
- [both|claude|codex] [file:line] [issue] → [fix]

LOW / NIT (track for later):
- [both|claude|codex] [file:line] [issue] → [fix]

CHECKED & CLEAN: [list of OWASP/STRIDE categories that were checked and are clean — to show coverage]
```

Omit the provenance tags when the check was single-model.

Rules:

- Don't cry wolf. A theoretical attack with no realistic path doesn't belong in HIGH RISK.
- For each finding, the fix matters as much as the identification. "This is broken" without a remediation is half a finding.
- If you didn't check something (e.g., infra not in scope), say so — don't claim coverage you don't have.
