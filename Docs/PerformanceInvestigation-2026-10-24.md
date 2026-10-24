# Catalog performance verification — 24 October 2026

The saved version 2 catalog benchmark passed. Its raw results reproduce the published summary exactly. The app recording contains responsiveness problems, but missing signposts and conflicting profiler views prevent a fully aligned benchmark/app timing comparison.

## Evidence and verification

Inputs: `/tmp/rawcull-performance-v2-before`, `/tmp/rawcull-opencatalog-export`, and `/Users/thomas/Downloads/opencatalog.trace`.

- Benchmark: 809 ARWs, 50,126,917,632 source bytes; three repetitions, Release, 1616 pixels, 100 browsing steps per repetition.
- Recomputed every phase distribution and resource summary from the three `run-N/results.json` files using the current reporting implementation: exact equality with `results.json`; no failures.
- Each repetition contains 6,923 metrics and 809 cached JPEG files. Metadata, source thumbnail loads and saves each total 809. Peak metadata concurrency is 8, thumbnail concurrency 4, saves 1. These meet the harness checks.
- Warm preload and prepared browsing checks passed without source fallback. Cancellation drains in about 30 ms and recovery succeeds. The three unsuccessful decode entries per cancellation run are intentional interrupted work, separate from ordinary benchmark failures.
- The copied benchmark JSON in the export is byte-identical to the original.
- All 23 exported XML documents parse to completion; every row count and byte size agrees with the export manifest. This is the helper's default selected-table export: the TOC has 79 tables, so this directory is not an `--all-tables` export. All exports in the supplied directory are complete.
- The original xcodebuild log confirms one Swift Testing integration test passed in 63.879 seconds; that one test exercises all three repetitions. The earlier “Executed 0 tests” lines refer to XCTest and do not mean the Swift test was skipped.
- Twelve Python runner/exporter tests rerun successfully with `python3 -B -m unittest discover -s Scripts -p 'Test*Catalog*.py' -v`.
- Four Swift `CatalogPerformanceReportTests` rerun successfully in Release (CPU conversion, timing boundaries, navigation presentation, and journal/resource bookkeeping). Xcode reports `TEST SUCCEEDED`; log: `/tmp/rawcull-report-validation-cached.log`. The first sandboxed attempts failed on package/cache access; the successful run reused existing Xcode package checkouts with cache access.
- The current source and harness fingerprints exactly match the benchmark, despite a different Git commit (benchmark `5afedbb0`, current `ad2562aa`).

## Benchmark results

| Measurement | Result |
| --- | ---: |
| Cold thumbnail preload median | 8.206 s |
| Warm thumbnail preload median | 3.553 s |
| Metadata scan, first / subsequent runs | 4.067 / 0.537 / 0.536 s |
| Source thumbnail loading median / p95 / worst | 13.563 / 33.155 / 2781.062 ms |
| JPEG encoding median | 5.005 ms |
| Grid creation median | 4.308 ms |
| Save encoded thumbnail median | 0.409 ms |
| Prepared disk browse median / worst | 0.330 / 1.363 ms |
| Browse during warm preload median / worst | 0.185 / 0.249 ms |
| Zoom preview readiness median / worst | 3.316 / 13.002 ms |
| Sampled peak footprint, repetitions 1–3 | 254.1 / 186.4 / 187.1 MiB |
| CPU seconds, repetitions 1–3 | 29.900 / 29.284 / 29.677 s |

Cold preload varies only from 8.192 to 8.276 seconds. Metadata has a strong first-run cache effect; the median alone conceals that. The 2.781-second worst decode is `_DSC5023.ARW` in repetition 1. Other repetitions have different slowest files, so this does not establish a defective file or a repeatable per-file problem.

Each repetition encodes 270,078,051 JPEG bytes and spends roughly 4.21–4.22 seconds in summed encoding operations. The 3,236 grid operations per repetition span four preload phases (cold, warm, concurrent browsing, recovery), rather than four cold resizes per file. Their 11.4–11.6-second sum is not cold preload wall time or CPU time. Per-operation times overlap and source loading includes scheduling/adapter overhead.

## App trace

The recording lasts 52.231635 seconds, 08:39:49–08:40:41 Oslo time, using `MySwiftUI` and a Release app. It contains 25 non-system hitches, totaling 1,650.108 ms of recorded hitch duration; the worst is 416.694 ms. There are zero detected potential hangs at the 250 ms threshold. Hangs and hitches are different measurements.

Thread-state intervals independently establish the main thread ran for 7.628 seconds and was blocked for 44.476 seconds over the entire recording. Much of that blocked time can be normal idle/event-loop waiting; it is not evidence of 44 seconds of stalled catalog work.

| Hitch start, seconds from recording start | Duration | Main running within interval | Interpretation |
| --- | ---: | ---: | --- |
| 0.796 | 300.020 ms | 240.592 ms (80.2%) | Startup-heavy; stacks include `AppDelegate.applicationOpenUntitledFile` |
| 3.246 | 416.694 ms | 30.221 ms (7.3%) | Mostly blocked; sampled stacks include `FileImportExportBridge.present` and `NSSavePanel.beginSheetModalForWindow` |
| 7.063 | 100.007 ms | 76.622 ms (76.6%) | Main-thread CPU/update work |
| 11.714 | 150.010 ms | 126.566 ms (84.4%) | Main-thread CPU/render work; stacks include `CA::Transaction::commit` |

