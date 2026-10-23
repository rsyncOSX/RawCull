# Real-catalog performance remeasurement — 2026-10-23

## Result

The Release app loaded and browsed yesterday's catalog, displayed embedded JPEG and developed RAW sources, completed a warm reload, and recovered after aborting an early load. The cache-preserved fresh-process CPU trace exercised preload, predominantly grid downscaling, with no sampled JPEG encoding and no process disk writes. **This run does not establish a performance improvement from bounded disk saves**: it did not exercise a measurable write backlog, and yesterday's action sequence and cache state were not controlled closely enough for a before/after speed comparison.

No source edits were made during measurement. The catalog files and existing caches were preserved.

## Reproduction

- Source checkout: `54058fce`, containing the approved bounded preload-save implementation.
- App: `/tmp/rawcull-preload-release/Products/Release/RawCull.app`, optimized Release, coverage disabled.
- arm64 build UUID: `60782AD2-A618-385A-A5BA-3BD3A30B07A9`.
- Catalog: `/Volumes/MacMini4/Orrfugl_lom_osv_mai_2026/DCIM/100MSDCF`.
- Verified 1,198 ARW files, 68,527,349,760 bytes, matching yesterday.
- Host Mac, Xcode Instruments 27.1 (27A9275). Recordings attached only to the profiling app.
- Existing caches were not purged. This is not a cold-cache benchmark.

## Workloads and resource counters

Process resource counters were sampled roughly once per second using `proc_pid_rusage`. MiB means bytes / 1,048,576. These counters are process I/O accounting, not a measurement of physical device throughput.

| Metric | Yesterday's manual workload | Today's browsing/reload session | Today's fresh-process load |
|---|---:|---:|---:|
| Sampling duration | about 160 s | 285.04 s | 81.28 s |
| Initial physical footprint | 165.9 MiB | 531.2 MiB | 666.9 MiB |
| Peak physical footprint | 1,428.4 MiB | 4,836.9 MiB | 990.2 MiB |
| Final physical footprint | 621.0 MiB | 692.9 MiB | 989.9 MiB |
| Read delta | 5,405.0 MiB | 14,782.4 MiB | 5,131.2 MiB |
| Write delta | 321.7 MiB | 261.3 MiB | 0.0 MiB |

The sessions differ materially. Today's longer session included multiple complete scans, scrolling to approximately `_DSC1138.ARW`, opening a large preview, embedded JPEG selection, 140% zoom, developed RAW selection, reopening, aborting, and recovery. Its 4.72 GiB peak occurred during the full-size source-exercise interval, not the initial-load observation interval. This timing association does not establish allocation ownership or a leak. Its footprint later fell to 692.9 MiB. The fresh-process sample ended near its peak; long-term memory stability was not tested.

The initial-load observation window in the longer session peaked at approximately 707 MiB. The fresh-process window is a separate run with different cache/session state; neither value is an isolated measurement of the save-ownership change.

## Functional observations and timing bounds

- Initial load: all 1,198 files and the first preview were observed; adjacent-image navigation and grid scrolling worked.
- Source exercise: embedded JPEG selection showed 8,640 × 5,760 dimensions; zoom reached 140%; developed RAW selection was verified. Native RAW 9 was unavailable, and the UI described the system decoder fallback. Source-selection verification is not a precise decode-latency measurement.
- Explicit same-process warm reload: still scanning at the 5.586-second observation; all 1,198 files and the preview were observed by 8.358 seconds after the Open action began. These are UI automation observation bounds, including automation overhead, not internal signpost timings.
- Early-load cancellation: Open followed immediately by Command-K returned to the zero-file/no-progress state in a 1.074-second combined action sequence. A subsequent load recovered all 1,198 files and a preview. Cancellation specifically during thumbnail writes was not established.
- Fresh-process load: still scanning at 5.386 seconds; all 1,198 files and a preview were observed by 13.046 seconds. The observation gap is not evidence that the load itself took 13 seconds.
- Comparison multi-selection could not be verified through the automation actions; no comparison-performance conclusion is made. AI/review analysis was not run.

