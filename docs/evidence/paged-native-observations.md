# Paged candidate native observations — 2026-10-03

These observations apply to source commit `239eb7a` and the frozen `build/AmidPagedHistory.app` executable SHA256 `10539a33bd1fbd9bb367c0476c362e1b6fb2628c651616814ab1371005b53b48`. They do not certify subsequent loading-presentation changes. The app ran with `--verification --light-appearance`, a fresh disposable store and an ephemeral key on arm64 macOS 27.0.1. Normal Amid data and existing credentials were not used.

Native accessibility and rendered-window observations between 17:59 and 18:07 CDT showed:

- Onboarding displayed the metadata/privacy boundary and default seven-day retention. Start observing opened Overview. Sampling-before-choice was not independently instrumented by this observation.
- Overview's System details disclosure started collapsed, expanded to expose physical/compressed memory, thermal, load, battery, volumes and interfaces, then collapsed again. Refreshed values and the owned application/project rows rendered. Screenshots were inspected inline; no saved screenshot artifact is claimed.
- Command-2/3/4/5/7 reached Applications, Projects, Ports, History and Settings. A deliberately unmatched Applications filter produced zero groups. This is a keyboard subset, not a full keyboard/VoiceOver audit.
- A bundled disposable Swift fixture exposed one loopback listener for at most 180 seconds. Projects displayed `DevelopmentFixture` with inline `TCP 54021`; searching for `54021` retained that project. Its inspector displayed retained values and View history opened the same project with the 24-hour range. Ports showed `127.0.0.1`, IPv4/Loopback, the owned fixture and matching project/port. The fixture exited naturally with status 0; no stop signal or service connection was used.
- The owned `scripts/run-history-spike.sh` fixture ([numeric phase record](paged-native-spike.json)) completed its real 60-second quiet, 60-second CPU/64-MiB allocation and 60-second quiet phases, then exited 0. History displayed four minute buckets: quiet memory about 1.2 MB, peak physical footprint about 65.3 MB and peak CPU 99.8–99.9% of one core, followed by quiet memory/CPU. Coverage and actual cadence remained visible; the 10-second cadence matched the observed battery policy. Both exited fixture names remained in the resource selector, and their retained points remained available.
- After pausing the disposable monitor, Settings→History returned the same four spike buckets without requiring a new sample.
- Settings already provides Icon only, System CPU and Memory pressure menu choices. Extending these choices is a possible future idea; basic menu readout selection is already implemented.

## Defect and limits

During one Settings→History transition, the resource picker was initially blank and the view said No saved measurements in this range. A later resource-picker observation showed the retained name and four buckets. This demonstrates a false empty/loading presentation, not data loss or a measured 20-second query. Source inspection found synchronous point/name invalidation followed by asynchronous metadata/query publication without a distinct pending state. A scoped loading-presentation fix is pending separate verification.

The owned app received Command-Q; a later identity-specific process check confirmed its recorded PID was absent. Both fixture sessions returned exit 0. Their private phase records and identities remain local.

Menu opening/navigation/dismissal and native p95 timing remain unverified: Control-F8 did not expose the extra and the system menu accessibility host timed out. No machine accessibility preferences or privacy grants were changed. VoiceOver speech, complete focus/appearance/display checks, larger cold-query behavior, offline/lifecycle coverage and sustained full-app CPU/RSS remain open. The earlier core measurements and prior native observations keep their original scopes.
