# Current local checkpoint candidate — 2026-10-02

`build/AmidCheckpoint.app` is the latest local ad-hoc package. It was launched at 18:42 CDT with temporary verification storage. New History columns, horizontal scrolling and a 24-second pause gap were observed; remaining native checks are open. [Evening record](evening-ui-observations.md). The [afternoon acceptance candidate](acceptance-candidate.md) remains the identity of the bundle actually observed earlier. No performance or affected UI pass is inferred from source/tests.

## Changes since the observed bundle

- Queued alert delivery now rechecks the current enabled rule and application exclusions before each notification. Two regressions failed before the fix; all seven notification tests passed afterward. Unrelated allowed events still deliver. Before (local record: `notification-race-before.log`), after (local record: `notification-race-after.log`).
- History displays recorded actual cadence as a min/max range and recorded gap duration. Interrupted time belongs to the next observation and can span earlier buckets; the tooltip explains this. Empty periods remain gaps. Native column layout and horizontal scrolling were observed in the evening; complete keyboard/tooltip/VoiceOver checks remain unverified.
- A separate synthetic filled-ring profile measured pre-ingest expiry/presentation cost. Hidden week-retention extra sync was about 0.03 ms per logical tick; Off with visible History was about 3 ms. No production expiry change was made because this does not materially close the background budget and lifecycle correctness takes priority. [Raw profile](filled-history-expiry-profile.json). It uses 650 synthetic processes / 65 applications / 181 raw samples and logical time, not live GUI or 150 seconds of wall-clock monitoring.

## Verification and identity

On the final runtime source, this command exited 0 at 16:13:12 CDT:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" \
swift test -c release --build-system native --disable-sandbox \
  --cache-path "$PWD/.build/cache" --filter AmidAppTests
```

It executed 18 tests, with one explicit opt-in filled-ring profile skip and zero failures. The profile was separately run successfully; its raw evidence records the exact invocation and runner exit 0. This is an affected-app suite, not a later full core suite. Test log (local record: `checkpoint-app-tests.log`).

```sh
AMID_PACKAGE_OUTPUT="$PWD/build/AmidCheckpoint.app" bash scripts/package.sh
```

Packaging exited 0 and strict ad-hoc verification passed. Package log (local record: `checkpoint-package.log`). Source base `427fe67`; runtime source fingerprint `00e61279b2fbc5ddc6d3aca767e2558843616737c6833c4ff7ab27549e91eb32`; executable SHA256 `0cfed1136f2dae65a32eba0015f913a6ef8b3de6312c12254fd96a54697c2d16`. [Complete hashes](checkpoint-candidate-hashes.json). Later test-only evidence does not alter these runtime bits.

Root and GPT-6.1 sol reviewers inspected the changes. No further actionable finding remained in that bounded review. Independent review was unavailable; only same-model review is claimed.

## Remaining local gate

The actual acceptance checks and interrupted benchmark are in [the native record](acceptance-ui-observations.md). Clear/cancel/retry and exact supported-server confirmation were observed; the newest History columns and a real pause gap were subsequently observed. Remaining menu/keyboard/accessibility/lifecycle paths are still open. The first two GUI benchmark attempts invalidated on screen lock. A later uninterrupted checkpoint-source run completed but failed CPU/RSS budgets (1.559615%/160.265625MiB); targeted profiling is next. Preserve reference/matched-baseline limitations. Never reuse an invalid run or describe collector-only timing as full-app overhead.

The previous `com.madeordinary.amid.benchacceptance` app was quit at about 18:42 and its finalized invalid report preserved. The fresh `com.madeordinary.amid.benchcheckpoint` run completed and was quit normally; its [final failed-budget report](gui-benchmark-checkpoint-completed.json) hash stayed unchanged after quit. Earlier normal and benchmark apps were already quit; the owned server exited 0. No existing user workload or normal store was modified.
