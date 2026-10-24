# Performance changes through phases 0–3

As of 24 October 2026. This document consolidates the changes, their mechanisms, and the measured results through phase 3. It covers catalog opening and thumbnail preparation, not AI inference throughput. It describes existing work; no new performance experiment was run while preparing this summary.

## What actually improved

The retained production optimization is **less progress-related main-thread work**. Phase 2 introduced progress publication coalescing, then simplified the progress animation in a separate experiment.

- **Progress coalescing:** two cold app captures showed 27.8% and 33.9% less main-thread sampled weight during thumbnail preload than the original capture. Preload elapsed time was also 7.0% and 11.5% shorter in those captures. This is repeated directional evidence, with only one before-run; it does not isolate all storage and scheduling variation.
- **Animation simplification, on top of coalescing:** main-thread sampled weight fell to 1.261 s, approximately 72.4% below the original 4.575 s. However, preload took 20.218 s, compared with 18.206–19.138 s for coalescing alone. This supports retaining a reduction in sampled main-thread work, **not claiming faster loading from the animation change**.
- **Phases 0 and 1:** made the evidence reproducible and phase comparisons possible. They did not demonstrate an application speed improvement.
- **Phase 3:** found no useful repeatable benefit from reusing JPEG encoder options. Production encoding was left unchanged. There is no phase 3 speedup to report.

The final combined implementation therefore has a substantial observed reduction in main-thread sampled work, but only a 1.7% shorter preload in its single capture versus the original. That small elapsed-time difference is not convincing evidence of a repeatable loading-speed improvement. Smoother frames and fewer hitches remain unverified.

## Workload and how to read the numbers

The common catalog contains 809 ARWs totaling 50,126,917,632 bytes, at `/Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF`. Preview size is 1616 pixels. Benchmark runs use Release, three repetitions and 100 browsing steps, with an independent initially empty thumbnail disk cache for each repetition.

There are two distinct measurement environments:

| Environment | What it measures | Appropriate comparison |
| --- | --- | --- |
| Version 2 catalog benchmark | Pipeline operations, cold/warm preload, prepared browsing, zoom image readiness, resources and correctness | Compatible benchmark runs with matching workload/settings |
| App in Instruments, Immediate Time Profiler plus os_signpost | Real app catalog intervals and sampled stack work within those intervals | Matching signpost windows in comparable app captures |

The original benchmark's cold preload median was 8.206 s and warm preload median was 3.553 s. The original phase 1 cold **app trace** measured 20.577 s of preload. Those numbers are not a before/after pair: instrumentation and execution environments differ. An 8-second benchmark result must not be presented as an improvement over a 20-second app recording.

“Cold” means initially empty thumbnail disk cache. OS and parser caches were not flushed. App cache state and action sequences were user-reported; signposts corroborate prepared count and pixel size. Display, power and unrelated background activity were not independently verified for every run.

“Sampled weight” means the profiler's recorded sample weights summed within a selected interval. The new app captures use standard sampling with recorded 1 ms weights. These are approximate work estimates, without independent thread-running validation in that instrument subset. They are not exact CPU accounting. Inclusive stack weights overlap; their sums cannot be interpreted as elapsed time. Image-ready latency also does not measure the first painted frame.

## Phase 0 — Preserve the baseline and make it reproducible

### Changes made

The original benchmark, trace, independent XML exports and analysis were preserved under `/Volumes/MacMini4/TestRunPerformance/firstrun`. The workflow records source identity, workload manifest, preview size, cache procedure, toolchain and action sequence. It distinguishes a cold thumbnail cache from fully cold storage and preserves the original cache backup.

When the original volume became accessible, the entire recorded workload manifest matched: 809 files, the same total bytes, and fingerprint `be62561f3e8de6cd31775afc3df0c282586f0c6803ed2fe3697f559faef549ce`. That fingerprint uses names, sizes and modification times, not a hash of every RAW file's contents.

The archived 23 XML exports were subsequently checked against their manifest, including the approximately 1.79 GB SwiftUI table. Matching binaries/dSYMs and checksum inventories were retained with later phase archives for build identity and symbolication.

### Performance consequence

Phase 0 did not make decoding, rendering or cache access faster. Its value was establishing a stable basis for deciding whether subsequent changes helped. Without the same input catalog, preview size and cache procedure, differences in timing could easily be mistaken for code improvements.

