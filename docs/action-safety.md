# Graceful stop feasibility and fixture evidence

The original supported adapter is deliberately narrow: its SHA-256- and CodeDirectory-hash-pinned native `AmidFixture` loopback development sample, with the exact trusted executable path and project root. The packaged app supplies the expected digests from its build manifest. The adapter never trusts a runtime name or project marker alone. Stage 3 below adds user-declared Node.js and Python development servers under a weaker, user-directed policy; other generic processes remain read-only.

## Public API investigation

Observed on arm64 macOS 27.0.1, Swift 6.4, macOS SDK 27.0. Builds use installed Xcode 27.0 rather than the incomplete CommandLineTools SwiftUI plugin set.

- Public `mach/mach_traps.h` declares `task_name_for_pid`; `mach/task_info.h` declares `TASK_AUDIT_TOKEN`. In an owned unprivileged Python fixture, acquiring the task name and retrieving its genuine audit token both returned `KERN_SUCCESS` (0), count 8. No private token layout is read or fabricated. The task port is deallocated after token acquisition.
- Public `libproc.h` declares `proc_pidpath_audittoken` and `proc_signal_with_audittoken`. A single token-bound SIGTERM on that owned fixture returned 0 and the child exited from signal 15. Retaining its token until natural exit then attempting token-bound SIGTERM returned ESRCH (3), and the child had exited normally. Signal 0 is rejected as EINVAL (22) by this API and is not used for validation.
- Public `sys/proc_info.h` exposes PID/start seconds/microseconds but no `PROC_PIDUNIQIDENTIFIERINFO` or PID-version getter. Neither private constants nor private APIs are imported.
- Apple's [kill(2) manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kill.2.html) describes numeric PID/group addressing; it cannot accept a recorded start identity. Reading PID/start immediately before `kill` leaves a reuse race. Amid never falls back to it.
- Apple's [XNU process implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c) describes matching a token's process version during kernel lookup. The product obtains genuine tokens through the public task API and passes them unchanged to the public signaling API. XNU source is supporting evidence, not copied implementation.

The first hypothesis that ordinary unprivileged token acquisition would be unavailable was disproved by the owned live probe. Header declarations alone were not treated as proof. `fixtures/audit-token-probe.c` reproduces acquisition, single owned SIGTERM, and retained-token-after-exit checks; its termination modes require the target to share this run's parent PID and UID. It sends no numeric-PID signals. Actual PID reuse is not forced by churn of arbitrary system processes; replacement identity behavior is also covered by deterministic validation tests. Minimum macOS 15 still requires external validation.

## Scope and race boundaries

An executable runtime, CWD, marker existence and TCP listener cannot establish that an arbitrary Node/Python/Swift listener is a development server rather than a database or production service. No arguments, environments, source, prompts or payloads are read. The supported binary is the repository's finite-lived fixture with known behavior: it neither forks nor execs other programs. SHA-256 reads that explicitly trusted executable binary, never project source or unrelated executables. The reviewed external adapter below adds independently pinned identity and behavior evidence plus explicit per-preview development intent.

Preview shows exact identities/endpoints and captures an opaque genuine audit token; no descendant is authorized. Enabling requires matching canonical executable/CWD/project, binary digest, token-bound dynamic code-signature requirement, current-user ownership, fully available listening endpoints, exclusively loopback endpoints, no observed children and no shared endpoint owner. Confirmation consumes its operation ID, re-samples immediately, validates the original identity and metadata, rechecks the digest, token-bound path and running-code requirement, then sends exactly one SIGTERM. Unknown, changed or stale states fail closed. Repeated confirmation never retries.

PID/start validation remains non-atomic by itself. Token-bound kernel process-incarnation lookup closes numeric PID reuse at dispatch. Metadata and descendant observations can still change between samples and dispatch; the supported fixture's verified behavior (no exec/fork) bounds that race. Untrusted general processes are disabled precisely because that assurance is absent. The app does not signal a process tree, process group, terminal, database, Ollama/model runtime or container, and never sends SIGKILL.

