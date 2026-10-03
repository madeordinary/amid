# Retained-history memory candidate — 2026-10-03

This local ad-hoc candidate includes three reviewed storage changes: bucket indexes instead of full-row grouping, in-place rollup/direct aggregate indexing, and skipping exclusion mutation when no exclusions exist. Per-segment autorelease pools were rejected and reverted. It is a development preview, not an application release or performance acceptance pass.

The complete release run passed **155 tests, nine opt-in profiling skips and zero failures**, exit 0, in 130.352 seconds. Nine injected C system-reply cases also passed. Owned Node/Python/Swift fixtures, IPv4/IPv6 endpoint scopes, the independently pinned reviewed-server integration, the unique temporary Keychain roundtrip, attribution matrix, seed import/tamper checks and storage regressions ran successfully. The skipped profiles require separate measurement runs; they are not correctness or Keychain skips.

All 83 files under Sources, Tests, Resources and scripts, plus Package.swift, matched before the suite, after the suite and after packaging. The [source manifest](history-memory-candidate-source.json) records fingerprint `895ff90b1f51943c944ee88c28f4830e67af7e16fd65b50f995e4eba07d392c2` and HistoryStore SHA256 `e2f6c3fa33997b97e662132af481ce1cfcff750daea4eecbf33f9d5d676f9076`.

`build/AmidHistoryMemory.app` packaged with exit 0. Its bundle ID is `com.madeordinary.amid.historymemory`; setting that ID, re-signing the outer bundle and strict deep ad-hoc verification each exited 0. Executable SHA256 is `00f108fa0c910bd9c0e1b423b3126c9f02fc4eb046e81a8c94d0c35ce64ef260`. The preceding [AmidReview candidate](review-candidate.md) remains preserved unchanged. Neither this packaging run nor its tests launched the GUI.

## Memory result and limits

The [matched copy-reduction trials](history-memory-copy-reduction.json) used separate fresh release test processes and copies of one synthetic 76-entity/week fixture. Within each pair, the fixed reference, retained counts and ciphertext size matched. The final retained change measured:

| Boundary | RSS |
| --- | ---: |
| After production load | 167.828125 MiB |
| Production-checkpoint lifetime peak through load/flush | 198.3125 MiB |
| Whole-test lifetime peak, including later heavy validation | 234.28125 MiB |

These are different boundaries. The whole-test maximum cannot be attributed solely to production loading; physical footprint is also distinct from RSS. The reductions do not pass the 150 MiB RSS gate. No filled-ring/loaded-GUI, sustained CPU, reference-hardware or matched no-monitor acceptance pass is claimed. New navigation and Overview behavior still needs native observation; complete keyboard/VoiceOver and remaining lifecycle checks remain open.

Raw command logs and before/after manifests are retained privately. This summary contains only reviewed relative paths, hashes, counts and outcomes. Review was same-model source review; no independent cross-tool review is claimed.
