# Overview presentation native checks — 2026-10-02

Observed through native CUA at 21:31–21:34 CDT on arm64 macOS 27.0.1. `build/AmidPresentation.app` uses bundle ID `com.madeordinary.amid.presentation`; [source/executable manifest](presentation-source.json) and package log (local record: `presentation-package.log`) identify the ad-hoc bundle. It includes conditional history index reconstruction and system reply size guards, but excludes the later unbuilt load-phase scope experiment.

Launch: `open -n "$PWD/build/AmidPresentation.app" --args --verification`. This uses a temporary process-specific store and ephemeral key, with Amid-only display filtering. No normal user store or existing Keychain data was touched. The initial CUA selection took 924 seconds before returning the onboarding sheet; that tool delay is not an app/menu latency measurement. No builds or profiles ran during the hold.

- Chose Off in the native onboarding sheet and selected Start observing. Overview initially showed CPU Unavailable, then numeric system/application CPU on subsequent samples. Memory values and coverage appeared with units. The only displayed application was the owned AmidPresentation process.
- Set the native Overview scrollbar to 0.7. Sent Command-H, observed the hidden-dialog role, then used its exposed Raise action. The standard window returned with the same 0.7 scroll value and updated system/application values. This is one observed hide/raise path, not every minimize/occlusion/multi-window path.
- Command-Shift-P paused monitoring; Command-7 opened Settings. Clicked Clear History, inspected the native confirmation, then confirmed deletion of this disposable test data. Command-1 returned to Overview: Monitoring paused, Awaiting applications, zero observed processes, and Unavailable values with no previous application row.
- Repeated Command-H and Raise while paused. The cleared state remained; no cached value reappeared. Command-Shift-P resumed. Fresh values appeared, with initial CPU Unavailable followed by numeric deltas and 5.2-second actual cadence.
- Inspected a live screenshot after resumption: Overview cards, columns, units, sidebar and coverage footer rendered without visible clipping in the inspected region. Screenshot viewed inline only; no saved screenshot artifact is claimed.
- Command-Q returned `App quit`. No owned server was started by this check.

These observations verify the recorded source subset. They do not establish menu p95, complete VoiceOver/keyboard workflows, all lifecycle races, minimum-OS compatibility or a CPU/RSS pass. The separate full-workload normal presentation profile was launched only after this test instance quit, with new disposable storage and distinct numeric report paths.
