# Local offline and traffic observations

Observed 2026-10-02 on arm64 macOS 27.0.1. The app has no account, update endpoint, analytics or network client dependency. Source absence alone does not establish measured traffic behavior.

## Network-denied collector process

The release probe ran under a process-scoped sandbox profile:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' .build/release/amid-probe
```

It exited 0. `offline-probe.json` reports available collection with 729 observed processes, 208 inaccessible, 354 app groups, 10 projects and 23 listeners; its own process was observed. The summary excludes identifying metadata. No machine network setting was changed. This verifies the collector can run without network operations; it does not prove every GUI flow under a network denial or establish cross-OS support for this test utility.

## Owned GUI network observation

For the owned performance app PID 41875, `nettop -n -P -p 41875 -L 7 -s 10 -J bytes_in,bytes_out -x` exited 0. The app was checked alive before/during the observation. `network-observation.csv` contains seven column headers and no process socket rows. No DNS resolution, endpoint details or payload capture was requested.

No socket rows were observed in this roughly one-minute window. This is a bounded observation, not proof that every future runtime path sends zero bytes. The window predates the latest package. Reference idle/background traffic and longer production-use observations remain release checks.

## Current Counters native network-denied subset

Observed October 3, 2026, 20:35–20:44 CDT (October 4 UTC), source revision `8432b3a15b7cee4a266a053a2f6fe3049fbcdda8`, executable SHA256 `52d1e49ca7cb1f03903b68f797decd5b1ec60f779a31b2ccd9f30dee0e9b3e6c`. All 103 frozen inputs and the executable remained unchanged; no suite rerun or production change occurred. [Candidate identity and prior verification](interface-counter-candidate-source.json).

A parent-owned loopback connection succeeded without payload. The retained child wrapper's connection to that same listener returned EPERM under `(version 1) (allow default) (deny network*)`; it then exec'd the exact verification app in the same birth identity. Policy was process-scoped, with no global network/preference change. This proves inherited denial for the exercised process, not packet absence or every helper/flow.

In disposable verification storage, native observations covered Off onboarding/badge, application search and details, an alias, exclusion/inclusion, project and listener inspectors, seven-day History with three then four retained buckets and coverage/cadence/method columns, empty Alerts/rules, and Settings. Notification and login toggles stayed off. Diagnostics preview was cancelled, reopened and saved: all 580 bytes matched the captured preview, SHA256 `306a8bbb762cd46e75ed6354eb64dc6c001b175f25258959edbbccfb3a5d371b`; the existing export remained unchanged after Clear. No global search for cancelled-save side effects was performed.

An owned packaged listener stop preview was cancelled, then freshly validated and confirmed. The app reported one signal and no remaining identity/endpoint; the retained fixture child exited -15, its parent exited 0 and the fixture launcher sent no signal. No connection or payload was sent to this fixture. Pause/resume reset CPU to unavailable. Paused Clear affected only verification history: seven-day choice and alias remained, storage fell to 604 bytes and History showed no saved measurements. Hide/Raise kept paused cleared values; resume restored measurements. Command-Q was sent through CUA; the retained app child and parent both exited 0 without launcher signal. The observed Quit action and owned-child exit were recorded separately.

Memory pressure remained Unknown. This is a narrow current-host native subset, not all-flow offline, menu/p95, complete keyboard/VoiceOver, notification consent/delivery, login service, sleep/lock, normal Keychain relaunch/failure, sustained performance or minimum/reference-hardware acceptance. Private identities, paths, raw logs and screenshots are not published. Review was same-model; no independent cross-tool review is claimed. Both owned children exited; verification evidence/export/storage were retained, and no normal user data was deleted.
