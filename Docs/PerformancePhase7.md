# Phase 7 — Current reference and historical comparison

25 October 2026. **Performance investigation closed with qualified acceptance,
by user decision.** The three-run normal benchmark and two reduced Instruments
captures are retained. Current correctness checks pass. Historical results support
lower sampled main-thread progress work, not a general loading speedup or verified
smoother interaction. No production code changed in this phase. The original full
Phase 7 validation criteria were not all completed; outstanding work is explicitly
deferred below rather than marked passed.

## Final close-out — RawCull 3.3.5

The project declares RawCull **3.3.5, build 426**. Keep Phase 2's production
changes: coalesced observable progress publication, short ring-only animation,
and immediate numeric progress text. Phases 3–6 retained investigation tools,
tests and optional source-load diagnostics, but no further production performance
optimization. No speculative encoder, grid, parser, picker or view rewrite is
justified by the collected evidence.

The user's priority is responsiveness, smooth interaction, background execution
of expensive work and stability. The evidence supports substantially less sampled
main-thread work during preload and correct operation across three catalog
benchmark repetitions. It does not prove that every expensive path avoids the
main thread, that all interactions are hitch-free, or long-duration stability.
Overall catalog loading is broadly similar, with source-load/resource signals
retained as follow-up concerns. Stop optimization work for this pass.

**Release verdict:** no confirmed release-blocking defect was established in this
performance investigation. RawCull 3.3.5 can proceed to the normal release process
from the performance-work perspective. This is not a complete release certification:
shipping archive/signing/notarization, the broader release regression suite and
long-duration stability were not validated here. The incomplete checks below are
not implicitly passed by closing this investigation. No release was published.

## What the before/after evidence supports

The original benchmark is
`/Volumes/MacMini4/TestRunPerformance/firstrun/tmp/rawcull-performance-v2-before`.
The current reference is
`/Volumes/MacMini4/TestRunPerformance/phase7-reference-20261025-062837`.
Both contain passed results from the original 809 ARWs (50,126,917,632 bytes),
three repetitions, 100 steps and 1616 pixels, Release with testability enabled.
Catalog path/manifest, machine/OS, settings, benchmark version and Xcode match.
The current benchmark records clean source commit `53c80dbb`, source fingerprint
`1e76ced2457704383a0157fdb59d956f270b526761ead53228822861e7e3b556`.

The runner correctly rejects the old baseline: harness fingerprints differ
(`bed47f1d…` before, `bff7071a…` current). Reviewing the harness diff from original
commit `5afedbb0` shows Phase 5's optional diagnostic loader, journal event/test
and runner flag/environment isolation additions. The ordinary benchmark test,
test plan and scheme have no diff. Normal mode still uses the shared production
loader; diagnostics are explicitly disabled. The Phase 5 control was captured
with uncommitted changes, explaining its different fingerprint again. This audit
does not waive the compatibility guard or establish zero measurement overhead.

The following is **historical numerical context, not an accepted automated
before/after comparison**. Positive differences mean longer time. Percentages use
the historical value as denominator. Three repetitions do not establish significance;
display/power/background work and OS/parser cache history were not independently
matched. Empty cache refers only to the benchmark thumbnail cache.

| Measurement, pooled median unless stated | Before | Current | Absolute difference | Difference |
| --- | ---: | ---: | ---: | ---: |
| Empty-thumbnail-cache preload | 8.206 s | 8.415 s | +0.209 s | +2.55% |
| Warm-thumbnail-cache preload | 3.553 s | 3.647 s | +0.094 s | +2.65% |
| Metadata scan | 537.351 ms | 649.007 ms | +111.656 ms | +20.78% |
| JPEG encode | 5.005 ms | 4.989 ms | −0.016 ms | −0.31% |
| Grid preload resize | 4.308 ms | 4.335 ms | +0.028 ms | +0.65% |
| Prepared disk browsing readiness | 0.330 ms | 0.314 ms | −0.016 ms | −4.97% |
| Zoom preview readiness | 3.316 ms | 3.376 ms | +0.059 ms | +1.78% |
| Individual preload source-load wrapper | 13.563 ms | 23.296 ms | +9.733 ms | +71.76% |
| Worst individual preload source-load wrapper | 2.781 s | 6.187 s | +3.406 s | +122.47% |

