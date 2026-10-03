# Dependencies and pinned toolchain

Original Amid code is MIT; see [LICENSE](../LICENSE). [Package.swift](../Package.swift) declares only local targets: CAmid, AmidCore, AmidApp and amid-probe. No external Swift packages or network-fetched runtime dependency is declared. The application needs no Python/Node runtime, account, model download or Serel installation.

Runtime uses Apple SDK facilities: Swift/SwiftUI, AppKit, Foundation, Charts, CryptoKit, Security, LocalAuthentication, ServiceManagement, UserNotifications, IOKit and public Darwin/libproc/Mach interfaces. Apple supplies these platform components under its SDK/platform terms; Amid does not relicense them. XCTest and the owned Node/Python/Swift fixture runtimes are development/test dependencies. Fixtures must record the versions actually run; a missing runtime leaves that fixture gate open rather than installing it silently.

## Observed build baseline

Read-only tool queries on 2026-10-02 returned:

| Item | Pin/observation |
| --- | --- |
| Xcode | 27.0, build 27A266a |
| Swift | Apple Swift 6.4; swiftlang-6.4.0.34.1; clang-2100.3.34.1; swift-driver 1.168.6 |
| SDK | macOS 27.0 |
| Host | arm64 macOS 27.0.1, build 26A434 |
| Language/minimum target | Swift 6 language mode; macOS 15 in Package.swift |
| Tool selection | Per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global xcode-select change required |

These values reproduce the inspected host, not a claim of macOS 15 runtime compatibility or an automatically supported future SDK. Build/test scripts use project-owned module/package caches and disable SwiftPM's nested build sandbox when necessary. The fixture's separate swiftc invocation initially failed because its module cache was not writable in the execution sandbox. Integration repaired that path. Later package builds passed after the storage and lifecycle fixes; exact candidate hashes and test boundaries are recorded in docs/evidence/candidate.md. Successful compilation/signature verification does not establish latest native UI acceptance.

Development workflow tooling, never linked or bundled: Serel Memory v0.6.0 at `5f99244d648735db94429bf4e77571325160e5ec`; Serel Kit v0.2.0 at `a4b7b29b9b80e72294e601da2c264f8a9082a795`. Their MIT notices are preserved under LICENSES/. They govern project memory/verification workflows only.

Local packaging currently prepares an app and owned development fixture with ad-hoc signatures. This is neither a Developer ID signature nor notarization. Distribution adds an authorized signing/notarization workflow; it does not add runtime telemetry or update traffic. See [release gates](release-gates.md).

## Optional externally built reviewed development server

`scripts/build-supported-darkhttpd.sh` optionally downloads the single official darkhttpd v1.17 source at commit `3075d35e1d2deb65ed8b079137c4ae1213de4b48`, verifies its SHA-256 before applying the independently pinned cleanup-order patch, compiles only in a new /private/tmp directory, ad-hoc signs the new binary and verifies exact signed SHA-256/CDHash against public core constants. It neither installs globally nor launches, vendors or bundles a server. The embedded ISC and BSD notices remain intact; source, patch, corrected source and binary provenance are recorded in [corrected-build evidence](evidence/darkhttpd-corrected-build.md).

Two stage-1 absolute-source-path rebuilds reproduced the pinned binary; the final optional script also exited 0 on the observed Xcode 27 arm64 host. A relative source invocation produced a different linker UUID/signature and was rejected; the script uses the exact reviewed absolute invocation. Future toolchains or differing bytes are rejected rather than self-enrolled. The binary basename stays darkhttpd because ad-hoc signing identity affects its digest. Deployment target 15 is not macOS 15 runtime proof. Amid's normal build/application remains free of third-party runtime packages and server downloads.