The worst hitch is associated with file-picker presentation, so attributing it to RAW decoding would be unsupported. Other hitches occur later, including at 35.532 and 44.116 seconds. Action timestamps were not supplied, so startup, importing, browsing and zooming cannot all be labeled precisely.

### Profiler weights require care

Both exported Time Profiler tables have 49,858 samples with identical sample time, thread, process, core and state sequences. Table 057 assigns 0.1 ms per sample (4.986 seconds total); table 058 assigns 1 ms (49.858 seconds total). Do not sum them or treat them as independent captures. Table 058's main-thread weight is 7.671 seconds, close to the independent 7.628-second running total; table 057 gives 0.767 seconds. This strongly favors table 058 for approximate CPU weights in this recording, while the export discrepancy remains unresolved.

Shares within either table are identical. Inclusive stack shares identify:

| Stack | Share of sampled weight | Approximate weight using table 058 |
| --- | ---: | ---: |
| `DiskCacheManager.jpegData(from:)` | 27.7% | 13.794 s |
| `OrientationNormalizedImageLoader.loadThumbnail` | 17.7% | 8.807 s |
| `GridThumbnailResizer.resize` | 14.7% | 7.337 s |

Inclusive stack costs overlap and cannot be added as elapsed time. Roughly 3.3% of leaf samples remain raw addresses. JPEG encoding and grid resizing are credible optimization targets, but the app's heavier instrumentation and unresolved phase/cache settings prohibit direct scaling against the 8.2-second benchmark.

### SwiftUI progress and animation work

Primary `swiftui-updates` contains 483,270 events: 466,899 Other Updates, 15,394 View Body Updates, and 977 Representable Updates. These are primary events, not update-group counts. The separately available `swiftui-update-groups` table was not included by the default exporter.

There are 108 Moderate and 45 High severity events. `SidebarARWCatalogFileView` has 862 body updates totaling 45.753 ms; `ProgressCount` has 837 totaling 34.842 ms. The cause graph has 371,471 edges, including 5,790 outgoing edges from `ProgressCount.body`. There are 3,510 shape-layout events attributed to `ProgressCount?`.

`RawCull/Views/Progress/ProgressCount.swift` animates the ring with a spring on every `completed` change and also applies a parent `.animation(.default, value: completed)`. `RawCullViewModel+Thumbnails.swift` publishes each completion. This supports testing throttled/coalesced progress publication and a simpler animation while preserving exact final counts. The body durations themselves are small; this evidence identifies repeated downstream work, not proof that progress caused every hitch. Generic cause names are aggregated across instances and should not alone be labeled a feedback bug.

### Filesystem and wait evidence

The filesystem table confirms activity on the same physical catalog path. RawCull issues 33,477 filesystem events attributed to paths within that catalog and 5,743 mentioning `Thumbnails`. These are syscall event counts, not unique images or cache hits.

`read` intervals sum to 17.536 seconds and `pread` to 4.908 seconds across threads. The slowest individual exported filesystem call is a 33.375 ms read of `_DSC4506.ARW` near 7.934 seconds. Logical byte counters report about 4.015 GB read and 411 MB written across the captured RawCull filesystem activity. These are not physical disk throughput measurements, and overlapping syscall durations are not wall time. The trace does not explain the benchmark's separate 2.781-second decode outlier; reads, scheduling, actor waits and parser behavior cannot be assigned across different runs.

## Limits and next steps

1. All signpost tables are empty: `OSSignpostIntervals`, `os-signpost`, and `os-signpost-arg`. The manifest's empty warning list is misleading because the exporter checks schema existence, not whether signpost rows exist. Fix that diagnostic in a separate implementation change.
2. Before the next recording, verify signposts actually arrive from the profiled Release build. Export alone cannot reconstruct missing catalog phase boundaries.
3. Notes still contain instructional placeholders for display/power mode, action times and visible pauses. Cold cache and 1616 pixels are asserted in the notes, not independently established by recorded signpost metadata. Source-path activity is corroborated, but exact app workload equivalence is incomplete.
4. The original `/Volumes/MacMini4/.../100MSDCF` folder is unavailable now. A fresh catalog run and current source-file fingerprint check were therefore not performed. Existing cached JPEGs were counted, not exhaustively decoded for image correctness.
5. No after-optimization results exist. This verifies a baseline; it does not establish a regression or improvement. The separate `Performance.xctestplan` AI/data-race tests are outside these exported catalog results.
6. Prioritize measuring JPEG encoding and grid preparation, then reduce progress animation/publication churn in an isolated experiment. Compare with the same instrument set and workload, and preserve startup/file-picker hitches as a separate category when phase evidence is available.

Analysis scratch data: `/tmp/rawcull-analysis.json`, `/tmp/rawcull-ui-details.json`, `/tmp/rawcull-hitch-symbols.json`. These paths are temporary. No application or benchmark implementation was changed.
