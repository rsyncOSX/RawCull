# RAW 9 ZoomView preview changes — 31 October 2026

## Selected policy

For a completed-preview memory-cache miss, fit view first reuses an existing developed JPEG from the persistent cache when available, preserving fast opens after an app restart. Otherwise normal fit-to-window RAW previews use `CIRAWFilter.scaleFactor` and direct, eagerly completed sRGB `CGImage` output. The target is the longest viewport edge in backing pixels, rounded up to a 256-pixel bucket. The unscaled native size is captured when the filter is created, because `CIRAWFilter.nativeSize` can change after setting `scaleFactor`. Native image dimensions are retained separately for the dimensions label, initial actual-pixels framing, and focus positioning. Zooming above fit requests native pixels; returning to fit requests the bounded preview again.

Normal native-resolution previews keep the existing developed-JPEG loader and its persistent disk cache. Normal native zoom retains the previous ImageIO loading behavior. This choice follows the real-file measurements: direct full-resolution rendering did not outperform the old path on this workload. Loupe and burst previews retain their existing policy.

Exposure/clipping inspection always renders at native resolution. The renderer reuses the current source filter between exposure changes, preserving the previous shadow boost, highlight recovery, and highlight-compression settings. Entering/leaving inspection recreates the filter so inspection settings cannot leak into normal previews. Adjusted inspection images never enter the persistent JPEG cache.

Completed previews use a 256 MiB byte-bounded LRU cache. Keys include source path, file size, modification date, requested dimension, and optional inspection exposure. Native, fit, and inspection entries are distinct. Older inspection exposures at the same size are replaced. Oversized images are returned but not retained. Closing ZoomView releases the active RAW graph while retaining the bounded completed previews. Memory-pressure warning/critical events and the existing clear-caches action release both completed previews and the source/render context.

Resize requests coalesce while a RAW image is loading. The completed request is followed by the latest requested size. Operation IDs prevent an obsolete completion from changing the active load state; cancellation prevents obsolete pixels or analysis from replacing the selected photo. The current image remains visible during resolution upgrades. Full-resolution development is deferred until native zoom/inspection, so the first zoom-in can still take a full development when the persistent JPEG cache misses. Display publication no longer waits for the analysis thumbnail.

## Reproduction

The optimized standalone benchmark compiles the actual renderer source and the exact RawParserKit revision in `Package.resolved`. It rejects a different or modified parser checkout. It reads original images and writes all artifacts into the output directory.

```sh
python3 Scripts/RunRAW9PreviewBenchmark.py \
  /Users/thomas/Pictures_raw/2026/26_sep_2026 \
  --parser-source /path/to/pinned/RawParserKit \
  --output /tmp/rawcull-raw9-results
```

The default workload is the first six filename-sorted ARW files, three passes per performance mode. Modes run in separate processes. `baseline` uses the original quality-1 JPEG development, ImageIO loading, and atomic disk write. `native` repeats that established pipeline after the changes, matching the selected ZoomView native policy on a disk-cache miss. `fit` renders directly at 3072 pixels. `revisit` warms the fit preview immediately before timing a completed-pixel cache hit. `direct-native` is available as an exploratory alternative, but is not the selected normal-native policy.

`delivery_ms` ends when the pipeline can hand its image to the UI. `materialized_ms` additionally forces a fully rendered bitmap for both paths, including the potentially lazy legacy JPEG. Process peak RSS includes framework/compiler caches and the benchmark's bitmap materialization; it is not the application's total memory use or just the preview-cache size. No OS/storage caches are flushed, and these timings do not establish first-painted-frame latency or UI hitch rates.

The `validate-fit` mode separately checks the actual 3072-pixel fit preview against the previous native JPEG, including preserved native dimensions and a mean absolute RGB error below 3/255. It reuses the same filter through 2048-, 3840-, and 3072-pixel requests, native resolution, and fit again, checking output dimensions and preserved native geometry throughout. The `validate` mode checks native geometry and compares downsampled sRGB pixels against the previous native JPEG path (mean absolute RGB error below 3/255, allowing JPEG loss). On the first photo it additionally compares native exposure inspection at -1, 0, and +1 EV against the previous inspection algorithm (error below 0.1/255), then checks that returning to normal resets the inspection state. It writes a representative direct PNG and legacy JPEG into the output directory for visual review. These checks are bounded comparisons, not a proof of equivalence for every camera, decoder, or image detail.

## Regression coverage

