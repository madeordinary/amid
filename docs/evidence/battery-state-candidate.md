# Battery unknown-state correction — focused evidence

The local candidate changes raw BatterySnapshot charging and internal-power fields to optional Booleans. The actual IOPS dictionary decoder preserves missing, unrecognized or malformed power states as unknown; charging requires CFBoolean and rejects numeric NSNumber values. Known capacity/health and Boolean states are preserved. Overview uses localized unknown-power copy while still displaying known charging independently.

Sampling policy is unchanged at both AppModel callers: known battery use requests ten seconds; unknown power retains the existing non-battery fallback. This correction does not resolve mixed public API power reports, force five-second cadence or diagnose hardware.

## Verification scope

- Corrected-SDK baseline: three collection tests, twelve failed assertions, one known-state case passed; exit 1. The first baseline log additionally contains eight incorrect Swift-Int capacity-fixture assertions and remains preserved separately; those are not product defects.
- Focused after run: sixteen affected tests, no skips or failures, exit 0. Four BatteryCollectionTests cover missing/malformed values, known-value parity and raw JSON compatibility; two BatteryPresentationTests cover wording and unchanged cadence policy.
- Final full release run: 206 total cases, 196 passed, 10 explicit opt-in profiling skips, zero failures in 95.320 seconds, plus 18 interface and nine system C cases. All six verification/package steps exited 0; 110 inputs unchanged (109 public plus private runner).
- `AmidPowerState.app` passed strict ad-hoc verification; [manifest](battery-state-candidate-source.json) records executable SHA256 `c64a9ca029e670831939411c14ccad994394bdbab0436b8b08f615a5db4e9889` and source commit `d9a6e813080c4063d78cf30a714edf27c0ddfe19`. The recorded build and tests apply to that source commit.
- Native verification failed at the automation boundary: the requested short getApp call returned only after the owned launcher deadline had sent one identity-checked SIGTERM. The owned child exited -15 and retained parent exited 0, not normal GUI Quit. The returned window lacked a VERIFICATION badge and was not interacted with; it cannot establish the intended isolated session. No native battery/unknown-state or performance pass is claimed.

Legacy raw JSON Boolean fields still decode; absent optional fields remain unknown and round-trip. No persisted aggregate/settings schema changed. No production argument/environment/payload collection or new permission was added.

Prior [collection-status native subset](collection-status-native.md) and [completed sustained failure](collection-status-background.md) retain their original frozen-source scope. Actual OS missing/unsupported charging state was not induced. Final source/executable identity is recorded in the [candidate manifest](battery-state-candidate-source.json); automated packaging does not establish native behavior.
