# Amid Product Requirements Document

| Field | Value |
|---|---|
| Version | 1.1 — name approved 2026-10-01; product requirements unchanged from 2026-09-29 |
| Readiness | Ready for Phase 0 feasibility and implementation planning; metric coverage and release gates are unverified |
| Owner | Made Ordinary |
| Public name | Amid by Made Ordinary — approved 2026-10-01. Final naming checks remain outstanding; see [naming review](docs/naming-review.md). |
| Platform | Apple silicon Mac; deployment target macOS 15.0 |
| Technology | Native Swift, SwiftUI and AppKit |
| Release | Free, open-source v0.1; direct signed/notarized download |
| Supersedes | 2026-09-26 Pulse discussion draft (historical; this document is canonical) |

## 1. Product and audience

The app explains which applications and development projects are consuming a Mac's resources. It connects processes to apps, local servers to projects and listening ports, and current usage to recent history.

> See what your Mac is doing, in terms that make sense.

The primary user develops software or uses local AI while running several editors, browsers, terminals and projects. Everyday questions include “Which app is using memory?”, “What owns port 3000?”, “Which servers did I leave running?” and “What was busy during that slowdown?” Other Mac users benefit from the application overview without needing the project features.

Example: show that a named project has a Node server listening on port 3000, its current measured memory footprint and recent CPU activity. Let the user inspect and explicitly stop that supported server. Low CPU alone cannot establish that it is unused or that stopping it is safe.

The product's advantage must be demonstrated through accurate grouping, project/port navigation, history and clear explanations. Activity Monitor and existing monitors remain comparison baselines. We do not claim that no existing monitor groups processes or provides history.

## 2. Decisions fixed for v0.1

| Area | Requirement |
|---|---|
| Main units | Applications and development projects, expandable to observed processes |
| Launch essentials | System overview, app CPU/memory, project/port attribution, local history, conservative alerts and narrowly scoped server stopping |
| History | Seven days recommended at onboarding; Off, 24 hours, 7 days or 30 days; no collection before the choice is accepted |
| Visibility | Best available unprivileged measurements; protected/inaccessible processes marked as outside coverage |
| Actions | Confirmed graceful stop of supported native development servers only; other apps/processes are read-only in v0.1 |
| AI tools | Identify observable runtimes where reliable; no provider quotas, prompts or semantic agent state |
| Privilege | No root helper, daemon, kernel/system extension or Full Disk Access requirement |
| AI inference | None; summaries use measured values and deterministic rules |
| Presentation | Menu bar plus a full native window; notch presentation deferred |
| Language | English first, with localizable strings |
| License | MIT for original code; dependency/reuse licenses reviewed before adoption |
| Network | Offline core; optional documented update traffic after user choice |

macOS 15 is the deployment target. Phase 0 must prove the minimum OS and supported newer releases; changing the target requires a documented revision. No date or implementation schedule is committed before the feasibility results.

## 3. Metric and feature contract

| Capability | v0.1 commitment | Limitation presented to the user |
|---|---|---|
| System CPU and load | Current use and history with defined units | Load and utilization are distinct; a spike is not proof of malfunction |
| Memory | Pressure, physical memory categories, compression and swap | Memory pressure, not raw percentage full, drives warnings |
| App/project CPU | Aggregation of uniquely assigned observed processes | Unknown and protected activity remains outside attribution |
| App/project memory | Physical footprint where accessible; clearly labeled RSS fallback | Shared/compressed memory and different accounting methods mean sums need not equal system memory used |
| Disk | Capacity/free space of accessible mounted local volumes; system activity only if verified | Do not sum APFS shared-container capacities as separate physical disks; per-app I/O attribution is deferred |
| Network | Host/interface byte deltas and throughput | No per-app traffic or destination inspection; virtual interfaces can overlap and are labeled |
| Battery | Available charge, health/status values from stable interfaces | Hidden/unavailable on desktops; no fabricated per-app watts or time-to-empty |
| Thermal | OS thermal-state category where available | No promise of sensor temperatures, fan speeds or GPU utilization in v0.1 |
| Ports | Listening TCP endpoints attached to observable user processes | Port alone is not process identity; no scanning, HTTP probes or connecting to the service |
| Projects | CWD/project-root attribution for a tested native server set | Unknown when hidden or ambiguous; supported coverage is published |
| Runtime labels | Native executables and trusted metadata for recognized tools | A process is not evidence of “agent waiting”, token usage or an individual model's memory consumption |
| History/alerts | Measured aggregates and rule-based events | No invented samples during sleep/quit; correlation is not established cause |

