# Full-GUI phase profile — 2026-10-02

The short baseline completed continuously on the current Mac. It is diagnostic evidence, not the required 30-minute performance pass.

## Frozen baseline

`build/AmidProfileBaseline.app` uses bundle ID `com.madeordinary.amid.profilebaseline`. Packaging and strict ad-hoc verification exited 0. The [source and executable manifest](gui-profile-baseline-source.json) captures the instrumentation-only build before the later output-path guard or runtime string-sharing changes. It preserves the preceding runtime behavior; profiling is explicitly enabled.

Launch returned exit 0. The actual Overview was observed during warmup through native CUA. The tool selection took 44.75 seconds; this is not an app-latency measurement. Own evidence initialized at 20:04:25 CDT, accepted six warmup samples, and entered measurement at 20:04:56. No builds or other profiling runs occurred during measurement; only source review/edits and evidence reads continued.

```sh
open -n "$PWD/build/AmidProfileBaseline.app" --args \
  --performance-verification --benchmark-retention week --benchmark-hidden \
  --benchmark 180 \
  --benchmark-output "$PWD/build/gui-profile-baseline-180.json" \
  --profile-pipeline-output "$PWD/build/gui-profile-baseline-phases.json"
```

The run completed at 20:08:00: 184.076811 seconds, 35 accepted samples, zero unavailable samples or invalidations, requested cadence 5 seconds, maximum gap 5.364210 seconds, and 616 observed processes at completion. Whole-app CPU was 2.391612 seconds, or 1.299247% of one core. Lifetime peak RSS was 155,631,616 bytes (148.421875 MiB); a short run does not establish the filled-ring or 30-minute RSS budget. Public own interrupt/package-idle wakeups were 561/12, separate counters with no total-wakeup claim.

| Phase | Own-process CPU seconds | Approximate share of one core over the interval |
| --- | ---: | ---: |
| Collection | 1.217482 | 0.6614% |
| History ingest | 0.731334 | 0.3973% |
| Alerts | 0.103271 | 0.0561% |
| Grouping | 0.030838 | 0.0168% |
| Publication, expiry, store sync, alert records, notifications | 0.010941 | 0.0059% |
| Residual | 0.298444 | 0.1621% |

Each phase measures the app's CPU across all threads during that wall interval. In particular, ingestion follows observable publication and can include concurrent SwiftUI work. The table does not attribute all ingestion-interval CPU to the store. Residual includes timers, rendering, other tasks, uninstrumented work and counter overhead. The profile starts after benchmark begin/status serialization and finishes after the final benchmark serialization: 184.078038 seconds and 2.392310 CPU seconds, close to but not identical to the primary report.

After completion, Command-Q on the reidentified app confirmed `App quit`. Both reports retained their hashes after quit:

- [Primary report](gui-profile-baseline-180.json): `b876187ffe92df15bdeca5f7f201220634962f45692599c6a554cc9920b0059f`.
- [Phase report](gui-profile-baseline-phases.json): `a2c84002e12d4b28fd75b6f80fd5e765c91cf374326438c9362b6cca0e759e50`.

All owned apps and servers were exited at this checkpoint. This host remains Mac17,9 / 24 GiB / 15 logical cores / macOS 27.0.1; no reference-M1 or matched-baseline claim is made.

## Follow-up under verification

Review identified an output-path collision that could replace primary benchmark evidence with the profiler schema. The baseline used distinct paths, so that defect was not triggered. The follow-up guard rejects canonical collisions with both primary and status outputs. These later source changes are not represented by the frozen baseline executable.

The next measurement separates synchronous store-thread CPU from concurrent UI CPU using numeric counters for the app's own current thread only. The memory candidate reuses equal, freshly collected string storage by full process identity; it never skips metadata collection or identity validation. Both require focused checks and another actual GUI observation before any performance claim.

