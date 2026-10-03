# Corrected darkhttpd local build: stage 1 evidence

Observed 2026-10-02 on arm64 macOS 27.0.1, existing Xcode 27 / SDK 27, Apple clang 21.0.0 (`clang-2100.3.34.2`). Same-model delegated self-review; Claude unavailable. This stage corrects and tests temporary third-party source only. It does not enable an Amid production adapter, install a server globally, add vendored source or bundle a server.

## Exact reviewed change

The official v1.17 source was fetched in the [earlier owned investigation](darkhttpd-feasibility.md), resolved to commit `3075d35e1d2deb65ed8b079137c4ae1213de4b48`. SHA-256: `450280b0010ee689b1984d8258afcc37d3f43a2cd8825661d275f9744e1f3ce8`. [Official pinned source](https://github.com/emikulic/darkhttpd/blob/3075d35e1d2deb65ed8b079137c4ae1213de4b48/darkhttpd.c).

The only source change moves `fclose(logfile)` from before connection cleanup to immediately before `return 0`, after connection logging and final statistics. This preserves default-stdout logging as well as explicit-log-file behavior. ISC copyright/license text and embedded BSD notices are unchanged. No privilege, serving, launch, daemon or signal behavior was changed. Reusable reviewed patch: [cleanup-before-log-close.patch](../../fixtures/darkhttpd/cleanup-before-log-close.patch).

| Artifact | SHA-256 |
| --- | --- |
| Reviewed patch | `14c39629dfdab7cff106fd624185ab133bccfac671b27c1b8cae1be2fbf0c42f` |
| Corrected temporary source | `199bdc83c308692533815fdabf2ebf01b537cdd54a550e4267e0d4bf8bf86994` |
| Signed plain build, both rebuilds | `c7c78d329a49f96044f513ab5a4d4acb08ac5f10eae98e49946370e8db7320e4` |

Temporary directory: `/private/tmp/amid-darkhttpd-corrected-feg17b4y`. Plain binaries were compiled independently from identical corrected source in `build-one` and `build-two` with different full source/output paths, both named `darkhttpd`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang -O2 -arch arm64 -mmacosx-version-min=15.0 "$BUILD/darkhttpd.c" -o "$BUILD/darkhttpd"
codesign -s - "$BUILD/darkhttpd"
codesign --verify --strict "$BUILD/darkhttpd"
```

Every compile/sign/verify command exited 0. Both signed binaries reproduced the same bytes/SHA-256 and CDHash `465b0edd621f1d6b7f1a7914d51e574088ecbef3`. Signing is ad-hoc, with no TeamIdentifier. This proves two local rebuilds under the exact observed toolchain/flags, not universal reproducibility across Xcode/SDK/architectures. Minimum deployment 15 is not runtime validation on macOS 15. An unknown build must not be enrolled solely by accepting its self-reported hash.

## Owned checks and safety

The prior launcher/helper procedure was reused. Before `execv`, a new launcher sets default SIGALRM and `alarm(8)`; the server never changes that signal. Each server is a newly created runner child, with recorded PID/UID/parent/start identity, synthetic temporary project/page/sparse 128 MiB file and kernel-selected loopback port 0. Metadata-only lsof verified each owned listener before the synthetic client connected. Cleanup only waited for exact children. No numeric-PID/group/force-kill fallback was used.

For every child, task-name/audit-token acquisition, token-bound executable-path match, Security audit-token guest lookup and pinned dynamic CDHash validity succeeded. The unchanged existing `fixtures/audit-token-probe.c` checks parent/UID and sends one token-bound SIGTERM. The plain slow-active cases read a synthetic HTTP 200 response then stopped consuming the 128 MiB transfer, leaving the request active when SIGTERM was dispatched.

The diagnostic build uses the same corrected source with wrappers for fclose/fprintf/fflush, separately compiled/signed. The wrappers report attempted writes/flushes to a previously closed FILE pointer without dereferencing it. Its CDHash is `9cf03eab633a70f12da2e1824858f2fdff63fb40`; it is not the plain adapter candidate.

| Owned case | PID | Loopback port | Token signal result | Child exit | Log/output bytes | Final statistics present | Diagnostic closed-stream write/flush attempts |
| --- | --- | --- | --- | --- | --- | --- | --- |
| plain-idle | 36533 | 64944 | 0 | 0 | 0 | true | 0/0 |
| plain-active | 36552 | 64945 | 0 | 0 | 86 | true | 0/0 |
| plain-stdout-active | 36561 | 64949 | 0 | 0 | 253 | true | 0/0 |
| observed-active | 36572 | 64951 | 0 | 0 | 86 | true | 0/0 |
| plain-natural | 36595 | 64953 | 3 | -14 | 0 | false | 0/0 |

Both **uninstrumented slow-active children exited 0**, printed final statistics and preserved active-request logging (explicit log 86 bytes; default stdout 253 bytes). The diagnostic slow-active child exited 0, preserved 86 bytes of log, and recorded **zero closed-stream write/flush attempts**, contrasting with one each before the correction. Plain idle also exited 0. These results demonstrate the corrected cleanup path for these declared cases, not request draining or completion of the interrupted download.

Natural lifetime expired via inherited SIGALRM (`-14`). Holding the original audit token until the helper's nine-second delay then signaling returned ESRCH 3. No replacement process was targeted; this is safety evidence for the retained token, not graceful completion of the natural alarm case.

Final runner `python3 "$TEMP/owned-check.py"` exited 0 and printed `ALL_OWNED_CHECKS_PASSED`. Raw records, reviewed temporary source, binaries and harness remain in that isolated directory. All created servers exited.

Two earlier corrected-run attempts are **not passes**: the PTY EOF loop required Ctrl-C of that exact tool session (exit 130 after the owned child had exited), then a PTY-output assertion failed (exit 1). The final harness uses a regular temporary stdout file and metadata-only listener discovery, preserves all substantive assertions and passes. The harness EOF loop briefly consumed CPU; do not use concurrent host measurements as uncontaminated workload evidence without checking overlap.

## Supported investigation boundary

Tests cover current-user foreground IPv4 loopback serving with default stdout and explicit temporary log, idle/active shutdown and natural lifetime. Source remains GET/HEAD-only, without CGI; inspection found startup daemonization fork and no exec/process-command path. No daemon, chroot, privilege-dropping/root, PID-file, syslog, IPv6, redirect, external interface or third-party deployment variant was tested or enabled. Those variants remain unsupported unless independently established; passive metadata cannot prove their launch flags.

The shutdown-order blocker is resolved for this corrected local build and tested path. Remaining adapter work is separate: independent static trusted-build metadata, exact per-preview development-use declaration, unchanged identity/UID/CWD/project/exclusive-loopback/no-child checks, audit-token running-code and dispatch validation, restart/substitution/refusal regressions and actual explicitly confirmed UI observation. CWD/project is an observed association, not proof of the served root; no arguments, environment or served content may be inspected by Amid. No persistent restart permission or automatic server launch is implied.
