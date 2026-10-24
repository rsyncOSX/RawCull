# RawCull performance improvement plan

Planning date: 24 October 2026. Status: **phases 0–1 complete; phase 2 implementation retained with UI acceptance incomplete; phases 3–5 investigated with optimizations deferred; phases 6–7 pending**.

This plan covers catalog opening, thumbnail preparation, prepared browsing, zoom readiness, and UI responsiveness. AI model throughput and the separate AI/data-race performance tests require their own workloads and are outside this baseline.

## Starting point and evidence

Read [the investigation](PerformanceInvestigation-2026-10-24.md), [the measurement workflow](MeasurePerformance.md), and [benchmark semantics](CatalogPerformance.md) before implementation.

The verified baseline is 809 ARWs (50,126,917,632 bytes) from `/Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF`, Release, 1616-pixel previews, three repetitions, 100 browsing steps. Cold preload median is 8.206 s; warm preload 3.553 s. Metadata takes 4.067 s on the first repetition and approximately 0.536 s subsequently. Prepared disk requests have a 0.330 ms median; zoom readiness has a 3.316 ms median. The benchmark passes correctness checks.

The 52.232-second app recording contains 25 hitches, worst 416.694 ms, and no detected hangs. Its worst hitch overlaps file-picker presentation. JPEG encoding and grid resizing consume substantial sampled CPU. Progress publication and animation create repeated SwiftUI work. These observations justify experiments, not a claim that one component causes all pauses.

Important limits:

- Catalog signpost exports are empty, so app phase boundaries are missing.
- Two profiler tables repeat the same sample identities with weights differing by 10×. Independent main-thread running intervals favor the 1 ms table, but the discrepancy remains unresolved.
- The source catalog was unavailable during verification. Restore access before repeating the catalog benchmark.
- Three repetitions support a baseline, not strong conclusions about rare tails.
- Prepared image readiness is different from first painted pixels and frame smoothness.

## Evidence retention: do this before deleting temporary files

**The investigation Markdown is a summary, not a complete archive. Do not use it as a replacement for the raw artifacts.**

| Artifact | What it preserves | Retention decision |
| --- | --- | --- |
| `/tmp/rawcull-performance-v2-before/` | Per-file metrics, resources, events, settings, report, build log, xcresult, generated caches | Archive the complete directory initially; it cannot be reconstructed from Markdown |
| `~/Downloads/opencatalog.trace` | Original Instruments recording, recorded lanes, stacks and timing relationships | Preserve the complete trace bundle; XML is not a replacement |
| `/tmp/rawcull-opencatalog-export/` | 23 independently exported XML tables, TOC, export manifest and benchmark copies | Preserve initially; potentially remove after verifying fresh exports from the archived trace |
| Matching profiled Release app and dSYM | Symbolication and build identity | Locate and archive alongside the trace before build cleanup |
| `/tmp/rawcull-analysis.json`, `/tmp/rawcull-ui-details.json`, `/tmp/rawcull-hitch-symbols.json` | Derived detailed analysis | Archive if available; the investigation contains selected findings only |
| `/tmp/analyze_rawcull_exports.py`, `/tmp/verify_rawcull_exports.py`, `/tmp/rawcull_ui_details.py`, `/tmp/rawcull_hitch_symbols.py` | Ad hoc analysis and validation procedures | Preserve with derived results for reproducibility; review before reuse |
| `/tmp/rawcull-report-validation-cached.log` | Successful four-test Swift validation log | Archive with verification notes |

Choose a durable user-controlled archive location outside `/tmp` and outside the Git repository. Do not commit multi-gigabyte recordings, XML or JPEG caches. Copy artifacts first; record original paths, capture times, source/harness fingerprints, toolchain and machine details in an archive manifest. Generate checksums for archived files and compare source/destination file inventories, counts and bytes. A `.trace` is a directory bundle: copy its entire contents.

Open the archived trace in Instruments, verify its duration and populated lanes, and export at least the profiler, SwiftUI, hitches and thread-state tables to a fresh location. Confirm expected row counts and usable references before considering the existing XML disposable. Retain the original benchmark JSON/events/configuration even if generated thumbnail caches are later removed; document any pruning. Keep matching binaries/dSYMs available for re-symbolication.

Only clean original temporary copies after archive verification. Deleting the only trace or raw benchmark data is irreversible evidence loss. This plan does not authorize or perform deletion.

## Execution and commit rules

Implement phases in order. Phase 1 establishes measurement trust before performance conclusions. Phases 3–6 are evidence-gated: if investigation shows no useful change, record the result and defer that optimization rather than forcing a rewrite.

For every phase:

1. Read applicable repository instructions and relevant SwiftUI/concurrency/testing skills before editing their code.
2. Inspect the worktree and preserve unrelated changes. Keep each phase focused and independently reviewable.
3. Record the hypothesis, exact change, validation commands, results and remaining limitations in this document or a linked phase report.
4. Complete the phase's exit criteria. Run meaningful correctness tests and the appropriate benchmark/trace checks; avoid timing assertions dependent on machine speed.
5. Review the diff, then **commit that completed phase before starting the next**. Stage only the phase's files and evidence summaries. Do not commit generated data or claim tests passed if unavailable.
6. Record the commit hash and artifact archive location below. If blocked, document the blocker and resume later; do not mark unverified work complete.

The commit titles below are proposed future messages. Creating this plan does not execute any implementation phase or create its commits.

## Phase 0 — Preserve evidence and make the workload repeatable

**Purpose:** retain a usable baseline and eliminate missing workload details.

Tasks:

