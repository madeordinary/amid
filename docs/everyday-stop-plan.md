# Everyday development-server stop — plan

Status: approved by the owner on 2026-10-17 with all six recommended choices and the PRD wording below, after a read-only Codex review (REVISE) whose corrections are incorporated. Implementation in progress; the `requirements.md` M-11 row is unchanged until evidence exists. On 2026-10-14 the owner decided to extend Stop from two pinned binaries to the development servers people actually run. This plan proposes how, within Amid's existing safety and privacy rules. Baseline: public `fd45ac3`.

## Goal

Let a user stop a development server they started, such as a Next.js or Vite server on Node or a Django, Flask or FastAPI server on Python, from Amid's process inspector. Stop sends exactly one identity-bound SIGTERM after a fresh, explicit, per-preview declaration, and then reports honestly what happened.

## Invariants (unchanged)

- Amid never reads process arguments, environments, or source, configuration or data files. The one exception, already used by today's adapters, is the target executable's code-signing information.
- It never sends SIGKILL, never signals a process group or tree, never retries, never falls back to `kill(pid)` and never remembers a stop permission.
- Every stop keeps the existing single-use preview, 120-second expiry, lifecycle invalidation on pause, lock, sleep, Clear History and quit, and the immediate re-sample and validation at confirm.
- Verification lasts up to ten seconds and reports what it observed.
- Running-code identity is captured only when the user opens a stop preview, never during sampling, so collection overhead is unchanged.

## What authorizes a stop

Today, [action safety](action-safety.md) keeps generic processes read-only because the owned fixture "neither forks nor execs". That reviewed behaviour bounds the race between the last sample and the signal. A general runtime has no such guarantee.

This plan adopts a **weaker, user-directed policy**. The checks below prove that Amid signals the same process, running the same executable, that the user reviewed. They say nothing about which script it runs, which modules it has loaded, what role it plays or how it shuts down. The user's declaration supplies the intent. All four are required:

1. **Incarnation binding.** A genuine audit token taken at preview is passed unchanged to `proc_signal_with_audittoken`. The kernel rejects any other incarnation of the PID. An `exec` also changes the token's version, so a completed `exec` before dispatch is rejected too, even when the process re-executes the same binary.
2. **Image binding.** The token-bound executable path must equal the previewed executable, both at preview and at confirm.
3. **Running-code binding.** Every step must succeed; any error leaves the target read-only.
   - At preview:
     1. Obtain the running guest with `SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token], …)`.
     2. Check it with `SecCodeCheckValidity`. Apple's `SecCode.h` requires a successful validity check before `SecCodeCopySigningInformation` returns trustworthy data ([Security source](https://raw.githubusercontent.com/apple-oss-distributions/Security/main/OSX/libsecurity_codesigning/lib/SecCode.h)).
     3. Read the CodeDirectory hash (`kSecCodeInfoUnique`) and build the requirement `cdhash H"…"`.
     4. Validate the guest against that requirement.
   - At confirm, obtain a fresh guest from the original token and validate the same requirement.
   - Native arm64 executables carry at least an ad-hoc signature, but Rosetta can run unsigned x86_64 binaries. A target without a valid running-code identity stays read-only. Translated targets are unverified until tested.
4. **Fresh declaration.** Every preview requires the user to tick a statement naming the project, the executable's basename and the port or ports: “This is my development server for ‹project› on port ‹n›, and I want to stop it. Open requests will be interrupted.” The controller enforces this from its stored adapter kind, never from a caller-supplied preview flag.

The eligibility rules below decide only when Amid *offers* a stop, the way `SupportedServerBuilds.canReview` does today. A runtime name, project marker or listener never authorizes a signal by itself. That keeps PRD M-11's “never a name match” rule intact.

**Residual race and failure modes:**
- Metadata, descendants and endpoints can still change between the confirm-time sample and dispatch.
- Identity is bound at dispatch, not at delivery. POSIX keeps pending signals across `exec`, so if the process execs right after the kernel accepts the SIGTERM, the new program receives it.
- A process can fork or change behaviour after the last sample.
- Amid cannot verify intent without reading arguments; the declaration is the user's assertion.

