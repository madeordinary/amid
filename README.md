# Amid by Made Ordinary

Amid is a native, offline Mac activity monitor for applications, development projects and listening TCP ports. It requires Apple silicon and targets macOS 15 or later. Local development builds have run on macOS 27.0.1. Owned native checks cover history clearing/recovery and confirmed supported-server stopping. An uninterrupted 30-minute full-GUI run completed but exceeded both CPU and memory budgets. Further native checks and diagnostic comparisons need the Mac awake and unlocked; minimum-OS compatibility and public-release gates remain unverified.

Latest local development checkpoint: `build/AmidHistoryLoading.app` passed 180 release tests with nine opt-in profile skips and no failures, nine C reply cases, packaging and strict ad-hoc verification. [Candidate evidence](docs/evidence/history-loading-candidate.md) and [exact manifest](docs/evidence/history-loading-candidate-source.json) record its native synthetic-history selection checks and limits. Earlier [paged core measurements](docs/evidence/paged-history-candidate.md) show lower 76/350-entity loaded memory; full-GUI CPU/RSS acceptance remains open. This is a local development candidate, not a public binary release.

Source is published as a development preview under MIT. See [repository hygiene](docs/repository-hygiene.md) for tracked files and the clean public history boundary.

## Build and run

Use Xcode 27.0 (27A266a), Swift 6.4 and SDK 27.0 for the recorded build. Scripts select this installed Xcode per command without changing the machine's global toolchain selection. No third-party runtime packages, Python or Node are needed to run Amid.

```sh
git clone https://github.com/madeordinary/amid.git
cd amid
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
open build/Amid.app
```

The package is locally ad-hoc signed. It is not Developer ID signed or notarized. Do not distribute it as a public release. The native SwiftPM build engine is selected because the default engine's dSYM step failed in the agent's tool sandbox; the native-engine option is deprecated in this Swift toolchain.

Choose Off, 24 hours, 7 days or 30 days at onboarding. No sampling starts before that choice. Off keeps a 15-minute RAM ring; lock and quit clear it. Notifications and launch at login start off and require your choice. This build has no updater and makes no update requests.

For disposable UI verification, use:

```sh
open -n build/Amid.app --args --verification
```

This mode uses temporary encrypted storage with an ephemeral key. It filters the displayed process list to Amid-owned executable names. It does not prove production Keychain persistence or full-workload storage overhead. Normal mode stores encrypted app data in `~/Library/Application Support/Amid` and uses an app-specific Keychain key.

## Find applications, projects and ports

Use Overview or Applications to inspect observed CPU and memory. CPU is 100% per logical core and may exceed 100%; normalized capacity is shown in the inspector. Physical footprint is preferred, with RSS fallback or mixed methods labeled. App and project totals overlap and must not be added together.

Projects use accessible working directories, bounded ancestor traversal and project-marker existence. Amid does not open source or config contents. Add an explicit root boundary in Settings for a nested workspace; rename or exclude a group in its inspector. Separate worktree paths remain separate projects.

Ports shows observed listening TCP endpoints, address scope, protocol family and exact process ownership. It does not scan, connect to services or inspect network payloads. Missing or protected ownership stays outside coverage. Generic Node/Python processes remain generic when identifying a tool would require reading its arguments.

Command-1 through Command-7 switch destinations. Command-R refreshes; Command-Shift-P pauses or resumes. The menu-bar panel opens the full window. History includes a text table beside the chart; coverage, missing values and gaps are explicit.

## Graceful-stop scope

The source supports the bundled development fixture and one independently pinned, corrected darkhttpd v1.17 build. Generic Node/Python/Swift servers, terminals, databases, model runtimes, containers and other applications remain read-only. Owned integration tests and native UI checks observed the real-server declaration, cancellation, fresh-preview reset, expired-preview refusal and one confirmed stop. See [native observations](docs/evidence/acceptance-ui-observations.md); this evidence covers only the reviewed adapter and owned test server.

```sh
bash scripts/start-demo-server.sh
```

The disposable loopback server exits naturally after five minutes. In Amid, find `AmidFixture` in Ports or its project, inspect it, and review the graceful-stop preview. Only your confirmation permits one audit-token-bound SIGTERM after identity, ownership, running-code hash, project and endpoint validation. Changed or expired previews are refused. There is no retry, group signal or force kill. Verification reports remaining identities/endpoints without promising that a port will stay free.

To build the optional external server with the tested toolchain:

```sh
bash scripts/build-supported-darkhttpd.sh
```