Several same-folder reopen attempts returned a zero-file state; repeating selection recovered. The restored folder picker also sometimes showed Open disabled until selecting `100MSDCF` from its parent directory. These observations need a separate correctness reproduction. They do not establish a regression from the preload-save change, and the picker behavior is not proven to cause the zero-file transitions.

`markers.jsonl` contains wall-clock observations written after actions. Some source-exercise markers were recorded together after several actions; do not treat them as exact individual action boundaries. `fresh-load-markers.jsonl` records the fresh Open action's actual start and later observation bound.

## CPU and responsiveness evidence

The primary SwiftUI recording failed to finalize. The wrapper stopped waiting after 60 seconds and killed xctrace. Its 40 KiB trace could not export: `Document Missing Template Error`. No CPU/hang conclusions are taken from that trace.

Two shorter Time Profiler recordings saved usable CPU and hang tables, but both reported: `Fatal logging system error: The log archive is corrupt or incomplete and cannot be read`. All conclusions from these traces remain qualified. No usable animation-hitch, SwiftUI update, or cause-graph measurements were obtained.

| CPU trace | Duration | Symbolicated samples | Recorded hangs |
|---|---:|---:|---:|
| Same-process fallback | 45.33 s | 3,127 | 0 |
| Fresh-process catalog load | 60.33 s | 12,341 | 0 |

The same-process fallback did not contain sampled preload/encoding paths. `handleSourceChange` skips preload for a URL already in `processedURLs`, so this recording could not assess preload savings.

The fresh-process trace captured these **inclusive sampled CPU weights**:

- Preload paths: 3,072 ms / 12,341 ms, approximately **24.9%**.
- `ScanAndCreateThumbnails.downscale`: 2,803 ms, approximately **22.7%** of total sampled weight, substantially overlapping preload.
- `DiskCacheManager.load` detached closure: 258 ms.
- `DiskCacheManager.jpegData`: no matching sampled frames.

Do not add overlapping frame weights. Sampled CPU weight is not elapsed load time. Yesterday's 44.1% preload and 19.1% encoding shares came from a different, manually driven session and are not comparable speedup measurements. No encoding samples plus zero process disk writes indicate that this fresh-load run did not meaningfully stress preload-originated writes; they do not prove that every source was a cache hit.

## Assessment and next steps

1. The real catalog remains usable with the new implementation, including recovery after early-load cancellation. The bounded-write invariant is supported by the controlled tests from the preceding implementation phase; this cache-preserved session did not stress that invariant at runtime.
2. Reproduce the intermittent zero-file same-catalog reopening behavior separately before assigning its cause or making further performance edits.
3. If optimizing cached preload next, investigate grid downscaling, now the largest identified preload call path in the fresh-load recording. This is a candidate, not an approved implementation or a demonstrated foreground bottleneck.
4. A controlled cache-miss A/B workload with matching action timing is required to quantify any memory, throughput, or responsiveness benefit from write backpressure. No cache purge or additional implementation was performed here.

## Artifacts

Durable summaries, process samples, markers, and recording logs are saved beside this report. `analysis.*` describes the 45-second fallback; `fresh-load-analysis.*` describes the fresh-process capture. `cpu-paths.json` and `fresh-load-cpu-paths.json` contain whole-stack inclusive aggregates, excluding samples without usable frames.

Temporary raw traces and exports:

- `/tmp/rawcull-54058fce-workload.trace` — unusable SwiftUI trace.
- `/tmp/rawcull-54058fce-timeprofiler.trace` — recoverable same-process fallback.
- `/tmp/rawcull-54058fce-fresh-load.trace` — recoverable fresh-process load.
- `/tmp/rawcull-54058fce-stacks.xml` and `/tmp/rawcull-54058fce-fresh-load-stacks.xml`.

All recordings and metric samplers have stopped. The profiling Release app is left open with the 1,198-file catalog loaded. No commit was created for this report.
