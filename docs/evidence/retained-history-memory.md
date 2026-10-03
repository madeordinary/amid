# Retained-history memory investigation — 2026-10-02

The initial small, populated seven-day store exceeded the 150 MiB RSS target in a fresh core test process, before adding the GUI or raw sample ring. This is a demonstrated memory issue, not a full-app acceptance measurement.

`RetainedHistoryMemoryProfileTests` generates encrypted schema-3 segments with a fixed public synthetic key in a new owned temporary directory. A separate fresh release test process loads them through production `HistoryStore`, checks state and flushes. The 21 entities are 20 synthetic apps plus System. The original fixture held 33,264 records across 1,440 minute buckets and 144 older hourly buckets, using 19,498,535 ciphertext bytes. No larger case has run. Production retention can merge/drop oldest records as the clock advances between trials.

| Variant | RSS after load | Lifetime peak RSS at load | Interpretation |
| --- | ---: | ---: | --- |
| Original load | 215,089,152 B | 215,089,152 B | After flush RSS reached 217,989,120 B (207.89 MiB). |
| Whole-load autoreleasepool, numeric-only helper | 145,997,824 B | 214,532,096 B | Reduces memory remaining after return, not the peak. |
| Whole-load plus per-segment decode/encode pools | 148,013,056 B | 217,792,512 B | No peak benefit; per-segment trial removed. |

The whole-load pool encloses the original synchronous body and retains the actor's resulting state. It does not change key access, schema validation, encryption or commit ordering. It is not a plaintext zeroization guarantee. The full HistoryTests run passed 22 cases with one opt-in Keychain skip and no failures; the later per-segment focused run passed 21 cases with one skip and no failures, excluding the already-run long soak. Both commands exited 0. Source review found no altered storage behavior, but this does not establish minimum-OS compatibility.

The later numeric helper reads only self Mach RSS/physical footprint and `getrusage` lifetime maximum. Heavy validation follows the load/state/flush memory checkpoints. Earlier state assertions could allocate temporaries between checkpoints, so those later current-RSS values are not a controlled pool comparison. CPU reported by the fixture includes assertions and is not GUI overhead. No heap or stack dump, monitored arguments/environment, Keychain mutation or user store was used.

Evidence: [original load](retained-history-memory-21-week-load.json), [whole-load numeric repeat](retained-history-memory-21-week-whole-load-pool-numeric.json), [per-segment trial](retained-history-memory-21-week-segment-pool.json), whole-load test log (local record: `retained-history-memory-21-week-whole-load-pool-test.log`), and per-segment test log (local record: `retained-history-memory-21-week-segment-pool-test.log`).

The next approved experiment adds an optional internal, default-nil stage callback to record scalar counts and own memory counters after decode, validation, assignment, enforcement, grouping, encoding, writing, reindexing and load return. The frozen GUI comparison executable excludes that instrumentation. The measured stages below narrow the next experiment; they do not identify object types or prove an architectural cause.

## Numeric stage result

The release focus passed 24 tests with three explicit opt-in skips and zero failures, exit 0. A fresh copied-fixture loader then passed with no skips/failures, exit 0. It decoded 33,264 records and retained 32,592 after current-clock rollups (2.02% fewer than the earlier baseline). The fixture helper now verifies successful Mach replies cover each requested field; absent/short fields stay unavailable. Earlier preserved RSS/footprint reads did not check returned field sizes. The getrusage lifetime-maximum evidence is separate.

| Load stage | Current RSS MiB |
| --- | ---: |
| Decoded | 65.72 |
| Duplicate-ID validation | 73.81 |
| Assignment | 73.83 |
| Enforcement/index | 123.31 |
| Grouping | 145.19 |
| Encoding | 174.77 |
| Written/cleanup | 188.14 |
| Reindexed | 202.72 |
| After load pool returns | 136.19 |

The subsequent unchanged flush encoded zero segments. Grouping, encoding and writing remained at 142,819,328 bytes RSS, then final reindexing reached 193,265,664 bytes: an increase of 50,446,336 bytes (48.11 MiB). Physical footprint rose by 50,348,056 bytes. This locates a substantial transient cost inside that block, without a heap/stack or object-type claim. [Stages and source hashes](retained-history-memory-21-week-stages.json), commands and exits (local record: `retained-history-memory-21-week-stages-test.log`).

A narrower pool experiment around final reindexing and the equivalent enforcement index construction passed 23 focused tests with two opt-in skips plus a fresh loader, but did not meaningfully lower peak: 212,402,176 versus 212,566,016 bytes, with 63 fewer records. Both experimental pools were removed and the exact previously tested stage source hash restored. Rejected trial (local record: `retained-history-memory-21-week-reindex-pool-test.log`).

The retained conditional-index change avoids final aggregates/index reconstruction when no groups were removed and aggregate times are already ordered. Off clearing, cap pruning and timestamp inversions retain reconstruction; commit and cleanup ordering remain unchanged. Four targeted tests cover unchanged-flush reuse, cap pruning, exclusion/Off/Clear reuse, and an older-clock/new-entity ordering fallback. The focused release run passed 27 tests with two opt-in skips and zero failures, exit 0; the separate fresh copied-fixture loader also passed.