- Execute the archive verification checklist above while source artifacts still exist.
- Restore the original volume and confirm the nonrecursive ARW manifest matches the recorded names, sizes, modification times and fingerprint. If it differs, retain the old baseline and create a separate new one.
- Record actual preview setting, app cache location/state, display configuration and refresh rate, power mode, storage connection, macOS/Xcode versions and background load.
- Define a repeatable action sequence: launch and settle; open the catalog; wait for metadata and thumbnail completion; browse the same sequence; open/close zoom; finish. Record action times relative to trace start.
- Preserve a written cold/warm cache procedure. Move only the actual thumbnail cache aside with the app closed; keep its backup. Do not delete catalog/culling state.
- Keep benchmark-before-app ordering consistent. State explicitly that OS/parser caches are not flushed.

Validation and exit criteria:

- Archive checksums/inventories match and the archived trace opens and exports correctly.
- Original workload is accessible, or a clearly labeled replacement workload and baseline are established.
- Reproduction notes have actual values rather than instructional placeholders.

Commit: `docs: preserve catalog performance baseline and reproduction protocol`.

## Phase 1 — Repair measurement visibility and exporter diagnostics

**Purpose:** distinguish startup, picker, metadata, thumbnail preparation, browsing and zoom work before optimizing.

Primary locations: `Scripts/ExportCatalogTrace.py`, `Scripts/TestExportCatalogTrace.py`, `RawCull/Actors/ScanFiles.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`, `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift`, and `Docs/MeasurePerformance.md`.

Tasks:

- Verify the profiled Release binary contains the existing `CatalogOpen`, `CatalogMetadataScan`, `CatalogThumbnailPreload` and completion instrumentation. Check Instruments signpost configuration with a short smoke recording before a full capture.
- Determine why signpost tables are empty. Prefer correcting recording configuration; change emission only if evidence shows an application issue. Check balanced intervals on success, cancellation and catalog switching.
- Warn when signpost schemas exist but exported rows are empty. Distinguish missing schema, empty data, successful export and phase-alignment readiness in the manifest.
- Preserve attributes for every profiler table. Detect duplicate sample identities and conflicting weights; avoid merging them. Validate the selected view against sampling configuration and independent thread running intervals. If unresolved, publish relative shares and thread-state evidence, with absolute profiler CPU estimates explicitly qualified.
- Add primary SwiftUI update-group export if needed for correlations; label group counts separately from primary updates and body updates.
- Use actual recorded weights and resolved XML references. Keep parsing memory bounded on the existing multi-gigabyte dataset.
- If instrumentation or harness semantics change, establish a new compatible baseline; retain the old version 2 artifacts as historical evidence.

Validation and exit criteria:

- Python exporter tests cover present-but-empty signposts, absent schemas, multiple profiler views, malformed/truncated XML, empty CPU exports and non-overwrite behavior where relevant to the implementation.
- A fresh short Release recording contains identifiable catalog intervals and completion metadata including pixels and prepared count.
- Full run exports have independently valid documents, checked row counts and explicit remaining warnings.
- Phase timing can be derived from signposts rather than inferred from total recording length.

Commit: `fix: validate catalog trace phase data and profiler selection`.

## Phase 2 — Reduce progress publication and animation work

**Purpose:** reduce repeated main-thread/UI work during catalog preparation without delaying image availability.

Primary locations: `RawCull/Views/Progress/ProgressCount.swift`, `RawCull/Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift`, `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift`, and progress callbacks in `ScanFiles.swift` / `ScanAndCreateThumbnails.swift`.

Tasks:

- Measure progress publication frequency and fan-out within the thumbnail signpost window. Separate metadata progress from thumbnail progress.
- Experiment with coalescing UI progress to a bounded cadence (initial candidate: 100 ms). Preserve internal per-file accounting, thumbnail readiness signals and cancellation responsiveness.
- Publish initial, terminal and error states promptly. Ensure final completed/total values are exact even when work finishes between ticks.
- Cancel pending publication when catalogs change or a load is cancelled. Prevent stale callbacks from updating the next catalog and avoid retaining the view model through a timer/task.
- Remove overlapping animation scopes experimentally; compare a simpler ring transition and nonanimated frequent numeric updates. Respect Reduce Motion.
- Keep changing progress dependencies near the overlay. Extract or narrow observed state only if the cause graph shows unnecessary wider invalidation.

Validation and exit criteria:

- Meaningful tests cover exact terminal state, fast completion, cancellation, rapid catalog replacement, and no stale publication. Prefer controlled scheduling over sleeps.
- Manually verify progress, ETA, cancellation and accessibility with small and full catalogs.
- Compare phase-scoped body/update counts, downstream events, main-thread running time and hitch durations under the same recording setup.
- Retain the change only if it reduces measured work or improves responsiveness without worsening correctness/readiness. A body-count reduction alone is not proof of smoother frames.

Commit: `perf: coalesce catalog progress and simplify progress animation`.

### Phase 2 results — 24 October 2026

Retained independent 100 ms progress coalescers for metadata and thumbnail
preparation, with immediate initial/terminal values, exact final counts and ETA,
and cancellation/generation guards against stale publication. A separate animation
experiment retained a ring-only 100 ms linear transition, immediate numeric text
and Reduce Motion support. Internal accounting, readiness, decode concurrency and
awaited saves retain their existing semantics.

Comparable Immediate CPU/signpost captures on the original 809-file catalog at
1616 pixels show:

| Thumbnail-preload measurement | Original | Coalescing 1 | Coalescing 2 | Coalescing + animation |
| --- | ---: | ---: | ---: | ---: |
| Wall time | 20.577 s | 19.138 s | 18.206 s | 20.218 s |
| All-thread sampled weight | 34.545 s | 31.853 s | 30.551 s | 31.094 s |
| Main-thread sampled weight | 4.575 s | 3.303 s | 3.026 s | 1.261 s |

All captures completed with prepared=809 and pixels=1616. The final candidate's
main-thread sampled weight is approximately 72% below the original, but preload
is only 1.7% shorter than the original and 5.6–11.1% longer than coalescing-only.
Retain the work reduction and positive manual feedback without claiming faster
loading or attributing the wall-time variation. Sample weights are approximate
and lack independent thread-running validation; CPU stack counts are not SwiftUI
body invocation counts.