`RAWPreviewRendererTests` adapts RawBrowse's cache, sizing, and resize-test ideas to RawCull:

- Portrait/landscape scaling, no upscaling, backing-pixel sizing, invalid geometry, native launch/zoom, and native exposure inspection.
- LRU ordering and byte limits, exact cached pixels/native dimensions, oversized entries, file revision invalidation, separate fit/native/inspection entries, and obsolete-exposure replacement.
- Resize coalescing, stale-operation completion, cancellation before decoding, and late cancelled pixels after changing selection.
- Display publication while the analysis thumbnail is blocked.
- Malformed input, cache cleanup, reuse of an existing developed JPEG in fit view, and exclusion of that JPEG from adjusted exposure inspection.

The existing viewport-math, session, analysis-image-policy, and image-loading integration suites run alongside these tests. The full suite also runs; unrelated failures are listed with the measurements below rather than changing release metadata or the established default source in this task.

## Results

The first six sorted ARW files in `/Users/thomas/Pictures_raw/2026/26_sep_2026` were tested. All six support RAW 9 and develop to 9984 × 6656 pixels. Each performance mode has 18 samples (six photos × three passes). RawParserKit remained pinned at 1.3.3 (`26df4abc2178d5c07d08f3883d84d0648f5141d3`). Originals and sidecars were not modified.

| Pipeline | Median delivery | Delivery range | Median materialized | Process peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Legacy JPEG, cache miss | 4382 ms | 4239–4813 ms | 4644 ms | 919 MiB |
| Selected native policy, cache miss | 4372 ms | 4251–4604 ms | 4632 ms | 919 MiB |
| Direct fit preview, 3072 pixels | 1418 ms | 1280–1760 ms | 1425 ms | 391 MiB |
| Completed fit-preview cache hit | 0.040 ms | 0.028–0.154 ms | 7.8 ms | 499 MiB |

Uncached fit-preview delivery is approximately **3.1× faster**, with approximately **57% lower process peak RSS** in this standalone workload. Native performance remains effectively unchanged. The cache-hit delivery number measures lookup/image delivery, not a painted frame. Native disk-cache hits and fit view's reuse of an existing developed JPEG are preserved by the loader policy and covered by a regression test; they are not included in the cache-miss table.

A direct-native exploratory run was rejected: its 18-sample median was 4807 ms and peak RSS was 1394 MiB. Disabling intermediate caching or omitting the explicit working format in shorter trials did not produce a native-resolution advantage. The final renderer disables Core Image intermediate caching, retains completed previews under its explicit byte limit, and leaves normal native zoom on the established JPEG path.

Native and fit geometry checks passed on all six photos, including successive sizes on the same filter and a native-to-fit transition. The maximum fit-preview mean absolute RGB error against the native JPEG reference was **0.779/255**, below the 3/255 bound. The maximum downsampled sRGB mean absolute error against the previous quality-1 JPEG was **0.190/255**. Native exposure inspection at -1, 0, and +1 EV matched the prior inspection algorithm exactly at the sampled pixels (**0/255 error**), and returning to normal restored unadjusted output. Representative native/direct-fit PNGs and the legacy JPEG were visually reviewed at 1600 pixels; framing, orientation, and overall appearance agree. This real-file cohort contains landscape images; portrait sizing is covered by unit tests.

The focused selection passed **32 tests**, including **10 new RAW preview tests**. The final full run executed **696 tests**, with **three pre-existing failures**:

- `ReleaseMetadataTests`: README version is 3.3.5 while the project version is 3.3.6.
- `ReleaseMetadataTests`: README lists RawParserKit 1.3.2 while the resolved version is 1.3.3.
- `ZoomOverlayLaunchContextTests`: the test expects `.thumbnail`, while the unchanged default is `.embeddedJPG`.

The README, project/package versions, and those failing expectations were left unchanged. The relevant baseline source content confirms these mismatches predate the RAW preview changes. Some existing image-loading tests also log LMDB/cache warnings while passing.

Raw samples, source hashes, and validation data are retained in [RAW9PreviewPerformanceResults.json](RAW9PreviewPerformanceResults.json). The fit timing run includes the retained unscaled-native-size fix. Native/inspection reference comparisons were captured separately; all measurement-run source hashes are retained. Warm-cache fallback is verified in the app test suite. Build/test logs and full-size review images remain under `/tmp/rawcull-raw9-20261031`.

These results support faster uncached fit viewing on this camera/file cohort. GUI first paint, UI hitches, other cameras, and actual portrait RAW files were not measured.
