# Phase 3 — JPEG encoding investigation

Decision: defer the production optimization. The tested changes show no useful
benefit; production encoding, quality, orientation/color handling, cache keys,
concurrency, cancellation and awaited saves remain unchanged. Retain a repeatable
diagnostic and this report instead of forcing a codec rewrite.

## Current three-run baseline

Executed the unchanged version 2 harness on the original 809 ARWs (50,126,917,632
bytes), 1616 pixels, 100 browsing steps, Release, pinned package cache, three
independent initially empty thumbnail caches. No other encoding benchmark ran
during the catalog measurements. OS/parser caches were not flushed; display,
power and unrelated background activity were not independently verified.

```sh
python3 -B Scripts/RunCatalogPerformance.py \
  /Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF \
  --output /tmp/rawcull-phase3-current-baseline --runs 3 --steps 100 --pixels 1616 \
  --baseline /Volumes/MacMini4/TestRunPerformance/firstrun/tmp/rawcull-performance-v2-before \
  --package-cache /Users/thomas/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/SourcePackages \
  --notes 'Phase 3 pre-change baseline; original 809 ARWs; 1616px; three independent empty thumbnail caches; OS/parser caches not flushed; no app trace running; display/power conditions not independently verified'
```

PASSED, no harness failures. Source/workload/toolchain checks pass against the
run's initial provenance; compatibility with the archived benchmark passes.
Commit at capture: `222d4b7b`. This is a current baseline, not an after-optimization
result. Outputs: `/tmp/rawcull-phase3-current-baseline`.

| Measurement | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| JPEG encode median | 4.942 ms | 4.928 ms | 4.917 ms |
| Cold preload | 8.400 s | 8.465 s | 8.385 s |
| Warm preload | 3.639 s | 3.602 s | 3.532 s |
| Process CPU delta | 30.447 s | 29.422 s | 29.425 s |
| Sampled peak footprint | 306.3 MiB | 211.1 MiB | 221.3 MiB |
| Zoom readiness median | 10.505 ms | 10.502 ms | 3.090 ms |

All 809 ordinary decodes/saves succeed per repetition. Warm preparation and
prepared browsing pass no-source-fallback checks; cancellation/drain and recovery
pass. Pooled disk browse median is 0.305 ms. Generated caches retain the same
quality/representation contract. The complete report contains historical deltas;
not every timing/resource metric matches the first-run archive. In particular,
zoom medians differ between repetitions and the historical summary. These are
pre-change observations, not an encoding-change regression or improvement.

## Profile within the exact preload interval

Reused the valid phase 2 final trace, whose production encoder is unchanged.
Resolved sample timestamps and stacks within its own CatalogThumbnailPreload
interval, 11.857836958–32.075632000 s. Of 31.094 s total recorded sample weight,
10.977 s includes DiskCacheManager.jpegData (35.3%). Inclusive costs overlap and
cannot be added as elapsed time. Absolute profiler weights remain approximate;
this instrument subset lacks independent thread-running validation.

Within the encoding samples, leading leaf weights are aj_block_encode_ac
6.412 s, aj_block_dct 1.433 s, aj_RGBA8888_YUV420 1.001 s, Huffman lookup
0.628 s and aj_mcu_dct 0.350 s. Most sampled work is codec processing, not the
small options dictionary. Procedure/result:
`/tmp/profile_rawcull_phase3.py`, `/tmp/rawcull-phase3-encoding-profile.json`.

## Controlled options-reuse experiment

`Scripts/BenchmarkJPEGEncoding.swift` replicates the existing ImageIO quality-0.7
encoder and compares fresh options with one immutable CFDictionary. It does not
change the app. Twelve sorted, decoded persisted JPEGs are warmed and encoded
in twelve paired rounds, six passes per round, alternating fresh/shared order.
Every input's fresh/shared output is byte-identical and decodes at matching
width/height. No quality reduction or changed image representation is proposed.

```sh
xcrun swiftc -O Scripts/BenchmarkJPEGEncoding.swift \
  -module-cache-path /tmp/rawcull-phase3-swift-module-cache \
  -o /tmp/rawcull-jpeg-experiment
/tmp/rawcull-jpeg-experiment \
  /tmp/rawcull-phase3-current-baseline/run-1/thumbnail-cache/v3-source-representation-thumbnails \
  > /tmp/rawcull-phase3-options-trial1.json
```

The same invocation produced trial2/trial3 in separate files.

| Invocation | Fresh options median | Shared options median | Change |
| --- | ---: | ---: | ---: |
| Quiet trial 1 | 8.1097 ms | 8.1222 ms | +0.153% |
| Trial 2 (excluded) | 8.2053 ms | 8.1973 ms | -0.098% |
| Quiet trial 3 | 8.7276 ms | 8.7331 ms | +0.063% |

Trial 2 overlapped the separate profiler XML analysis and is excluded from the
decision. Trial 3 ran after both workloads exited. The tiny fresh/shared differences
are smaller than between-invocation drift; there is no useful repeatable saving.
NSImage construction plus cgImage retrieval averages 0.0036–0.0037 ms in the
quiet trials, small compared with production encoding's 4.929 ms pooled median.

Limits: the diagnostic is sequential and re-encodes persisted thumbnails, not
native RAW-derived bitmap inputs. Its approximately 8 ms encode values must not
replace production measurements or be interpreted as a regression. The 12 inputs
are not an exhaustive orientation/color or feather-detail corpus. Byte equality
establishes equivalence only between the two tested diagnostic variants. Since
no production/quality change is retained, no new visual-quality contract is
asserted and no cache version bump is needed.

## Rejected paths and remaining work

- Options reuse: rejected for negligible/no measured benefit and unnecessary
  shared-state complexity in concurrent production code.
- Switching to RawParserKit.thumbnailCGImage: source inspection shows that it
  calls thumbnail() and then retrieves cgImage, retaining the wrapper round trip.
  Rewriting dependency internals is not justified by the small measured wrapper
  cost. No package checkout was edited.
- Quality reduction, altered chroma/color handling, thumbnail-size reduction and
  unbounded background saves were not introduced. The codec dominates the tested
  path; larger alternatives need separate evidence and representation/visual QA.

Encoding optimization is explicitly deferred under the plan's evidence gate.
The full three-run benchmark already covers the unchanged final production
state; a second nominal "after" run would contain no production intervention.
All 18 Python catalog checks and diff checks pass. The optimized diagnostic runs
successfully and validates bytes/decode dimensions. SwiftLint has no source errors;
the diagnostic has style/complexity warnings. No new tests mirror the encoder.
The normal benchmark's correctness, bounded saves, cancellation and recovery
checks passed; application encoding code was not modified.

Archive: `/Volumes/MacMini4/TestRunPerformance/phase3-encoding-investigation-2026-10-24`.
Preserve complete current benchmark data/caches/xcresult/logs, diagnostic source
and executable, all trials (including the excluded one), profiling procedure/input
XML and results, matching benchmark app/dSYM, source identity and SHA-256
inventories. Original phase 0/1/2 archives remain unchanged. Phase 4 is not started.

Diagnostic implementation commit: `f7e9b6de`. Findings/ledger follow in a separate
commit so this exact source hash can be recorded. The archive predates this Git
annotation; its verified evidence copies remain unchanged.