Validation recorded in the report: 11 focused Swift tests pass, 18 Python catalog
checks pass, optimized Release builds pass, changed-view SwiftLint has no source
violations, and diff checks pass. User feedback reported normal behavior, but did
not separately enumerate every accessibility/edge-case check. Combined Deferred
collection still fails, so phase-scoped SwiftUI/hitch acceptance is **incomplete**;
no smoother-frame or hitch improvement is claimed. Carry timing uncertainty and
remaining UI validation into phase 7.

Implementation: `0cccc19c`, `649cea17`, `de0dbef8`; final findings: `1a291cd8`.
Evidence archives under `/Volumes/MacMini4/TestRunPerformance/`:
`phase2-publication-candidate-2026-10-24`,
`phase2-publication-repeat-2026-10-24`, and `phase2-animation-2026-10-24`.
See [the phase 2 report](PerformancePhase2.md) for commands, capture identity,
comparison procedures and limitations.

## Phase 3 — Reduce thumbnail JPEG encoding cost

**Purpose:** reduce the measured encoding cost without degrading persisted thumbnail usefulness.

Primary locations: `RawCull/Actors/DiskCacheManager.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`, `RawCull/Model/Cache/ThumbnailCacheKey.swift`, and `RawCullPerformanceTests/`.

Tasks:

- Profile the encoding path in its own phase window. Check image materialization, orientation/color conversion, redundant representations and encoder setup before changing compression quality.
- Compare one intervention at a time: avoid redundant image conversion; reuse safe immutable configuration where appropriate; evaluate encoding options only if still needed.
- Preserve orientation, requested dimensions, color handling and usable detail. Any quality reduction requires explicit visual comparison of fine feather detail, high-contrast edges, noise and rotated images.
- Preserve awaited save completion, bounded concurrency and cancellation behavior. Do not move saves to an unbounded queue to improve apparent wall timing.
- If persisted output semantics change, version/invalidate affected cache keys so existing files cannot silently represent the wrong contract.

Validation and exit criteria:

- Decode representative generated JPEGs and verify orientation, dimensions and visual quality, not just file existence.
- Run the full three-repetition benchmark; compare encoding, cold preload, CPU, output bytes, peak memory, browse and zoom results.
- Confirm warm preload and prepared browsing still need no source fallback. Check failure/cancel/recovery paths.
- Retain only a repeatable improvement with acceptable quality and resource costs; record rejected experiments.

Commit: `perf: reduce catalog thumbnail encoding overhead` (proposed optimization;
actual retained work uses the diagnostic/findings commits below).

### Phase 3 results — 24 October 2026

**Investigation complete; production optimization deferred under the evidence
gate.** The unchanged version 2 harness passed three runs on the original 809 ARWs,
1616 pixels and 100 browsing steps, using independent empty thumbnail caches.
This is a current baseline, not an after-optimization result.

| Measurement | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| JPEG encode median | 4.942 ms | 4.928 ms | 4.917 ms |
| Cold preload | 8.400 s | 8.465 s | 8.385 s |
| Warm preload | 3.639 s | 3.602 s | 3.532 s |
| Process CPU delta | 30.447 s | 29.422 s | 29.425 s |
| Sampled peak footprint | 306.3 MiB | 211.1 MiB | 221.3 MiB |
| Zoom readiness median | 10.505 ms | 10.502 ms | 3.090 ms |

All 809 ordinary decodes/saves succeeded per repetition. Warm preparation and
prepared browsing passed no-source-fallback checks; cancellation/drain and recovery
passed. Pooled disk browse median was 0.305 ms. OS/parser caches were not flushed;
display, power and unrelated background activity were not independently verified.
Zoom and resource variation remain baseline observations.

Within the final phase 2 trace's exact preload interval, inclusive
`DiskCacheManager.jpegData` sampled weight is 10.977 s of 31.094 s (35.3%), mostly
codec processing. Inclusive weights overlap and are approximate, not elapsed time.
The controlled diagnostic compared fresh encoder options with an immutable shared
dictionary on 12 persisted JPEGs. Quiet trials showed shared options 0.153% and
0.063% slower, below between-invocation drift; the overlapping trial was excluded.
Both variants produced byte-identical output with matching decoded dimensions.
Wrapper construction/retrieval averaged only 0.0036–0.0037 ms.

Rejected options reuse for no useful repeatable benefit. Source inspection found
that RawParserKit's CGImage convenience path retains the wrapper round trip, so
no dependency rewrite was justified. Production encoding, quality, orientation/
color handling, cache keys, bounded concurrency, cancellation and awaited saves
remain unchanged. The sequential persisted-JPEG diagnostic is not a native RAW
benchmark or an exhaustive visual-quality corpus. A second nominal after-run
would contain no production intervention.

Retained `Scripts/BenchmarkJPEGEncoding.swift` and the findings. The optimized
diagnostic validates bytes/dimensions; all 18 Python catalog checks and diff checks
pass. SwiftLint reports no source errors, with diagnostic style/complexity warnings.
Diagnostic commit: `f7e9b6de`; findings: `43acd4af`.
Archive: `/Volumes/MacMini4/TestRunPerformance/phase3-encoding-investigation-2026-10-24`.
See [the phase 3 report](PerformancePhase3.md) for exact commands, provenance,
profiling results and rejected paths. Phase 4 has not started.

## Phase 4 — Reduce grid preparation and warm-cache work

**Purpose:** improve cold and warm readiness by removing measured unnecessary image work.

Primary locations: `RawCull/Model/Cache/GridThumbnailResizer.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`, `RawCull/Actors/RequestThumbnail.swift`, `RawCull/Actors/SharedMemoryCache.swift`, and thumbnail cache key/types.

