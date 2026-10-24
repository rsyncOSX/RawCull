# RawCull performance improvement plan

Planning date: 24 October 2026. Status: **phase 0 complete per user; phase 1 in progress**.

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

Commit: `perf: reduce catalog thumbnail encoding overhead`.

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
| 1 — Measurement visibility | In progress | — | Exporter diagnostics implemented and tested; fresh recording and full export validation pending |
| 2 — Progress publication/animation | Pending | — | Experiment required |
| 3 — JPEG encoding | Pending | — | Experiment required |
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