Excluded from v0.1: file cleaning, cache deletion, RAM purging, antivirus/security scores, per-app volume control, fan control, provider authentication, credential reading, cloud monitoring, generic chat, automatic optimization, arbitrary force quit, container control, and iOS/Intel/App Store releases.

Docker Desktop may appear as an observed application. Individual container contents, Linux processes, databases, ports and memory require a Docker adapter, which is deferred. Do not read the Docker socket automatically. Similarly, a visible Ollama process does not establish which model is loaded; model API adapters are later work.

## 4. Native interface and user flows

The menu-bar icon shows a neutral state unless measured pressure requires attention. The user may choose one numeric metric. Its panel shows CPU, memory pressure/swap, free disk space, top observed consumers, projects/ports and alerts. The full window has Overview, Applications, Projects, Ports, History and Alerts. Settings covers retention, exclusions/aliases, alerts, sampling, updates and data removal.

### Onboarding

Explain observed process/project metadata and local retention. Ask the user to choose history duration, offer optional notifications, launch at login and update checks, then show live data with a brief glossary. Defaults: seven-day retention recommended, launch at login off, background update checks off, notification delivery off until enabled. In-app events work without notification permission.

### Investigate a slowdown

Open the menu-bar panel, inspect current pressure and top consumers, then choose an app/project to see its process breakdown and history at the same time range. Wording is tied to evidence: “This application's CPU rose during the selected interval.” Do not assert an application caused a slowdown solely because it was large or busy.

### Find a server or port

Search a project or port number. Show the listener, executable, owning user/process identity, project association and current measurements. Project names are readable and user-renamable. A server's observed lifetime is distinguished from the time Monitor began watching it. Unknown owners remain Unknown and have no stop action.

### Stop a supported development server

Select Stop on a native server with validated identity and supported shutdown behavior. Preview the project, exact process identities and listening endpoints affected, including any validated child processes. Explain that active requests may be interrupted. Confirm, request graceful termination once, then check the original identities and listener state. If termination fails or descendants/listeners remain, report them. Do not silently escalate, send SIGKILL, terminate the terminal, or stop every process in a project.

## 5. Functional requirements