Tasks:

- Separate grid measurements by cold, warm, concurrent browsing and recovery phases. Do not treat all 3,236 operations per repetition as one cold workload.
- Inspect repeated drawing/conversion and size/orientation handling. Verify the grid cache's identity and hit behavior before changing its lifetime or representation.
- Evaluate a cheaper resize/downsample path with equivalent visible quality and correct display scale. Avoid full-resolution decode when a suitable source thumbnail already exists.
- Investigate why warm preparation still costs about 3.6 seconds; measure cache JPEG decode, grid resize, key resolution and filesystem metadata separately.
- Consider lazy visible-item preparation or persisted grid variants only if evidence justifies their complexity. Preserve deterministic readiness semantics or explicitly revise the benchmark contract and establish a new baseline.
- Keep memory budgets and eviction behavior bounded. Do not retain every large preview simply to eliminate work.

Validation and exit criteria:

- Check orientation, aspect ratio, dimensions, cache hits/misses, changed source files and changed requested size.
- Exercise scrolling, reverse browsing, multiple catalogs and memory pressure.
- Compare cold/warm phase time, grid operation counts, CPU, peak memory and source fallbacks. Verify benchmark correctness, cancellation and recovery.
- Avoid introducing a visual first-scroll penalty concealed by faster preload completion.

Commit: `perf: reduce grid thumbnail preparation cost`.

### Phase 4 results — 24 October 2026

**Tested alternative rejected; production optimization deferred.** Reanalysis of
phase 3's three-run baseline assigns 809 grid operations to each of cold, warm,
concurrent browsing and recovery, with no failed or unassigned operations.
The 3,236 operations are four deliberate RAM-cleared passes, not one cold load.
Warm grid-duration sums are 3.313–3.407 s within 3.532–3.639 s preload windows;
these sums include lazy JPEG decoding triggered by drawing and are not pure
resampling CPU or an additive wall-time breakdown.

The optimized diagnostic compares the actual production resizer with direct
ImageIO downsampling on 12 normalized cached JPEGs. Across three sequential
invocations, direct downsampling is 2.95%, 3.45% and 3.31% slower. Dimensions and
RGB comparison pixels match on the sample. Retain diagnostics and phase-analysis
tooling; no production, cache, scale, memory-budget or readiness change is justified
by this experiment. Persisted variants/lazy preparation and independent production
metadata/key/decode/resample timing remain deferred. No app speedup is claimed.

Optimized diagnostic compilation/execution, 26 Python checks and diff checks pass.
Production correctness/no-fallback/cancellation/recovery evidence is the unchanged
phase 3 baseline, not a fresh run. Manual scrolling, pressure, multiple-catalog and
visual acceptance remain outstanding; no new Instruments capture is needed to
reject this alternative. See [the phase 4 report](PerformancePhase4.md).

Diagnostic implementation: `61f661a9`. User-approved evidence archive, with
matching copy checksums and existing input fingerprints:
`/Volumes/MacMini4/TestRunPerformance/phase4-grid-investigation-2026-10-24`.

## Phase 5 — Diagnose and address source-load latency outliers

**Purpose:** explain occasional 1–2.8 second adapter durations before changing concurrency or storage behavior.

Primary locations: `RawCull/Model/RawImageLoading.swift`, `RawCull/Model/RawImageLoadingConcurrency.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`, `RawCullPerformanceTests/CatalogPerformanceLoader.swift`, and the RawParserKit adapter boundary.

Tasks:

- Add opt-in diagnostic timing for submission, limiter/actor wait, parser/decode execution and result delivery. Keep diagnostic overhead distinguishable from the normal benchmark.
- Correlate a slow operation with thread-state, syscall and I/O evidence in the same run and for the same file. Do not match the old benchmark outlier to a different recording's read.
- Repeat enough controlled runs to distinguish occasional scheduling/storage effects from reproducible file behavior. Track named files, phase, cache state and first/subsequent-run effects.
- Check whether interactive requests queue behind preload. Adjust priority or cancellation only if measured contention supports it.
- Change concurrency limits only through controlled experiments measuring CPU, memory, storage behavior, interactive readiness and cancellation together.
- If the cause belongs to RawParserKit, isolate a minimal reproduction and propose a separately scoped dependency fix; do not silently rewrite external package checkouts.

Validation and exit criteria:

- Outliers have evidence-backed classification, or the report clearly states the unresolved cause and instrumentation limits.
- Any retained fix reduces repeatable latency without breaking concurrency bounds, exhausting memory, starving interactive work or slowing cancellation.
- All ordinary decodes succeed; interrupted cancellation decodes remain classified separately.
- If no application fix is justified, commit diagnostic/reporting improvements and defer the optimization explicitly.

Commit: `perf: diagnose and address catalog decode latency outliers` (adjust to `test:` or `docs:` if only diagnostics/findings are retained).

### Phase 5 results — 24 October 2026

**Diagnostic investigation closed; production optimization deferred.** Retained
opt-in source adapter timestamps and UUID/file signposts, separate JSONL source
records, a diagnostic runner flag with normal-mode isolation, and a containing-
interval analysis that keeps cancellation separate. Default application behavior,
concurrency limits, priorities and dependency implementations are unchanged.

Three diagnostic and three normal-control repetitions on the original 809 ARWs,
1616 pixels and 100 browsing steps pass all harness checks. All 2,487 ordinary
diagnostic source records succeed and match outer metrics; nine cancellation
records remain separately classified. Fifteen diagnostic preload calls exceed
one second (maximum 3.192 s); at least 99.995% of each adapter delay is inside the
RawParserKit API round trip. Adapter work outside it is at most 0.068 ms and the
outer timer adds at most 0.074 ms for these outliers. They affect 15 different
files, each loading in 11.496–36.819 ms in the other repetitions. Normal controls
also reproduce outliers. No stable slow file or application-side access/reporting
cause is established for these events.