Verification follow-up: the release run at 20:14:18 exited 1 with the two intended menu-observation failures plus one discovered output-alias guard failure. All three own-thread tests passed. After correcting the scalar attention dependency and resolving existing output parents, the release run at 20:15:28 exited 0: 30 tests, zero skips or failures, covering profiler accounting, output guards, own-thread ownership/parity, menu observation, benchmark continuity, notification delivery, stop lifecycle and verification paths. Before (local record: `profile-menu-regressions-before.log`), after (local record: `profile-menu-regressions-after.log`). A further conservative case-insensitive output guard is under focused verification; the 30-test result is not relabeled as testing that later change.

The case-insensitive reserved-output regression subsequently passed in a focused release run at 20:16:50: eight profiler tests, zero skips/failures, exit 0. Log (local record: `profile-output-case-guard-tests.log`). This guard conservatively rejects case-only variants even on case-sensitive volumes. It avoids relying on the host volume's case behavior for evidence separation.

## Candidate short GUI run

`build/AmidProfileCandidate.app` was packaged and strictly ad-hoc verified with exit 0. It includes the string-storage and scalar-attention changes plus process/current-thread instrumentation and output guards. [Source/executable manifest](gui-profile-candidate-source.json). The same protocol used separately named `gui-profile-candidate-180.json` and `gui-profile-candidate-phases.json` outputs. Actual Overview was observed during warmup; the CUA selection took 70.18 seconds, not an app-latency measurement.

Own measurement ran 20:20:41–20:23:45 CDT after six warmups: 184.330666 seconds, 35 accepted samples, zero unavailable samples or invalidations, requested cadence 5 seconds and maximum gap 5.396190 seconds. Whole-app CPU was 2.200257 seconds (1.193647% of one core); lifetime peak RSS was 135,593,984 bytes (129.3125 MiB). This is still too short to pass the sustained CPU/RSS gate. The workload changed from 616 observed processes at the baseline's completion to 686 here; the before/after numbers do not isolate either production change's contribution.

The separate current ingestion-thread counter recorded 0.090376 CPU seconds over 35 calls, versus 0.667772 own-process CPU seconds during the awaited ingestion intervals. Substantial work occurred on other threads or while awaiting main-actor continuation; the difference is not proof that all of it was rendering. Own collection-interval CPU was 1.138754 seconds. One phase was still in flight at finalization, so the profiler correctly omitted summed/residual CPU rather than inventing a complete attribution.

After completion, the exact candidate app was quit with Command-Q and `App quit` was confirmed. [Primary report](gui-profile-candidate-180.json) and [phase report](gui-profile-candidate-phases.json) hashes matched their originals after quit. No builds or other profiling runs overlapped this valid measurement. All owned apps and servers are exited.

The next bounded investigations are repeated formatting work in the UI and retained-history load memory. A separate fresh-process, 21-entity seven-day fixture reached about 208 MiB RSS without the GUI or raw ring, so the initial raw-string improvement does not settle long-retention memory. No larger retained-history fixture or storage redesign is claimed here.

## Formatting and hidden-Overview diagnostics

The synthetic MainActor byte-formatting comparison completed 21,600 calls per variant with exact output parity. The current convenience API used 0.032242 CPU seconds; a reusable local formatter used 0.031162 seconds. The 1.08 ms difference over all calls does not justify a production formatter cache or locale-observer machinery. Two tests passed with no skips/failures, exit 0. [Numeric result](byte-format-profile.json), test log (local record: `byte-format-profile-tests.log`).

A subsequent verification-only flag, `--profile-suppress-hidden-overview`, is effective only together with `--performance-verification`. It suppresses only hidden Overview content and explicitly labels initial status/final benchmark evidence `hiddenOverviewSuppressed`, including a diagnostic-only acceptance disclaimer. Normal presentation, collection, publication, history and alert behavior remain unchanged. A separate synchronous `Sampler.profiledSample` wrapper measures numeric own-current-thread collection work; its supplemental counters are never added again to whole-process phase totals.