| ID | Requirement and acceptance behavior |
|---|---|
| M-01 Sample lifecycle | Five-second background target, two seconds while detail is visible, ten seconds on battery or elevated thermal state. Stop polling during sleep; restart with fresh delta baselines. Display actual cadence and stale/unavailable status. Phase 0 validates overhead and API behavior. |
| M-02 Identity | Distinguish boot/session identity, UID, PID and process start time. PID reuse, counter reset and reparenting cannot merge unrelated processes or authorize a stop. |
| M-03 App grouping | Use auditable bundle/executable/ancestry evidence; expose grouping reasons on demand. Ambiguity remains separate. Ancestry alone cannot assign every terminal child to the same project. Stable app grouping survives ordinary helper churn. |
| M-04 Aggregation | Count each process once within an app view and once within a project view. These are alternate views, not additive totals. Raw multi-core CPU and normalized share are labeled; app values can exceed 100% when one core equals 100%. Group memory methods are disclosed. |
| M-05 Project roots | Inspect accessible working-directory metadata and marker existence only, with bounded parent traversal. Do not open source/config contents to infer projects. User-specified aliases/root boundaries resolve monorepo ambiguity. Treat separate worktree paths as separate projects until explicitly combined. |
| M-06 Port mapping | Map listening TCP endpoints to observed owners where available. Include protocol/address scope and port, distinguish IPv4/IPv6/shared listeners, and avoid identifying a server by port number alone. Permission denied and process exit are normal missing-data cases. |
| M-07 Runtime identification | Required fixture families: native Node, Python and Swift development workloads. Target labels include Codex CLI, Claude Code, Gemini CLI and Ollama when executable or trusted non-content metadata permits. Generic Node/Python processes remain generic if identifying the tool would require reading prompts/arguments. |
| M-08 Low-activity suggestion | Label as “Low observed CPU” with the observation window. Default candidate: a recognized native dev listener observed continuously for ≥2 hours with average CPU <1% of one core in the last 30 minutes. Missing samples reset the qualifying window. No claim of no clients, no traffic, or “safe to stop” without those measurements. Suggestions are in-app and dismissible. |
| M-09 History | Persist compact system/app/project aggregates only after opt-in. Off means a bounded 15-minute RAM ring, cleared on quit/lock; no persisted history, alerts or action history. Show gaps for sleep/quit/missing data. No retroactive attribution of historical unknown processes. |
| M-10 Alerts | Published thresholds, sustained conditions, cooldown and recovery state. The complete initial rules are below. No alerts from missing/stale data or unsupported estimates. |
| M-11 Stop | Native supported dev servers only. Check identity/ownership immediately before action and reject changed/ambiguous targets. Use a validated adapter/target set, never a name match, port-only kill, shell string or blanket negative-PGID signal. |
| M-12 Data controls | Exclude apps/projects from persistence; aliases are independent of measured identity. Clear History includes alert/action records and caches. Lowering retention purges out-of-window app-managed history. Key/store failure must not fall back to plaintext. |
| M-13 Diagnostics | Local preview of explicit fields, then user-controlled export. Default export omits command arguments, usernames, full project paths, remote endpoints and process payloads. Report aliases and coarse measurements unless the user includes identifying fields. No upload button in v0.1. |
| M-14 Empty/error states | Distinguish unsupported metric, denied permission, process gone, sleeping, store unavailable and stale sample. Unknown is not zero. Data resumes after transient failures without inventing continuity. |
| M-15 Settings | Show history size, pause/clear, aliases, exclusions, alert controls, notification preference, optional numeric menu-bar display, launch/update choices and documented metric units. No undocumented toggles enable private APIs or elevated access. |

### Default alert rules

These are product defaults to validate during dogfooding, not diagnostic claims:

- System memory pressure remains warning/critical for 60 seconds; recover after five minutes of normal pressure.
- An observed app consumes at least 25% of total logical CPU capacity on average for five minutes; show both normalized share and raw CPU. Users can exclude expected build/render workloads.
- An observed app's measured memory grows by at least 1 GiB and 25% over 30 continuously observed minutes. Say “memory increased,” not “memory leak.” Require a consistent metric method throughout the window.
- Swap grows by at least 1 GiB over 15 minutes while memory pressure is warning/critical. Swap alone does not establish trouble.
- Startup-volume available capacity stays below 10 GiB for five minutes. Show the OS-reported capacity definition; allow a user-selected threshold.

Cooldown is one notification per category/entity per hour. Continued episodes update the existing event rather than flooding the user. Low-activity server suggestions are in-app only. Disabling a rule stops subsequent evaluation/notification; it does not silently erase already retained history.

### Stop boundaries and race handling

General apps, terminals, database processes, local-model runtimes, container hosts and unknown processes are read-only in v0.1. Their detail view may offer navigation to Activity Monitor, not covert termination. The service-stop scope does not expand when an item is grouped under a project.

A PID/start-time check reduces risk but is not treated as proof of an atomic handle. Phase 0 must document the residual OS identity/action race and test rapid exit/relaunch. If a target cannot be addressed with acceptable assurance, disable Stop for that adapter. A group stop requires a proven isolated target set and verified ownership; no assumption that every descendant of a shell is disposable.