The parser span combines internal scheduling, actor/limiter waits, I/O and decode;
no same-run thread-state/syscall capture separates them. Cold interactive
contention remains unmeasured: the existing concurrent browse workload is warm.
No concurrency/priority fix or dependency rewrite is justified, and no speedup is
claimed. Diagnostic overhead is explicitly labelled; the sequential controls do
not establish a causal overhead percentage. See [the phase 5 report](PerformancePhase5.md).

All 31 Python checks, five focused Swift report tests, optimized builds and diff
checks pass. Final lint has only verified pre-existing identifier/complexity
findings; it is not a clean repository-wide result. Complete captured source
fingerprints and the matching app/dSYM are retained locally. Diagnostic
implementation: `0b1efff7`. User-approved, checksum/inventory-verified archive:
`/Volumes/MacMini4/TestRunPerformance/phase5-source-load-investigation-2026-10-24`.
No Instruments recording is required from the user for this defer decision.

## Phase 6 — Address remaining startup, picker, browsing and zoom hitches

**Purpose:** improve user-visible pauses left after pipeline changes, without assigning unrelated startup work to catalog decode.

Tasks:

- Record and compare separate windows for launch, file-picker presentation, catalog metadata, thumbnail creation, browsing and zoom.
- Inspect the 300 ms startup pattern and file-picker presentation separately. Use main-thread running versus waiting intervals to distinguish CPU work from blocking/system UI waits.
- For CPU-heavy windows, identify the expensive user-code caller and overlapping SwiftUI/render events. For waiting windows, inspect the actual wait stack before attempting to move work off the main actor.
- Follow trace-named views into source, including `RawCullMainView`, `FileDetailView`, `ZoomOverlayView` and thumbnail presentation only where evidence points there.
- Narrow observations, cache genuinely repeated derived computation, and relocate eligible expensive non-UI work only with correct isolation and cancellation.
- Preserve native picker behavior and accessibility. If a pause is system-controlled and no actionable application cause exists, document it rather than adding speculative workarounds.

Validation and exit criteria:

- Repeat the same scripted actions and compare phase-specific hitch count, total duration, worst duration, main-thread running time and visible behavior.
- Verify selection, keyboard browsing, ratings/filters, zoom orientation/quality, catalog cancellation and switching.
- No new hangs, stale views or delayed first visible images. Do not use zero detected hangs as the smoothness criterion.

Commit: `perf: reduce measured catalog and preview UI hitches` (name the actual retained change more specifically).

## Phase 7 — Final comparison and reproducible handoff

**Purpose:** leave trustworthy results and a clear future regression procedure.

Tasks:

- Run the unchanged normal harness for three repetitions with the established workload/settings and a compatible baseline. Preserve raw after-results and per-repetition values.
- Record cold and fresh-launch warm app sessions with the same instrument configuration, profiler settings, display, action sequence and notes.
- Compare metadata, cold/warm preload, encoding/grid costs, source-load tails, browse/zoom readiness, CPU, memory and output/cache size. Compare UI hitches within aligned phases.
- State whether each result is improved, unchanged, regressed or inconclusive. Report absolute and percentage differences; do not claim significance from three samples.
- Use the existing optional >20% and >5 ms median regression gate as a coarse guard, not the sole acceptance criterion. Investigate meaningful resource, tail or visual regressions even when medians pass.
- Rerun the Python runner/exporter checks and Swift report tests. Run relevant changed-component tests and required repository checks; include the catalog integration run once the volume is accessible.
- Archive final artifacts, binaries/dSYMs and a compact comparison report. Update this plan with phase statuses and commit hashes.

Validation commands (adapt output paths to fresh directories):

```sh
python3 -B -m unittest discover -s Scripts -p 'Test*Catalog*.py' -v

python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" \
  --output "$AFTER_OUTPUT" --runs 3 --steps 100 --pixels 1616 \
  --baseline "$COMPATIBLE_BASELINE" \
  --notes "Actual storage, cache ordering, display and power conditions"

python3 -B Scripts/ExportCatalogTrace.py "$AFTER_TRACE" \
  --benchmark "$AFTER_OUTPUT" --output "$NEW_EXPORT_OUTPUT" \
  --notes "Actual cache state, pixels, action times and observed pauses"

xcodebuild test -project RawCull.xcodeproj -scheme RawCullPerformance \
  -destination 'platform=macOS,arch=arm64' -configuration Release \
  -testPlan CatalogPerformance \
  -only-testing:RawCullPerformanceTests/CatalogPerformanceReportTests \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  ENABLE_TESTABILITY=YES ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS=
```

Set variables explicitly before running. Never reuse an existing output directory or compare incompatible harness versions. Package/compiler cache access may be required by Xcode; a build failure is not a test result.

Commit: `docs: record verified catalog performance improvements and remaining limits`.

## Resume checklist and progress ledger

On resuming: check the worktree and current source fingerprints; locate the evidence archive; confirm the original catalog is mounted; read this plan and the investigation; start at the first incomplete phase. Re-baseline if source/harness/workload changes make old comparisons invalid. Implement one phase, validate it, and commit before proceeding.

