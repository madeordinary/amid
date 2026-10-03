# Native keyboard observations — 2026-10-02

At 21:50–21:54 CDT, Codex used CUA against the frozen `build/AmidPresentation.app` described in [its manifest](presentation-source.json). A new `--verification` instance used disposable encrypted storage, an ephemeral key, and Amid-only process display. Seven-day onboarding was accepted. No normal store, Keychain credential or macOS preference was changed.

Observed:

- Command-2 opened Applications. Tab focused Search applications; typing `Amid`, Tab, then Down selected the own application row and exposed its inline inspector, grouping explanation, physical-footprint label and recorded interval.
- Subsequent Tab focused the custom-name field, then the sidebar. Buttons and range controls were not reached in that observed sequence; no complete keyboard-navigation pass is claimed.
- Command-3/4/5/6/7 each selected Projects, Ports, History, Alerts and Settings respectively. Empty project/listener states explicitly described unknown coverage. The Alerts view exposed the published rule durations and thresholds.
- History initially showed no saved measurements in an AX observation. After the window's exposed Raise action, the rendered view showed three retained minute buckets, CPU ranges, coverage, actual cadence and a text table. This is evidence for visible restoration, not a measured latency or missing-data regression claim.
- Diagnostics was opened by an AX button click, not a keyboard route. Its exact JSON preview contained coarse metrics and an omitted-fields list. Escape dismissed it without export.
- Command-Shift-P changed the visible status to Monitoring paused and the Settings switch to on. Repeating it resumed. Command-1 returned to Overview; Command-R was accepted, and the initial post-resume CPU/network deltas were unavailable before later numeric values appeared.
- Control-F8 did not expose the menu panel in the observed AX state. A single attempt to inspect SystemUIServer's menu accessibility surface timed out. No settings change or alternate UI-control technology was used.
- Command-Q returned `App quit` at cleanup. No server or other application was terminated.

The app's main window and History screenshot were inspected inline; no screenshot file was saved. Tool round-trip times are not app-response measurements. This run does not verify menu-panel opening, its spoken name, menu p95, VoiceOver speech, complete focus order or every action's keyboard path. Current macOS keyboard-navigation behavior and the exposed tool surface remain boundaries to resolve.