## Eligibility: when Stop is offered

A new adapter kind, `declaredDevelopmentServer`, sits beside the owned fixture and the pinned darkhttpd build, which stay unchanged. Every failed rule leaves the process read-only with a specific reason.

- **Owner:** current user ID only.
- **Listener:** at least one listening TCP endpoint, complete port availability, and no other observed owner of those ports.
- **Address:** loopback (`127.0.0.1`, `::1`) or wildcard (`0.0.0.0`, `::`). Next.js binds `0.0.0.0` by default ([Next.js CLI](https://nextjs.org/docs/app/api-reference/cli/next)), while Vite binds `localhost` ([Vite server options](https://vite.dev/config/server-options)). A wildcard listener shows a notice that it “may be reachable from your network”. A specific non-loopback address stays read-only. *Owner choice 1.*
- **Project:** working directory inside a detected project root.
- **Runtime:** the executable's basename is a recognized development runtime. The initial set is Node.js and Python, the runtimes Amid already labels. *Owner choice 3.*
- **Not an application:** the executable is not inside an `.app` bundle.
- **Not launchd-parented:** the parent PID is not 1. *Owner choice 4.*
- **Never-stop names:** databases, model runtimes, container and VM hosts, terminals and shells, Amid itself and its fixture.

These filters reduce surprise; they are not role guarantees. They limit exposure, not disposability. They cannot mechanically exclude any of the following, all of which run under Node.js or Python and look the same as a development server without their arguments:
- TCP language or MCP servers
- Jupyter kernels
- Python model servers
- editor helpers that live outside an `.app` bundle
- services behind a wrapper process
- processes an agent started in the project

The declaration is the real gate. *Owner choice 6.*

## Child processes and supervisors

Development servers commonly have child processes. `next dev` runs a parent orchestration process and a child server process ([Next.js CLI, CPU profiling](https://nextjs.org/docs/app/api-reference/cli/next)). esbuild's Node API keeps a long-lived esbuild child process ([esbuild source](https://github.com/evanw/esbuild/blob/main/lib/npm/node.ts)), which tools built on it, including Vite versions that use esbuild, inherit. The current rule, “no observed descendants”, would refuse these servers.

Proposed (*owner choice 2*):
- **Preview** lists observed descendants by full identity, and confirm requires the same set.
- **Only the listener is signalled.** Amid promises only that it directly signals the listener; the listener may forward the signal or stop its workers while cleaning up.
- **Results** report which previewed descendants are still running, matched by recorded identity, since children can be reparented after their parent exits. A descendant that Amid can no longer observe while coverage is incomplete is reported as unknown, not as exited.
- **Ancestors:** the preview shows ancestor basenames from the already-sampled parent chain, for example `zsh › npm › node`, so the user can see what started the server.

## Verification semantics

These rules apply to this adapter kind.

- **The token can disappear without the process exiting.** An `exec` invalidates the original token while the process keeps running. If the same PID and start time are still present, report that the process switched to another program, not that it exited. Today's confirm path reports a vanished token as “already exited”.
- **Keep sampling until the ten-second deadline**, even after the original exits, so a delayed replacement listener is seen.
- **A new owner of the port is not proof of a restart.** Report it as “Another process now owns port ‹n›, possibly restarted by a supervisor. Amid will not retry; stop the parent in its terminal.”
- **Supervisors** such as nodemon, pm2, turbo or the Next.js parent are not detectable without arguments, and Amid will not claim to detect them. Whether the Next.js parent restarts its child after SIGTERM is unverified.

## Proposed PRD wording (for owner approval)

**PRD M-11 row:**

> Supported development servers only: the bundled fixture, independently pinned reviewed builds, and user-declared development servers: current-user Node.js and Python listeners in a detected project. Non-fixture targets need a fresh per-preview declaration. Every target needs audit-token incarnation binding, plus token-bound path and running-code identity checks at preview and immediately before action. Changed or ambiguous targets are rejected. Runtime names, markers and listeners only decide when Stop is offered; they never authorize it. Never a port-only kill, shell string, SIGKILL, or group or tree signal.

**“Stop boundaries” first paragraph:**

> General apps, terminals, databases, local-model runtimes, container hosts and unknown processes are read-only in v0.1. A Node.js or Python listener in a detected project may be stopped as a user-declared development server. Amid cannot tell a model server, kernel or editor service running under those runtimes from a development server without reading arguments, so the user's per-preview declaration decides, not a name list. Read-only detail views may offer navigation to Activity Monitor, not covert termination. The stop scope does not expand when an item is grouped under a project.

The `requirements.md` M-11 row is rewritten only after implementation evidence exists.

## Implementation steps

1. **Owner approval** of the wording above, the owner choices and a decision-log entry, before any code.
2. **Core.**
   - Add the adapter kind and a pure, testable eligibility evaluator that returns specific reasons.
   - Implement the running-code capture contract above. Skip disk SHA-256 for this kind: hashing a large runtime binary per preview adds cost without assurance beyond the running-code check.
   - Allow loopback and wildcard endpoints, and listed descendants, for this kind only.
3. **Verification and copy** as specified above.
4. **UI.** In the process inspector, add the declaration text with project and ports, the exposure notice, the descendant and ancestor context, and the specific read-only reasons.
5. **Tests.**
   - An eligibility matrix with one failing rule per case.
   - A missing or forged declaration sends zero signals.
   - Declaration and lifecycle invalidation.
   - **Exec after the final validity check and before dispatch**, including a same-path re-exec, through an internal test seam. Old token rejected, zero signals, and no false “exited” report.
   - Pending SIGTERM across `exec`, to document actual behaviour.
   - Pathname replacement before capturing the hash.
   - Ad-hoc-signed, Developer ID-signed, unsigned and translated binaries.
   - PID reuse refused.
   - Descendants: listed and not signalled, including reparenting, grandchildren, and inaccessible observations reported as unknown.
   - A delayed replacement owner.
   - Existing fixture and darkhttpd adapter tests stay unchanged.
6. **Owned integrations**, opt-in through `scripts/test-fixtures.sh`, using only the Node and Python already installed. No downloads.
   - A plain server stops with one SIGTERM.
   - A server that ignores SIGTERM is reported as still running, with no SIGKILL.
   - A parent that restarts its child is reported as another owner, with no retry.
   - A server with a long-lived child keeps the child unsignalled.
   - Plain fixtures do not establish Next.js or Python-reloader behaviour. Claiming support for those needs real installs, which require separate owner permission to download.
7. **Docs and evidence.** Add a stage-3 section to `action-safety.md`, then update `requirements.md` and the README. Run the full suite, build an identified package, and produce a native checklist for owner observation.

## Owner choices

1. **Wildcard listeners.** Allow `0.0.0.0` and `::` with an exposure notice (recommended, needed for the Next.js default), or loopback only.
2. **Child processes.** Allow, list and require unchanged while signalling only the listener (recommended, needed for Next.js and esbuild-based tools), or keep the no-children rule.
3. **Initial runtimes.** Node.js and Python first (recommended). Bun, Deno, Ruby, PHP and compiled binaries inside the project root become follow-ups, because each needs runtime-label work under M-07.
4. **launchd-parented processes.** Keep them read-only (recommended), or offer Stop with a supervisor warning.
5. **Per-preview declaration only.** Keep it (recommended). A persistent “always allow for this project” would be a separate decision.
6. **The declaration as the real gate.** Accept that model servers, kernels and editor or agent services running under Node.js or Python may be offered Stop and are excluded only by the user's informed declaration (recommended), or require mechanical exclusion, which these rules cannot provide.

## Out of scope

Process-tree or group stops, SIGKILL or force quit, persistent enrollment, restarting servers, stopping supervisors, containers and their hosts, databases, model runtimes, and anything requiring arguments, environments, or source, configuration or data files.
