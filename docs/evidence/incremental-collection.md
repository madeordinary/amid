# Incremental process collection

Observed 2026-10-18 on arm64 macOS 27.0.1 (Apple M5 Pro), Xcode toolchain. This is not the reference M1 MacBook Air, and it is not a matched no-Amid baseline.

## Change

The app's sampler now reads CPU and memory for every process on every sample. A process's executable path, working directory, project and listening ports are re-read only in these cases:
- the process is new or younger than one minute;
- its name changed, which suggests `exec`;
- its cached metadata is older than a 30-second window, which is staggered per process.

Project-marker results are kept for 60 seconds instead of being rebuilt every sample. Stop validation and the command-line probe keep full reads (commit `c9bff74`).

The trade-off: for a long-running process, path, working directory, project and ports can be up to 30 seconds stale.

## Side-by-side collection measurement

`IncrementalCollectionExperimentTests` (opt-in, release build) alternated a full and an incremental sampler in ABBA order. It took 24 rounds at a five-second cadence after two warm-ups, with 603–628 readable of 833 enumerated processes. The measure is own sampler-thread CPU per sample.

| Mode | Mean | Median | Range |
| --- | --- | --- | --- |
| Full | 22.37 ms | 22.64 ms | 13.62–31.54 ms |
| Incremental | 9.20 ms | 7.91 ms | 3.87–22.61 ms |

At five-second cadence that is about 0.45% versus 0.18% of one core. The audit compared adjacent snapshots from both modes for 14,791 shared process observations and found zero differences in executable, working directory, project, application, endpoints or port availability. Host load varied, so the comparison is descriptive, not causal. The 22.61 ms maximum came from simultaneous first-cycle refreshes, before staggering was added.

A baseline profiled run of the full sampler, with instrumentation included, attributed process-loop wall time as follows:

| Work in the process loop | Time per sample |
| --- | --- |
| Kernel reads | 8.4 ms |
| Socket and identity rechecks | 4.8 ms |
| Application derivation | 4.2 ms |
| Project markers (1,523 checks per sample) | 4.1 ms |
| String decoding | 3.2 ms |

`IncrementalCollectionTests` cover four behaviours, which passed 10/10 repeats:
- the cached window holds while full reads see changes immediately;
- metadata refreshes after its window;
- a young server's late listener appears on the next sample;
- an `exec` forces an immediate re-read.

The full suite ran 234 tests with 23 opt-in skips and 0 failures, plus 27 C cases.

## Thirty-minute GUI run: INVALID

The bundle was `build/AmidIncremental.app` (executable SHA-256 `3ba04909fb2aa9342e45252e598c70b2752ff08afb3d6e95beb3e8b95c3ffa8c`), launched through LaunchServices. A first launch from a sandboxed shell had no window server connection; it was ended after one minute without measuring.

Settings: synthetic 76-entity, seven-day seed with 120,232 loaded aggregates; hidden normal presentation; week retention; a 30-second warm-up; requested cadence five seconds throughout.

| Measurement | Observed |
| --- | --- |
| Phase | **invalid**: monitoring suspended by a screen lock |
| Accepted samples | 296; last at 1,541.4 s of the 1,801.2 s interval; maximum gap 5.39 s; 0 unavailable |
| Whole-interval own-process CPU | 13.785 s, 0.7653% of one core, including about 260 s of suspended tail |
| Lifetime peak RSS | 161,284,096 bytes, 153.81 MiB, including seed import and startup |
| Wakeups (separate public counters) | 3,444 interrupt and 103 package-idle |

If the suspended tail used negligible CPU, the active-period mean would be about 0.89% of one core; that is an estimate only. The run cannot pass or fail the budget.

It suggests that, with collection near 0.18%, most of the remaining full-app cost is now outside collection: history ingestion, presentation and alerts. That needs a phase profile to confirm. The previous [collection-status run](collection-status-background.md) (0.7980%, mixed five- and ten-second cadence) is not directly comparable.