Preload, JPEG, grid and readiness show no demonstrated material gain. Metadata
and source-load increases are regression signals requiring investigation, not a
proven code regression. Metadata repetitions were 4067/537/536 ms before and
4075/649/529 ms current: the aggregate median obscures substantial warm-up/order
effects. Source-load medians were 20.202/13.351/13.619 ms before and
23.395/23.200/23.240 ms current; this increase is not just one maximum outlier.
The wrapper includes asynchronous parser waits, I/O and scheduling, not solely
decode CPU. No same-run stage capture explains the new 6.187-second tail.

If these were compatible results, metadata and preload source-load medians would
cross the optional >20% and >5 ms gate. Do not label the comparison as passing.
Other meaningful tail/resource changes deserve attention regardless of that gate.

Median process CPU delta is 29.677 → 29.995 s (+0.318 s, +1.07%). Median sampled
peak footprint is 187.1 → 211.0 MiB (+23.8 MiB, +12.72%); first-run peaks are
254.1 → 373.6 MiB. Samples are every 100 ms and include the test host. Median
reported disk reads are 4.219 → 130.176 MiB; current repetitions are
3324.301/130.176/4.082 MiB, so warm-cache history is visibly variable. Median
disk writes are 272,519,168 → 272,322,560 bytes (−0.07%). Encoded-save bytes are
identical at 270,078,051 in every repetition, and operation/peak concurrency
counters match. This is output payload size, not a complete cache-directory size
comparison. Resource changes remain inconclusive as causal before/after claims.

## New CPU/signpost app recording

`~/Downloads/rawcull-phase7-cpu-signposts.trace`, run 1, 58.913138 seconds,
07:04:57–07:05:56 Oslo time. Immediate mode, standard sampling, Time Profiler
and os_signpost. User described opening an empty-thumbnail-cache catalog and
browsing; OS/parser caches were not flushed. Completion metadata confirms
809 prepared images at 1616 pixels. Exact action times were not supplied.

The sampled main image is the Xcode Release executable under
`~/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/Build/Products/Release/RawCull.app/Contents/MacOS/RawCull`,
UUID **D64E676D-90C4-3746-B932-088CBCA1D738**. The currently available executable
and dSYM have that UUID and were archived. This is not the separately prepared
workspace build. The trace does not independently establish a source hash for
the user's Xcode build; do not assign the benchmark's source fingerprint to it.
The dyld-library-load export has zero rows; CPU stack binary metadata supplies
the image identity instead.

Two exported signpost tables repeat the same seven application events. The
analysis deduplicates time/type/name/identifier/message before pairing; all three
intervals pair. There are 47,355 CPU rows, all weighted 1 ms, in the selected
time-profile view. No independent thread-running lane was collected.

| Interval | Relative start–end | Elapsed | Main-thread sampled weight |
| --- | --- | ---: | ---: |
| CatalogOpen | 5.795–30.800 s | 25.005 s | 1.604 s |
| CatalogMetadataScan | 5.795–9.994 s | 4.199 s | 0.085 s |
| CatalogThumbnailPreload | 10.545–30.800 s | 20.254 s | 1.325 s |

Compared with the original phase-aligned app preload in [Phase 2](PerformancePhase2.md),
sampled main-thread weight is 4.575 → 1.325 s (−3.250 s, **−71.0%**), while elapsed
preload is 20.577 → 20.254 s (−0.323 s, −1.57%). The prior retained Phase 2 capture
was 1.261 s sampled main work / 20.218 s elapsed, consistent in direction with
the new observation. These are separate observational captures with differing
configuration/provenance and no controlled matched repetition. The historical
profiler-view ambiguity remains documented. This supports directional reduction
in sampled progress-presentation work; it does not prove a 71% speedup, exact CPU
savings, or smoother painted frames. App preload and benchmark preload have
different workloads and must not be compared as equivalent timers.

