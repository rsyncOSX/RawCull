# Deferred investigation: preload image-load latency

## Decision

Keep the current 25_okt implementation. The comparison passed all recorded correctness checks and improved total preload time, CPU use, and memory footprint. Investigate the long background image-load outliers when resuming performance work, or sooner if browsing exhibits visible pauses. This note records a follow-up; it does not propose an immediate decoder change.

## Evidence from 25 October 2026

The compared outputs were `/private/tmp/rawcull-performance-v2-23_okt` and `/private/tmp/rawcull-performance-v2-25_okt`. Preserve their reports, `results.json`, and `run-*/events.jsonl` outside temporary storage before relying on them long term.

Both used the same 809-file ARW catalog and catalog fingerprint, three repetitions, 100 steps, 1616-pixel previews, cache limits, machine, and toolchain. Source commits were `0c4b04666375a2419d5d017357985de2c2e37c60` (23_okt) and `a143a5f0a7a261b700878aaf7751965cb2c22ec3` (25_okt).

| Measurement | 23_okt | 25_okt |
| --- | ---: | ---: |
| `decode.preload` median | 21.678 ms | 13.410 ms |
| `decode.preload` p95 | 34.023 ms | 34.261 ms |
| `decode.preload` maximum | 343.486 ms | 2011.928 ms |
| Empty-cache preload median | 8.617 s | 8.188 s |
| Warm-cache preload median | 3.973 s | 3.634 s |
| Preload with browsing median | 4.169 s | 3.685 s |
| Recovery preload median | 4.310 s | 3.661 s |
| Average process CPU per repetition | 34.019 s | 29.648 s |
| Highest sampled process footprint | 310.7 MiB | 253.4 MiB |

The worst 25_okt source-load sample in each repetition was:

| Repetition | File | Elapsed load |
| --- | --- | ---: |
| 1 | `_DSC5097.ARW` | 2011.928 ms |
| 2 | `_DSC4793.ARW` | 1866.092 ms |
| 3 | `_DSC4947.ARW` | 1290.057 ms |

The different filenames suggest checking scheduling and storage effects, but do not establish a cause. Three repetitions are insufficient to characterize rare-tail behavior reliably. The benchmark measures image readiness, not visible frames or UI smoothness.

## What changed in code, and what did not

- The checked-out RawParserKit `Sources` trees and pinned dependency revisions were identical between these builds. The normal `RawParserKitImageLoader.thumbnailImage` path still retains catalog access, starts a task, awaits `RawParserKit.RawImageLoader.shared.thumbnail`, and checks cancellation.
- `RawImageLoadingConcurrency.thumbnailPreloadLimit` was unchanged: four on this machine. RawParserKit's decoder admission logic was also unchanged.
- 25_okt added optional source-load diagnostics in `RawCull/Model/RawImageLoading.swift`. These comparison runs did not enable `--source-diagnostics`.
- The surrounding pipeline changed grid preparation from AppKit `lockFocus`/drawing to `GridThumbnailResizer`, with the decoded `CGImage` passed to the resizer. This occurs after the same image's decode measurement, but can affect other concurrent loads through contention and scheduling. This is a hypothesis to test, not a proven explanation.
- The legacy grid output was 200 points (observed as 400×268 pixels); the optimized output is capped at 200 pixels. Keep this workload difference in mind when interpreting grid speed and memory savings.

Relevant code: `RawCullPerformanceTests/CatalogPerformanceLoader.swift`, `RawCull/Model/RawImageLoading.swift`, `RawCull/Model/RawSourceLoadDiagnostic.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`, and RawParserKit's `RawImageLoader.swift` in the benchmark's package checkout.

## Meaning of the existing timer

`CatalogPerformanceLoader.thumbnailImage` starts the timer before awaiting the production loader, then awaits `journal.finished` and calls `journal.record(..., since: start)`. The end is calculated in the journal actor. Consequently, `decode.preload` includes catalog-access acquisition, task/actor scheduling, parser admission waits, I/O, image decoding/construction, and journal scheduling. It is elapsed image-load latency, not isolated decode execution or CPU time.