Unchanged flush RSS rose from 137,822,208 to 137,969,664 bytes (144 KiB), compared with the earlier 48.11 MiB reindex increase. Lifetime peak was 202,227,712 bytes (192.859375 MiB), versus 212,566,016 bytes before this change. The later run retained 32,319 records, 273 fewer because of clock-driven rollups, so these are not exact-count controlled comparisons. The small core loader still exceeds 150 MiB. [Result and source hash](retained-history-memory-21-week-conditional-index.json), tests (local record: `retained-history-memory-21-week-conditional-index-test.log`).

A subsequent approved experiment extracted the original authenticated decode/validation/assignment body verbatim into a synchronous helper, returning before enforcement and persistence. The release focus passed 27 tests with two opt-in skips and no failures at 21:43:33 CDT; a fresh copied-fixture loader passed at 21:43:41. Both exited 0. Lifetime peak was 187,154,432 bytes (178.484375 MiB), 14.375 MiB below the conditional-index trial. It retained 31,626 records, 2.144% fewer because the same original fixture had aged; this does not isolate an exact causal saving.

Enforcement RSS was 122,519,552 bytes versus the earlier 136,232,960. The inside-enforcement and returned-enforcement counters were equal, so the measurement does not establish Foundation autorelease temporaries as the cause. Post-load RSS was 136,183,808 bytes, physical footprint 45,319,104. The synchronous scopes remain because of the measured peak reduction and unchanged reviewed semantics; they still fail 150 MiB. [Phase result](retained-history-memory-21-week-phase-scopes.json), tests and actual exits (local record: `retained-history-memory-21-week-phase-scopes-test.log`). Source SHA `1118dc99d22707f6ee250196b7f07be1c1fea76be6c4bd8ef0e8d56de299e54a` is ahead of the frozen GUI package. No larger fixture ran.

## Fixed-clock clean-generation comparison — 22:09 CDT

The approved candidate reuses authenticated schema-3 generations whose rows remain unchanged. It still rewrites every inline archive group (including groups shared with segmented rows), missing/null migration defaults, affected exclusions, pathless groups, minute rollups, noncanonical older buckets and arithmetic signed-zero normalization. Legacy schema-1/2 migration stays dirty-all. Every referenced segment is still authenticated and validated; manifest-first commit/recovery ordering and storage schema are unchanged. The immutable fixed load date is internal test-only; public initialization uses the actual clock.

Two independent copies of the original fixture were loaded in fresh release test processes with the same epoch, `1790996334.016682`. Both decoded 33,264 records and retained exactly 31,311: 28,266 minute records and 3,045 hourly records. Both ended with 18,410,966 ciphertext bytes. There is no count drift in this pair.

| Measurement | Dirty-all baseline | Clean-generation candidate |
| --- | ---: | ---: |
| Segments encoded during load | 1,491 | 2 |
| Process-lifetime peak RSS | 186,908,672 B (178.25 MiB) | 145,096,704 B (138.375 MiB) |
| RSS after load returns | 135,938,048 B | 145,031,168 B |
| Physical footprint after load returns | 45,581,248 B | 120,292,240 B |
| Own CPU across loader and validation | 1.063302 s | 0.485978 s |

The controlled trial supports a 39.875 MiB lifetime-peak reduction, but current RSS increased by 9,093,120 bytes and returned physical footprint increased by 74,710,992 bytes. It does not establish lower retained memory. Numeric stages cannot identify live-object ownership versus retained allocator pages; a JSON-decoder backing-buffer hypothesis is unproven. No string-detachment experiment ran. The candidate stays because of the measured peak improvement and tested storage semantics, without claiming a full-GUI memory or CPU pass.

Before the fix, two generation-reuse/exclusion tests failed with three assertions, exit 1. The final release run passed 34 affected storage, migration, recovery, index and measurement-helper tests with two explicit opt-in skips and zero failures, exit 0. New regressions cover unchanged authenticated generations, distinct and shared-bucket inline rows, each of nine missing/explicit-null migration fields, exclusion scope, minute-to-hour merging, noncanonical resolutions/timestamps, all ten added scalar signed-zero cases, and legacy inline migration. Existing interrupted-commit, cap, Clear/Off and index-order checks also ran. Each fresh paired loader passed one test without skips/failures, exit 0. An initial candidate compile failed on throwing-operator syntax; it was corrected before the passing test run. The already-run long soak was not repeated.

[Baseline and fixed-clock invocation](retained-history-memory-clean-v3-baseline.json), [candidate stages and source hashes](retained-history-memory-clean-v3-candidate.json), and commands, true exits and test log (local record: `retained-history-memory-clean-v3-validation.log`) preserve the evidence. Candidate `HistoryStore.swift` SHA-256 is `e5648f6c75bda8631addfa09d56cd8231a88ea9e911a2b4e897b5ac6b5a11bf3`. The baseline predates this candidate. The release build also includes the root's subsequent two-line menu accessibility change, which does not change core loader semantics; earlier frozen GUI packages exclude the clean-generation change.

This remains a single synthetic 21-entity/seven-day core loader pair with bounded names and a test key. It includes startup and validation costs, excludes GUI/raw-ring/entity-churn workloads, and does not establish 30-day or larger-entity memory behavior. No larger fixture, monitored metadata, heap dump or stack trace was used. Prior dated trials above remain historical observations, not exact-count comparisons.