The focused release run at 20:39:23 passed 27 tests with one opt-in formatting skip and zero failures, exit 0. Source review found no actionable issue in gating, initial/final evidence labeling, cadence preservation or double-counting boundaries. Test log (local record: `hidden-overview-profile-tests.log`). These tests are not measured performance evidence.

The frozen comparison package `build/AmidProfileOverview.app` packaged and strictly ad-hoc verified with exit 0. Its [manifest](gui-profile-overview-source.json) predates the later test-only history stage observer. Two sequential fresh-store 180-second comparisons use this identical executable, normal first and suppressed second. Both intervals completed and the app was quit normally after each. Reports were copied before quit and remained byte-identical afterward. A suppressed run can identify a rendering contribution but can never replace a normal-app acceptance run.

| Same-executable run | Normal Overview | Hidden Overview suppressed |
| --- | ---: | ---: |
| Measurement CDT | 20:48:00–20:51:00 | 20:52:32–20:55:32 |
| Elapsed seconds | 180.152847 | 180.620021 |
| Warmup / accepted samples | 6 / 33 | 3 / 29 |
| Unavailable / invalid reasons | 0 / none | 0 / none |
| Requested cadence range | 5–10 s | 5–10 s |
| Observed processes at completion | 1,036 | 1,092 |
| Whole-app CPU seconds | 2.667652 | 1.760363 |
| Mean one-core CPU | 1.480771% | 0.974622% |
| Lifetime peak RSS | 128.328125 MiB | 135.984375 MiB |
| Own collection-thread CPU | 1.121617 s | 1.165440 s |
| Own ingestion-thread CPU | 0.160717 s | 0.125782 s |
| Whole-process ingestion interval CPU | 1.063381 s | 0.209547 s |
| Own interrupt / package-idle wakeups | 446 / 1 | 370 / 3 |

Actual Overview was observed during each warmup, before automatic hide. The second warmup showed Fair thermal state and external power; neither was changed by the test. CUA selection durations (35.63 s and 1.29 s) are not app-response measurements. The app followed its existing thermal/battery cadence policy; different sample counts and growing external workloads prevent a controlled subtraction. No builds or other profiling ran during either measured interval.

The drop in whole-process ingestion-interval CPU with similar own ingestion-thread work supports a hidden-Overview rendering contribution. It does not quantify an isolated saving. Collection itself used more than 0.5% of one core across both intervals; suppressing Overview cannot alone meet the complete budget. Normal rendering and preserving hidden-window state still need a production strategy. The suppressed report has an explicit diagnostic label; neither short result is a normal sustained pass. One phase was in flight at suppressed finalization, so summed/residual CPU remains unknown rather than being reconstructed afterward.

[Normal primary](gui-profile-overview-normal-180.json), [normal phases](gui-profile-overview-normal-phases.json), [suppressed primary](gui-profile-overview-suppressed-180.json), [suppressed phases](gui-profile-overview-suppressed-phases.json). SHA-256 values respectively: `f2ae58f226932eab038b077b080ff41c7b9d3a26e1cfa02252661b013e891ff0`, `c8773493a69c3cfd41f04477a18d35d33929ebc8684c449a16454abde6ef8a8c`, `61424957d103c4ee16262b11dcad2316513e58243e776d372099bcd3e88dae02`, `df54155ae7a7b1b003bd8112c5283bff7cc05bf43da333a54265e29aa3ee985e`.

The later synthetic executable-derivation comparison also did not justify a production memo. At 650 processes per simulated sample, a repeated-path fixture saved 0.84–0.92 ms/sample, while 650 unique paths were slower with the memo. Three regular/opt-in tests passed without skips/failures, exit 0. Exact-UTF8 keys preserved byte-distinct Unicode paths and identity/name fallback for unavailable executables. [Numeric result](executable-derivation-profile.json), tests (local record: `executable-derivation-profile-tests.log`). No runtime memo was added.

## Production Overview presentation under native verification

