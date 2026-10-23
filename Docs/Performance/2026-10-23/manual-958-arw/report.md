# Manual 958-ARW Instruments baseline — 2026-10-23

## Assessment

The recordings identify repeated catalog sorting in sharpness controls, repeated zoom-navigation projection work, and background grid downscaling as optimization candidates. They also show meaningful SwiftUI tracing overhead. These are diagnostic recordings, not controlled latency benchmarks. No performance improvement has yet been measured and no implementation changes were made for this report.

This baseline is separate from the 1,198-file measurements in the parent directory.

## Environment and provenance

- User-reported machine: MacBook Pro M3, 18 GB unified memory.
- User-reported catalog: 958 ARW files. Catalog path, camera model, storage medium, window size, preview settings, source mode and cache state were not recorded.
- `opencatalog.trace`: opening the catalog and scanning files.
- `browsing.trace`: opening the same catalog, browsing and zooming.
- Both use the SwiftUI template; Instruments 27.1 (27A9275).
- Release profiling was requested in the preceding conversation. The recorded build configuration, binary revision and build UUID were not independently verified.
- Reviewed source checkout: `0eb96fc57f0bf877900eb4461cb1befff97bbad2`, clean before this documentation was added. This is source-review provenance, not proof of recorded binary identity.
- Raw traces remain at `/Users/thomas/Downloads/opencatalog.trace` and `/Users/thomas/Downloads/browsing.trace`. Keep these originals for deeper reanalysis. Large binary traces and the approximately 440 MB browsing XML export were not copied into Git.

## Recorded measurements

| Measurement | Open / scan | Browsing / zoom |
| --- | ---: | ---: |
| Trace duration | 86.07 s | 120.45 s |
| Symbolicated CPU samples | 877,383 | 569,597 |
| Total sampled weight, all recorded threads | 87,738 ms | 56,960 ms |
| Recorded hangs | 1 | 3 |
| Total recorded hang duration | 325.31 ms | 1,108.19 ms |
| Worst recorded hang | 325.31 ms | 579.14 ms |
| Animation hitches | 53 | 462 |
| Total recorded hitch duration | 1,791.53 ms | 9,845.13 ms |
| Worst hitch | 500 ms | 716.67 ms |
| Exported SwiftUI update rows / cause edges | 0 / 0 | 0 / 0 |

Trace duration is not catalog load time. Hitch counts depend on interactions, frame cadence and instrumentation. Do not infer a speed ratio from this table or treat summed hitch duration as a percentage of time the UI was frozen.

## Findings and proposed order

### 1. Sharpness control presentation sorts the full catalog

`RawCullViewModel.sharpnessScoringTargetFiles` sorts `activeCatalogFiles` by localized filename before deciding which selection/rating branch applies. `SharpnessControlsView` reads it for button availability; its tooltip reads `sharpnessScoringTargetDescription`, which calls it again.

Browsing inclusive sampled main-thread weights:

- `sharpnessScoringTargetFiles`: 1,455.1 ms.
- Its selection closure: 855.5 ms, overlapping the getter.
- `sharpnessScoringTargetDescription`: 723.3 ms, overlapping the getter.

Source: `RawCull/Model/ViewModels/RawCullViewModel+Sharpness.swift:24` and `RawCull/Views/GridView/SharpnessControlsView.swift:30` at the reviewed revision.

Prepare count/availability separately from ordered scoring input. Only construct the ordered target array when scoring needs it. Preserve visible selection order, hidden-selection filename order, star-rating fallback and semantic-search scope. These weights include observation/tracing costs and are not pure sorting timings.

### 2. Zoom navigation repeatedly derives its ordering and selected index

`ZoomNavigationPresentation.orderedZoomFiles` rebuilds a whole-catalog dictionary for contextual navigation, or filters and potentially sorts files for ordinary navigation. `currentZoomIndex`, previous/next availability, and actions can request the ordering repeatedly.

Browsing inclusive sampled main-thread weights: `orderedZoomFiles` 580.2 ms; `currentZoomIndex` 579.3 ms. These overlap. Keyboard navigation call paths include further selection observation/tracing work; do not attribute their whole weight to sorting.

Source: `RawCull/Model/ZoomNavigationPresentation.swift:7`.

Use a reusable ordered-file projection with an ID-to-index lookup, invalidated by its actual inputs. Selection-only movement should not rebuild catalog ordering. Preserve contextual ordering, rating behavior and analysis ordering.

### 3. Grid preparation remains active while browsing

Browsing background inclusive weights: preload closure 10,203.2 ms; `processSingleFile` 9,943.2 ms; `storeInGridCache` 9,397.5 ms; `downscale` 9,301.4 ms. These heavily overlap. ImageIO property-reading and RAW-reader initialization also appear prominently. These are evidence of background preparation during the recording, not proof that every hitch was caused by it.

Source: `RawCull/Actors/ScanAndCreateThumbnails.swift:308`. The current 200-pixel grid conversion uses `NSImage.lockFocus`, draw, and unlockFocus. Investigate an explicit bitmap/Core Graphics resizing path separately, preserving orientation, color, dimensions, cache identity and cancellation behavior.

The open/scan recording is dominated by JPEG encoding, resampling and pixel conversion. Its largest leaf symbols include JPEG AC encoding (5,793.7 ms) and horizontal resampling (5,678.4 ms). These are sampled weights, not an isolated measure of metadata scanning.

## Instrumentation and hang qualifications

- Browsing hang at 119.874 s: 579.14 ms, during `NSApplication.terminate` and `SwiftUITrace.registerTerminationObserver` / `Client.endTracing` / `Trace.SwiftUI.finalize`. Exclude this from interactive browsing hang comparisons.
- Browsing hangs at about 40.390 s (263 ms) and 95.885 s (266 ms) include rendering/layout and trace event/backtrace/symbol work. They are not isolated proof of an app-specific blocking call.
- Approximately 5,803.9 ms of sampled main-thread weight had a tracing-named frame somewhere in the stack. This is a broad diagnostic heuristic, not an exact removable profiler cost. It overlaps other weights.
- Runtime symbol lookup is visibly associated with SwiftUI tracing/observation. Do not optimize application symbol lookup based on these samples.
- The open/scan 325 ms hang occurs at the very end of that trace. Its full stack was not separately exported, so do not assume it is either scanning or tracing cleanup.
- SwiftUI update tables exported no rows; individual expensive views and cause graphs cannot be reliably ranked from these exports.
- No memory footprint, leak, or allocation conclusions are supported here.

## Saved data and interpretation rules

- `baseline.json`: normalized comparison data, environment, provenance and limitations.
- `open-analysis.json`, `browse-analysis.json`: original five-lane analyzer output.
- `browsing-stack-details.json`: full-stack inclusive aggregates and representative stacks.
- `stack-analysis-provenance.py`: the additional aggregation script; replace its `/tmp` input/output paths to rerun against a fresh time-profile XML export. Its tracing-frame heuristic is diagnostic only.
- `update-plan.md`: implementation sequence and repeatable comparison procedure.

**Analyzer correction:** original JSON correlation `main_running_coverage_pct` assumes approximately 1 ms per sample, while this recording has 0.1 ms sample weights. Its coverage percentages and derived blocked/CPU-bound labels are not reliable and must not be used. Original per-symbol `thread` is the first observed thread for that symbol, not a reliable per-thread aggregation. The dedicated stack aggregates explicitly separate main/background samples. Inclusive weights overlap; never sum parent/child or alternative accessor weights as independent costs.
