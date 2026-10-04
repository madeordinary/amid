# Scoped native collection-status observation

On 2026-10-04 UTC, UI access recovered after resetting the automation session. The owned `AmidCollectionStatus.app` candidate used explicit verification mode, Off retention, a temporary store and an ephemeral key. Source commit `2548bd944687ccb16a9a1bdfee7ac3ed2e40befd`; executable SHA256 `504e8d9bc6cdab42bfc0185211a7931b62bf6691af673c589f72a15679ce4caa`. All 107 public inputs remained unchanged. [Build/test scope](collection-status-candidate.md).

The observed subset covered:

- Onboarding Off and the VERIFICATION badge; CPU initially unavailable then numeric.
- Readable startup volume and 26 separate interface rows/rates, with overlap labels and no false unavailable message for complete nonempty collection.
- Pause, Settings, and confirmed Clear in the disposable store. Expanded Overview showed “Volume collection unavailable” and “Interface collection unavailable”, rather than successful-empty copy.
- Resume restored volume, memory and battery data. First fresh CPU remained unavailable and interface rates awaited a delta; later rendering showed approximately five-second actual cadence.
- External power/Charging and thermal Nominal were observed. These are readiness observations, not sustained performance evidence.
- Bound Command-Q ended the owned direct child and retained parent with exit 0 and no launcher signal.

No actual OS enumeration denial, successful-empty or partial collection was induced: unavailable presentation followed paused Clear. Controlled reply tests cover those boundaries separately. No saved screenshot is claimed. This is not complete keyboard/VoiceOver/menu p95, lifecycle/offline/all-view or performance acceptance. The historical HistoryRefresh timeout remains unchanged evidence; recovery does not retrospectively establish that run's selected presentation.

A subsequent normal-presentation, hidden-requested sustained benchmark completed but failed CPU/RSS targets. [Result and limits](collection-status-background.md). Its cleanup is separate from this observed native Command-Q. No new Vitals-inspired implementation was added.

## Current light-appearance and diagnostics subset

A separate owned run on the same unchanged executable used disposable verification storage, Off retention and app-only light appearance. All 107 public inputs and the executable hash remained unchanged; no new build or automated suite was run.

- Light Overview rendering was inspected. Command-7 selected Settings; an accessibility click opened the diagnostics review. Its exact local JSON preview and omitted-field list were exposed. Escape dismissed the sheet back to Settings; an individual restored keyboard focus was not observed. No export was requested.
- Command-2 selected Applications. After clicking the search field, typing `Amid`, Tab and Down selected the owned application. An accessibility click opened its process detail: one-core CPU units, normalized capacity, physical footprint, grouping evidence, no observed endpoints/available coverage and the read-only unsupported-runtime state were exposed. Escape returned to the selected row with the search preserved.
- Command-Q returned “App quit”; direct child and retained parent exited 0 without a launcher signal. Screenshots were inspected inline, not saved.

The app status icon was absent from the exposed accessibility tree and cropped window screenshot, so menu-to-details and p95 remain unobserved. No blind global-key or window-close retry was used. This mixed keyboard/accessibility subset does not establish complete keyboard focus, VoiceOver speech, scaling or all-view acceptance. Machine settings and normal app data were unchanged.
