# Collection status and runtime labels

Source commit `2548bd944687ccb16a9a1bdfee7ac3ed2e40befd` distinguishes failed volume/interface reads from successful empty collection. Partial volume results retain readable rows; failed, oversized and empty interface replies reset rate baselines. Overview displays the corresponding status. Optional raw snapshot fields accept legacy JSON with absent status fields; persisted aggregate/settings schemas are unchanged.

Python display labels now require an exact supported basename or nonempty ASCII numeric version segments. Before the fix, four runtime-label tests exited 1 with ten malformed-name failures; afterward they passed. Generic runtime paths inside tool-named folders stay generic. This is display-label coverage, not proof of running code, developer intent or stop authorization.

## Observed checks

- Focused release run: 14 tests, no skips or failures, exit 0.
- Integrated release run: 200 tests, 190 passed, 10 explicit opt-in skips, zero failures in 95.281 seconds, exit 0. Owned native fixtures, unique test Keychain storage, disk-exhaustion recovery and own-memory reference checks were enabled.
- C reply fixtures: 18 interface and 9 system cases passed.
- Package, distinct bundle ID, ad-hoc signing and strict verification each exited 0. All 108 inputs stayed unchanged: 107 public inputs and one private fixture runner. [Source and executable manifest](collection-status-candidate-source.json).

The local bundle is `build/AmidCollectionStatus.app`, identifier `com.madeordinary.amid.collectionstatus`. Its executable SHA256 is `504e8d9bc6cdab42bfc0185211a7931b62bf6691af673c589f72a15679ce4caa`; ad-hoc CDHash is `7ca9030f3229996778e2c76b03c36a91646fcf9a`.

## Fresh public source build

A fresh `git archive` export of the source commit contained 304 public files and no private memory bank, Git metadata, build output or existing project cache. Every exported file matched its committed contents before and after `bash scripts/package.sh`. Release compilation, owned development-fixture packaging and strict ad-hoc verification exited 0. The resulting separate executable SHA256 is `7baa8e25d47e2aad66264a686b0e442b9fece6d92785b2d31424e53d925f89c6`.

This checks the public build recipe on the existing host and installed toolchain. It is not a fresh-machine test, bit-for-bit reproducibility claim or GUI launch. The normal public build command remains `bash scripts/package.sh`; the private bank is unnecessary.

## Remaining acceptance

No native UI observation or new performance benchmark ran on this candidate. The earlier UI-tool timeout, sustained GUI CPU/RSS failure, menu latency, accessibility, lifecycle, minimum-OS/reference hardware, real beta and signed/notarized release gates remain open. Prior [HistoryRefresh](history-refresh-candidate.md) and Counters observations retain their exact executable scope. This is an ad-hoc development package; no public binary was released.
