# Fresh metadata storage profile — 2026-10-02

The full GUI missed the 150 MiB RSS budget. The existing raw-ring fixture reused one process array, so it did not represent fresh metadata strings retained across samples. This new controlled test reconstructs long UTF-8 strings for 600 synthetic processes in each of 181 logical five-second samples. Ten percent have one IPv6 endpoint. It preserves a full 15-minute raw ring without a wall-clock wait. Off retention and an ephemeral test key isolate raw memory from retained aggregates.

Separate fresh test processes measured their own RSS, footprint and lifetime RSS, before and during ingestion and after clearing. No host process metadata, stack trace, heap dump or GUI was captured. These synthetic cases cannot predict exact savings for real process paths or framework memory.

The initial test-only storage-sharing trial saved about 57 MiB. Its [baseline](raw-ring-memory-baseline.json), [sharing result](raw-ring-memory-sharing.json) and test log (local record: `raw-ring-memory-test.log`) remain unchanged. The subsequent production helper compares exact UTF-8 bytes; Swift's canonical Unicode equality alone could substitute differently encoded paths.

## Production helper results

The helper retains only permitted string fields from one accepted sample, keyed by full process identity. All process, endpoint and attribution reads still run. Only a newly read byte-identical string can reuse its previous immutable storage. Fresh nil values and changed fields survive. Endpoint arrays and measurement values are not cached. A new accepted sample replaces the identity map; reset, enumeration failure and empty results clear it.

In separate fresh release test processes:

| Measurement after 181 samples | Baseline | Production helper |
| --- | ---: | ---: |
| Current RSS | 120,045,568 bytes | 60,932,096 bytes |
| Current footprint | 95,503,224 bytes | 36,373,344 bytes |
| CPU across the synthetic run | 0.344385 s | 0.441671 s |

RSS was 56.375 MiB lower. Added CPU was about 0.537 ms per sample, or 0.01075% of one core at a five-second cadence for this fixture. This is a single paired synthetic measurement, not a sustained full-app pass or a CPU optimization claim. Current allocator-resident pages need not return to baseline after the logical ring is cleared; zero retained samples was asserted.

Four correctness tests passed: changed/nil/scalar/endpoint values, canonically equal but byte-distinct Unicode, full identities/departures/reset, and actual sampler reset after supported nonempty collection. The focused release run executed 19 tests with two explicit skips (sandbox loopback and opt-in profile); the separate native collection run passed all eight collection tests without skips. Both fresh synthetic profile processes exited 0. [Production baseline](raw-ring-memory-production-helper-baseline.json), [production sharing](raw-ring-memory-production-helper-sharing.json), commands and exits (local record: `raw-ring-memory-production-helper-test.log`).

The next live GUI measurement must establish actual overhead. Persistent aggregate memory is a separate open measurement; this Off fixture does not cover retained-history load or the 250 MiB ciphertext cap's relationship to RAM.
