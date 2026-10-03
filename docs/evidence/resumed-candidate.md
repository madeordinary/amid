# Resumed local candidate — 2026-10-02

This is a local ad-hoc development build, not a completed local goal or public release. Native UI verification was pending at this checkpoint. The preceding [09:30 candidate](candidate.md) and [pre-deduplication hashes](resumed-candidate-before-dedupe-hashes.json) are historical.

## Artifact identity

- Bundle: `build/AmidResumed.app`, rebuilt with exit 0 after final full-identity deduplication. It has not yet been launched. The older `build/Amid.app` running instance was preserved.
- Executable SHA256: `2f8d665bcb234551991b8349dac14a83cf488b5f23aad22ba133f71d14f3e8d6`.
- Source fingerprint: `a86e9dab962f6df95ec396a9c1d2fac97c8140e714271d857f265b47105d29f6` (canonical SHA256 map of Sources, Resources, fixtures, scripts, Package.swift and LICENSE).
- Exact source/test/bundle file hashes: [resumed-candidate-hashes.json](resumed-candidate-hashes.json). Reviewed implementation/evidence commit: 377adca (source base 752066c; initial implementation 058e5a8). The following memory checkpoint does not change the packaged source.
- Command: `AMID_PACKAGE_OUTPUT="$PWD/build/AmidResumed.app" bash scripts/package.sh`; actual exit 0, release build and strict deep ad-hoc signature verification passed. Package log (local record: `resumed-package.log`). The packaged fixture SHA256 equals its enrollment manifest. Ad-hoc signing is not Developer ID/notarization.
- Host/toolchain: arm64 macOS 27.0.1, Xcode 27.0 build 27A266a, Swift 6.4, SDK 27.0, macOS 15 deployment target. Minimum OS behavior is unverified.

## Observed checks and boundaries

| Check | Actual result | Source/evidence boundary |
| --- | --- | --- |
| Integrated `bash scripts/test.sh` | Exit 0 at 13:03:09 CDT; 78 tests, 6 skips, 0 failures in 260.035s | Log (local record: `resumed-integrated-tests.log`). Before the final dedupe change. Skips: sandbox loopback; opt-in native fixture, own-Keychain, synthetic profile, live profile and reviewed-server integration. |
| Owned `bash scripts/test-fixtures.sh` | Exit 0 at 13:06:32; one integration, no skips/failures, 24.344s | Log (local record: `resumed-native-fixtures.log`). Node/Python/Swift project/port fixture coverage 1.0 for that set; running-code substitution refused; one token signal and after-exit ESRCH 3. Before final pure grouping change. |
| Final focused release tests | Exit 0 at 13:15:51; 21 tests, no skips/failures, 9.080s | Log (local record: `resumed-final-focused.log`). Latest source: nine action, two presentation, two reviewed-server, two app stop-lifecycle and six aggregation/privacy tests. |
| Alert formatting trial | Eleven alert tests plus one opt-in synthetic profile passed | Log (local record: `alert-format-profile.log`). Late evaluation 1.068→0.309ms/sample at 650 processes/65 apps. This is not a full-GUI cost result. |
| Live pipeline trial | Actual exit 0; 0.720980% XCTest CPU over 61.096s | [Trial](live-pipeline-profile.json) versus [baseline](live-pipeline-profile-before-group-cache.json). Host counts changed. Includes a sampler cache removed afterward for no measurable benefit and earlier alert optimization; not final-source evidence. |
| Same-model source review | No remaining concrete finding after IPv4-only scope, excluded-mode declaration and action/history-generation fixes | GPT-6.1 sol root and bounded agents. Independent review unavailable; no independent audit claimed. |

The final focused command was:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
AMID_REVIEWED_DARKHTTPD=/private/tmp/amid-supported-darkhttpd-tLYDLCIB/darkhttpd \
swift test --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" \
  -c release --filter 'ReviewedServerAdapterTests|ActionTests|ActionPresentationTests|StopLifecycleTests|PrivacyAndAggregationTests'
```

The optional binary was built with `scripts/build-supported-darkhttpd.sh` and independently matched the compiled SHA256/CDHash pins. On another run, use that script's printed path instead of assuming the temporary path persists. An initial `--skip-build` invocation exited 1 because the root release test bundle did not exist; it ran no tests. The command above built that test bundle and then passed. Raw local logs were copied with the user-home prefix and boot UUID redacted; test-owned PIDs/start times remain for identity evidence.

## Actual native observations

[Resumed UI evidence](resumed-ui-observations.md) records the earlier package hashes and actual interactions: Off RAM history expired while paused for 15 minutes; resume had fresh unknown CPU; native Settings preview cancelled; light/dark paths were inspected; expired fixture preview sent zero signals and a fresh confirmed preview sent one SIGTERM. No UI claim is transferred to this later binary.

The full-GUI benchmark started after warmup, accepted 275 samples, then became invalid when the screen locked at 12:31 CDT. Its [final report](gui-benchmark-resumed-invalid.json) includes suspended time: 1.103341% CPU and 153.3 MiB lifetime peak RSS, both above targets. It is not a continuous, final-source, reference-hardware or matched-baseline pass. [Performance ledger](performance.md).

## Required next work

For a fresh verification run, launch this bundle with disposable verification storage. Verify the real-server declaration/confirmation, corrected unavailable results, store error/retry, Clear History preserving preferences/aliases, visibility cadence, keyboard/menu and remaining nine-map flows. No store fault injection has started in the old verification directory. Complete and, if needed, optimize a fresh continuous 30-minute GUI measurement, menu latency and visible-history cost. No current performance budget pass is claimed.

Reference M1/minimum OS/newer devices, real VoiceOver and chosen system preferences, elapsed two-week beta and public signing/notarization remain separate external gates. [Handoff](../handoff.md), [requirements](../requirements.md), [release gates](../release-gates.md).