The script verifies upstream source, the cleanup patch and the resulting binary identity, then prints its temporary location. It does not install or launch anything. Keep the executable name `darkhttpd`; different builds remain read-only. Supported use is foreground static-file serving as the current user, on IPv4 `127.0.0.1`, without daemon, chroot, user/group switching, PID-file, syslog or redirect options. Start it yourself from the intended development project; Amid does not infer the served directory from the working directory.

Every reviewed real-server stop requires a fresh declaration of that supported development use, then confirmation of the exact target. The declaration supplies user intent; Amid does not read launch arguments. Active transfers may be interrupted. [Source, patch and owned shutdown evidence](docs/evidence/darkhttpd-corrected-build.md) and [controller safety evidence](docs/action-safety.md) define the tested boundary.

The automated native fixture tests create only their own Node, Python and Swift workloads:

```sh
bash scripts/test-fixtures.sh
```

The test needs local Node/Python plus the pinned Swift toolchain. See [action safety](docs/action-safety.md) for exact adapter scope and identity-race evidence.

## Privacy and recovery

Amid never reads monitored command arguments, environments, prompts, source contents, editor buffers, clipboard, credentials or network payloads. It has no account, analytics, cloud storage, automatic crash uploads, root helper, Full Disk Access requirement or Docker-socket adapter.

Retained aggregates, preferences, aliases and retained event/action records are encrypted with CryptoKit AES-GCM. Temporary files follow the same rule. A missing key or damaged store fails closed; there is no plaintext fallback. Retry history access after a transient Keychain/storage problem. Clear History removes app-managed records and caches while preserving preferences and aliases. It does not erase exports, backups or OS crash dumps, and does not promise forensic SSD erasure.

Diagnostics shows a frozen preview of the exact JSON before a local save. Default fields omit full project paths, usernames, command arguments, remote endpoints and process payloads. User-chosen aliases can still identify something; review them before exporting. There is no upload action.

## Evidence and release status

The [latest short loaded-app run](docs/evidence/history-loading-gui-short.json) completed 188.208 seconds at 0.404334% of one CPU core and 106.031250 MiB lifetime peak RSS. This is a three-minute battery-mode check at a ten-second interval, not the required sustained five-second/reference-hardware pass.

A successful build does not establish all PRD gates. The first CPU benchmark used incorrect Mach-tick units and remains invalid evidence. The optimized collector-only run measured 0.41994% of one core over 1,801 seconds with peak RSS 12,615,680 bytes; it does not establish full-app performance.

The [completed uninterrupted full-GUI run](docs/evidence/gui-benchmark-checkpoint-completed.json) measured 1.559615% of one core and peak RSS 160.265625 MiB over 1,803.225 seconds, exceeding both budgets. A [later short candidate](docs/evidence/gui-profile-candidate-180.json) measured 1.193647% and 129.3125 MiB over 184.331 seconds. Different workloads and duration prevent treating it as a sustained pass or attributing the change to one optimization. Its [numeric phase report](docs/evidence/gui-profile-candidate-phases.json) separates current-thread ingestion work from concurrent whole-process cost.

A separate [21-entity, seven-day retained-history loader](docs/evidence/retained-history-memory-21-week-load.json) reached about 207.89 MiB RSS without the GUI or raw ring. That historical all-row loader has been replaced by authenticated bucket paging; [76/350-entity core results](docs/evidence/paged-history-candidate.md) are separate from full-GUI acceptance. No passing sustained full-GUI result or matched reference-hardware baseline exists. The [handoff](docs/handoff.md) and [latest manifest](docs/evidence/history-loading-candidate-source.json) distinguish current source from preserved failed runs.

- [Short profiling candidate source and executable hashes](docs/evidence/gui-profile-candidate-source.json)
- [Native acceptance observations](docs/evidence/acceptance-ui-observations.md)
- [Requirement-to-evidence matrix](docs/requirements.md)
- [Collector capabilities](docs/phase0-collectors.md) and [storage design](docs/storage-design.md)
- [Release gates](docs/release-gates.md) and [two-week beta plan](docs/beta-plan.md)
- [Dependency/license inventory](docs/dependencies.md) and [localization status](docs/localization.md)
- [Development handoff](docs/handoff.md)

Original app code is MIT. Serel Memory v0.6.0 and Kit v0.2.0 are installed development workflows, with both Claude and Codex adapters and hooks off. They are not shipped runtime dependencies. Working memory and verification maps are private local files; public clones build and test without them. Contributor instructions and reusable testing/evidence documentation remain public. [Installation provenance](docs/serel-installation.md) records the pins and verification. `PRD.md` defines product scope; `GOAL.md` records the user's work authorization and genuine approval boundaries.
