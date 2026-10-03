# Native acceptance continuation — 2026-10-02 afternoon

Root observed these interactions through native CUA on the unlocked arm64 macOS 27.0.1 host. Times are CDT. Screenshots were inspected inline; no saved screenshot file is claimed. Stores and servers were newly created for this test. No existing user server or normal Amid store was modified.

## Cleanup and initial candidate

At about 15:40, the older Amid verification instance and `com.madeordinary.amid.benchresumed` were each reidentified through their own UI and quit with Command-Q. Both calls reported App quit. The interrupted benchmark report had SHA256 `4eda256129e79e31154809a5b4d35ca971e6c2ca300657ac148b6aea1517a228` before and after quitting; it still matches the preserved invalid evidence.

The first sandboxed `open` returned kLSNoExecutableErr although the executable existed with the recorded SHA256. Launch through the approved local execution boundary returned exit 0. `build/AmidResumed.app`, executable SHA256 `2f8d665bcb234551991b8349dac14a83cf488b5f23aad22ba133f71d14f3e8d6`, launched with `--verification --verification-owned-server /private/tmp/amid-supported-darkhttpd-tLYDLCIB/darkhttpd --light-appearance`. The UI showed a fresh welcome sheet and seven days recommended. Return accepted the disposable choice at 15:42:23; first CPU values were Unavailable.

## Clear, storage error and retry — 15:44–15:46

The app identified its own process as PID 67996. In Applications, the test renamed its group to `Verification Alias`. Settings immediately showed that alias. Pause was enabled before Clear History. Opening the confirmation and cancelling with Escape preserved three retained system buckets in History. A later explicit Clear History confirmation reduced encrypted storage from 8 KB to 608 bytes; seven-day retention, Pause on and Verification Alias remained visible. History then displayed `No saved measurements in this range`, and coverage was zero with `No sample yet`.

Only the paused temporary store `amid-ui-verification-67996` was fault-injected. Its directory contained just the encrypted manifest after clear. The directory was renamed to an exact backup path, and an empty regular file temporarily occupied its original path. Changing the disposable menu metric to System CPU triggered `Encrypted history could not be saved. No plaintext fallback.` and a `Retry history access` button. The empty blocker was removed and the exact backup directory restored. Clicking Retry removed the error, restored the last saved Icon only choice, and retained the alias and pause/retention choices. No fault remained. Resuming displayed Monitoring locally, the saved alias and fresh unavailable CPU. The instance was then quit through Command-Q.

This is an observed directory-write failure/recovery case. It is not disk-full, locked-Keychain or abrupt-power-loss evidence. The test changed no normal Application Support/Keychain data.

## Verification-path defect and correction

An independently hash-verified optional darkhttpd build was launched as newly owned PID 68427, start `1790973754.321725`, UID 501, IPv4 `127.0.0.1:61729`, in synthetic project `amid-ui-owned-server-cyax_l96`. A small owned launcher applied a natural 600-second SIGALRM lifetime before exec. The initial verification UI omitted this server although the permitted metadata probe found it. Foundation normalized `/private/tmp` to `/tmp` in the explicit filter input, while the collector retained `/private/tmp` in the executable path.

A focused regression reproduced three failed assertions. Symmetric canonical comparison fixed only the explicit verification filter. The final regression and two stop lifecycle tests passed, exit 0; before (local record: `verification-path-before.log`) and after (local record: `verification-path-final.log`). Normal monitoring and action authorization are unchanged by this correction.

`build/AmidAcceptance.app` packaged with exit 0 and strict ad-hoc verification. Its executable SHA256 is `046bda0cdebde1d3f98b0d565d9a85aabe1a3c2d52b5bfcc33421e75d7f35ddd`. At 15:48, fresh onboarding accepted seven-day disposable retention. Ports then showed the exact owned PID, project, IPv4 address and port. Selecting and inspecting it showed its identity, executable and project. A visible detail sample reported 2.1 seconds actual cadence.

## Real-server declaration, expiry and stop — 15:48–15:51

The native stop sheet displayed the exact owned identity, endpoint, project and zero validated children. Its supported-mode declaration started unchecked and Confirm graceful stop was disabled. Checking it enabled confirmation. Cancel returned to the still-observed server. Opening a new preview reset the declaration to unchecked and confirmation to disabled again. The sheet was visually inspected with all text and controls visible. No signal had been sent at this point.

A second preview opened immediately before 15:49:01 remained open beyond two minutes. At about 15:51:10, confirmation after checking the declaration returned `Preview expired or current validation is unavailable; review a new preview. No signal sent. Signals sent: 0. Remaining process and endpoint state is unavailable.` This observes the corrected unavailable-state copy without false zero counts.

A fresh preview again started unchecked. After a new declaration and explicit confirmation, the process detail displayed `Previewed server exited; no remaining observed endpoint owner. Signals sent: 1. Remaining observed identities: 0; endpoints: 0.` It also displayed No current observation for the captured identity. The exact owned server launch session exited 0 by 15:51:48 and printed its clean shutdown statistics. No other process was targeted. The server exited before its natural deadline, so no server cleanup remains.

## Visibility and keyboard — 15:52–15:54

Applications displayed 2.1 seconds actual detail cadence at 15:52:13. Command-M minimized its window at about 15:52:38. After about 45 seconds, a native accessibility observation restored the window and displayed the last measured 5.6-second interval at 15:53:28. A subsequent observation displayed 2.1 seconds at 15:53:36 and continued near that cadence. This observes a background interval and resumed detail interval; it is not a complete lifecycle matrix or transition-latency measurement.

Tab and Control-F8 produced no observed focus/menu-state change through this UI surface. Complete keyboard, menu-bar panel and VoiceOver acceptance remain unverified. The Acceptance instance was quit through Command-Q before the benchmark launch.

## Full-GUI benchmark — interrupted again

A copy at `build/AmidBenchAcceptance.app`, bundle ID `com.madeordinary.amid.benchacceptance`, was ad-hoc signed and strictly verified. Executable SHA256: `6cf3e5c1a64b67343e26d097d84353324f93bbc4f5e572df4bd60f758ab1f65e`. Launch with performance verification, seven-day temporary retention, hidden measurement and a requested 1,800 seconds returned exit 0 at 15:55:02. The following native app selection took about 222 seconds; its first UI and own status showed initialization at 15:58:50. The cause of this delay is unmeasured; tool time is not app or menu latency.

Run `7278FD8C-BAB4-4C0C-9499-106DAD68A77F` accepted six warmup samples and began measuring at 15:59:20. Its own status permanently invalidated the run at 16:02:20 with `Monitoring suspended: screen`, after 35 accepted samples and 179.593 seconds. Maximum accepted gap before suspension was 5.383 seconds. The [raw status](gui-benchmark-acceptance-invalid-status.json), SHA256 `26d5d29e3bc2b38bdbd8c8f8b33f2089922e39e323ca855ff3f38766468da472`, was preserved. Native inventory subsequently confirmed session suspension. No 30-minute CPU/RSS pass follows from this run. At this checkpoint the final report was pending; later finalized evidence is recorded in the performance ledger.