`OverviewPresentation` stores the current system values and at most six application/four project display rows. It retains no raw process arrays or resource groups. Accepted publications update it only while the full window is visible; showing the window synchronously restores the latest accepted values. The normal Overview subtree and ScrollView stay in place. Its aliases/actions still use existing model identity, and the menu continues to consume live measurements.

A cleared-source guard prevents on-show repopulation after Clear, suspension or quit until a new accepted publication. Those lifecycle paths clear presentation before their first await. Fifteen-minute presentation expiry runs before the optional store early return, for every retention choice even without a store. Existing generation, sampling, action and notification guards remain.

The final release focus at 21:05:06 passed 27 tests with no skips/failures, exit 0, covering presentation bounds/unknowns, actual publication parity, hidden Observation silence, show resync, expiry, clear/quit no-resurrection, lock/sleep, menu, stop, benchmark and queued notifications. Test log (local record: `overview-presentation-tests.log`). The initial compile-only failure was a missing test-module import, corrected before the successful runs and retained in its own log (local record: `overview-presentation-compile-error.log`). Source review found no actionable issue, including the final cleared-source guard. The later native checks below apply to this source; the earlier diagnostic executable does not contain it.

The frozen `build/AmidPresentation.app` includes production Overview presentation, conditional history-index reconstruction and the short system-reply guards. Package and strict ad-hoc verification exited 0. Its [source manifest](presentation-source.json) records executable SHA-256 `f91f539608d360e30b7980ab72e7aaeda96ddbf2f55274f6333c9a6aba4b8274`; the later decode-scope experiment is excluded. Actual disposable verification UI at 21:31–21:34 CDT showed fresh values, preserved scroll position through Hide/Raise, and no cleared values returning after paused Clear History and Hide/Raise. Resume first showed unavailable delta CPU, then fresh numeric CPU. [Native observations](presentation-ui-observations.md). This is not complete menu/VoiceOver/minimize/multiple-window verification.

## Normal presentation short profile

Run `738F0564-1167-4E61-BDA1-D4727214A975` used that exact frozen bundle, a fresh temporary encrypted week-retention store, normal presentation, 30-second warmup and a requested 180 seconds hidden measurement. No diagnostic suppression was enabled. Own evidence began at 21:36:03 CDT; measurement ran 21:36:35–21:39:44. No builds or other profiles overlapped measurement.

| Measurement | Result |
| --- | ---: |
| Elapsed / warmup / accepted samples | 189.477190 s / 3 / 18 |
| Unavailable / invalid reasons | 0 / none |
| Requested cadence / maximum gap | 10 s / 10.699988 s |
| Observed processes at completion | 1,082 |
| Whole-app CPU / mean one-core CPU | 1.275080 s / 0.672946% |
| Lifetime peak RSS | 122,404,864 B / 116.734375 MiB |
| Own collection-thread / ingestion-thread CPU | 0.861823 s / 0.110393 s |
| Whole-process ingestion interval CPU | 0.168861 s |
| Own interrupt / package-idle wakeups | 332 / 6 |

CPU still exceeds the 0.5% target. The ten-second cadence and different workload prevent isolated savings claims against earlier five/mixed-cadence results. Collection alone accounted for about 0.455% of one core during this interval. This short run does not pass the 30-minute gate or establish filled-store/reference-hardware behavior.

After completion, CUA Raise and a subsequent rendered/AX observation showed current Overview values and coverage again. The app reported On battery and Nominal thermal state at that post-run observation; neither was changed. No screenshot containing the live application/project names was saved. Command-Q returned `App quit`, and both reports remained byte-identical after quit. [Primary](gui-profile-presentation-180.json), [phases](gui-profile-presentation-phases.json), SHA-256 respectively `240b0c9852e0d4ab98ecacfd7ba3208a1d8529bfb9b3c30600552340c13a1199` and `033b1a585fab1dc7e03f0fa05526202bd49ea085f4ea816420b01628af81e02c`.
