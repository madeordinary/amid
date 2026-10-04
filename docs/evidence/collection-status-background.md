# Completed collection-status background run

**Completed; both targets failed.** Normal-presentation GUI, hidden requested, synthetic 76-entity/seven-day retained history, 30-second warmup, measured on the recorded macOS 27.0.1 host. This is not the reference M1 workload or a matched no-Amid baseline.

| Measurement | Observed |
| --- | --- |
| CPU interval | 1810.590821209 seconds |
| Samples | 341 accepted, 0 unavailable; no invalid reasons |
| Mean process CPU | 0.7980405528816107% of one logical core; target ≤0.5% |
| Lifetime peak RSS | 162971648 bytes / 155.421875 MiB; target ≤150 MiB |
| Requested cadence | Five seconds initially, ten seconds later |
| Maximum sample gap | 10.67347212499999 seconds |
| Loaded synthetic aggregates | 120308; declared source records 120384 |

CPU is an own-process delta after warmup; lifetime RSS includes synthetic import, startup and warmup. The policy change means this is not uninterrupted default-five-second acceptance. Continuous sampling does not prove continuous UI visibility. No pure-renderer attribution or causal improvement against historical runs is claimed. Interrupt/package-idle wakeups are separate counters, not all wakeups.

Frozen source commit `2548bd944687ccb16a9a1bdfee7ac3ed2e40befd`, executable SHA256 `504e8d9bc6cdab42bfc0185211a7931b62bf6691af673c589f72a15679ce4caa`; public input hashes and executable were rechecked against [the manifest](collection-status-candidate-source.json). [Numeric report](collection-status-background.json) preserves measurements and synthetic provenance; original report SHA256 `536eeda9023d2ab661302817373d69fcc71da9ec5627898002d3b0a00d0ae733`.

The owned direct child and retained parent both ended with exit 0, without a launcher signal. Native Quit is **not** credited: the final CUA Quit request errored. No active owned benchmark remains. Previous native subset and historical failed/invalid reports retain their original scope. Further remediation needs a bounded evidence-led plan; this result is not a reason to repeat an uncontrolled run.

Public API checks reproduced mixed power reports: system-level providing source said AC while the internal battery dictionary said Battery Power; immediate pmset also reported AC with discharging. Ten-second conservation follows that known internal-battery state. This does not justify forcing five-second cadence or diagnose a hardware/adapter cause. Apple documents [the source-state key](https://developer.apple.com/documentation/iokit/kiopspowersourcestatekey) and [providing-source API](https://developer.apple.com/documentation/iokit/iopowersources_h/1810316-iopsgetprovidingpowersourcetype); its [public implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.c) reads notification state separately. Serial readings are not a guaranteed shared snapshot.