Status: preservation/reproduction complete, with the condition-reporting limitations above. This phase is enabling work, not a runtime optimization.

## Phase 1 — Make phase timing and profiler evidence trustworthy

### The problems found

The historical trace contained CPU and SwiftUI data but empty catalog signpost exports. The old exporter checked for schema presence without adequately distinguishing empty data, so successful export did not imply usable catalog phase boundaries.

Two historical Time Profiler views also contained the same 49,858 ordered sample identities but weights differing by 10×. Independent main-thread running intervals favored the 1 ms view, but the export discrepancy remained unresolved. Treating both views as independent work, or selecting a weight silently, would produce misleading totals.

### Changes made

`Scripts/ExportCatalogTrace.py` and its tests were extended to:

- Distinguish missing signpost schema, empty data and nonempty exports in the manifest. Nonempty unrelated signposts do not automatically establish catalog phase readiness.
- Retain each profiler view's original attributes and independent XML document.
- Resolve XML references using a disk-backed SQLite index and fingerprint ordered sample identities and weights. Warn about duplicate views with conflicting weights without merging or automatically selecting them.
- Export SwiftUI update groups when available, separately from primary update events and body-update subsets.
- Detect malformed/truncated XML, unresolved references, empty CPU output and interrupted export; preserve overwrite protection.

`Scripts/ValidateCatalogSignposts.py` and its tests added repeatable raw-event validation. The checker pairs Begin/End events by process, scope, identifier and name, validates completion metadata, and detects unfinished, duplicate or malformed intervals. It supports overlapping catalog sessions and partial prepared counts after cancellation without pretending those counts alone prove cancellation.

The recording procedure was corrected as well. The installed `/Applications/RawCull.app` was older and lacked the expected instrumentation strings, so the workflow uses the verified DerivedData Release executable and process identity. Immediate Time Profiler plus os_signpost with the RawCull subsystem enabled produced usable same-run CPU and phase data. The larger Deferred instrument set repeatedly failed logging collection and produced no usable signposts.

No application signpost emission fix was needed: the existing intervals already ended through `defer`. This phase changed measurement tooling and procedure, not the production pipeline.

### Results and performance consequence

Completed cold, warm and catalog-switch captures had balanced raw events and valid completion metadata. The cold trace established the app baseline used for phase 2:

| Original cold app phase | Elapsed time |
| --- | ---: |
| Catalog open | 25.179 s |
| Metadata scan | 4.068 s |
| Thumbnail preload | 20.577 s |

The switch trace also validated pairing while the previous load drained and the replacement began. It did not establish every aspect of cancellation UI correctness or prove absence of stale UI callbacks.

These changes **improved measurement validity, not app speed**. They allowed the phase 2 comparisons to exclude startup, picker presentation, idle recording time and unrelated work. A shorter total recording was no longer mistaken for a faster catalog load.

Validation recorded at close-out: all 18 Python catalog checks passed, full export documents parsed with checked row counts, and raw-event pairing succeeded on completed captures while rejecting a truncated capture. Same-run SwiftUI/hitch correlation remained unavailable.

Implementation/provenance: `8b44df75` and `54d28736`. Archive: `/Volumes/MacMini4/TestRunPerformance/phase1-2026-10-24`.

## Phase 2A — Coalesce observable progress publication

### Previous behavior and source changes

Per-file metadata and thumbnail completion callbacks wrote progress state as work arrived. That state drives the sidebar and progress overlay. Repeated writes created opportunities for repeated SwiftUI invalidation and progress animation work even when the user could not usefully perceive every intermediate count.

The retained implementation adds `RawCull/Model/Handlers/CatalogProgressCoalescer.swift` and integrates it in `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift`, with independent publisher ownership stored in `RawCullViewModel.swift`. `ScanAndCreateThumbnails.swift` exposes exact actor accounting through `progressCounts()`.

The important behavior is:

