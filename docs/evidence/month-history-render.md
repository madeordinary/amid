# Short month-History presentation diagnostic

Observed October 4, 2026 UTC on the frozen Counters candidate, executable SHA256 `52d1e49ca7cb1f03903b68f797decd5b1ec60f779a31b2ccd9f30dee0e9b3e6c`; [source manifest](interface-counter-candidate-source.json). No application change, build or suite rerun accompanied this diagnostic.

The requested 180-second normal-presentation run completed: **183.303409417 seconds, 18 accepted samples, 0 unavailable samples, no invalid reasons**, three available warmups and requested cadence min/max **10 seconds**. Maximum gap was 10.740683666 seconds. Whole-process CPU was 6.863888 seconds, **3.7445500997% of one core**; lifetime peak RSS was **318,111,744 bytes (303.375 MiB)**. This short visible workload is separate from the background default-five-second/sustained-thirty-minute acceptance protocol; its numbers do not pass that gate.

A thirty-day/76-entity synthetic seed declared 162,336 records; normal load/maintenance reported 161,652 loaded aggregates. Import/startup allocations are included in lifetime RSS and precede the measured CPU interval. This is loaded synthetic history, not normal-store startup cost or thirty elapsed real days. [Sanitized numeric report](month-history-render.json) retains counters, cadence and fixture provenance.

Root observed History/System/thirty days selected before measurement, at a mid-run capture (21:38:08 CDT October 3), and after report completion (21:42:50 CDT). The later capture showed 2,127 buckets, 663 observed / 198 inaccessible / 862 enumerated processes and displayed cadence 10.7 seconds. These are bracketed observations, not a continuous visibility trace; later process counts are not the report-completion counts.

CUA Command-Q was sent after report inspection; retained app child and parent exited 0 without launcher signal. No private identity, output/seed path, log or screenshot is published.

AX/screenshot observations and light local documentation work occurred during the interval; no build, test fixture or generator ran concurrently. The result combines collection, storage, queries, SwiftUI/AppKit and other process work. It cannot isolate renderer cost or establish a causal before/after change. No background/default-five-second/thirty-minute, reference-hardware, matched-baseline, complete accessibility or performance pass is claimed. Startup/import RSS cannot be relabeled a selected-renderer allocation. Separate interrupt/package-idle counters are not total wakeups.
