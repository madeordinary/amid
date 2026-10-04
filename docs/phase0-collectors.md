# Collector capability evidence

The collector uses the macOS SDK's public libproc headers, Mach host statistics, Foundation volume metadata, public IFALLDATA 64-bit interface counters, IOKit power-source descriptions and Dispatch memory-pressure notifications. It requires no root helper, process task port, Accessibility, Full Disk Access or network connection. The deployment target is macOS 15; only arm64 macOS 27.0.1 has been observed here. Older OS coverage remains unverified.

## Metadata contract

| Field | Source and definition | Missing/reset behavior |
| --- | --- | --- |
| Process identity | Boot session UUID, PID, real UID, BSD start seconds/microseconds | Inaccessible/exit identities are omitted and counted; start identity checked before/after metadata |
| Process CPU | rusage user+system nanoseconds; task-info fallback | First/reset/identity-change/counter regression is nil; percent of one logical core, may exceed 100 |
| Process memory | rusage physical footprint; task-info RSS fallback | Nil if both fail; every result labels its method |
| CWD | PROC_PIDVNODEPATHINFO current directory path | Nil when denied; no permission escalation in app |
| Project | Explicit containing root (longest matching path) wins; otherwise nearest marker within twelve ancestors | Unknown if no marker; no file contents or recursive indexing |
| Application | Outermost .app path containing executable; otherwise exact executable path | Individual identity when executable unknown; no parent ancestry inference |
| TCP listeners | PROC_PIDLISTFDS and PROC_PIDFDSOCKETINFO, TCP LISTEN only | Available empty means successful scan; denied/unavailable explicitly flagged; 256-listener bound |
| System CPU | Mach host cumulative ticks, normalized across logical cores | First/reset/regressed counters nil |
| Memory | Mach VM page categories, physical memory, vm.swapusage | Unknown categories/swap nil; categories are not summed into a diagnosis |
| Memory pressure | Public Dispatch memory-pressure change notifications | Unknown until a normal/warning/critical event arrives; no undocumented pressure sysctl |
| Volumes | Foundation mounted local volume capacity and available capacity | Missing metadata nil; shared APFS capacity may overlap |
| Interfaces | public IFALLDATA `ifmibdata.ifmd_data` 64-bit byte counters, per-interface deltas | First/reset/regression nil; virtual classification is a conservative name heuristic (non-en), not hardware proof |
| Battery/thermal | IOKit internal battery description; ProcessInfo thermal state | Power/thermal metadata refreshes at most once every ten seconds and immediately after baseline reset. No battery means nil; health condition from documented power-source description keys when present, otherwise unavailable; thermal is qualitative, not temperature |

Recognized runtime labels are executable-name facts for Node.js, Python, Swift, Codex CLI, Claude Code CLI, Gemini CLI and Ollama, not claims about agent state or server behavior. Arguments, environments, source/config contents, prompts, credentials and socket payloads are never requested. Bundle grouping reads path metadata only. Marker filenames are `.git`, `Package.swift`, `package.json`, `pyproject.toml`, `Cargo.toml`, and `go.mod`. Marker results are cached only for the current sample, preventing repeated checks for a shared CWD while allowing changes next sample.

## Observed host evidence

An isolated native C probe on 2026-10-01 inspected only its own PID and host aggregate counters. Under the Codex tool sandbox: identity, CPU cumulative time, physical footprint, CWD, FD enumeration, system CPU and VM categories succeeded; swap was unavailable. The same disposable executable outside that tool sandbox, still unprivileged, observed swap successfully. No credentials, privileges or service connections were involved. A temporary experimental kernel pressure sysctl was removed from shipping code; Dispatch is the supported pressure source and deliberately starts unknown.

The Swift sampler revalidates UID/start identity after socket enumeration so a replacement PID cannot inherit endpoint metadata or deltas. UI lifecycle must call resetBaselines on wake; the sampler does not itself own app sleep notifications. Snapshot cadence describes caller policy, not a timer managed by Sampler. Snapshot duration records actual elapsed collection time.

## Verification and outstanding gates

`CollectionTests` covers UID/PID/boot/start identity differentiation, bounded nearest-marker attribution with unread sensitive contents, explicit project roots (including a root above a nested marker), conservative app grouping, own-process live memory/CPU/reset behavior and an owned loopback TCP listener without connecting to it. Tests never terminate processes. Build and test results are recorded below after execution.

Minimum macOS 15, actual M1 workload, long observer-overhead gate, sleep/wake integration, attribution precision across browser/helper/native-project fixtures and battery hardware transitions remain external or integration gates. No percentages or compatibility guarantees are inferred from unit tests.

Observed validation: collector-only harness built with Xcode 27.0 / Swift 6.4 / SDK 27.0. Five XCTest cases ran; tool-sandbox run passed four and skipped the denied loopback bind. Xcode's `xcrun xctest` runner outside the tool sandbox then passed all five with zero skips/failures (2026-10-01 22:35 local test log). The fixture bound an ephemeral 127.0.0.1 TCP listener, sampled its owning PID, verified its endpoint, and closed the socket; no client connected. The full app integration build is tracked separately because UI was still being authored.

Final collector update (2026-10-02 08:27 local): the uninstrumented collector-only harness passed eight tests outside the tool sandbox, with zero skips and failures. Coverage includes lazy construction, bounded traversal and explicit roots, PID identity/reset, real memory/CPU, and an owned listener. The CPU workload consumed 1.118129 seconds by `getrusage`; sampler CPU was 99.9506% against the reference 99.9996%. Both public process counter paths convert Mach ticks through the cached timebase before calculating CPU. The earlier raw-unit benchmark is invalid and retained separately in the evidence directory.

A short disposable profiler compared thirty rapid samples of copied collector source on this host. Own-process CPU total fell from 0.923238 seconds to 0.655274 seconds after replacing repeated Foundation path traversal with strings, using `access(F_OK)` for marker existence, and extracting executable basenames without URL construction. Process counts and host conditions varied. These short instrumented comparisons identify a candidate improvement; they do **not** establish the sustained five-second observer budget, reference-M1 performance, or full-GUI overhead. Product code contains no profiling instrumentation. A fresh sustained benchmark of the final integrated build remains required.

Sampler now reports requested cadence separately in `expectedCadence`, including unavailable samples, so consumers can detect delayed sampling even when display cadence records the actual interval. Construction still starts no boot-session read or pressure observer; those begin on the first authorized sample.

Current interface follow-up (2026-10-04 UTC): [full-width counter evidence](evidence/interface-counter-followup.md) records 18 mocked interface cases and a 26-row numeric API-path comparison. Denied/short/overflow replies remain unavailable. Native/minimum-OS and sustained GUI acceptance remain open.