Give graceful stop ten seconds to complete, then show Still running with remaining identities. No automatic retry or force kill. Return expected already-exited results without targeting a replacement process. Memory and ports are remeasured; do not promise an exact amount of RAM will be freed or a port will remain free after another process binds it.

## 6. History and privacy

Retain raw in-memory samples for 15 minutes. Persist one-minute aggregates through 24 hours and hourly aggregates for older retained periods. Store count, min, max, average and coverage so brief recorded spikes are not represented only by averages. Time gaps, sampling-rate changes and missing owners remain visible. Seven days is the default retention recommendation; history is capped at 250 MiB and enforces retention/rollups before deleting oldest aggregates. Show if the storage cap shortens the requested window.

No command-line arguments, environment variables, source contents, editor buffers, prompts, clipboard, credentials or network payloads are read for monitoring. Paths and process identities are used only when required for grouping. Resolving project marker existence must not become filesystem indexing. Do not request broad access merely to improve coverage.

Persisted identifiable history and aliases are encrypted using an established storage design and a per-install Keychain key; journals and temporary files obey the same rule. Access permissions restrict app-managed files. Encryption does not protect against every process running as the signed-in user or an already compromised Mac.

Stop-result records contain operation type, result and a minimal local target ID, and obey the chosen history retention. With history Off, they remain in RAM only. Operational logs exclude paths/arguments; no automatic telemetry/crash uploads. User exports, original files, backups and OS crash dumps are outside app-managed deletion guarantees. Clear History removes active store, indexes and caches; no forensic SSD erasure promise.

Core monitoring works offline. Optional manual/automatic updates use a published domain/field list after user choice. No remote diagnostic service, quota API, account or billing endpoint is required. Test actual traffic rather than relying on missing network entitlements in an unsandboxed app.

## 7. Swift architecture and distribution

- SwiftUI for dashboard, history, tables and Settings; AppKit for menu-bar integration, application lifecycle and appropriate native navigation.
- Swift 6 language/concurrency direction, a pinned supported Xcode/SDK, availability checks for macOS 15 and supported newer releases. No web wrapper or required Python/Node runtime.
- Separate sampler, process-identity, attribution, aggregation/history, alert and action components. UI reads immutable snapshots; a slow collector cannot block the menu bar.
- Prefer public, documented interfaces. Low-level Darwin process APIs are admitted only after per-version validation and documented limitations. No private frameworks, root helpers or undocumented sensor paths in the launch release.
- Versioned local storage with recoverable migrations and rollups. Dependencies and crypto/storage design are fixed by the Phase 0 architecture record.
- Each executable-recognition/server-stop adapter declares what metadata it reads and its tested scope. No arbitrary executable commands generated from UI or inferred project data.
- Original code uses MIT, with preserved third-party notices. A GPL project may be studied as a competing product, but its implementation cannot be copied into an MIT release without resolving the license obligations. Build instructions and dependency versions are published.
- Ship a separate app and repository from Winnel and Within. Share small components only when actual reuse appears; do not make a common-framework project a prerequisite.

Direct distribution is selected because the desired process/project visibility and confirmed termination need a broader capability set than a simple status widget. It is not a claim that all monitors are prohibited from the App Store. Apple's sandbox documentation explicitly restricts terminating other apps; actual monitoring capabilities must be evaluated separately. A future App Store edition would need a clear feature contract rather than assumed parity.

## 8. Accessibility and performance

All charts have a textual summary/table and units. VoiceOver can inspect grouping reasons, navigate time ranges and hear the exact stop target. Every action has a keyboard path. Status uses text/icons in addition to color, respects Increase Contrast/Reduce Motion, and does not require hover or a physical notch.

Budgets below are initial targets, not measured results. Reference fixture: M1 MacBook Air, 8 GB RAM, several browser/Electron apps, three native development projects and approximately 1,000 observed processes; document exact OS/workload and compare against an identical run without Monitor. Add a newer Apple silicon system, external display, minimum/latest stable supported OS, sleep/wake and battery cases.

