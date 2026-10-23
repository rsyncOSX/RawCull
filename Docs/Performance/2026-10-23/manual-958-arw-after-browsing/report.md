# Browsing after updates — 2026-10-23

Trace: `/Users/thomas/Downloads/timeprofileafter.trace`. Time Profiler, 72.47 seconds, Instruments 27.1, macOS 27.0.1, 18 GiB MacBook Pro. Recorded process path points to Release products; exact recorded binary UUID was not verified. Current source hashes match the saved implementation validation record.

## Findings

- **Zero recorded hangs over 250 ms.** Animation-hitch and SwiftUI event/cause lanes are absent, so frame smoothness cannot be compared with the old SwiftUI recording.
- 40,435 samples, each weighted 1 ms; main-thread sampled weight 14,011 ms and background 26,424 ms. These totals are sampled weights, not action latencies or reliable utilization estimates.
- Zoom navigation projection and current-index lookup each account for about **3 ms** of inclusive main-thread sampled weight (overlapping). The old sharpness ordered-target getter does not appear in samples. This supports the targeted work no longer being a sampled hotspot. Absence may also reflect inlining/coarser sampling or workload differences; it does not prove zero cost.
- The original browsing trace had approximately 580 ms in ordered zoom files and 1,455 ms in the sharpness ordered-target getter. It used the SwiftUI template, 0.1 ms samples, lasted 120 seconds, and included substantial tracing overhead. **Do not turn these figures into a percentage speedup.** A matched pre-change Time Profiler run is required for that.
- This new recording also includes opening/scanning and background preparation. Metadata-loader stacks span approximately 10.9–16.4 seconds; preload stacks 17.4–30.84 seconds. These are sampled activity bounds, not exact completion markers.
- Preload accounts for about 10.21 seconds of inclusive background weight, including 9.23 seconds in grid resizing. The old browsing recording had about 9.30 seconds in its grid resize path; unlike the separate open-catalog comparison, these cached/preload workloads show no clear grid-resize CPU reduction. Cached preparation remains a possible future investigation; do not claim the earlier cold/preparation improvement generalizes to every workload.

## Later browsing window

An approximate window from 31 seconds to recording end excludes sampled preload activity. No precise per-action markers are available.

- Main application paths include `ZoomOverlayView.body` (325 ms), selected-file lookup (252 ms), and focus-point lookup (197 ms), inclusive and overlapping. These are cumulative weights, not individual stalls.
- Background work includes RAW-filter initialization (about 2.33 seconds), ImageIO property reading (2.30 seconds), and focus-mask generation (1.88 seconds), also overlapping.
- These suggest remaining work is primarily image/source preparation and overlay analysis. Selected-file/focus-point lookup is a smaller future optimization candidate, not a demonstrated responsiveness defect.
- No process footprint, allocation or leak conclusions are supported by this trace. Kernel/IPC leaf samples are not evidence of a specific app algorithm bottleneck.

## Conclusion and handoff

The targeted sharpness and navigation changes are supported by the new call-path evidence, with no detected hangs in this session. Overall browsing speedup and hitch improvement remain unquantified because recording templates, duration and actions differ.

No further code changes were made. Work was wrapped up when the user reported 6% AI credits remaining. Existing implementation validation remains 114 tests / 133 executions passed and arm64 Release build passed. No further recordings or tests are needed to preserve this state.

Baseline: `../manual-958-arw/report.md`. Catalog comparison: `../manual-958-arw-after-open/report.md`. Saved `analysis.json` contains the standard analyzer output; `cpu-paths.json` adds full-stack aggregates and the later browsing window. Ignore any generic coverage assumptions; this report uses actual sample weights. The provenance script uses temporary export paths and must be adjusted before rerunning.