Disk hash alone is insufficient: a different executable can start at a path that is subsequently restored to trusted bytes. The adapter additionally asks Security for the running guest using [kSecGuestAttributeAudit](https://developer.apple.com/documentation/security/ksecguestattributeaudit), then calls [SecCodeCheckValidity](https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:)) with a requirement for the packaged build's exact CodeDirectory hash. Apple's documentation specifies dynamic validity and resistance to filesystem-source modification. The trust manifest supplies that expected running-code identity independently of the current disk hash. Missing or mismatched signing identity disables the action. A test starts a distinct owned native image, replaces its pathname with trusted bytes and verifies refusal without sending a signal.

After dispatch the actor samples for up to ten seconds and returns observed remaining identities and endpoints. Original-target visibility is verified with the retained token; unrelated protected system processes do not prevent recording that the original target exited. Endpoint statements concern observed owners only. Remaining children or endpoint owners are not targeted; another owner may already have bound the port. There is no automatic retry/force kill, promise of freed RAM, or guarantee that a port remains free.

## Owned native workloads

`scripts/test-fixtures.sh` compiles a temporary native Swift fixture and uses already installed Node and system Python. No dependencies are downloaded. Each fixture binds a kernel-selected loopback port, touches 16 MiB, creates a short CPU spike, and exits on its own after eight seconds by default. The known Swift demo accepts an explicit own lifetime argument bounded to 1–3600 seconds; no other behavior or target is configurable. The opt-in integration test records generated PID/port/project metadata and sampler identities, checks project/endpoint attribution and CPU/memory availability, stops only the enrolled Swift fixture once, observes Node/Python natural exit, and checks Node restart identity. Ordinary unit runs skip it unless `AMID_RUN_FIXTURES=1`.

Cleanup waits for finite-lived owned children and never searches existing workloads or terminates an arbitrary port. The Swift stop occurs only after explicit test confirmation and enrollment with the digest of the exact test-built executable. Collector attribution checks project marker existence, not marker contents. Passing these fixtures is a narrow observed result, not coverage of arbitrary projects or minimum-OS behavior.

## Observed results

2026-10-01: all five deterministic ActionTests passed (0 failures): preview identity/endpoints; PID/boot/UID replacement and exit; exec/reparent/CWD/project/endpoint/coverage/staleness; shared endpoints and descendant changes; protected/unknown runtime read-only checks. Live C probe results: token acquisition 0; owned token SIGTERM 0, child signal 15; original token after natural exit ESRCH 3, no replacement targeting. Final native-engine script passed (exit 0; 1 integration test, 0 failures, 24.26 seconds): Node/Python/Swift project+port coverage 3/3 = 100%; CPU/memory measurements available; trusted Swift preview enabled and exactly one SIGTERM verified with no remaining observed target/endpoints; reused confirmation zero signals; natural exit and Node restart passed. Latest controller regression also passed (24.281 seconds), including natural exit between enabled preview and confirmation returning alreadyExited with zero signals. Wrong digest and same-path running-image substitution were both refused with zero signals; the impostor exited naturally. The reproducible script also asserts live token SIGTERM result 0 and original-token-after-exit ESRCH 3. Sanitized actual log: action-fixtures.log (local record: `action-fixtures.log`). Broad coverage and macOS 15 remain unverified.

2026-10-02 bounded refusal regression: six ActionTests passed, zero failures (native engine; build exit 0). An expired preview now reports expiry/validation unavailability without implying that the process changed, sends zero signals, and retains the original incarnation's identities/endpoints observed in the fresh snapshot. Metadata, token-path and running-signature refusals have separate messages. The helper test also excludes a replacement with the same PID. Ten-second expiry, one-time authorization and single token-bound SIGTERM are unchanged; no long fixture suite was repeated for this copy/state correction.

Root agent's live UI observation on 2026-10-02: confirming a preview after its ten-second lifetime correctly refused with zero signals; the prior generic copy and empty remaining counts prompted this regression fix. A fresh preview then confirmed the same owned packaged demo successfully: exactly one SIGTERM, child exit status 143, and no remaining observed endpoints. This is a reported root-agent observation, not a new UI run by the delegated action agent. The corrected refusal wording/state still needs live UI observation in the rebuilt bundle.

2026-10-02 final usability adjustment: preview validity is now 120 seconds to allow reading the complete target, including spoken labels. A same-model read-only review confirmed that the old ten-second authorization age was an implementation choice, not the kernel identity guarantee. Every immediate identity/ownership/metadata/digest/token-path/running-code check remains, as do single use, lifecycle invalidation and one SIGTERM. Post-signal verification still has a ten-second deadline. Deterministic tests assert age120 remains valid and age121 is stale. Historical observations above used the older ten-second preview and are not re-labeled as new UI verification.

## Reviewed external darkhttpd adapter (stage 2)

Core additionally recognizes only the corrected v1.17 native `darkhttpd` build pinned in SupportedServerBuilds: SHA-256 `c7c78d329a49f96044f513ab5a4d4acb08ac5f10eae98e49946370e8db7320e4`, running CDHash `465b0edd621f1d6b7f1a7914d51e574088ecbef3`. Caller-provided hashes and imported manifests cannot enroll this adapter. A basename offers review only; every preview and dispatch retains disk/running-code, audit-token, UID, canonical CWD/project association, exclusive available IPv4 127.0.0.1 endpoint and no-observed-descendant validation. Generic runtimes remain read-only. CWD association does not establish the served root.

Each real-server preview requires a fresh explicit declaration that this exact process is the user's foreground development server and is intended to stop, without daemon/chroot/user-group/PID-file/syslog/redirect options. The controller checks this requirement from its stored adapter kind, never the caller's mutable preview flag. Missing declaration consumes the operation without signaling. There is no persistent enrollment, inherited restart permission, automatic server launch or bundled server. Passive metadata cannot detect those launch modes; the declaration is a user assertion, not an automatic flag check. Privileged and untested variants have no verification claim. Active transfers are interrupted, not drained.

The ten-second post-signal verification deadline uses ContinuousClock; preview age still uses Date and rejects future/expired observations. Canonicalization treats /tmp and /private/tmp as the same existing directory while immediate metadata validation still detects observed changes. Test/build evidence below is limited to this host/toolchain; stage 2 does not complete M-11 until actual reviewed UI and owned integration observations are recorded.

Stage-2 observed 2026-10-02 12:57:52 CDT: focused native run exited 0, 13 tests / 0 skips / 0 failures (nine ActionTests, two ReviewedServerAdapterTests, two App StopLifecycleTests). The real-controller integration launched only new eight-second bounded owned servers: PID 46250 / port 49274 idle and PID 46261 / port 49276 with synthetic HTTP 200 then unread 128 MiB transfer. Both received exactly one authorized token-bound SIGTERM and exited 0, with original identity and endpoint observations empty. Missing declaration, forged requiresDevelopmentConfirmation=false, repeated/consumed authorization, reset and previous-incarnation confirmation sent zero signals. PID 46272 / port 49278 ran the same server with a distinct ad-hoc signing identity; replacing its pathname with the independently trusted bytes still failed running-code validation and sent zero signals; it naturally expired via SIGALRM. All owned children exited. These are automated controller observations, not live app UI acceptance.

Earlier stage-2 attempts remain failures: two canonical-path association runs stayed read-only and naturally expired; a curl-buffering client assertion failed despite controller stops. The final direct synthetic socket asserts an HTTP 200 response before stopping consumption and verifies the server's final GET log. The optional script initially rejected a different relative-path linker UUID, then rejected incomplete CDHash extraction; final absolute-path build and verbose signature extraction exited 0 at `/private/tmp/amid-supported-darkhttpd-tLYDLCIB/darkhttpd`. No failed attempt is counted as a pass.

## User-declared development servers (stage 3)

Owner decision 2026-10-14, approved 2026-10-17 with the six recommended choices in the [everyday stop plan](everyday-stop-plan.md). A current-user Node.js or Python listener in a detected project may be stopped as a user-declared development server.

This is a **weaker, user-directed policy** than the pinned adapters above. The checks prove that Amid signals the same process, running the same executable, that the user reviewed. They say nothing about its script, loaded modules, role or shutdown behaviour, so the user's per-preview declaration supplies the intent.

**When Stop is offered** (`DeclaredServerEligibility`, discovery only, every rule required):
- current user ID;
- an executable whose basename Amid labels Node.js or Python;
- an executable outside any `.app` bundle, except a standard framework Python interpreter (`…/Python.framework` or `Python3.framework/Versions/<v>/Resources/Python.app/Contents/MacOS/Python`). Xcode, Homebrew, python.org and Command Line Tools Python run this way; only Xcode's `Contents/Developer/Library/Frameworks` may enclose it in an application;
- a parent PID above 1;
- a working directory inside the detected project;
- complete listening endpoints, all loopback or wildcard, with no other observed owner of those ports.

Wildcard listeners show a notice that they may be reachable from the network. With the initial Node.js and Python allowlist, the plan's never-stop names (databases, model runtimes, container hosts, terminals, Amid) cannot be offered, so no separate list exists yet. One is needed if the runtime set grows.

**What authorizes the signal:**
1. A genuine audit token taken at preview. Its token-bound path must equal the previewed executable.
2. The running guest is validated with `SecCodeCheckValidity` before its CodeDirectory hash is read, as `SecCode.h` requires. That hash is then required through a `cdhash` requirement at preview and again, against the original token, at confirm.
3. A fresh per-preview declaration naming the project, executable basename and ports. It is enforced from the stored adapter kind.
4. An immediate re-sample with unchanged identity, metadata, endpoints and descendants, and eligibility re-checked on that fresh sample.

One SIGTERM is sent through `proc_signal_with_audittoken`. Listed descendants are shown with full identities and are never signalled.

**Verification and reporting:**
- The ten-second window is watched in full, so a delayed replacement listener is seen.
- When the token disappears, a read-only lookup of the same PID, user and start time tells exit from `exec`. It reports "already exited", "switched to another program", or "unavailable" when it cannot tell.
- A new owner of the port is reported as possibly restarted by a supervisor, with no retry.
- Previewed descendants that are still observed are reported by identity, including after reparenting; descendants Amid cannot observe are reported as unknown.

**Residual risks:**
- Metadata and descendants can change between the final sample and dispatch.
- A signal accepted just before an `exec` reaches the new program.
- Amid cannot verify intent without reading arguments. Model servers, notebooks and editor or agent services running under Node.js or Python can be offered Stop, and only the declaration excludes them.

**Observed 2026-10-17** (arm64 macOS 27.0.1, Xcode toolchain): owned integrations `DeclaredServerFixtureIntegrationTests` passed 7/7 in 74.4 s, with no downloads.
- Node.js v22.21.1 (nvm, Developer ID: Node.js Foundation):
  - Plain server: undeclared and reused confirmations sent zero signals; the declared confirmation sent one SIGTERM, and the server exited 0.
  - A server ignoring SIGTERM was reported still running; there was no force, and it exited on its own timer.
  - A long-lived `sleep` child was listed, never signalled, and reported still running by identity after reparenting.
  - A parent that restarts its child after two seconds was reported as "another process now owns port …".
  - A copied `node` whose pathname was replaced with `/bin/sleep` bytes stayed unavailable ("Running code identity is unavailable").
- Xcode framework Python 3.9:
  - Through the test seam between the final checks and dispatch, an `exec` of `/bin/sleep` and a same-path re-exec were both rejected by the kernel. Zero signals were sent, and each was reported as a program switch.

Deterministic `DeclaredServerTests` cover the eligibility matrix, framework-path limits, forged previews, exec and exit lookup, descendant identity and coverage, grandchildren, ancestors, and live running-code capture from `/bin/sleep`.

**Not covered:**
- native UI observation;
- pending SIGTERM across `exec`, which cannot be made deterministic;
- unsigned or Rosetta-translated binaries;
- real Next.js, Vite or Python-reloader behaviour, which needs separately approved installs;
- macOS 15.

Two read-only Codex reviews (plan and implementation, both REVISE) shaped these rules; their implementation findings are folded in above.