| Phase | Status | Commit | Evidence / decision |
| --- | --- | --- | --- |
| 0 — Preserve and reproduce | Complete (user confirmed) | — | Archive: `/Volumes/MacMini4/TestRunPerformance/firstrun` (user confirmed) |
| 1 — Measurement visibility | Complete with documented UI limitation | `8b44df75` + close-out commit | Cold/warm/switch CPU + signposts validated and archived; SwiftUI correlation remains a phase 2 measurement prerequisite |
| 2 — Progress publication/animation | Implementation retained; full UI acceptance incomplete | `0cccc19c`, `649cea17`, `de0dbef8`; findings `1a291cd8` | Final capture: main sampled weight 1.26 s vs original 4.58 s; preload 20.22 s vs 20.58 s (slower than coalescing-only 18.21–19.14 s). Missing SwiftUI/hitch validation and timing uncertainty remain explicit. See [phase 2 report](PerformancePhase2.md) |
| 3 — JPEG encoding | Investigated; optimization deferred | `f7e9b6de`, `43acd4af` | Three-run baseline passes; options reuse has no useful benefit; no production encoder change. See [phase 3 report](PerformancePhase3.md) |
| 4 — Grid/warm preparation | Pending | — | Experiment required |
| 5 — Decode outliers | Pending | — | Same-run diagnostics required |
| 6 — Remaining UI hitches | Pending | — | Phase-aligned recording required |
| 7 — Final comparison | Pending | — | Depends on preceding retained changes |

### Phase 1 work log — 24 October 2026

Hypothesis: schema-only diagnostics hid the missing phase data, and independently
exported profiler views need explicit identity/weight diagnostics before analysis.
Added missing/empty/nonempty signpost states, conservative phase readiness,
resolved profiler identity/weight fingerprints with a temporary SQLite index,
duplicate/conflicting-view warnings, and primary SwiftUI update-group export.
All original table attributes and independent XML documents remain preserved.
No application emission or benchmark semantics changed; version 2 remains intact.

Validation: `python3 -B -W error::ResourceWarning -m unittest discover -s Scripts -p 'Test*Catalog*.py' -v`
passed all 14 tests. `git diff --check` passed. Tests cover absent/empty/nonempty
signposts, duplicate profiler identities with conflicting weights, unresolved
references, truncated XML, empty CPU exports, and overwrite protection.

The existing Release executable at
`~/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/Build/Products/Release/RawCull.app/Contents/MacOS/RawCull`
contains all four expected signpost names and public `prepared`/`pixels` formats
(checked with `strings`). Source inspection confirms all three intervals use
`defer` to end on return, including cancellation/early-return paths. This is static
evidence only; cancellation/switch pairing still requires recording validation.
`xcrun xctrace list templates` succeeded with cache access and lists SwiftUI,
Logging, MySwiftUI and MySwitfUI. Instrument filters and collection are unverified.

Remaining: locate the user-preserved phase 0 archive, inspect its recording
configuration and source/build identity, perform a fresh short Release catalog
recording, derive actual phase boundaries, and validate full exports against the
archived multi-gigabyte dataset. `/Volumes/MacMini4` is currently unmounted;
previous `/tmp` artifacts and `~/Downloads/opencatalog.trace` are absent in this
session. No historical artifacts were modified. Phase 1 is deliberately incomplete
and uncommitted until its recording/export exit criteria are met. Do not begin phase 2.

#### Archive located and validated

User supplied archive: `/Volumes/MacMini4/TestRunPerformance/firstrun`.
The `tmp/` subtree contains the benchmark, all 23 XML exports and analysis;
`Downloads/opencatalog.trace` contains the historical trace bundle. Read-only
validation on 24 October confirmed all 23 XML row counts and file sizes match
its manifest, including the 1.79 GB SwiftUI table. Resolved profiler fingerprints
identify tables 057/058 as duplicate ordered samples with conflicting weights;
the signpost diagnostic correctly reports `empty_data`. Detailed validation:
`/tmp/rawcull-phase1-archive-validation.json` (new, temporary derived artifact).
The mounted original catalog matches the entire archived manifest exactly:
809 files, 50,126,917,632 bytes, fingerprint
`be62561f3e8de6cd31775afc3df0c282586f0c6803ed2fe3697f559faef549ce`.

The current MySwiftUI template's `--show-recording-options` reports an empty
`os_signpost.dynamicTracingEnabledSubsystems` list and high-frequency profiler
sampling. A new options file explicitly enables `no.blogspot.RawCull` and uses
standard sampling; it must include every required field, not just overrides.
Also, `/Applications/RawCull.app` is an older installed executable lacking the
catalog signpost strings. Attaching by process name selected that executable.
Always launch the explicit verified Release executable; this finding does not
establish which executable produced the historical trace.

#### Recording blocker and partial outputs

Both new xctrace attempts reported: `Data stream: Fatal logging system error:
The log archive is corrupt or incomplete and cannot be read`. One attached by
name to the old installed app; the second requested a launch via the DerivedData
executable, but process inspection still showed an installed-app launch alongside
the independently opened DerivedData app. The 809-file catalog did open in the
verified Release app via its native picker. This does **not** prove the recording
target collected its signposts. Future smoke checks must attach by verified PID,
not name, and first resolve the Instruments logging-stream failure.
No valid new phase timings or completion metadata were obtained.

Failed captures and options are retained in temporary phase 1 paths; they are
failure diagnostics, not baselines. A fresh historical re-export at
`/tmp/rawcull-phase1-full-export` was interrupted after the recording failures;
its manifest explicitly says `interrupted`, and it is not a validated full export.
The original 23 archived documents were independently validated in full, as above.
The exporter now also records an explicit interrupted status on Ctrl-C (covered
by the existing integration test). All 14 Python tests and diff checks pass.
Phase 1 remains in progress, uncommitted; phase 2 has not started.

The failed finalizer exited with status 2 after termination; its partial output
was moved outside the repository to `/tmp/rawcull-phase1-failed-launch.trace`.
The earlier failed attachment is `/tmp/rawcull-phase1-smoke.trace`; complete
recording options are `/tmp/rawcull-phase1-recording-options.json`. None of these
is a valid replacement baseline. No recording/export process remains active.

#### User-recorded Immediate smoke trace — 13:33 Oslo

