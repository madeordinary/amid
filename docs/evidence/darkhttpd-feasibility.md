# Darkhttpd feasibility: owned local checks

Observed 2026-10-02 on arm64 macOS 27.0.1, Xcode 27 / SDK 27; Apple clang 21.0.0 (`clang-2100.3.34.2`). This was a same-model delegated review, not an independent Claude review. Only new temporary processes/files were used. No app adapter, runtime resource or global installation was added.

## Result

A real read-only native server can be addressed through the existing public audit-token and running-code checks: the owned darkhttpd build demonstrated that capability. **Unmodified darkhttpd v1.17 is not yet an acceptable production adapter**: its shutdown logging order has a reproduced write/flush-after-close path. Passive CWD/project/loopback metadata also cannot establish development-use intent or the served root. These are precise outstanding conditions, not evidence that all native adapters are impossible.

A future bounded adapter could enroll a separately installed, independently pinned, corrected read-only server with explicit development-use confirmation bound to its exact incarnation/project. Enrollment must not infer intent from loopback, runtime names or project grouping. Amid need not launch or bundle a server. This task did not implement enrollment, repair third-party source, enable an adapter, or claim M-11 complete.

## Provenance and license

The official [v1.17 release](https://github.com/emikulic/darkhttpd/releases/tag/v1.17) resolved through GitHub's commit API to `3075d35e1d2deb65ed8b079137c4ae1213de4b48`. Downloaded the three source files over HTTPS into `/private/tmp/amid-darkhttpd-dm7pl_mk`; the prior sandboxed fetch failed DNS and the authorized network fetch succeeded. No release executable was downloaded.

| Exact official file | SHA-256 of fetched bytes |
| --- | --- |
| [darkhttpd.c](https://raw.githubusercontent.com/emikulic/darkhttpd/3075d35e1d2deb65ed8b079137c4ae1213de4b48/darkhttpd.c) | `450280b0010ee689b1984d8258afcc37d3f43a2cd8825661d275f9744e1f3ce8` |
| [README.md](https://raw.githubusercontent.com/emikulic/darkhttpd/3075d35e1d2deb65ed8b079137c4ae1213de4b48/README.md) | `1ae82db1f3a630d8788240a2b27f175cd7cc49019bef3fa44b7ef4e00a0b13d1` |
| [Makefile](https://raw.githubusercontent.com/emikulic/darkhttpd/3075d35e1d2deb65ed8b079137c4ae1213de4b48/Makefile) | `81cdec2841276db84ddc48fc7358d91ae3f3168781e9a0adc103e63a264dc95a` |

Official README identifies ISC licensing; the source also preserves embedded BSD attribution/notices for copied queue macros. Preserve all those notices if redistributing. No official prebuilt signed macOS artifact was established; the release showed source assets. This test binary is a local build, not an official binary.

Compiled unmodified source with existing Xcode clang:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang -O2 -arch arm64 -mmacosx-version-min=15.0 "$TEMP/darkhttpd.c" -o "$TEMP/darkhttpd"
codesign -s - "$TEMP/darkhttpd"
codesign --verify --strict "$TEMP/darkhttpd"
```

`TEMP` denotes this run's unique directory. Compiler and signature verification succeeded. Signed binary SHA-256: `4c6f0383ecf18d84c47c744fdc8e551df2183327a8eb25739a8818ca24dc3539`; CDHash: `e046d71f766601d59eaa4bda225cb4487ab064a6`. Signature is ad-hoc, with no TeamIdentifier. Deployment target 15 is not a macOS 15 runtime observation.

## Source boundary

The exact fetched single-file server accepts GET/HEAD and has no CGI implementation. Search found one `fork()` in startup daemonization, no `exec`, `posix_spawn`, `system`, `popen` or `getenv` occurrence. No request-loop process creation was found. This is source inspection plus the declared owned run; it is not proof against injected code or a compromised same-user environment. The tested launch omitted daemon mode. Its served root is an argument, independent of ordinary CWD; only chroot setup changes CWD. Amid must not read those arguments to infer scope.

SIGTERM sets `running=0`; cleanup closes listener/log/pidfile, then frees connections. The latter invokes logging. Closing the log first leaves a stale FILE pointer when a parsed connection remains. Active transfers are interrupted, not drained. [Pinned source](https://github.com/emikulic/darkhttpd/blob/3075d35e1d2deb65ed8b079137c4ae1213de4b48/darkhttpd.c).

## Safe owned test procedure

A new C launcher set `signal(SIGALRM,SIG_DFL); alarm(8); execv(...)` before each server launch. The fetched server does not alter SIGALRM. The natural-exit case proved that inherited eight-second hard lifetime on this host. Cleanup waited for these exact children; it never used numeric-PID, group, force-kill or existing-server cleanup.

The Python runner created a synthetic project marker/page and sparse 128 MiB file, launched each server as its child with loopback bind and kernel-selected port 0, and recorded PID/UID/parent/start time. Before a synthetic client connected, target-bound lsof verified the owned loopback listener. No unrelated process arguments, environments, payloads or files were inspected.

A temporary identity-check helper required matching current UID and parent, acquired the genuine task audit token, checked token-bound executable path, obtained the Security guest with `kSecGuestAttributeAudit`, and validated the independently recorded CDHash requirement. Task acquisition, token acquisition, Security guest lookup, requirement creation and dynamic validity all returned 0 for all three owned processes. The existing unchanged repository `fixtures/audit-token-probe.c` was compiled and used for the single owned SIGTERM; it checks matching UID/parent and never falls back to PID signaling.

| Owned case | PID | Loopback port | Token signal result | Child exit | Closed-stream write attempts | Closed-stream flush attempts |
| --- | --- | --- | --- | --- | --- | --- |
| plain-idle | 19786 | 63798 | 0 | 0 | 0 | 0 |
| observed-active | 19803 | 63800 | 0 | 0 | 1 | 1 |
| plain-natural | 19823 | 63802 | 3 | -14 | 0 | 0 |

For the unmodified idle build, token SIGTERM returned 0 and the child exited 0 within 0.734 s after starting the probe. For natural expiry, the child exited from its inherited SIGALRM (`-14`); the helper retained the original token for nine seconds and token SIGTERM then returned ESRCH 3. No replacement process was targeted. These are actual observations, not a fabricated token/layout or signal 0 test.

For the active case, a separate diagnostic build substituted wrappers only for `fclose`, `fprintf`, and `fflush`; source bytes were unchanged. It served one synthetic slow GET, leaving a parsed connection active. `observed_fclose` recorded the closed FILE pointer. Subsequent `observed_fprintf`/`observed_fflush` compared pointer identity and emitted `WRITE_AFTER_CLOSE`/`FLUSH_AFTER_CLOSE` to stderr instead of dereferencing that closed stream. Exactly one of each occurred; access-log length was 0 and the diagnostic child exited 0 after token SIGTERM. This proves attempted use after close in the tested path. It does **not** claim a crash of the unmodified binary or prove cleanup in all modes. The plain active case was deliberately not treated as safe merely because an undefined operation might happen to survive.

Runner `python3 "$TEMP/owned-check.py"` exited 0 and printed `ALL_OWNED_CHECKS_PASSED`; raw owned records remain in the temporary `results.json`. Every created server has exited. Temporary source/harness files remain for local inspection; none are app resources.

## Adapter decision and next evidence

Keep darkhttpd unsupported in the current app. A concrete adapter is technically plausible once a reviewed build removes the closed-stream path, exact source/build/signature provenance is pinned, and owned idle/active/exit/restart/substitution tests pass. Explicit target development-use enrollment must supply intent rather than guessing from passive metadata; exact current identity, UID, CWD/project, exclusive loopback endpoints, no children, dynamic CDHash, disk digest, immediate validation and lifecycle invalidation still apply. No promise of no clients, no interrupted downloads or freed ports follows.

This would support one real static-development server, not generic Node/Python/Swift or arbitrary executables. Minimum OS, broad attribution, production launch variants and final GUI confirmation remain unverified. No download, installation or adapter implementation beyond this authorized temporary investigation is implied.
