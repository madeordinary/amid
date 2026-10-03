# Owned port-list candidate — 2026-10-02

The test-only stack-buffer candidate did not justify a production change. `fixtures/native/port-list-profile.c` compares the current collector with a bounded 128-descriptor stack attempt and conservative fallback. It reads only its own descriptors and a newly created loopback listener; it makes no connection and reads no payload. The runner cleans up its own descriptors and temporary executable.

The first sandboxed run exited 1 at listener setup; its errno was not captured, so the cause is not proven. That result is preserved in the initial log (local record: `owned-port-list-profile-sandbox.log`). The authorized unsandboxed local rerun exited 0, passing fourteen candidate boundary cases, a valid mocked baseline parity check, and full endpoint/coverage parity for low and high descriptor counts. The JSON total of fifteen deterministic cases includes the mocked parity check.

For 1,000 low-descriptor calls, baseline CPU was 1.686 ms and candidate CPU 1.558 ms: only 0.128 microseconds saved per call. It reduced list calls from 2,000 to 1,000 and user allocations from 1,000 to zero. With 256 additional owned descriptors, CPU increased from 2.720 to 3.261 ms, list calls increased to 3,000, and allocations remained 1,000. These short fixed-order timings do not measure full-app overhead or kernel-internal call counts.

No production fast path was added. [Numeric report](owned-port-list-profile.json), commands, source hashes and exits (local record: `owned-port-list-profile.log`).
