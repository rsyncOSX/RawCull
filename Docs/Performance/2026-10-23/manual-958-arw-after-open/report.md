# Catalog opening comparison — 2026-10-23

## Result

The new recording shows substantially less sampled background CPU work in grid resizing and thumbnail preparation. **Grid resizing falls from 26.96 to 7.82 seconds of inclusive sampled weight (71% lower in these recordings); preload falls from 41.62 to 21.43 seconds (49% lower).** Grid resizing is part of preload, so these reductions overlap and must not be added.

This is promising evidence that the resizing change reduced work. It is not a controlled end-to-end load-speed measurement, and the hitch measurements do not show a clear responsiveness improvement. Browsing/zoom validation is still pending a separate new recording.

No application code was changed for this comparison.

## Captures and comparability

- Original: `/Users/thomas/Downloads/opencatalog.trace`, 16:03:26–16:04:52 Europe/Oslo, 86.07 seconds. Its start timestamp matches the saved baseline exactly.
- Updated: `/Users/thomas/Downloads/opencatalog2.trace`, 16:43:59–16:45:01 Europe/Oslo, 61.67 seconds.
- Both target RawCull on the same 18 GiB MacBook Pro, macOS 27.0.1, Instruments 27.1 (27A9275).
- Both use the SwiftUI template, deferred recording, Time Profiler **High** sampling, and a 250 ms hang-reporting threshold. Layout Updates are not included.
- Every exported CPU sample has 100,000 ns (0.1 ms) weight in both captures. All comparisons use summed sample weights rather than assuming 1 ms per sample.
- The original and new process paths point into Xcode's Release build products. Exact recorded binary UUID/revision was not extracted. Updated stacks include `GridThumbnailResizer.resize`, confirming the new resize path was exercised.
- Reviewed checkout: `30a19246`; relevant source hashes still match the saved implementation validation record.
- Catalog size is taken from the conversation: 958 ARWs. File count, exact catalog path, storage, cache state, per-action timestamps and settings were not independently verified from these recordings.

The user started catalog work at different offsets in the recordings: first matching scan samples occur at about 20.70 seconds before and 13.22 seconds after. Therefore the difference in whole-recording duration is not an elapsed load-time improvement.

## CPU comparison

All figures below are **inclusive background-thread sampled CPU weights**, accumulated from full stacks. Parent/child paths overlap.

| Call path | Original | Updated | Observed reduction |
| --- | ---: | ---: | ---: |
| Grid resizing | 26,961.6 ms | 7,821.9 ms | 70.99% |
| Preload | 41,617.9 ms | 21,427.1 ms | 48.51% |
| Metadata loading | 5,957.7 ms | 5,807.0 ms | 2.53% |
| JPEG encoding | 13,067.0 ms | 12,258.7 ms | 6.19% |

Original resizing matches `ScanAndCreateThumbnails.downscale`; updated resizing matches `GridThumbnailResizer.resize`. Their enclosing grid-store paths fall from 27,064.8 to 7,892.5 ms, consistent with the helper-level comparison.

Both runs contain substantial JPEG encoding and similar metadata-reading costs. This makes a simple cache-hit-only explanation for the whole improvement less likely, but does not prove identical file counts or per-file work. The runs were not randomized or repeated, and caches were not controlled.

Whole-recording sample weights are 87,738.3 ms before (18,983.5 main / 68,754.8 background) and 55,170.1 ms after (10,924.5 main / 44,245.6 background). Different trace durations, idle periods and interactions mean these totals must not be presented as a controlled CPU utilization or user-visible speedup measurement.

## Responsiveness

| Measurement | Original | Updated |
| --- | ---: | ---: |
| Recorded hangs >250 ms | 1 | 0 |
| Animation hitches | 53 | 51 |
| Total recorded hitch duration | 1,791.53 ms | 1,833.22 ms |
| Worst hitch | 500 ms | 508.33 ms |

Hitch count and total duration are broadly similar; this comparison does not demonstrate smoother UI. The updated trace's two largest hitches occur around 0.780 and 3.184 seconds, before sampled catalog scanning starts. Another 208 ms hitch occurs around 19.526 seconds, near the transition to preload. These timings are associations, not call-stack root-cause attribution.

The original 325 ms hang was at the very end of its recording and was not independently classified with full hang-window stacks. The original process ended with `exit(0)`; the new process metadata reports `SIGKILL` while the recording summary says the user pressed Stop. Do not interpret zero hangs in the new trace as proof that a graceful-termination issue was fixed, or interpret SIGKILL alone as an application crash.

## SwiftUI data and analysis limits

The original recording exported no SwiftUI update/cause rows. The new recording's SwiftUI event export is substantially heavier. The initial full five-lane analyzer reached approximately 9 GB resident memory while parsing that data and was stopped to avoid further memory pressure. Its incomplete output was not used. CPU stacks were exported and analyzed separately; hangs and hitches were successfully exported with a smaller dedicated parser.

This analysis-process memory is not RawCull memory. It supports using smaller captures and avoiding unnecessary SwiftUI event collection, but does not establish the cause of the user's earlier 60 GB Instruments save-time memory growth.

No SwiftUI view/cause ranking, allocation/footprint measurement or process-memory improvement claim is made here. No sample-count-based main-thread coverage or blocked/CPU-bound classification was used.

## Next recording

For the pending browsing test, use **Time Profiler only**, targeting RawCull, at **default/normal rather than High sampling**. Wait for background preparation to finish, record 20–30 seconds of a repeatable browsing/zoom sequence, then stop and save before closing RawCull. Preserve the original traces and use a new filename.

Compare target-count work, navigation projection reuse and image-loading paths. A Time Profiler-only trace will have different instrumentation from the old SwiftUI browsing baseline; it can validate CPU behavior, but an exact speedup or hitch comparison needs a matched pre-change capture with the same settings.

## Saved artifacts

- `comparison.json`: normalized measurements, capture metadata and limitations.
- `before-cpu-paths.json`, `after-cpu-paths.json`: stack-pattern weights, sampled activity bounds, per-second weights and representative stacks.
- `after-responsiveness.json`: successful hang/hitch analysis.
- `compare-stacks-provenance.py`: aggregation source; replace its `/tmp` input/output paths to rerun against equivalent time-profile XML exports.

Original baseline: `../manual-958-arw/report.md`. Original binary traces stay in Downloads. Large temporary XML exports remain under `/tmp/rawcull-open-before-cpu.xml` and `/tmp/rawcull-open-after-cpu.xml`; those files are not required to read the saved comparison.