The owned instance wrote its report, then received one SIGTERM from the watcher that launched it. Raw report, status, logs and seed path are kept privately with the run.

## Three-minute phase profile

On 2026-10-18 the same bundle ran with `--profile-pipeline-output`, a fresh 76-entity seven-day seed and hidden normal presentation. The Mac was on battery (25%), so Amid's policy requested a ten-second cadence. The run **completed**: 18 accepted samples over 187.8 s with 676 processes at completion. It measured 0.5260% own-process CPU of one core and a lifetime peak RSS of 129.97 MiB, including the seed import.

| Phase | CPU per sample | Share of one core at 10 s |
| --- | --- | --- |
| Collection (profiled sampler) | 22.77 ms | 0.218% |
| History ingest (whole process during the interval) | 13.28 ms | 0.127% |
| Unattributed residual: timers, rendering, heartbeat | 11.7 ms per sample interval | 0.112% |
| Alert recording and evaluation | 5.31 ms | 0.051% |
| Grouping, store sync, publication, expiry | 1.92 ms | 0.018% |

Phase CPU is whole-process CPU during each phase's wall interval, so ingestion includes concurrent work. The ingestion thread's own CPU was 7.79 ms per call. Profiling mode times each process step, which inflates collection: the unprofiled side-by-side run measured 9.20 ms per sample. With that figure, per-sample work is about 30 ms. That is about 0.6% of one core at a five-second cadence before the residual, so history ingestion is now the largest single cost after collection.

This is descriptive: a short battery-cadence run on non-reference hardware, with no matched baseline. Memory rose from 130 MiB in this three-minute run to 154 MiB in the 30-minute run. A plausible but unverified cause is the 15-minute in-memory observation ring filling.

## Hidden-window re-render fix

Two causes kept the hidden main window busy. First, `AlertEvent` was not `Equatable`, so each sample's store sync reassigned the alert list and `@Observable` notified the window; comparable properties are already skipped when unchanged. Second, the sidebar status timer and the footer read per-sample state while hidden. Commit `05883d9` made `AlertEvent` `Equatable` and shows the timer and footer only while the window is visible.

A regression test fails without the conformance and passes with it. The full suite ran 236 tests with 24 opt-in skips and 0 failures, plus 27 C cases.

Direct ingestion measurement (`IngestCostProfileTests`, opt-in) used 681 live processes against the imported 120,384-record seed. Ordinary calls averaged 0.76 ms. Minute-boundary calls, which enforce retention and persist encrypted state, averaged 24.5 ms. That is 2.8 ms per sample at five-second cadence, so ingestion itself was not the large cost.

Alternating comparison on 2026-10-21: AC power throughout and a five-second cadence. Each run was 180 s and 35 accepted samples, with the same seed, a hidden window, normal presentation and the profiler enabled. Order was old, new, old, new. Old is `build/AmidIncremental.app` (`c9bff74`, `3ba04909…`); new is `build/AmidHiddenUI.app` (`05883d9`, `ed546718…`).

| Build | Own-process CPU of one core | Concurrent CPU during ingestion | Unattributed residual per sample | Lifetime peak RSS |
| --- | --- | --- | --- | --- |
| Old | 0.8938%, 0.9394%; mean 0.9166% | 4.44, 5.98 ms | 12.18 ms (one run unavailable) | 147.7, 126.2 MiB |
| New | 0.7508%, 0.6353%; mean 0.6931% | 0.07, 0.07 ms | 1.61, 2.45 ms | 135.8, 141.6 MiB |

The concurrent work during ingestion disappeared, and the residual fell by about 10 ms per sample. Mean CPU fell by 0.22 percentage points.

Every run includes the profiler's per-process timing. Profiled collection measured 18–24 ms per sample, against 9.2 ms unprofiled, so an unprofiled app is probably near 0.5% of one core on this Mac. That is an estimate: only an unprofiled 30-minute run can show it. Two runs per build are descriptive, not a statistical result. This is not the reference M1 or a matched baseline, and peak RSS varied between runs.
