# Afternoon acceptance candidate — 2026-10-02

This record identifies the package actually observed at 15:48–15:54 CDT. Later source changes require a new package and fresh observations for affected behavior. [Native record](acceptance-ui-observations.md), [source and artifact hashes](acceptance-candidate-hashes.json).

## Source, tests and package

Base checkpoint: `427fe67`. The only subsequent implementation change in this package canonicalizes both sides of the explicitly supplied owned-server verification filter. `/private/tmp` and `/tmp` aliases had prevented the newly owned test server appearing in verification mode. Normal collection and action authorization are unchanged. A focused regression first failed three assertions; after the correction it and two stop lifecycle tests passed with exit 0 at 15:45:38. Before (local record: `verification-path-before.log`), after (local record: `verification-path-final.log`).

Earlier evidence retains its exact scope: 78 integrated tests / six skips / zero failures at 13:03 before final grouping dedupe; separate owned Node/Python/Swift integration at 13:06; 21 release action/presentation/lifecycle/aggregation tests / zero skips / zero failures at 13:15 after dedupe. These counts do not describe a full suite after the verification-filter change. See [preceding candidate](resumed-candidate.md).

```sh
AMID_PACKAGE_OUTPUT="$PWD/build/AmidAcceptance.app" bash scripts/package.sh
```

Packaging and strict ad-hoc signature verification exited 0. Package log (local record: `acceptance-package.log`). Source fingerprint: `64f4200f91311e167fbabce30ca68a795838cb73faa3bdf7cf346867fca359ca`. Executable SHA256: `046bda0cdebde1d3f98b0d565d9a85aabe1a3c2d52b5bfcc33421e75d7f35ddd`. This is a local development bundle, not Developer ID signed or notarized.

## Observed behavior

The preceding AmidResumed bundle demonstrated Clear History cancel and confirmed removal while preserving aliases/preferences; an actual temporary-store directory write failure showed an error without plaintext fallback, and Retry recovered the saved settings after exact directory restoration.

AmidAcceptance displayed the new owned pinned real server. Its development declaration started unchecked, controlled the confirmation button, and reset after cancellation. An expired preview sent zero signals and displayed unavailable remaining state. A fresh declared preview sent one SIGTERM to the exact owned server, whose launch session exited 0. Background and restored-detail intervals were observed at 5.6 and 2.1 seconds. Both normal bundles were quit through their own UI, and the server exited. These observations have separate build/identity details in the native record.

## Performance boundary

The separately signed benchmark copy has bundle ID `com.madeordinary.amid.benchacceptance` and executable SHA256 `6cf3e5c1a64b67343e26d097d84353324f93bbc4f5e572df4bd60f758ab1f65e`. Its run began measurement after six available warmups, then invalidated on screen suspension after 179.593 seconds. The [preserved status](gui-benchmark-acceptance-invalid-status.json) is not a 30-minute overhead result. Full-GUI CPU/RSS, matched baseline/reference hardware, menu p95 and visible-history cost remain open. Native menu/keyboard/VoiceOver checks remain incomplete.
