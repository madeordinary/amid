# Settings-load race

This follow-up fixes a data-loss defect found by the [independent Vitals plan review](../vitals-inspired-review.md); it adds no Vitals feature. Fix commit `df61fae`, parent `9a7594f`. It has not been packaged or observed natively.

## Defect

`AppModel.start()` and `retryStore()` recorded the settings revision before awaiting the encrypted store load, then imported saved settings only if the revision was unchanged. The main-window Pause control, the Monitor menu command and the Settings form stayed enabled during that await. A change there skipped the import, leaving the default draft with nil retention. Saving that draft made the store clear its in-memory catalog. Onboarding then reappeared, and the next accepted retention choice committed an empty manifest that removed every retained bucket file, along with saved aliases and exclusions.

## Fix

Saved settings now always replace the pre-load draft, because no draft can be derived from saved state before the import. While a startup or retry load is in progress, `saveSettings()` writes nothing and the pause, alias, exclusion, notification, launch-at-login and retention writers return without changes. The pause controls and the Settings form are disabled during the load. A Pause click or Settings edit in that window is dropped, not merged: one lost click is preferred to replacing saved preferences and history. `HistoryStore` is unchanged.

## Verification scope

Two regressions in `Tests/AmidAppTests/SettingsLoadTests.swift` seed a disposable encrypted store with saved retention, an alias and persisted aggregates. They then hold the load inside a key-provider barrier and apply the edit.

| Run | Result |
| --- | --- |
| Before the fix | Both tests failed (11 assertions). Pause: the store reopened from disk had 0 retained aggregates and no alias. Settings draft: retention and alias were replaced by the draft. |
| Focused, after | Settings-load, notification, History-query and stop-lifecycle suites: 28 tests, 0 failures. |
| Repetition | The two new tests passed 25 of 25 runs. |
| `scripts/test.sh` | Exit 0: 208 tests, 15 opt-in skips, 0 failures, plus 9 system and 18 interface C cases. Owned fixture, Keychain, ENOSPC, darkhttpd and footprint integrations were not enabled. |
| Release | Focused settings tests 9/0; `scripts/build.sh` exit 0. |

## Limits

- The regressions exercise `retryStore()`. `start()` uses the same import and guard but is not driven by a test, because it opens the real Application Support store.
- Disabled controls during load have not been observed in the running app.
- A save already in flight when Retry is clicked relies on same-priority actor ordering to reach the store before the reload. Later iterations of that save are refused.
- `HistoryStore` still clears its in-memory catalog when given nil retention. No UI path can now send nil over saved data, so this remains a store-level hazard only.
- After a failed verification startup, the pause controls and Settings form stay disabled. This is intended, because startup has stopped.
