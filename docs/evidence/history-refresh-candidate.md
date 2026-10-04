# History pending-presentation candidate

Loaded History and app/project summaries no longer observe loading-state changes that cannot affect their display. Empty-history views still observe loading start and completion. Each surface's two-case regression run showed one failure before its fix. Both actual-body tests passed afterward; no unrelated collector/storage behavior changed.

Final release verification exited 0: **192 executed tests, 182 passed, 10 explicit opt-in skips, 0 failures in 95.119 seconds**, plus **18 interface and 9 system C cases**. Packaging, distinct bundle ID, ad-hoc resign and strict verification all exited 0. All 105 inputs stayed unchanged: 104 public inputs plus one private fixture runner. [Exact source/executable manifest](history-refresh-candidate-source.json).

`build/AmidHistoryRefresh.app` executable SHA256: `0fffb7601d675b08c3d1dacb01e382fbab47fd3ac5decce0c7136198441cc285`; ad-hoc CDHash: `204c8ff41852f283d9e356fc7eca663a36b04d4d`. This remains a local development candidate, not a Developer ID signed or notarized public binary release.

## Unobserved short diagnostic

The requested normal-presentation 180-second harness completed internally: 188.064102833 seconds, 18 accepted samples, zero unavailable samples, no invalid reasons, requested cadence min/max 10 seconds. CPU was 0.779664 seconds / 0.4145735354% of one core; lifetime peak RSS 132,694,016 bytes. [Sanitized numeric report](history-refresh-unobserved-short.json).

CUA app selection unexpectedly blocked for approximately 1660 seconds then timed out. No native window, History selection or continuous visibility was observed. The launcher reached its 900-second deadline, revalidated exact ownership/identity/hash, and sent one audit-token-bound SIGTERM successfully; child exited -15 and retained parent exited 0. This was cleanup, not native GUI Quit.

Requested presentation mode is not proof of visibility. These numbers cannot be compared with the earlier [observed Counters month-History workload](month-history-render.md) as renderer improvement or CPU savings. Clock/process coverage and actual presentation differ. Lifetime RSS includes synthetic import/startup; CPU excludes import. No default-five-second/thirty-minute, matched-baseline, reference-hardware or native pending-spinner acceptance is established.

Prior Counters native month/navigation/offline observations retain their original executable scope. Next checks are native pending-state/selection visibility and a ready, uninterrupted default-five-second sustained run; menu/p95, accessibility, full lifecycle and external release gates remain open. No additional fix follows from this unobserved numeric diagnostic.