1. Each metadata scan and thumbnail preload owns its own MainActor coalescer.
2. Intermediate updates replace the latest presentation snapshot and share one cancellable 100 ms tick. New arrivals do not create a timer per file or continually postpone that pending tick.
3. Initial state, totals and terminal values publish immediately. Identical snapshots do not republish. The cadence is approximately ten intermediate publications per second under sustained activity, not a hard limit on all writes because immediate events bypass it.
4. Thumbnail snapshots combine completed count, total and ETA. Completed values are monotonic so queued callbacks cannot move displayed progress backwards.
5. After preload drains, the view model reads the actor's exact completed/total values, flushes them with ETA zero and closes the publisher. It does not rely on delivery order of queued fire-and-forget callbacks.
6. Cancellation invalidates both publishers before resetting catalog state. Publisher identity checks, timer generation tokens and weak captures prevent stale timers/callbacks from reviving an old publisher, including a later reopening of the same URL.
7. Memory-pressure and extraction-needed notifications remain immediate. Image delivery, internal per-file accounting, readiness gates, bounded decode concurrency and awaited disk saves retain their existing semantics.

This coalesces observable presentation writes. Per-file MainActor callbacks still occur; their scheduling overhead was not eliminated. Separate JPG export/cache workflows were not changed.

### Why it can reduce work

Several internal completions can become one visible progress snapshot. Fewer observable writes give SwiftUI fewer opportunities to recompute dependent views and propagate layout/animation work. Duplicate suppression also avoids publishing an unchanged state.

The optimization removes intermediate presentation work rather than doing fewer decodes or making a JPEG encoder faster. Leaving worker accounting and readiness independent is essential: a thumbnail does not wait for the next progress tick to become available, and exact final progress does not wait an extra 100 ms.

This is the mechanism supported by the code and the observed stack/work changes. The captures did not independently count actual application publication frequency or SwiftUI invocations, so the mechanism is not a measured breakdown of every saved sample.

### Measured result

Animations were unchanged for these two after-captures, allowing publication cadence to be evaluated separately.

| App measurement | Original cold | Coalescing capture 1 | Coalescing capture 2 |
| --- | ---: | ---: | ---: |
| Catalog-open elapsed time | 25.179 s | 23.785 s | 22.889 s |
| Metadata elapsed time | 4.068 s | 4.066 s | 4.093 s |
| Preload elapsed time | 20.577 s | 19.138 s | 18.206 s |
| Preload all-thread sampled weight | 34.545 s | 31.853 s | 30.551 s |
| Preload main-thread sampled weight | 4.575 s | 3.303 s | 3.026 s |

Relative to the original, main-thread sampled weight decreased by 1.272 s and 1.549 s (27.8% and 33.9%). Preload elapsed time decreased by 1.439 s and 2.371 s (7.0% and 11.5%). Metadata time was essentially unchanged, so there is no evidence here of a faster metadata parser.

The first comparison also found fewer inclusive main-thread CPU samples containing `ProgressCount.body.getter` (21 → 4) and `SidebarARWCatalogFileView.body.getter` (16 → 4). These small sample counts corroborate less sampled progress-related work; they are **not counts of body executions**, and must not be described as an 81% reduction in view updates.

Both after-captures completed with prepared=809 and pixels=1616. Their consistent direction supports retaining coalescing, alongside correctness tests and positive manual feedback. One before-run and two after-runs do not establish statistical significance or fully separate the code change from storage and scheduling variation.

### Correctness and retention

Six controlled coalescer tests cover bursts, exact final state/ETA, completion before a tick, cancellation, replacement, stale timers and publisher lifetime. An 809-event synthetic burst produced only initial/latest publication within its controlled window; that demonstrates the algorithm, not the publication rate in the captured app.

Eleven focused Swift tests passed across the coalescer, save ownership/cancellation and catalog lifecycle suites. A save callback in an existing test was explicitly labeled `saveToDisk:` to resolve binding ambiguity, and an actor-accounting assertion was added. Optimized Release builds, 18 Python catalog checks and diff checks passed. The user reported normal behavior after the manual-check instructions; this was not an itemized verification of every edge case.

Implementation: `0cccc19c`; capture findings: `649cea17`, `0a635a49`. Archives: `phase2-publication-candidate-2026-10-24` and `phase2-publication-repeat-2026-10-24` under `/Volumes/MacMini4/TestRunPerformance/`.

## Phase 2B — Simplify progress animation

### Changes and rationale

Only `RawCull/Views/Progress/ProgressCount.swift` changed in this experiment:

| Before | Retained behavior |
| --- | --- |
| 600 ms spring on progress-ring completion changes | 100 ms linear transition scoped to the ring |
| Parent-wide default animation for completion changes | Parent-wide completion animation removed |
| Numeric text content transition | Numeric count updates immediately |
| Ring animation without the new Reduce Motion condition | Ring animation disabled when `accessibilityReduceMotion` is true |