| Gate | Passing result |
|---|---|
| Background overhead | Mean process CPU ≤0.5% of one logical core over 30 minutes after warm-up; report baseline variation and wakeups. RSS ≤150 MiB including frameworks. Separate visible-history/render costs from idle. |
| Responsiveness | Warm menu-bar panel p95 ≤150 ms; no sampling or database work blocks main-thread interaction. |
| Attribution | ≥98% precision in declared app fixtures and ≥95% coverage of declared supported project/port fixtures; unknowns reported separately. No false cross-app merge in release fixtures. |
| Identity/actions | PID reuse, reparenting, shared port, monorepo/worktree and exit/restart fixtures pass. Stop affects only previewed supported targets; remaining children are reported. |
| Measurement | CPU accounting, counter deltas/reset, memory-method labels and overlapping app/project views checked against reference collectors. Unknown data is never recorded as zero. |
| History | Reproduces a controlled spike at retained resolution; wake/reboot gaps and coverage shown; 30-day synthetic soak fits 250 MiB cap and enforces deletion. |
| Alerts | Each rule passes trigger, cooldown, recovery and missing-data tests. In two-week dogfooding, ordinary known build/render sessions do not generate repeated unwanted notifications after exclusion. |
| Privacy | No prompts/arguments/credentials in collection, logs or exports; offline test passes; only chosen update traffic; encrypted store/journal/key-failure behavior verified. |
| Release | Keyboard/VoiceOver workflows pass; no unresolved unintended-stop/data-loss defect; signed/notarized build plus source, licenses, compatible-metric list and build instructions. |

Usability validation: a new user identifies the largest observed app memory consumer within two minutes and maps a known test port to the correct project. Success is faster investigation with an understandable coverage boundary, not an unexplained “health score.” Evaluate through voluntary feedback, without installed analytics.

## 9. Delivery plan and feasibility decisions

1. **Phase 0 — capability matrix.** On target OS/hardware, prove unprivileged CPU/memory accounting, process identity, app grouping, accessible CWD, repository-marker checks, TCP ownership and graceful-stop isolation. Establish encrypted history design and observer overhead. Record fields requiring inaccessible APIs as unsupported; do not substitute invented values.
2. **Core alpha.** System/app views, raw drill-down, project/port linking and known runtime labels with synthetic fixtures. No termination until identity/target tests pass.
3. **Workflow beta.** Retained history, published alert rules, diagnostics and supported server-stop adapters. Run two-week dogfood with voluntary reports, accessibility review and performance comparison.
4. **Public v0.1.** Resolve release gates, complete final naming checks for Amid and publish signed/notarized builds, source and measured compatibility documentation.

Application grouping and native project/port attribution are essential to this release. If Phase 0 cannot support them without prohibited data access/privilege, document the blocker and revise scope before proceeding. Final product requirements do not imply these capabilities have already been proven.

Later candidates: optional notch UI, documented agent-state integrations, container/model adapters, measured GPU/temperature data, and local-model summaries of verified facts. No single candidate automatically adds credential access, privileged helpers or provider-network calls.

## 10. Sources and decision record

Finalized decisions: developer/local-AI user emphasis with an approachable overview; required project/port workflow; seven-day history choice; supported native dev-server graceful stop only; other processes read-only; supported facts only; optional numeric menu-bar indicator; no inferred agent waiting/finished state, AI inference or notch UI in v0.1. The founder approved Amid on 2026-10-01. Final naming checks remain a release task.

References checked 2026-09-29:

- [Vitals](https://vitalsmac.com/): inspiration for app/project grouping and history. Product-page descriptions are not validation of our APIs or performance.
- [Apple App Sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox): termination/other capability restrictions relevant to distribution.
- [Pulse: CPU & System Monitor on the Mac App Store](https://apps.apple.com/us/app/pulse-cpu-system-monitor/id6758529153): direct naming conflict and evidence that monitoring itself is not categorically excluded from the Store.
- [Naming review](docs/naming-review.md): Amid name approval and reasons for retiring the earlier Pulse brand proposal.