Saved trace: `/Users/thomas/Downloads/rawcull-phase1-signpost-smoke.trace`.
Read-only TOC/interval/raw-event exports succeeded, retained at
`/tmp/rawcull-phase1-user-smoke-{toc,intervals,events}.xml`.
TOC confirms Immediate recording, explicit RawCull dynamic subsystem,
DerivedData Release app path, PID 4940, duration 14.508992 s and user Stop.
Catalog signposts are present: metadata begins at 5.187582 s and ends after
4.027597 s. CatalogOpen begins at 5.187501 s but has a sentinel end-process;
thumbnail preload begins at 9.780380 s with pixels=1616 and also has a sentinel
end-process. Both modeled durations reach the recording boundary; these are
incomplete intervals, not measured completed phase times. Raw dynamic-subsystem
events contain no CatalogThumbnailPreloadComplete name. A longer Immediate run
is required to capture full preparation and prepared-count completion metadata.
The screenshot shows a yellow warning whose text remains unverified.
This establishes a working collection configuration, not that Immediate mode
alone caused the improvement. Phase 1 remains incomplete.

#### Complete user smoke trace — 13:40 Oslo

Validated `/Users/thomas/Downloads/rawcull-phase1-signpost-complete.trace` by
independent TOC, interval and raw dynamic-signpost event exports to
`/tmp/rawcull-phase1-complete-{toc,intervals,events}.xml`. TOC identifies the
DerivedData Release app, PID 5306, Immediate mode and enabled RawCull subsystem.
All three intervals have matching raw Begin/End events and IDs:

| Interval | Start (s) | End (s) | Duration (s) |
| --- | ---: | ---: | ---: |
| CatalogOpen | 5.230207 | 16.162209 | 10.932002 |
| CatalogMetadataScan | 5.230300 | 9.317921 | 4.087621 |
| CatalogThumbnailPreload | 9.900918 | 16.162087 | 6.261169 |

Completion event at 16.162040 s shares preload ID 0xf7 and records
`prepared=809 pixels=1616`. Recording ends at 17.393850 s. This passes the normal
success-path signpost smoke check; timings are diagnostic, not a speed comparison
(cache conditions and instrument set differ). The user-shared yellow warning says
backdated intervals are not visualized until Immediate recording stops; it does
not report the previous fatal archive-reading failure. Successful collection is
established for this configuration; no application instrumentation change is needed
on this evidence. Cancellation/switch pairing and the full correlated recording
remain to validate before phase 1 is complete.

#### Combined Deferred trial — 13:58 Oslo

User saved `/Users/thomas/Downloads/rawcull-phase1-deferred-trial.trace` and
reported the fatal logging archive error again. Independently exported TOC,
OSSignpostIntervals (table 35), dynamic RawCull os-signpost (table 8) and
Time Profiler (table 13) to `/tmp/rawcull-phase1-deferred-trial-*.xml`.
Recording is 40.742397 s, Deferred, enabled RawCull subsystem, standard profiler
sampling, hang threshold 250 ms. XML documents parse; intervals and dynamic
signposts both have zero rows, while Time Profiler has 46,514 rows. Thus the
combined trial cannot support phase alignment, despite surviving CPU samples.
Immediate mode is disabled by the combined instrument set (user screenshot).
Do not request another identical combined Deferred run or clear caches for it.
Next isolate an Immediate-compatible subset starting with os_signpost plus
Time Profiler, checking mode availability before recording. Separate sessions
cannot provide same-run CPU/SwiftUI phase correlation.

#### Warm CPU + signposts Immediate trial — 14:05 Oslo

Validated `/Users/thomas/Downloads/rawcull-phase1-cpu-signposts.trace` via
independent TOC/interval/raw-event/CPU exports. Immediate mode; standard sampling;
15.429780 s duration. CPU has 10,203 rows and passes resolved-reference
fingerprinting. Intervals table has 4,537 rows; dynamic signpost events 9,413.
Metadata completes from 6.070478 to 10.116750 s (4.046272 s). CatalogOpen
starts 6.070397 s; preload starts 10.646612 s with pixels=1616. Both have sentinel
end-process and no raw End or completion event before Stop. Thus simultaneous
CPU/signpost collection works but this capture is truncated during preparation.
Warm cache is user-reported, not independently proven. Retain it and repeat
unchanged configuration/cache with a longer recording before any cold run.
Derived evidence: `/tmp/rawcull-phase1-cpu-signposts-validation.json` and
`/tmp/rawcull-phase1-cpu-signposts-{toc,intervals,events,cpu}.xml`.

#### Complete warm CPU/signpost trial — 14:08 Oslo

`~/Downloads/rawcull-phase1-cpu-signposts-complete.trace` validated: Immediate,
60.990540 s, standard profiler sampling. Independent XML exports have 4,690
interval rows, 9,768 dynamic signpost event rows and 11,050 CPU samples; profiler
references resolve. All catalog Begin/End IDs balance: CatalogOpen 0x98 from
4.980372 to 15.545556 s (10.565184 s); metadata 0x99 from 4.980444 to 8.959697 s
(3.979253 s); preload 0xb4 from 9.498076 to 15.545405 s (6.047329 s).
Completion at 15.545340 s records prepared=809 pixels=1616, same ID 0xb4.
Warm cache is user-reported. This confirms same-run CPU/catalog phase collection
with this smaller set. SwiftUI/hitch correlation remains unavailable under the
failed combined Deferred configuration. Derived validation and independent XML:
`/tmp/rawcull-phase1-cpu-signposts-complete-validation.json` and sibling
`*-{toc,intervals,events,cpu}.xml`. Do not treat these timings as a cold comparison.

#### Cold CPU/signpost recording — 14:13 Oslo

