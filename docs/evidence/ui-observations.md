# Native UI observations, 2026-10-02

Observed by root through the actual native UI/accessibility tree on arm64 macOS 27.0.1. This is not a full VoiceOver audit. All named processes below are disposable Amid/test workloads. Personal process metadata from a separate performance run is deliberately omitted.

## Build before final integration

`bash scripts/package.sh` exited 0; log `/private/tmp/amid-package-corrected.log`. This is an ad-hoc build against uncommitted source after CPU-unit correction, before later durability/cadence/localization changes. It was launched with `--verification`: ephemeral-key temporary history and an Amid-only displayed process filter.

- Onboarding showed Off/24h/7d/30d, seven days recommended, metadata/privacy explanation and no-data-before-choice message. Physical memory behind onboarding was Unavailable, not zero. The segmented control consumed excessive vertical space; source subsequently adds a fixed control height, not yet reobserved.
- Return accepted the disposable history choice. Command-2 selected Applications. The first CPU reading was Unavailable; later readings were numeric with 100%=one-core units, labeled Physical footprint and Observed coverage.
- Selecting Amid displayed exact executable-bundle grouping evidence. Its process sheet exposed UID/PID, start time, observed-since, raw and normalized CPU, memory method, executable/project fields, no listeners and a read-only reason. The accessibility tree included values as Details rather than names alone. Escape dismissed the sheet.
- Command-3 selected Projects and showed the owned probe's project with its measured process. Command-4 selected Ports.
- `bash scripts/start-demo-server.sh` started this run's loopback-only Swift fixture. The fixture output and Ports agreed on port 63532, IPv4 loopback address, owning PID and DevelopmentFixture project. No connection to the service was made. The fixture naturally expired; no UI stop was confirmed during this run.
- Ports exposed the correct row in its accessibility tree, but clicking it failed with `cannotClickOffscreenElement`. The screenshot showed an oversized table pushing content offscreen. This is a real failed layout observation. Source now constrains table sizing; the correction is pending live verification.
- Command-1 returned to a normally rendered Overview. System CPU, pressure Unknown, swap, disk, memory categories, interface deltas and group/project summaries were visible. Unknown pressure was not replaced with a normal claim.
- Command-Q quit this disposable UI instance. No notification, launch-at-login, OS privacy or security setting was enabled.

## Outstanding observations

Rebuild current source and repeat onboarding/Ports layout, all destinations and keyboard paths, selected group/history range, actual fixture preview/confirmation/result, frozen diagnostics export bytes, settings/empty/error handling, light/dark, scaled layouts and textual charts. Verify menu panel responsiveness with an appropriate timestamped method. Actual VoiceOver speech and user system accessibility preferences remain a human check unless already enabled; no consent or machine settings may be changed by the agent.

## Follow-up native observations, approximately 08:36–08:46 local

The actual ad-hoc geometry-fix package was rebuilt successfully (`/private/tmp/amid-package-geometry.log`, exit 0) and observed through native CUA. These observations precede the later pause-interruption, refusal-message, group-cache and app-only light-appearance source changes.

- Onboarding's fixed-height retention picker rendered correctly. The app waited for the explicit disposable choice; unavailable physical memory stayed labeled unavailable before collection.
- Ports' final `GeometryReader` bound kept the table inside the available window. The owned fixture row could now be selected. After the stop it showed the expected empty state inside the same intact sidebar/header layout, resolving the earlier offscreen failure.
- The loopback Swift fixture started by this run had PID 17170 and port 51271. The first preview expired before confirmation and sent zero signals. A fresh preview followed by confirmation sent exactly one SIGTERM. The UI reported “Previewed server exited; no remaining observed endpoint owner.” Remaining identities/endpoints were zero. The owning fixture tool session exited 143, consistent with that SIGTERM. No other workload was targeted. The later source makes the expired-preview explanation more specific; that revised copy has not been observed live.
- History rendered real CPU chart points, a textual table, coverage/gap information, observed memory methods and load columns. Native horizontal scrolling exposed the remaining columns. The chart did not claim continuous data across missing intervals.
- The selected owned project was renamed `Fixture Project` in its inspector. The alias appeared immediately. The inspector showed current processes alongside its recorded CPU/memory summary. Choosing the one-hour range and then View history preserved that range and resource selection.
- Settings displayed retention, storage, privacy, alert and integration controls. Notifications and launch at login stayed off. No system privacy setting or consent was changed.
- Diagnostics' frozen preview contained 561 bytes of reviewed coarse JSON. After later samples, the native save panel wrote `docs/evidence/Amid-ui-diagnostics.json` with the reviewed values and no user home path. SHA-256: `2692fef960645fd2ff6ac11572351f7c75df691aecdc1d150b106e55d4ee5435`. This demonstrates the observed export; exact-string behavior also has a unit privacy regression.
- Command-Shift-P changed the status to “Monitoring paused.” Resume/gap verification was not completed: at approximately 08:59, the GUI session became unavailable.
- Native accessibility values for measurements, grouping reasons, chart alternatives and exact action targets were observed. This is not a VoiceOver speech audit. Full keyboard-only, menu-panel timing, light appearance, scaled display, contrast/motion preferences and external display checks remain unverified.

## Latest package versus observed package

`bash scripts/package.sh` subsequently exited 0 (`/private/tmp/amid-package-cached.log`; release compilation 29.96 seconds) after group caching, pause interruption, localized status/action messages, native Settings diagnostics presentation and verification-only light appearance changes. The bundled fixture and app passed `codesign --verify --deep --strict` with ad-hoc signatures. This latest binary has not been reobserved because the Mac is locked. A successful build is not a replacement for that check.
