# Evening native continuation — 2026-10-02

Observed through native CUA on arm64 macOS27.0.1. Times below are CDT. Screenshots were inspected inline; no saved screenshot is claimed. Normal verification used temporary storage and an ephemeral key.

## Cleanup and prior invalid report

At about 18:42, native inventory showed the Mac available and the exact prior `com.madeordinary.amid.benchacceptance` instance running. It was reidentified by full bundle path and quit with Command-Q; the tool confirmed App quit. Its final report SHA256 remained `dbf262bf281605bcb4bf5a0d829bcc9443ff91717a32fbca218db5e0cc52ff2e` and is preserved as [gui-benchmark-acceptance-invalid.json](gui-benchmark-acceptance-invalid.json).

The report finalized at 16:29:24, but the run had already invalidated on screen suspension at 16:02 after only 35 accepted samples. Its 0.333395% mean CPU includes the long suspended tail; peak RSS was 133,267,456 bytes. These numbers cannot pass the active 30-minute budget. The earlier invalid-status snapshot remains unchanged.

## Current History and keyboard checks — 18:42–18:44

The exact `build/AmidCheckpoint.app` executable SHA256 `0cfed1136f2dae65a32eba0015f913a6ef8b3de6312c12254fd96a54697c2d16` passed strict ad-hoc verification and launched with `--verification --light-appearance`, exit0. Return accepted fresh seven-day onboarding. Command-5 opened History.

Actual cadence and Recorded gap columns appeared in the native table and accessibility rows. The screenshot showed readable values and headings. Setting the exposed horizontal scrollbar to its right endpoint revealed Memory method, Load 1/5/15 and Samples without losing the cadence/gap values. A direct scroll attempt returned windowNotFoundAtPosition; the supported scrollbar action succeeded. No unsupported UI workaround was used.

Command-Shift-P paused monitoring and changed the control to Resume. Command-6 selected Alerts; its rule explanations and empty state were present. Command-5 returned to History, and Command-Shift-P resumed. The next retained row showed `Recorded gap 24.0 s`, while the prior row retained zero; coverage did not invent measurements during the interruption. Screenshots also showed the actual cadence ranges and separate chart marks. This is a real pause/resume gap observation, not sleep/reboot or a controlled retained CPU-spike result.

One AX read during a visibility transition briefly exposed the empty History state; selecting History restored the existing rows. No store deletion was observed. The provider raises the app during interaction, so this does not establish the exact transition timing.

Control-F8 followed by Down did not expose a menu-bar panel in the bound app UI. Complete menu keyboard access, tooltip accessibility and VoiceOver speech remain unverified. The normal app was then quit with Command-Q; App quit was confirmed.

## Fresh benchmark — completed, budgets failed

A new `build/AmidBenchCheckpoint.app` copy uses identifier `com.madeordinary.amid.benchcheckpoint`. Strict ad-hoc verification passed; executable SHA256 `4eaec3a5356a971b572103263302a8a8cde2056196585f5f84f25ca34b69670b`. It has the same recorded checkpoint runtime source, with a separate bundle identity/signature.

Launch used `--performance-verification --benchmark-retention week --benchmark-hidden --benchmark 1800 --benchmark-output /path/to/amid/build/gui-benchmark-checkpoint-1800.json` and returned exit0 at about 18:44. The subsequent CUA app selection took 2,118.343 seconds to return. Its first returned UI showed monitoring at 19:20:00. Tool elapsed time is not evidence of app startup or menu latency; the source of that delay was not measured.

The app's own status was created at 19:20:00, accepted six available warmup samples, and entered measuring at 19:20:31 with run ID `EC5053B5-21D1-4D29-B383-1F7AFC175F4C`. The run completed at19:50:35CDT with phase `completed`:1,803.225233 seconds,343 accepted samples,zero unavailable samples or invalidation reasons,maximum gap5.417335 seconds,requested cadence5 seconds,and591 observed processes at completion. Own CPU28.123373 seconds gives1.559615% of one core, above the0.5% target. Lifetime peak RSS168,050,688 bytes (160.265625MiB) exceeds150MiB. Interrupt wakeups4280 and package-idle wakeups821 are distinct public counters, not a total-wakeups claim.

The final [raw report](gui-benchmark-checkpoint-completed.json) has SHA256 `ae958c02af5f6b23cbfefd1d94eb9fa423124c96c3c42c9a5cb9d097a977ff92`. The benchmark app was quit through its own UI after completion; App quit was confirmed. The original and preserved report hashes matched after quitting. All owned apps and servers are exited.

Public host metadata was Mac17,9,24GiB RAM,15 logical cores. This is not the reference M1/8GB workload and has no matched no-monitor baseline. No additional build, fixture or profiling workload ran during the valid measurement. No temporary wake assertion, power/lock setting or privacy permission was changed. The run is valid evidence of a budget failure, not a completed performance gate.