User saved `~/Downloads/rawcull-phase1-cold-cpu-signposts.trace` after moving
thumbnail cache aside per the agreed protocol (cache state user-reported).
TOC confirms Immediate mode, 79.159900 s duration and standard CPU sampling.
Independent XML exports to `/tmp/rawcull-phase1-cold-cpu-signposts-*.xml` contain
39,201 modeled intervals and 81,886 dynamic signpost events. All three catalog
intervals balance in raw events: CatalogOpen 0xcc 6.031183–31.210348 s
(25.179165 s); metadata 0xcd 6.031254–10.098829 s (4.067575 s); preload 0x117
10.632797–31.210177 s (20.577380 s). Completion at 31.210084 s shares preload
ID and records prepared=809 pixels=1616. Same-run CPU export and resolved
fingerprinting are retained in the sibling validation JSON. These are app
recording timings under instrumentation, not directly comparable to the original
component benchmark. Cold/warm differences do not establish a code regression
or improvement. Cancellation/switch validation and SwiftUI correlation remain
outstanding; no further phase is started.

#### Phase 1 close-out review

Exporter implementation is already committed by the user as `8b44df75` (Phase 1).
Subsequent trace findings and the pairing checker remain pending final review.
Complete default exporter runs succeeded for both captured cold/warm recordings:
`/tmp/rawcull-phase1-cold-reviewed-export` and
`/tmp/rawcull-phase1-warm-reviewed-export`, each with nine independently parsed
XML documents, checked row counts and explicit missing-instrument warnings.
No automatic profiler CPU selection is claimed without independent running-time
validation. Exact phase timing is available from raw signposts in these same runs.

Added `Scripts/ValidateCatalogSignposts.py` and four tests for process/ID/name
pairing, overlapping sessions, partial cancellation counts, truncated/unmatched/
duplicate events, metadata disagreement, missing references and malformed XML.
All 18 catalog Python tests pass with ResourceWarnings treated as errors.
The checker passes the complete cold/warm raw exports and deliberately rejects
the earlier truncated CPU/signpost capture. These are parser tests, not simulated
proof that actual app cancellation or UI state is correct.

Swift Concurrency skill consulted for source review: Swift 6, complete checking,
approachable concurrency; app default isolation MainActor. Catalog switching calls
cancelCurrentCatalogLoad, cancels catalog/preload tasks and asks the old actor to
cancel preload. The preloader forwards parent cancellation to its worker task,
drains its group, emits completion, then closes via defer. Metadata/catalog-open
also close via defer. No application behavior or instrumentation changed.
Runtime cancellation/switch pairing remains pending the requested user recording.

SwiftUI limitation: combined Deferred collection reproducibly loses signposts;
Immediate-compatible CPU/signpost subset succeeds. Root cause is unresolved;
no claim is made that SwiftUI or progress caused a particular hitch. The original
phase-scoped SwiftUI acceptance criterion for phase 2 remains blocked. Separate
SwiftUI captures may provide qualitative evidence, but cannot establish same-run
phase-aligned UI/hitch improvements. Record this as a deferred measurement blocker;
do not silently weaken the phase 2 acceptance criteria or mark phase 1 complete.

#### Switching validation and final phase 1 decision — 24 October

User reports starting with cold cache and selecting a warm replacement during
thumbnail creation. `~/Downloads/rawcull-phase1-switch.trace`: Immediate,
76.314569 s, standard CPU sampling. Raw events pass the repeatable pairing
checker with six completed catalog intervals and no unfinished interval:

| Load / phase | ID (decimal) | Start (s) | End (s) | Prepared |
| --- | ---: | ---: | ---: | ---: |
| First catalog open | 638 | 20.086154 | 55.403796 | — |
| First metadata | 639 | 20.086236 | 29.794781 | — |
| First preload | 695 | 30.808335 | 55.398297 | 1,107 |
| Replacement catalog open | 2142 | 55.343505 | 65.312695 | — |
| Replacement metadata | 2143 | 55.343595 | 59.321761 | — |
| Replacement preload | 2147 | 59.791054 | 65.312588 | 809 |

Both completion events report pixels=1616 and match their preload IDs. The
replacement begins approximately 55 ms before the first preload ends; the earlier
catalog-open interval drains approximately 60 ms after replacement starts. This
validates pairing across the user-performed switch/cancellation path. It does not
prove how many files were skipped, because source totals/catalog URLs and explicit
cancellation outcomes are not recorded in the existing metadata. No claim of
zero stale UI callbacks or standalone cancellation-button testing is made.

All three successful CPU/signpost captures now have full default-export packages,
nine independently validated documents each, retained with explicit warnings.
All 18 catalog Python tests pass; diff checks pass. Normal success and switching
paths have runtime evidence; source review covers deferred closure on other
returns. No application instrumentation fix or benchmark semantic change was needed.
The historical duplicate profiler weights remain unresolved; report shares and
qualify absolute CPU estimates. New standard-sampling views are retained without
asserting independent thread-running validation, which their instrument set lacks.

Phase 1 measurement/exporter work is complete **with the documented SwiftUI
collection limitation**. Exact catalog phase boundaries and same-run CPU data
are available. Phase 2 may begin with investigation, but its retention gate still
requires evidence of UI/progress work reduction; these CPU-only recordings cannot
establish smoother frames or phase-scoped SwiftUI/hitch improvement. Resolving or
replacing that measurement remains an explicit prerequisite for those claims.
Earlier in-progress entries above are historical and superseded by this decision.

Durable phase 1 archive: `/Volumes/MacMini4/TestRunPerformance/phase1-2026-10-24`.
Contains cold/warm/switch traces, the failing Deferred trial, complete export
packages, pairing summaries/tools, and matching Release app/dSYM. Mach-O and dSYM
UUID A767BC36-0ACE-3925-9375-8664678CC15E matches the RawCull emit locations in
the switch raw-event XML. Archive manifest records original paths, file inventories,
byte sizes and SHA-256 digests; source/destination inventories compared exactly.
First-run archive and original new traces remain untouched. No generated evidence
is committed to Git. Exporter core: `8b44df75`; close-out commit is recorded in Git
history with this report (self-referential hash omitted).
