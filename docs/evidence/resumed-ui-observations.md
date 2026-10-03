# Resumed native verification, 2026-10-02

All observations use native CUA and disposable verification storage. No consent or machine-security settings were changed. Screenshots were inspected inline; no saved screenshot file is claimed.

## Candidate from 09:30, observed 11:56–12:15 CDT

Executable SHA256 a5afc3dfa389324b036ff7de4ce5966ec2dc8a1f640cb49c76bf9ceb14430864; implementation revision 058e5a8. Launched `open -n build/Amid.app --args --verification --light-appearance` after quitting both older owned instances through their own UI. Old benchmark session 79503 exited 0 without a report; no performance claim follows.

- Onboarding offered Off/24h/7d/30d, with 7d recommended. Selecting Off changed the explanatory text to a 15-minute RAM ring. Start observing showed first CPU as Unavailable, then measured deltas.
- Command-5 opened Off History: Last 15 minutes, memory only; raw observations, unknown first CPU, numeric later CPU, coverage and Active pages labels. Light chart/table rendered with readable labels; wide table columns use native horizontal scrolling.
- Command-comma opened the separate native Settings window. Preview diagnostics opened its own sheet with coarse JSON and omission list. Escape cancelled it and returned to Settings. No export or file-equality claim in this run.
- Command-W closed Settings. Command-Shift-P paused at about 11:58:02, with 34 raw observations (latest 11:58:01). No samples were added while paused. At 12:15, Applications showed 0 groups and History showed No observations in the memory window. Cached group/inspector selection had cleared. This is an actual wall-clock expiry observation, not a shortened timer.
- Command-Shift-P resumed at 12:15:25 with one new raw observation and unavailable CPU/memory bucket values, preserving the interruption boundary. Real sleep/wake and lock/quit RAM clearing are separate tests.
- Command-4 and Command-6 opened empty Ports/Alerts, with coverage and published rule explanations. Command-2, Tab to search, Tab and Down selected the application row and exposed its inspector with simultaneous RAM history. Further Tab reached the alias field. Full keyboard-only process/stop traversal and VoiceOver speech remain unverified.
- Native status-menu inspection through SystemUIServer timed out. The app remained available after refreshing its AX state. No menu-latency or menu-panel observation is claimed.

## Updated measurement harness

The resumed release build exited 0 (31.19 s). Focused final harness/lifecycle suite exited 0: 14 tests, 0 skips, 0 failures at 12:04:18. Same-model GPT-6.1 sol review found and helped fix completed-report rewriting on quit. The regression compares saved report/status bytes after repeated finish/cancellation.

The harness records warmup and accepted samples, monotonic elapsed time, status heartbeats, gap limits, actual retention and permanent invalidation on interruption. Own-process CPU is independently measured with checked getrusage counters; own interrupt/package-idle wakeups are distinct optional deltas. No stack sampling occurred.

A separately identified ad-hoc benchmark copy launched successfully. Run 9EFD2843-5E17-4B59-9421-312C8921D245 warmed up with 6 available samples and began measurement at 12:07:03 CDT for 1800 seconds. Its executable hash is d09d9450e1700fb0bd79a2d00ae7be00b7a17d5494988631e9b627446ac2af5f. The run was later invalidated by screen suspension at 12:31:04 CDT; it is not a pass. The binary comes from the same release compilation; its different bundle identity/signature changes the full executable hash. No reference-M1 or matched no-monitor baseline is claimed.

## Rebuilt normal bundle

Packaging exited 0 after the same release compilation (cached build 0.22 s), with strict ad-hoc signature verification. Normal bundle executable hash 2f0c2447d7a9a6f3c7a27e07900b804327332b771b6fb99ed4629cb4b1c6bb92. New disposable launch followed the current system dark appearance, and Return accepted 7-day retention from onboarding. This confirms only the observed native paths; later checks are recorded below as they occur.

## Owned stop preview, 12:19–12:24 CDT

The rebuilt dark-appearance verification app PID 980 used disposable encrypted storage. Launched only the packaged owned fixture from its DevelopmentFixture directory with lifetime 600 seconds; session 6818 reported PID 2241, loopback 127.0.0.1 port 62711 and 16 MiB allocation. Ports and inspector showed that exact endpoint/identity/project/executable.

- Preview at about 12:19:25 showed one target, zero children and the two-minute expiry explanation. Confirming at 12:21:48 refused the expired preview and sent zero signals.
- That refusal also displayed zero remaining identities/endpoints despite lacking a fresh observation. This is a presentation defect, not evidence that the target exited. Source now carries an explicit remainingObservationAvailable flag and displays unavailable instead of zero when no measurement exists. At 12:35:20 the release run passed 11 tests: eight core action tests, two presentation regressions and one synthetic profile. The GUI correction remains unobserved. The packaged app predates this correction.
- A new preview at about 12:23:50 remained usable beyond 30 seconds. Confirmation at 12:24:39 sent one SIGTERM to the owned fixture. The UI reported the previewed server exited with no remaining observed endpoint owner; session 6818 exited 143. No unrelated process was targeted.
- The inspector showed instantaneous benchmark CPU 3.5–4.7% of one core around 12:26–12:27 and physical footprint 155–169 MB. These are instantaneous samples and physical footprint, not mean CPU or RSS; they do not close the performance budget.

## Interrupted benchmark

Status for run 9EFD2843-5E17-4B59-9421-312C8921D245 changed to invalid at 12:31:04 CDT with reason Monitoring suspended: screen. It had 275 accepted samples, zero unavailable samples and maximum inter-sample gap 5.399 seconds before suspension; elapsed status 1440.150 seconds. At 12:32 the GUI session was unavailable. No settings/TCC/security change was made. The invalid report cannot establish a continuous 30-minute performance result.

No store fault injection, retention reduction, or Clear History operation was started in this resumed run. The original disposable store was not modified through shell file operations.

The final invalid benchmark report was written at 12:37:05 CDT and preserved verbatim as [gui-benchmark-resumed-invalid.json](gui-benchmark-resumed-invalid.json). Over 1801.928 seconds including the suspended tail it recorded 19.881403 CPU seconds, mean 1.103341% of one core, lifetime peak RSS 160,710,656 bytes (153.3 MiB), 4321 interrupt wakeups and 133 package-idle wakeups. It exceeds the numeric CPU/RSS targets even with the interrupted interval, but is not a valid continuous-run, baseline, reference-device or release-gate measurement. The interruption status and raw numbers are retained together.

## Integrated source verification, 13:03 CDT

`bash scripts/test.sh` exited 0: 78 tests, six explicit skips, zero failures in 260.035 seconds. The skips are the sandbox-denied owned loopback bind and the opt-in native fixture, own-Keychain, synthetic profile, live pipeline profile and reviewed-server integrations. Their separate evidence is not silently counted as part of this run. The suite includes the new unknown endpoint-coverage result, async clear/suspension action-record guards, declaration policy and alert-formatting regressions. Exact sanitized log (local record: `resumed-integrated-tests.log`).