The previous spring could continue across multiple 100 ms publication intervals, and the parent animation broadened the scope of animated changes. A shorter ring-only transition reduces the duration and scope of animation work; immediate numeric text avoids interpolating frequently changing counts. Reduce Motion removes that ring animation when requested by the system setting.

This explains why less progress-related UI work is plausible. It does not mean the image-processing critical path becomes faster.

### Measured result and tradeoff

| Preload measurement | Original | Coalescing 1 | Coalescing 2 | Coalescing + simpler animation |
| --- | ---: | ---: | ---: | ---: |
| Elapsed time | 20.577 s | 19.138 s | 18.206 s | 20.218 s |
| All-thread sampled weight | 34.545 s | 31.853 s | 30.551 s | 31.094 s |
| Main-thread sampled weight | 4.575 s | 3.303 s | 3.026 s | 1.261 s |

The final capture used the matching Release binary/dSYM, valid phase pairing and prepared=809 at 1616 pixels. Its metadata duration was 4.069 s and catalog-open duration 24.854 s.

Main-thread sampled weight was 58.3–61.8% below the coalescing-only captures and 72.4% below the original. All-thread sampled weight was within the coalescing-only range and approximately 10.0% below the original.

However, preload elapsed time was **5.6–11.1% longer than coalescing alone**, and only 1.7% shorter than the original. The evidence does not explain whether storage, scheduling, animation or another factor caused this variation. There was only one animation after-capture.

The retained benefit is therefore reduced sampled main-thread work, supported by positive manual visual feedback. No repeatable loading-speed gain, smoother-frame result, reduced hitch count or measured input-latency improvement is established. More main-thread headroom is useful, but the recordings do not directly measure the user's resulting responsiveness.

Release build and changed-view lint checks passed; existing behavioral tests cover the unchanged coalescing/pipeline behavior. Reduce Motion is implemented, but the manual feedback did not separately document every accessibility setting. Full phase 2 SwiftUI/hitch acceptance remains incomplete because the combined Deferred collection fails.

Implementation: `de0dbef8`; final findings: `1a291cd8`. Archive: `/Volumes/MacMini4/TestRunPerformance/phase2-animation-2026-10-24`. See [the phase 2 report](PerformancePhase2.md) for capture identities and analysis procedures.

## Phase 3 — Investigate JPEG encoding without retaining an ineffective change

### Why encoding was investigated

The original trace identified JPEG encoding as a substantial CPU consumer. The phase 3 analysis narrowed that finding to the final phase 2 trace's own preload interval: 10.977 s of 31.094 s sampled weight included `DiskCacheManager.jpegData`, or 35.3%.

Within those encoding stacks, major leaf weights were JPEG codec routines: `aj_block_encode_ac` 6.412 s, `aj_block_dct` 1.433 s, `aj_RGBA8888_YUV420` 1.001 s, Huffman lookup 0.628 s and `aj_mcu_dct` 0.350 s. That points primarily to codec processing, rather than options-dictionary construction. The inclusive 35.3% is not an automatically removable share of elapsed preload time.

### Current production baseline

The unchanged version 2 harness ran three times on the original workload at commit `222d4b7b`, after the retained phase 2 changes. This establishes the current production baseline, not an encoding optimization result.

| Measurement | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Per-file JPEG encode median | 4.942 ms | 4.928 ms | 4.917 ms |
| Cold preload | 8.400 s | 8.465 s | 8.385 s |
| Warm preload | 3.639 s | 3.602 s | 3.532 s |
| Process CPU delta | 30.447 s | 29.422 s | 29.425 s |
| Sampled peak footprint | 306.3 MiB | 211.1 MiB | 221.3 MiB |
| Zoom readiness median | 10.505 ms | 10.502 ms | 3.090 ms |

All 809 ordinary decodes/saves succeeded per repetition. Warm preload and prepared browsing passed no-source-fallback checks; cancellation/drain and recovery passed. Pooled disk-browse median was 0.305 ms. The variation in zoom and memory is part of this baseline, not a gain or regression caused by a new encoder.

### Experiment and rejected alternatives