## Warm-cache hitch recording

`~/Downloads/rawcull-phase7-hitches-warm.trace`, run 1, 35.553899 seconds,
07:20:21–07:20:56 Oslo time, Deferred, Hitches + Display. Warm thumbnail cache is
user-reported. The target is an Xcode-launched RawCull PID 22777. The target
environment names the Xcode Release products directory, but this capture has no
CPU stacks and its exact image UUID/source identity has not been verified.

The exported hitches table has **74 non-system RawCull events**, total recorded
duration **2650.172 ms**, worst **416.694 ms at 3.300 s**. Other large events:
300.020 ms at 0.717 s, 166.678 ms at 21.318 s, and 133.342 ms at 11.084 s.
Generic “potentially expensive” labels do not establish an application cause.
There are no catalog signpost, CPU or SwiftUI lanes to align actions or explain
these events; Hangs was not collected, so no hang-count claim is available.

Original: 25 hitches / 52.232 s; Phase 6: 31 / 50.799 s; current warm capture:
74 / 35.554 s. **Do not compare these counts or normalize them into a regression
rate:** workloads/actions, cache state, capture configurations and phase coverage
differ. The current trace demonstrates hitches, not improved or regressed
smoothness. SwiftUI-inclusive attempts caused growing analysis memory/disk use
and were abandoned. No further heavy capture is requested by this report.

## Validation and evidence retention

The current integration benchmark passed all three repetitions and its recorded
correctness checks. Python runner/exporter suite rerun: **18 tests passed**, using
`python3 -B -W error::ResourceWarning -m unittest discover -s Scripts -p 'Test*Catalog*.py' -v`.
Swift report tests have not been rerun for Phase 7; Python success is not a
substitute. No application changes were made. Documentation whitespace checked
with `git diff --check`.

Durable archive:
`/Volumes/MacMini4/TestRunPerformance/phase7-evidence-2026-10-25`.
585 copied files / 347,208,924 bytes verified source-to-copy with SHA-256.
`checksums.json` records file inventories and hashes. Includes both complete
trace bundles, matching CPU-capture app/dSYM, selected XML/TOCs, analysis script
and JSON, and Python validation log. Original saved traces remain in Downloads.
Benchmark raw results/logs/xcresult remain in their separate external reference
directory; no evidence was deleted. Large working caches are not archive evidence.

Reproduce exports with `xcrun xctrace export --input TRACE --toc --output NEW.xml`;
for selected tables use XPath `/trace-toc/run[@number="1"]/data/table[@schema="SCHEMA"]`.
Selected CPU schemas: `os-signpost`, `time-profile`, `dyld-library-load`; hitch
schema: `hitches`. The archive retains the exact exported XML and
`rawcull-phase7-analyze.py`; pass the archive directory as its argument to reproduce
the derived analysis (benchmark paths must also remain mounted).

## Deferred validation and follow-up

- A strict speed comparison requires the same audited harness on both app
  revisions, or a separately reviewed compatibility policy. Do not edit historical
  fingerprints or disable the runner guard to manufacture comparability.
- Investigate source-load median/tail and resource signals under controlled
  cache/power/workload conditions if pursuing stronger performance claims or
  visible delay reports. Causality is unresolved; these are not proven harmless.
- Run Swift report tests and any required remaining repository checks.
- Full SwiftUI acceptance, first-painted-frame smoothness, timestamped interaction
  coverage, and matched cancellation/catalog-switch validation remain incomplete.
- The investigation/handoff is closed by scope decision, with these items
  deferred. Full original Phase 7 acceptance and blanket improvement claims are
  not justified by the current evidence.
