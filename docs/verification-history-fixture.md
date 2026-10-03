# Disposable retained-history verification

The normal app stores encrypted history with its per-install Keychain key. The explicit verification launch modes can instead import an owned synthetic fixture into a fresh disposable directory. This uses a fixed **public test key** and must never contain real activity. It does not open or replace the normal store or its Keychain item.

Build the release tests with the selected Xcode SDK, then generate a fresh seven-day fixture. The 76 entities represent one system, 65 applications and ten projects; the fixture declares 120,384 minute/hour records. Actual counts after retention enforcement are recorded separately.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swift test -c release --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" --filter RetainedHistoryMemoryProfileTests/testMachReplyFieldCoverageRejectsShortAndImpossibleCounts
seed="/private/tmp/amid-owned-retained-profile-$(uuidgen)"
AMID_RETAINED_PROFILE=generate AMID_RETAINED_DIRECTORY="$seed" AMID_RETAINED_DAYS=7 AMID_RETAINED_ENTITIES=76 xcrun xctest -XCTest AmidCoreTests.RetainedHistoryMemoryProfileTests/testOptInRetainedHistoryMemory .build/arm64-apple-macosx/release/AmidPackageTests.xctest
seed_hash="$(shasum -a 256 "$seed/history.aesgcm" | awk '{print $1}')"
```

Generate immediately before use: the importer rejects a fixture anchor more than one hour from the current clock. Source and destination must be owned, direct children of `/private/tmp` with the documented prefixes. The importer rejects links, existing destinations, an unexpected manifest hash, malformed descriptors and excessive ciphertext. It authenticates the manifest and copies only bounded ciphertext; normal `HistoryStore.load` then authenticates every committed segment before maintenance. Maintenance may reread affected buckets; selected queries read and cache only their requested points. A bad request or load stops verification startup with an error and never falls back to the normal store.

After packaging, launch a new owned app process while the Mac is unlocked and awake. Adjust the bundle path to the candidate being tested. Use unique absolute report paths, and do not overlap the run with builds or fixture workloads unless those workloads are the declared subject of the measurement.

```bash
report="/private/tmp/amid-seeded-gui-$(uuidgen).json"
build/AmidReview.app/Contents/MacOS/Amid --performance-verification --verification-history-seed "$seed" --verification-history-sha256 "$seed_hash" --benchmark 180 --benchmark-output "$report" --benchmark-hidden
```

This short run is diagnostic. A completed report proves only its recorded interval; it does not pass the 30-minute budget or reference-hardware gate. `monitoring.historySeed` records fixture hashes, declared counts and the actual aggregate count immediately after load. Process-lifetime peak RSS includes the import and startup allocations; the measured CPU interval begins after the 30-second warmup. Keep visible-History, filled live-ring and normal-store startup costs separate. Do not add measurements from different processes to invent a full-GUI result.

The source fixture is retained unchanged. The copied store and reports stay local under temporary directories; they are not release artifacts. Quit only the owned verification instance after observation and remove only the exact disposable paths created by that run. Invalid or interrupted reports remain labeled invalid.

The core-only retained-history profiler also accepts 350 synthetic entities (339 applications, ten projects and the system) with a bounded 750,000-record/512 MiB input fixture. The production disk cap remains 250 MiB, so this larger input tests actual oldest-bucket eviction. It is not accepted by the stricter GUI seed importer. Core load/metadata/flush and selected-query checkpoints precede the explicitly expensive diagnostic full-state validation; the latter and the whole-test peak must not be reported as the production working set. Neither boundary establishes a full-GUI budget pass.
