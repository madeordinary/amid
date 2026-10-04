# Sampler instrumentation diagnostic

Observed 2026-10-04 UTC, arm64 macOS 27.0.1. A test-only synchronous actor extension wraps `sample` and `profiledSample` uniformly in own-current-thread measurement, beginning before profile initialization. One retained sampler made two available warmups five seconds apart, followed by twelve anchored five-second samples: normal/profiled/profiled/normal repeated three times. No application code changed.

The ordinary focused test built and explicitly skipped its one opt-in case. An initial build hit default module-cache denial; rebuilding with project-local caches exited 0. The enabled release case then **passed, exit 0, in 65.173 seconds**. All six listed source inputs stayed unchanged. No full-suite or application package rerun was performed; the frozen Counters executable remains SHA256 `52d1e49ca7cb1f03903b68f797decd5b1ec60f779a31b2ccd9f30dee0e9b3e6c`.

| Path | Samples | Mean own-thread CPU/sample | Mean wall/sample | Observed process range |
| --- | --- | --- | --- | --- |
| Normal | 6 | 18.8695 ms | 19.058292 ms | 647–661 |
| Profiled | 6 | 25.2585 ms | 27.889236 ms | 648–659 |

The descriptive mean difference is 6.389 ms. Host workload and readable counts changed; six samples per path do not establish a paired causal difference or a production saving. Both wrappers include numeric measurement cost. Sixty-four empty wrappers reported 68 microseconds total CPU, 1.0625 microseconds mean and 5 microseconds maximum; timer quantization permits zero CPU readings. Calibration is reported, never subtracted from acceptance measurements.

Whole-test process measurement includes warmups, calibration and both paths: 65.1634045 seconds, 0.400231 CPU seconds, 0.6141959633% of one core, lifetime peak RSS 33,357,824 bytes. Interrupt/package-idle counter deltas were 627/7; they are separate counters, not all wakeups. This mixed test-process result is not normal collector utilization, GUI overhead or a sustained budget pass. [Anonymous numeric rows, calibration aggregate and hashes](sampler-instrumentation-overhead.json) preserve all twelve readings.

## Latest GUI attempt remains invalid

The frozen Counters app requested 1800 seconds with a fresh synthetic 76-entity/week seed. Although `pmset` initially said AC Power, actual sampled policy requested only 10-second battery cadence; native thermal state was Nominal. The attempt ended early via CUA Command-Q: 15 accepted samples over 147.054 seconds, requested cadence min/max 10 seconds, report invalid because the app quit before completion. App child and retained parent exited 0 without launcher signal. Late native Raise/disclosure interaction is included; no late UI-cost comparison or CPU/RSS acceptance follows.

Next: establish actual sampled default-five-second readiness before another sustained GUI run. This diagnostic introduces no runtime fix and cannot justify subtracting profiling cost from any acceptance report. Reference hardware, matched baseline, visible-History cost and complete GUI gates remain open.

## Repeat the opt-in diagnostic

Use the recorded Xcode/SDK and project-local caches:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" swift test -c release --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" --filter SamplerInstrumentationOverheadTests
AMID_SAMPLER_OVERHEAD=1 AMID_SAMPLER_OVERHEAD_OUTPUT=/private/tmp/amid-UNIQUE.json xcrun xctest -XCTest AmidCoreTests.SamplerInstrumentationOverheadTests/testOptInSamplerInstrumentationABBA "$PWD/.build/arm64-apple-macosx/release/AmidPackageTests.xctest"
```

Replace UNIQUE with a fresh owned filename; overwrite is refused. Normal public metadata visibility was available for the observed enabled run outside the tool sandbox. No monitored identities, paths, arguments, environments or payloads are serialized. Source review was same-model, not an independent Claude review.
