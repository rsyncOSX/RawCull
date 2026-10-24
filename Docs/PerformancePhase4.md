# Phase 4 — Grid preparation and warm-cache investigation

24 October 2026. **Investigation complete for the tested alternative; production
optimization deferred under the plan's evidence gate.** Direct ImageIO
thumbnail creation did not improve the controlled workload. No application code,
cache representation, display scale, readiness, concurrency or eviction policy
was changed. This phase establishes no production speedup.

## Separate the four preparation passes

`Scripts/AnalyzeGridPreparation.py` assigns each `grid.preloadResize` measurement
to the containing completed preload interval in each version-2 results file.
It requires the entire operation interval to fit one phase; missing/duplicate/
failed phase intervals are rejected and ambiguous/crossing operations are
reported as unassigned. It does not rely on the latest phase-start journal event:
concurrent browsing emits its own phase-start event inside preload.

Input is the unchanged phase 3 three-run baseline, original 809 ARWs, 1616-pixel
previews, 100 browsing steps. These are **reanalysed existing measurements**, not
new catalog runs or an after-optimization comparison.

| Pass | Run 1 wall / grid sum | Run 2 wall / grid sum | Run 3 wall / grid sum |
| --- | ---: | ---: | ---: |
| Cold | 8.400 / 1.354 s | 8.465 / 1.345 s | 8.385 / 1.336 s |
| Warm | 3.639 / 3.407 s | 3.602 / 3.375 s | 3.532 / 3.313 s |
| Concurrent browsing | 3.625 / 3.396 s | 3.516 / 3.298 s | 3.504 / 3.286 s |
| Recovery | 3.639 / 3.394 s | 3.525 / 3.298 s | 3.604 / 3.368 s |

Every pass has 809 grid measurements, no failed grid operations, and no unassigned
operations. Thus the 3,236 operations per repetition are four deliberate passes,
not 3,236 cold operations. The harness explicitly clears preview and grid RAM
before each pass. These counts do not establish a cache-hit failure in the app.
Grid median durations are 1.647–1.665 ms cold and 4.417–4.621 ms warm.
Sums may overlap other operations and are not CPU time or an additive wall-time
breakdown.

The apparent warm/cold discrepancy has an important measurement explanation.
`DiskCacheManager.load` calls RawParserKit's orientation-normalized loader, which
creates a CGImage with immediate caching disabled. For orientation 1, the loader
returns that image directly. The subsequent `CGContext.draw` in
`GridThumbnailResizer` can trigger lazy JPEG decoding. Consequently
`grid.preloadResize` includes decode/materialization work, whereas the cold path
already has its RAW-derived bitmap. This follows from source inspection; no
separate production decode-versus-resampling timer was added. Do not label the
3.3–3.4 s sum as pure resampling CPU or claim it is all removable.

## Cache identity and boundedness review

Preload derives the grid key from the resolved preview source fingerprint,
changing purpose to grid and requested pixels to 200. `ThumbnailLoader` resolves
the same grid identity before acquiring a decode slot and again after waiting
for preload. Identity includes standardized path, source size, modification date,
orientation policy, purpose and requested pixel size. Changed source metadata
invalidates reuse; absent metadata bypasses it. Requested preview sizes remain
separate identities. Source content changes preserving size and modification
metadata are outside this existing fingerprint contract.

The grid uses the tracked cache, configured byte budget and 3,000-entry count
cap. Warning pressure reduces the byte budget, critical pressure clears grid and
preview caches, and normal pressure restores settings. No lifetime extension,
unbounded retention or persisted grid variant was introduced. This is a source
review, not newly measured hit rates or a manual pressure/scrolling test.
The existing display-independent 200-pixel contract and aspect fitting remain
unchanged; this phase does not claim to validate a new Retina sizing policy.

## Controlled direct-downsample experiment

`Scripts/BenchmarkGridPreparation.swift` compiles alongside the actual production
resizer. It compares lazy JPEG loading followed by that resizer with
`CGImageSourceCreateThumbnailAtIndex` at 200 pixels, applying source transform and
requesting immediate decoding. Both variants inspect source properties, require
normalized orientation, and open the same URLs with source caching disabled.
This is a synchronous image-path diagnostic; it excludes disk-cache actor hops,
cache-key hashing and the production file-existence check.

