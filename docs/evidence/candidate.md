# Historical local candidate, 2026-10-02 09:30 CDT

This record preserves the earlier compiled snapshot. Later resumed changes and observations are recorded in [resumed evidence](resumed-ui-observations.md); the hashes below do not describe current source or an overwritten bundle.

This is an ad-hoc local development candidate, not a completed v0.1 or public release. Native UI acceptance was pending at this checkpoint. The source has actual monitoring, encrypted history/alerts and tested narrow actions; broad production-server stopping and full-app/reference performance remain open.

- Implementation commit: `058e5a84bb47c3e80867f5cd265d195312fc253f`.
- Source fingerprint: `97194522754bc4ef95817c7794314e4e2295e2f0e408c99580e0ff477f72cb0f`; exact inputs and artifact hashes: [candidate-hashes.json](candidate-hashes.json).
- Bundle: `build/Amid.app`; arm64, `com.madeordinary.amid`, macOS15 deployment target.
- `bash scripts/package.sh`: exit0, latest release build35.40s; app and nested fixture signed ad-hoc, `codesign --verify --deep --strict` passed. No Team ID, Developer ID, notarization or upload.
- Bundle executable SHA256: `a5afc3dfa389324b036ff7de4ce5966ec2dc8a1f640cb49c76bf9ceb14430864`.
- Packaged fixture digest manifest matches its actual binary. Signing changes require regenerated digest/CDHash enrollment; never reuse these values for another signed build.
- Xcode27.0 build27A266a / Swift6.4 / SDK27.0 / arm64 macOS27.0.1 build26A434. Fixtures: Nodev22.21.1, system Python3.9.6 and pinned Swift toolchain. MinimumOS runtime remains unverified.

## Observed verification

| Check | Actual result and boundary |
| --- | --- |
| Integrated suite | `bash scripts/test.sh` exit0 at09:12:23:56tests,3explicit skips,0failures,246.061s. Includes thirty-day/1000-process synthetic history soak. Predates final expiry/baseline guards. Log (local record: `final-integrated-tests.log`). |
| Final affected code | Native SwiftPM targeted expiry/lifecycle/action/collector tests exit0 at09:26:11:24tests,1sandbox-owned-socket skip,0failures. Own CPU99.96195% versus reference100.06082%. Includes no-ingest RAM expiry and sampler reset. Log (local record: `expiry-integration-tests.log`). |
| Final owned integrations | `bash scripts/test-fixtures.sh` exit0 at09:27:07:one native integration test,0failures,24.238s, Node/Python/Swift coverage3/3. Expired authorization0signals, fresh trusted stop1SIGTERM, reused/substituted/exited targets refused; audit-token result0 and after-exitESRCH3. Log (local record: `final-native-fixtures.log`). |
| Own Keychain | Earlier isolated create/read/delete passed outside execution sandbox. No existing credentials were changed. Locked-Keychain recovery is unverified. Log (local record: `history-alerts.log`). |
| Collector overhead | Optimized1801s CPU0.419938% one core, peakRSS12,615,680bytes. Full-GUI report absent; matched baseline/wakeups/reference gates open. [Performance record](performance.md). |
| Privacy | Network-denied probe exit0; bounded owned-GUI observation had no socket rows. Frozen diagnostic export observed. [Privacy record](offline-and-traffic.md), [UI record](ui-observations.md). |
| Native GUI | Earlier actual bundle: onboarding, system/app/project detail, corrected Ports, alias/range/history, diagnostic export and exact fixture stop. Latest cache/Off history/Settings/light/window-visibility/120s copy changes needed a live recheck at this checkpoint. AX inspection is not VoiceOver speech. |

Resource plists/catalogs passed `plutil -lint`; Source/docs whitespace checks passed. Saved unified-diff proposals retain their required single-space context markers; those markers are checked separately. Failed/invalid earlier evidence is preserved and labeled. Independent review was unavailable; reviews were same-model GPT-6.1sol delegation plus integration-owner review.

## Resume

For a fresh verification run, launch `open -n build/Amid.app --args --verification --light-appearance`. Recheck the latest native paths using the nine verification maps. Re-run full-GUI timing only after observing initialization and measurement start, in a continuous active-monitoring interval. Do not infer completion from a live PID or absent output.

The active goal remains incomplete. No remote, push, PR, publication, machine-consent change or public signing was performed. See [requirements](../requirements.md), [release gates](../release-gates.md) and [beta plan](../beta-plan.md) for remaining technical/external gates.
