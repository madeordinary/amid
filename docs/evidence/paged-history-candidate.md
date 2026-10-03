# Paged-history candidate — 2026-10-03

This development candidate keeps an authenticated bucket catalog and one mutable minute in the history actor. The UI requests metadata and the selected entity/range instead of copying the whole archive. It preserves the encrypted schema and commit barriers; at most two selected-entity queries are cached. Selection, settings, Clear, hide, sleep, lock and quit transitions invalidate stale UI replies. See [storage design](../storage-design.md).

The full release run passed **174 tests, nine opt-in profiling skips and zero failures**, exit 0, in 69.968 seconds. All nine injected C system-reply cases passed. Owned native fixtures, the independently pinned reviewed-server integration and a unique temporary Keychain roundtrip ran successfully. New tests cover query parity, bounds, caching, failure cleanup, aliases, stale replies and a real ephemeral-store UI model path. One earlier run failed a test's asynchronous publication assumption; the corrected test waits for the actual nonempty selected result with a strict deadline and preserves its assertions. Original failures and correction evidence remain private.

All 85 files across Sources, Tests, Resources, scripts and Package.swift matched through tests and packaging. The [source manifest](paged-history-candidate-source.json) records fingerprint `f8266a1458b9cc857a34f7aed531010f41bb83be6a9848d7b4f81d38f297cbb9`. `build/AmidPagedHistory.app`, ID `com.madeordinary.amid.pagedhistory`, packaged and passed strict deep ad-hoc verification; executable SHA256 `10539a33bd1fbd9bb367c0476c362e1b6fb2628c651616814ab1371005b53b48`. Both preceding candidate bundles remain unchanged. This bundle has not been launched or natively observed.

## Retained-history measurements

The [numeric record](paged-history-memory.json) separates production checkpoints from expensive diagnostic validation. Each generation/load command exited 0. Fresh release processes and a fixed reference clock retained exactly **109,364 minute rows, 11,020 hourly rows and 70,783,894 ciphertext bytes** on both sides of the 76-entity/week comparison.

| Core measurement | Before paging | Paged candidate |
| --- | ---: | ---: |
| RSS immediately after load | 168.171875 MiB | 39.3125 MiB |
| Lifetime peak through load/metadata/flush | 198.328125 MiB | 39.328125 MiB |

For the candidate, the first selected-system query returned 1,583 points in 1.065571 seconds; its cached repeat took 1.669667 ms. RSS after the cold query was 40.453125 MiB. The later warm checkpoint was 51.09375 MiB, including a harness JSON equality assertion. Full diagnostic materialization reached 195.59375 MiB; whole-test peak was 239.0625 MiB. Those last measurements are not the normal UI working set.

The separate 350-entity/week fixture generated 554,400 rows and 325,708,199 ciphertext bytes. Loading enforced the unchanged 250 MiB disk cap, leaving 446,600 minute rows, no hourly rows and 262,010,514 bytes. Loaded RSS was 55.84375 MiB; peak through flush was 55.90625 MiB and through the cold query 56.296875 MiB. The first selected-system query returned 1,276 points in **4.908793 seconds**; the cached repeat took 1.497292 ms. Diagnostic full-state RSS was 537.03125 MiB and whole-test peak 727.25 MiB, including all-row validation.

## Collector diagnostic

A separate [numeric collector profile](paged-candidate-sampler.json) passed one opt-in test with no skips/failures. Twelve samples over 60.005923 seconds observed 680–686 readable processes. Sampling-thread CPU was 0.327694 seconds (0.546103% of one core); whole-test CPU was 0.430283 seconds (0.717068%). The process loop dominated sampling-thread cost. Fine wall stages identify OS reads, ports/validation, project work and application derivation separately; wall time is not CPU time, and instrumentation overhead is included. This short diagnostic does not pass the sustained full-app CPU gate or establish a causal saving against another host workload.

## Remaining acceptance

The memory improvement is measured; full-app acceptance is not. Cold history queries, especially the 4.9-second larger fixture, need native loading/cancellation observation. The GUI/frameworks, live raw ring, high entity churn, legacy inline migration and unusually large individual buckets have separate costs. The 150 MiB full-app RSS and 0.5% sustained CPU gates remain open; previous GUI runs failed the CPU target. Menu latency, current navigation/ports/Overview behavior, complete accessibility, offline/lifecycle checks, minimum OS/reference hardware and real beta remain unverified where listed in [release gates](../release-gates.md).

Review was same-model source/evidence review; independent cross-tool review was unavailable. No competitor binary, new machine consent, public binary, Developer ID signing or notarization is claimed. Raw logs, fixture paths and working memory remain private.