Twelve evenly spaced sorted cached JPEGs from baseline run 1 are compared before
timing. Twelve paired rounds then run six passes per variant, alternating order,
with an autorelease pool per image. Three sequential invocations ran without a
concurrent catalog benchmark or trace. OS caches were not flushed and power,
display and unrelated system activity were not independently verified.

| Invocation | Current median per image | Direct downsample | Relative change |
| --- | ---: | ---: | ---: |
| 1 | 1.8753 ms | 1.9306 ms | 2.95% slower |
| 2 | 1.8520 ms | 1.9159 ms | 3.45% slower |
| 3 | 1.8736 ms | 1.9356 ms | 3.31% slower |

Both paths produced matching 200×134 dimensions and identical pixels after
rasterizing into the same RGB comparison context for all 12 images in all three
invocations. This comparison is limited to those normalized JPEGs. It does not
cover portrait/EXIF variants, transparency, wide-gamut rendering or exhaustive
feather-detail quality. Those require explicit validation before adopting a
changed production path. Timings from this small sequential warm-cache diagnostic
must not replace concurrent catalog medians.

Reject direct ImageIO downsampling for this workload: the result supplies no
useful benefit to justify integration or broader representation changes. Persisted
grid variants and lazy preparation remain deferred; neither was benchmarked.
Lazy preparation would change deterministic readiness and could shift cost to
first scrolling. Larger preview retention would consume the bounded memory budget.
Filesystem metadata, key resolution, JPEG decode and resampling still need
independent production timing before choosing a more complex intervention.

## Reproduction and validation

```sh
python3 -B Scripts/AnalyzeGridPreparation.py \
  /Volumes/MacMini4/TestRunPerformance/phase3-encoding-investigation-2026-10-24/catalog-baseline \
  > /tmp/rawcull-phase4-grid-phases.json
xcrun swiftc -O -parse-as-library Scripts/BenchmarkGridPreparation.swift \
  RawCull/Model/Cache/GridThumbnailResizer.swift \
  -module-cache-path /tmp/rawcull-phase4-modules -o /tmp/rawcull-grid-diagnostic
/tmp/rawcull-grid-diagnostic \
  /Volumes/MacMini4/TestRunPerformance/phase3-encoding-investigation-2026-10-24/catalog-baseline/run-1/thumbnail-cache/v3-source-representation-thumbnails \
  > /tmp/rawcull-phase4-grid-trial1.json
python3 -B -m unittest discover -s Scripts -p 'Test*Catalog*.py'
python3 -B -m unittest discover -s Scripts -p 'TestValidateCatalogSignposts.py'
python3 -B -m unittest discover -s Scripts -p 'TestAnalyzeGridPreparation.py'
git diff --check
```

Repeat the diagnostic invocation to separate trial2/trial3 paths. Optimized
compilation and all three executions succeeded. All 26 Python checks passed
(18 exporter/catalog, 4 signpost, 4 new phase-analysis checks); diff checks passed.
The compiler emitted environment sandbox/cache warnings but returned success and
produced the executable used above. No application build or Swift suite was
rerun because production sources and the benchmark contract are unchanged.
The full three-run baseline's correctness, no-source-fallback, cancellation and
recovery checks remain the existing evidence; they were not rerun for this phase.
Scrolling, reverse UI browsing, catalog switching, pressure and visual acceptance
remain outstanding UI checks, alongside phase 2's SwiftUI/hitch acceptance.

No new Instruments recording is required to reject the tested alternative.
A future recording should target an explicit remaining hypothesis and distinguish
materialization from resampling rather than infer them from the current label.

Diagnostic implementation: `61f661a9`.
Evidence archive:
`/Volumes/MacMini4/TestRunPerformance/phase4-grid-investigation-2026-10-24`.
The user explicitly approved this payload and destination after automatic review
initially blocked the copy. Diagnostic sources, executable, three raw trials,
phase summary and reports are copied with matching SHA-256 checksums. The input
manifest fingerprints the existing phase 3 results and 809 cached JPEGs rather
than duplicating that archive. No historical evidence was removed.
Phase 5 has not started.
