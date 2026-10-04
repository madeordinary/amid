# Coverage and conservative alert recovery

This follow-up changes low-activity recovery and adds verification; it does not add the further Vitals-inspired features. Candidate identity, source hashes and final exits are recorded in [the exact manifest](coverage-candidate-source.json).

A missing CPU observation resets listener qualification. Previously, thirty minutes of still-low CPU could mark the suspended suggestion recovered solely because the restarted listener had not yet reached two hours. The fix keeps that episode suspended and resumes the same event after requalification. Actual recovery requires a known thirty-minute weighted CPU average of at least 1% of one core. A regression failed before the fix; the 26 affected alert, notification and lifecycle tests passed afterward. Other rule thresholds, cooldowns and storage remain unchanged.

## Verification scope

The final release run exited 0: **189 tests, 9 explicit opt-in profiling skips, 0 failures in 94.094 seconds**, plus nine C reply cases. All 88 input hashes stayed unchanged through packaging and strict ad-hoc verification (exit 0). The owned storage, memory, native listener and unique Keychain integrations were enabled. Earlier test-scenario corrections and the failing low-activity regression are retained in private logs; no failed run is relabeled a pass.

The alert suite has 17 cases. New boundaries cover each memory-growth threshold, full missing-data resets, disk equality/custom thresholds, swap pressure/recovery, hourly notification eligibility and low-activity recovery/requalification. Synthetic policy tests do not prove OS notification delivery or the two-week beta.

| Owned fixture | Declared denominator | Observed coverage |
| --- | --- | --- |
| Outer bundle/helpers/distinct executables | 5 processes, 4 application groups, 2 project roots | All explicit memberships matched; all 5 exited naturally. |
| Native Node/Python/Swift | 3 expected joint project/listener matches | 3/3 matched. |
| Endpoint scope | IPv4 wildcard, IPv6 loopback, IPv6 wildcard | 3/3 cases matched. |
| Shared listener/reparenting | 2 expected processes and listener owners | Both readable, correctly grouped and mapped; surviving full identity stayed stable. Parent wait status was 0; child reported return 0, without an independent grandchild wait status. |

These are small declared fixtures, not accuracy percentages for every installed application. Families are not averaged into a broader percentage.

## Storage exhaustion and metric references

The opt-in test created a fixed 64 MiB HFS+ image, verified its held mount descriptor/device/capacity, then filled it until a one-byte write returned ENOSPC. New history writes failed closed, the prior manifest/bucket hashes remained unchanged, and releasing the filler restored the exact prior record with no attempted new record. Normal detach and owned-directory removal completed. The store exposes a generic error; its own syscall errno was not directly captured. This is not APFS, abrupt-power-loss or failure-path cleanup proof.

A disposable child touched 64 MiB and reported its own current Mach RSS and physical footprint. Amid used the physical-footprint method and matched the independent API-path reference within the predeclared 1 MiB boundary allowance. The paths share kernel accounting; RSS, footprint and lifetime peak are distinct metrics. Exact numeric results are in [the numeric evidence](coverage-metric-references.json).

A separate serial tool comparison found exact physical-memory and startup-capacity agreement; available capacity matched the later reading, and load averages matched tool rounding. Dynamic VM values varied across the reads. This supplies a current-host implementation cross-check, not an atomic accuracy tolerance, system-CPU/interface-rate proof or reference-hardware acceptance.

## Remaining gates

The preceding loaded GUI run was invalidated by screen suspension after 123 samples and about 21 minutes. Its final report includes suspended time and later host test activity; it is not a performance pass. See [the invalid report](history-loading-sustained-invalid.json). The new package has not been inspected natively while the Mac is locked. Uninterrupted default-five-second performance, menu latency, complete keyboard/VoiceOver/offline/lifecycle checks, minimum/reference hardware and the real beta remain open. No public binary release or signing/notarization is claimed.

## Repeat the focused integrations

Use the recorded Xcode toolchain, then run:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
AMID_ENOSPC_TEST=1 AMID_OWN_MEMORY_REFERENCE=1 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" swift test -c release --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" --filter 'HistoryENOSPCTests|OwnMemoryReferenceTests|SharedListenerReparentTests|AlertTests'
```

The ENOSPC test mounts only its newly created fixed image and requires more than 512 MiB backing free space. Enabled setup/permission/cleanup failures fail rather than skip. An unidentified attachment or failed normal detach is preserved for scoped cleanup; never force-detach or remove an unknown mount. Ordinary suites leave the two explicit opt-ins skipped. The native shared-listener fixture uses bounded natural exits and sends no signals.