The added `Scripts/BenchmarkJPEGEncoding.swift` diagnostic reproduces the quality-0.7 ImageIO encoder and compares creating fresh options with reusing an immutable `CFDictionary`. It warms 12 persisted JPEG inputs, uses twelve paired rounds and six passes per round, and alternates variant order. Both variants produced byte-identical output with matching decoded dimensions.

| Quiet diagnostic invocation | Fresh options median | Shared options median | Shared relative to fresh |
| --- | ---: | ---: | ---: |
| Trial 1 | 8.1097 ms | 8.1222 ms | 0.153% slower |
| Trial 3 | 8.7276 ms | 8.7331 ms | 0.063% slower |

Trial 2 overlapped profiler XML analysis and was excluded from the decision. The tiny differences in the quiet trials were smaller than between-invocation drift. **Options reuse did not provide a useful repeatable improvement and was rejected.**

The same diagnostic measured `NSImage` construction plus `cgImage` retrieval at only 0.0036–0.0037 ms on average. Source inspection showed that RawParserKit's `thumbnailCGImage` convenience path still calls `thumbnail()` and then retrieves `cgImage`, retaining the wrapper round trip. Neither result justified a dependency rewrite.

The approximately 8 ms diagnostic timings are from sequential re-encoding of persisted JPEGs, not native RAW-derived production bitmaps. They must not replace the approximately 4.929 ms pooled production encode median or be treated as an encoding regression. Twelve images also do not constitute exhaustive orientation/color/detail QA.

### What was retained and why

Only the diagnostic and findings were retained. Production JPEG encoding, quality, orientation/color handling, cache keys, bounded concurrency, cancellation and awaited saves were unchanged. No cache-format/version change was required. Lower quality, smaller thumbnails and unbounded background saves were not used to create an apparent speedup.

Phase 3's useful outcome is rejecting a low-value optimization and identifying where encoding work actually lies. It did **not improve production speed**. Larger codec or representation changes require their own measured experiment and visual-quality checks.

The optimized diagnostic ran successfully with byte/dimension validation; all 18 Python catalog checks and diff checks passed. These are recorded phase results, not tests rerun for this document. Implementation: `f7e9b6de`; findings: `43acd4af`. Archive: `/Volumes/MacMini4/TestRunPerformance/phase3-encoding-investigation-2026-10-24`. See [the phase 3 report](PerformancePhase3.md) for exact commands.

## Overall interpretation and remaining evidence

| Change | Demonstrated result | Claim supported today |
| --- | --- | --- |
| Baseline preservation and workload protocol | Recoverable evidence and matching workload | Reproducibility; no runtime gain |
| Export diagnostics and signpost pairing | Valid same-run catalog windows and explicit data limitations | Trustworthy phase comparison; no runtime gain |
| Progress publication coalescing | Lower preload main-thread sampled weight in both captures; shorter elapsed preload in both | Retained directional work reduction; encouraging, limited latency evidence |
| Ring-only short animation and immediate numeric text | Much lower main-thread sampled weight in one capture; preload slower than coalescing alone | Retained sampled-work reduction; no demonstrated extra loading-speed gain |
| JPEG options reuse | No useful repeatable improvement | Rejected; no production change |
| JPEG diagnostic and codec profiling | Repeatable comparison procedure and clearer cost distribution | Investigation capability; no runtime gain |

The best-supported answer to “why did performance improve?” is that the app spends less sampled main-thread work presenting progress: it publishes fewer intermediate observable snapshots and animates a smaller part of the UI for less time. The evidence does not show a faster RAW decoder, faster JPEG codec, faster metadata scanner or faster grid resizer from phases 0–3.

A final controlled comparison still needs to resolve loading-time variation and obtain usable phase-scoped SwiftUI/hitch evidence before claiming smoother interaction. The historical 25 hitches, including a worst hitch associated with picker presentation, cannot be attributed wholesale to progress or compared with missing after-tables. Grid/warm-cache preparation, decode outliers and remaining hitches belong to pending phases 4–6; final acceptance/comparison belongs to phase 7.

This document summarizes repository source, commit history and the recorded reports; it does not revalidate the external archives. Large traces, caches and raw exports remain outside Git. For the full status ledger and pending work, see [the performance plan](performancefixes.md); for measurement definitions and reproducible procedures, see [CatalogPerformance.md](CatalogPerformance.md) and [MeasurePerformance.md](MeasurePerformance.md).