The lower median therefore does not prove a faster decoder, and the longer maximum does not prove a decoder regression.

## Suggested investigation

1. **Establish repeatability.** Repeat ordinary 25_okt runs and record counts above 100 ms, 500 ms, and 1000 ms, plus p95, p99, maximum, filenames, repetition, and phase-relative timestamps. Compare per-repetition distributions rather than only pooled medians. Check whether slow files repeat or move between runs.
2. **Separate adapter stages.** Run the existing opt-in diagnostics. For each `source-load` event with operation `thumbnail.preload`, calculate the intervals below and correlate with the normal metric by file and phase. Filter cancellation separately. The diagnostic timestamps are captured before journal delivery, which helps expose journal delay.
3. **If the parser interval dominates, inspect inside it.** Its duration still includes RawParserKit actor/limiter waits, storage reads, embedded-thumbnail extraction or fallback, orientation processing, and image construction. Use Instruments or a later, separate instrumentation change to distinguish these before changing the algorithm or concurrency limits.
4. **Check shared-resource pressure.** Correlate slow samples with grid resizing, JPEG encoding/saving, CPU scheduling, filesystem activity on the external volume, and memory pressure. Do not infer a cause from temporal overlap alone.
5. **Check user impact.** Browse the real app while preparation is active and use Time Profiler/System Trace if visible pauses occur. The benchmark's browsing-during-preload phase uses a warm thumbnail disk cache; it does not reproduce browsing during cold source decoding. A dedicated cold-preload interaction test would be a separate future exercise.

| Diagnostic interval | Calculation | Interpretation |
| --- | --- | --- |
| Catalog access | `accessReady - submitted` | Access acquisition, including actor wait |
| Task start | `taskStarted - accessReady` | Delay until the read task begins |
| Parser call | `parserReturned - taskStarted` | Parser waits, I/O, and decode combined |
| Delivery | `delivered - parserReturned` | Delay returning to the adapter |
| Adapter total | `delivered - submitted` | Adapter request-to-delivery time |

Convert these uptime differences from seconds to milliseconds. To align with the event stream, subtract `journalOriginUptime` from an absolute diagnostic uptime. Reporting the diagnostic occurs after `delivered`; the outer `decode.preload` timer can also include that reporting overhead, so diagnostic and ordinary totals are not directly interchangeable.

## How to test later

From `25_okt/RawCull`, set `CATALOG` to the original catalog and run the following manually. Each output directory must be new; choose a fresh suffix for subsequent attempts.

```sh
python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" \
  --output /private/tmp/rawcull-decode-normal-01 \
  --runs 3 --steps 100 --pixels 1616 \
  --notes "Decode follow-up; record volume, AC power, power mode, display setup, and background applications"

python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" \
  --output /private/tmp/rawcull-decode-diagnostics-01 \
  --runs 3 --steps 100 --pixels 1616 --source-diagnostics \
  --notes "Diagnostic run; record the same environment; exclude from normal performance baselines"
```

Inspect `report.md` and `results.json` for ordinary metrics, and `run-*/events.jsonl` for raw `source-load` records. The diagnostic stages are raw events, not a stage breakdown in the Markdown report. Source-load signposts use subsystem `no.blogspot.RawCull`, category `SourceLoadDiagnostics`, and interval `RawSourceLoad` when captured with Instruments.

Keep the workload and environment consistent. Empty benchmark disk caches do not flush OS or parser caches; repetitions share a process. If repeating the version comparison, alternate 23_okt/25_okt run order across separate invocations to reduce ordering bias. Do not use diagnostic runs as normal baselines or treat a single maximum as a regression gate.

## Completion criteria

Document whether the tail is reproducible, which stage dominates, whether it affects interactive readiness, and whether a proposed change improves tails without harming total preload, CPU, memory, cancellation, or correctness. If there is no demonstrated user impact and overall performance remains better, retaining the current implementation is a valid outcome.
