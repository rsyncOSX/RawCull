# RawCull 2.3.4 Stabilization Plan

## Status

- Planned version: **2.3.4**
- Release line: **macOS 26 maintenance**
- Baseline: released RawCull **2.3.3**, commit `e576ca0`
- Current deployment target: **macOS 26.2**
- Intended audience: existing RawCull users who will remain on macOS 26
- Successor: `RawCullAIModels`, expected to become the main macOS 27 release line

## Release intent

Version 2.3.4 should be the final planned feature-frozen release for macOS 26. Its purpose is to leave macOS 26 users with a stable, internally consistent, and recoverable build before RawCull moves to macOS 27 and the Apple Core AI framework.

This release should contain correctness fixes, crash prevention, cache correctness improvements, focused performance stabilization, test-gate repairs, and documentation corrections. It should not introduce new culling workflows, new AI functionality, visual redesigns, new persistence formats, or broad refactoring.

After 2.3.4, the macOS 26 line should receive another update only for:

- data loss or data corruption;
- a reproducible crash affecting normal use;
- a security issue;
- a serious RAW compatibility regression;
- an App Store or signing problem that prevents installation or launch.

## Evidence from the 2.3.3 review

The review of the released 2.3.3 baseline produced the following results:

- `make test-smoke` succeeds on macOS 26.5.
- The complete test run fails in `ZoomViewportMathTests` because the current implementation and the expected meaning of “Actual Pixels” disagree.
- The dedicated Thread Sanitizer data-race test passes; no data race was reported in the reviewed run.
- The new per-file similarity artifact persistence has substantial test coverage and passed its persistence, cancellation, migration, and partial-failure tests.
- The initial histogram path contains a reachable `fatalError` for an image conversion failure.
- The thumbnail disk-cache identity is based on the source path, not the source file fingerprint.
- A source comment records thumbnail scan/grid request contention that remains unresolved.
- The README lists older package versions than the exact versions shipped by the project.
- The public GitHub issue tracker had no open RawCull issues at the time of review.

## Scope and priority

### P0 — Required before release

1. Resolve the “Actual Pixels” behavior and test mismatch.
2. Remove the histogram crash path.
3. Repair the smoke and full-test release gates.
4. Run and pass the complete macOS 26 regression suite.
5. Update version/build metadata and release documentation.

### P1 — Strongly recommended

1. Make thumbnail cache entries reject replaced or modified source files.
2. Verify that changing thumbnail settings cannot reuse an unsuitable cached representation.
3. Reproduce and address scan/grid request contention with the smallest safe change.

### P2 — Include only if low risk and verified

1. Accessibility corrections for purely single-action tappable rows.
2. Small diagnostics improvements for cache failures and similarity persistence failures.
3. Performance tuning supported by a repeatable measurement.

## Work item 1: define and correct “Actual Pixels”

### Problem

`ZoomViewportMath.actualPixelsScale` currently returns `0.6 / fitScale`. This produces a 60% inspection scale relative to a mathematical 1:1 mapping. One test was updated for that factor, while the remaining transform and fit-upscale tests still expect `1.0 / fitScale`.

This creates two problems:

- the full test suite is red;
- the command and launch context are called “Actual Pixels” even though the implementation applies an additional 0.6 factor.

### Planned product decision

The preferred 2.3.4 behavior is genuine 1:1 inspection:

```swift
return 1.0 / fitScale
```

The user-visible “Actual Pixels” name, keyboard shortcut, focus-point centering, and tests should then remain aligned.

If the 60% scale is intentionally preferred for usability, do not leave the inconsistency in place. Rename the mode to communicate the actual behavior, move `0.6` into a named constant such as `inspectionScaleFraction`, and update every expectation and accessibility label. A mode called “Actual Pixels” must not silently mean 60%.

### Files

- `RawCull/Views/ZoomViews/ZoomOverlayView.swift`
- `RawCullTests/ZoomOverlayKeyActionTests.swift`
- Any menu, tooltip, accessibility label, or About/help text that names “Actual Pixels”

### Required tests

- A fitted 6000×4000 image in a 1500×1000 viewport returns the selected documented scale.
- An 800×600 image in a 1600×1200 viewport returns the selected documented scale.
- A missing focus point keeps the image centered.
- A normalized focus point centers correctly when the scaled image permits the requested offset.
- Offset clamping prevents empty space at all four image edges.
- Zero, negative, non-finite, and degenerate dimensions return a safe fallback.
- Portrait image and non-matching viewport aspect-ratio cases are covered.

### Manual verification

1. Open a landscape image from the thumbnail grid with the actual-pixels shortcut.
2. Repeat with a portrait image.
3. Verify an image with a normalized camera focus point.
4. Verify an image without focus-point metadata.
5. Switch between thumbnail, embedded JPEG, and developed RAW sources.
6. Resize the window and confirm the transform remains bounded and centered appropriately.
7. Confirm keyboard zooming and panning continue from the calculated initial transform without a jump.

### Acceptance criteria

- The feature name, implementation, and test expectations describe the same behavior.
- All `ZoomViewportMathTests` pass without Thread Sanitizer and with Thread Sanitizer.
- No image opens outside the visible viewport or with an invalid scale.

## Work item 2: remove the histogram crash path

### Problem

`HistogramView` safely logs and returns when image conversion fails in `onChange`, but the initial `.task` calls `fatalError` for the same failure. A malformed or unsupported `NSImage` representation should not terminate RawCull.

### Implementation

- Replace `fatalError` with the same guarded logging behavior used by `onChange`.
- Clear `normalizedBins` when the input image becomes `nil` or cannot be converted, preventing an old histogram from remaining visible for a new failed image.
- Ensure an older histogram task cannot publish bins after a newer image has been selected. Prefer `.task(id:)` using a stable image/load identity, or explicitly cancel the previous task.
- Keep histogram calculation away from the main actor.
- Do not add a modal alert for this recoverable rendering failure.

### Files

- `RawCull/Views/Histogram/HistogramView.swift`
- Add a focused histogram test file if the conversion/calculation boundary can be injected cleanly.

### Required tests

- `nil` input produces no bins and no crash.
- A conversion failure produces no bins and no crash.
- A valid image produces normalized bins.
- Replacing a valid image with `nil` removes the previous histogram.
- A slow calculation for image A cannot overwrite the result for newer image B.

### Acceptance criteria

- No `fatalError` remains in the histogram display path.
- Failed conversion is recorded through structured logging.
- Rapid selection changes cannot show the histogram of the previously selected file.

## Work item 3: repair the release test gates

### Problem

The smoke command uses a manually maintained `-only-testing` list. Several tests marked with `.tags(.smoke)`, including the failing zoom math tests, are not included. This allowed the smoke command to pass while known smoke-tagged behavior was failing.

### Implementation

- Make the checked-in smoke plan or command the authoritative definition of the smoke suite.
- Prefer executing every test carrying the Swift Testing smoke tag if the Xcode 26 test-plan tooling supports that configuration reliably.
- If tag selection cannot be made reliable from `xcodebuild`, add every smoke suite explicitly and document that the Makefile list must be updated whenever a smoke tag is added.
- At minimum, add `ZoomViewportMathTests` to the smoke gate.
- Keep the full Thread Sanitizer run as a separate required release gate; do not make every local development build pay its cost.
- Ensure a test suite is not unintentionally executed twice. Investigate the duplicate suite reporting seen in the reviewed runs and confirm that the final test count is stable.

### Files

- `Makefile`
- `Smoke.xctestplan`
- `RawCull.xctestplan`
- Test documentation, if the release commands are documented elsewhere

### Required commands

```bash
make test-smoke
make test-full
make test-performance
```

Also perform a clean release compilation without running notarization:

```bash
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile \
  build
```

### Acceptance criteria

- Breaking any smoke-tagged test makes `make test-smoke` fail.
- `make test-smoke` passes from a clean checkout with exact resolved packages.
- `make test-full` passes with Thread Sanitizer enabled.
- The dedicated high-load data-race test passes.
- The performance plan completes without a crash, hang, or test failure.
- Release configuration builds without compiler errors or new warnings attributable to RawCull.

## Work item 4: invalidate stale thumbnail cache entries

### Problem

`DiskCacheManager` derives the cache filename from the standardized source path and a cache version. If a RAW file is replaced or modified while retaining the same path, RawCull can continue displaying the old JPEG thumbnail.

The in-memory preview and grid caches are also keyed by URL. Cache correctness therefore requires a consistent source identity across the disk and memory layers.

### Implementation approach

Introduce a small sendable thumbnail source fingerprint containing:

- standardized file path;
- source file size;
- source modification date;
- cache schema/version;
- representation purpose where required, such as preview versus grid;
- requested maximum pixel size if differently sized disk artifacts are retained.

Use that fingerprint consistently for cache lookup and storage. Prefer passing already-known `FileItem` metadata rather than performing a filesystem metadata read on every grid lookup. URL-only callers may create a fingerprint from resource values at their boundary, with a documented fallback when resource values cannot be read.

Changing the cache-key schema should naturally invalidate old 2.3.3 thumbnail entries. Old entries are disposable cache data and do not require migration.

Do not change the identities of the full-size embedded/developed preview cache unless the same stale-source behavior is confirmed there and can be addressed with tests.

### Files likely involved

- `RawCull/Actors/DiskCacheManager.swift`
- `RawCull/Actors/RequestThumbnail.swift`
- `RawCull/Actors/ScanAndCreateThumbnails.swift`
- `RawCull/Actors/SharedMemoryCache.swift`
- `RawCull/Model/Cache/CachedThumbnail.swift`
- `RawCullTests/DiskCacheAndScanAdmissionTests.swift`
- `RawCullTests/ThumbnailProviderTests.swift`

### Required tests

- The same unchanged source produces the same cache identity.
- Replacing source contents at the same URL changes the cache identity.
- A modification-date or file-size change is a cache miss.
- A cached 200 px grid representation cannot incorrectly satisfy a request requiring a larger preview representation.
- An older cache-schema entry is ignored safely.
- Cache clearing removes both old and current thumbnail artifacts.
- Cancellation during extraction does not persist an incomplete entry.

### Acceptance criteria

- Replacing a RAW file at the same path cannot display the previous file’s thumbnail.
- Grid and preview requests receive an image suitable for their documented size.
- Cache misses remain recoverable and never block catalog loading.
- Existing ratings, saved-file records, burst decisions, settings, and similarity artifacts are unaffected.

## Work item 5: control scan/grid thumbnail contention

### Problem

`ThumbnailLoader` records a known issue where grid-driven thumbnail requests compete with catalog thumbnail generation while scanning is active. This can duplicate work, increase disk traffic, and reduce perceived scan performance.

### Measurement before modification

Use a representative uncached catalog and record:

- catalog file count;
- scan duration;
- cold extraction count;
- disk-hit count;
- boomerang-miss count;
- peak preview-cache and grid-cache cost;
- whether the grid was opened during scanning;
- cancellation responsiveness.

Compare these scenarios:

1. Scan completes without opening a grid.
2. Open the normal grid immediately after scan begins.
3. Open the rated grid immediately after scan begins.
4. Cancel the catalog load while both scan and UI requests are active.

### Preferred fix order

1. Coalesce identical in-flight requests by source fingerprint and representation.
2. Let a UI request await or reuse an active scan extraction rather than starting another extraction.
3. Preserve UI responsiveness and cancellation priority.
4. Use temporary grid disabling only if request coalescing is too risky for 2.3.4.

If grid disabling is selected, show a clear progress/disabled state and restore interaction immediately on completion, cancellation, or failure. Do not leave navigation disabled because a stale scanning flag was not cleared.

### Required tests

- Concurrent scan and UI requests for the same source perform one extraction.
- Different sources still respect the configured concurrency limit.
- Cancelling a queued UI request does not cancel work still required by the scan.
- Cancelling the catalog load releases all waiters and returns the UI to an idle state.
- Opening a grid during scanning cannot exceed the loader’s admission limit.

### Acceptance criteria

- Opening a grid during scanning does not materially increase duplicate cold extractions.
- Scan cancellation remains prompt.
- No continuation leak, deadlock, or oversubscription is detected by the concurrency tests or Thread Sanitizer.

## Work item 6: preserve similarity artifact correctness

The per-file similarity artifact store is the largest new persistence change in 2.3.3. No redesign is planned for 2.3.4, but its existing behavior must be treated as a release-critical regression area.

### Required regression coverage

- Compatible artifacts survive model and application recreation.
- Added files generate only missing artifacts.
- Changed files generate replacement artifacts.
- Corrupt or incompatible records are rejected and safely regenerated.
- A partially failed indexing run keeps successful in-memory results and reports persistence failures.
- Cancellation stops later commits without damaging records already written.
- A superseded indexing generation cannot publish or clear newer state.
- Legacy burst snapshot artifacts migrate into the per-file store.
- Pruning respects age and entry-count limits.
- Clearing the analysis cache removes per-file artifacts and burst snapshots without touching ratings or settings.

### Manual verification

1. Index a catalog and record completion time and artifact count.
2. Quit and reopen RawCull.
3. Reload the catalog and confirm cached artifacts are reused.
4. Add one RAW file and confirm only that file is indexed.
5. Replace one RAW file at the same path and confirm its artifact is regenerated.
6. Force-refresh the similarity index and verify failed generations do not masquerade as refreshed results.
7. Clear analysis caches and confirm a subsequent run rebuilds them successfully.

### Acceptance criteria

- No rating, tag, manual burst winner, or saved sharpness result is lost.
- Indexing progress always returns to idle after success, cancellation, or failure.
- Persistence failures remain diagnosable without making successfully generated session results unusable.

## Work item 7: accessibility and interaction audit

This is a bounded audit, not a redesign.

- Preserve `onTapGesture(count:)` where RawCull genuinely distinguishes single-click and double-click image behavior.
- Convert purely single-action tappable rows to `Button` where doing so does not alter selection semantics.
- Ensure selected thumbnails expose a selected accessibility trait.
- Ensure image-source, rating, reject, focus-mask, and burst-review controls have meaningful labels and values.
- Mark purely decorative status symbols as hidden from accessibility.
- Verify keyboard navigation and VoiceOver focus do not conflict.

Only include these changes when they are isolated and covered by manual verification. Do not delay 2.3.4 for broad accessibility restructuring.

## Work item 8: documentation and metadata

### Project metadata

- Set `MARKETING_VERSION` to `2.3.4` for Debug and Release.
- Increment `CURRENT_PROJECT_VERSION` from `230` to `231`, unless a build has already consumed 231 in App Store Connect.
- Keep `MACOSX_DEPLOYMENT_TARGET` at `26.2`.
- Keep Apple Silicon as the supported architecture.
- Confirm About displays the bundle version rather than duplicated hard-coded version text.

### README corrections

Update the imported package table to match the exact project requirements and `Package.resolved`:

- `RawParserKit` 1.2.8
- `RawCullCore` 1.1.2
- retain the other exact versions currently resolved by the project

### User-facing release notes

Describe 2.3.4 as a macOS 26 stabilization release. Explain that it:

- resolves actual-pixel inspection consistency;
- prevents a histogram conversion failure from terminating the app;
- improves thumbnail cache correctness;
- reduces or prevents scan/grid duplicate thumbnail work, if that fix ships;
- strengthens release test coverage;
- contains no new AI requirements and remains compatible with macOS 26.2 or later.

Do not announce macOS 26 end-of-support until the macOS 27 release date and migration policy are final.

## Compatibility requirements

Version 2.3.4 must read all supported 2.3.3 user data without destructive migration:

- `savedfiles.json`;
- `settings.json`;
- persisted ratings and tags;
- sharpness and saliency records;
- manual burst winner overrides and review states;
- compatible similarity artifacts;
- compatible burst-analysis snapshots.

Disposable caches may be invalidated by a cache-schema change. Persistent user decisions must not be invalidated merely to simplify implementation.

The 2.3.4 fixes should be merged into `RawCullAIModels` after the macOS 26 release branch is verified so the macOS 27 line does not reintroduce them.

## Manual QA matrix

### Installation and upgrade

- Clean installation of 2.3.4.
- Upgrade from the released 2.3.3 build.
- Upgrade with existing ratings, settings, thumbnail caches, full-size preview caches, burst caches, and similarity artifacts.
- Launch from a signed/notarized GitHub DMG installation.
- Launch the App Store build when available.

### Hardware and system

- Minimum supported macOS 26.2.
- Latest available macOS 26 update used for release validation.
- At least one earlier Apple Silicon generation and one current generation where available.
- A lower-memory Mac and a higher-memory Mac where available.

### Core workflow

- Open a small catalog.
- Open a large catalog that exceeds the in-memory grid working set.
- Sort and search during and after scanning.
- Use normal grid, rated grid, table, burst home, comparison, and zoom overlay.
- Apply reject, pick, and star ratings by mouse and keyboard.
- Quit and relaunch; verify ratings and review states.
- Extract embedded and developed JPEGs.
- Copy tagged and rated RAW files and verify the exact copied set.
- Cancel scan, scoring, similarity indexing, burst analysis, extraction, and copy operations.
- Simulate or observe memory pressure and verify cache reduction without loss of user data.

### RAW coverage

- Sony ARW with embedded JPEG and AF metadata.
- Sony ARW without usable AF metadata.
- At least one supported non-Sony RAW format.
- Unsupported and malformed files in an otherwise valid catalog.
- A source file replaced at the same path after it has already been cached.

## Release gates

All boxes must be checked before tagging 2.3.4:

- [ ] P0 work items are complete.
- [ ] Every shipped P1 change has focused automated tests.
- [ ] `make test-smoke` passes from a clean build state.
- [ ] `make test-full` passes with Thread Sanitizer.
- [ ] `make test-performance` passes.
- [ ] Release configuration builds using only `Package.resolved` versions.
- [ ] No new compiler warnings attributable to RawCull.
- [ ] No known reproducible crash, data-loss bug, or stale-state publication remains open.
- [ ] Existing 2.3.3 persistence data has been tested with 2.3.4.
- [ ] Version and build numbers are correct in the built application.
- [ ] README package versions match `Package.resolved`.
- [ ] The GitHub DMG is signed, notarized, stapled, installed, and launched on a clean test account.
- [ ] The DMG SHA-256 is recorded in the release notes.
- [ ] App Store build metadata reports macOS 26.2 as the minimum version.
- [ ] The final commit is merged into `RawCullAIModels` or a follow-up merge is explicitly tracked.
- [ ] The release tag points at the exact tested commit.

## Detailed issue-closure execution plan

This section turns the work items above into an implementation and verification
sequence. It is based on the repository state inspected on 3 August 2026. It is
a plan, not a claim that the commands below have already passed.

### Current-state reconciliation

Before implementation, record the current state in the release issue or pull
request so that completed work is verified rather than repeated:

- ZoomViewportMath.actualPixelsScale still returns 0.6 / fitScale.
  ZoomViewportMathTests currently contain mixed 60% and 1:1 expectations, so
  work item 1 remains open.
- HistogramView still contains the reachable initial-load fatalError, does not
  clear bins for nil or failed conversion, and starts independent tasks from
  both .task and .onChange; work item 2 remains open.
- make test-smoke still uses a manually maintained SMOKE_ONLY_TESTING list.
  The smoke plan itself includes the whole test target and the Makefile list
  omits ZoomViewportMathTests; work item 3 remains open.
- Thumbnail disk, preview-memory, and grid-memory caches are still keyed by URL
  alone. The disk key has schema version v2-oriented-thumbnails but contains no
  source size, modification date, purpose, or requested size. Work item 4
  remains open.
- ThumbnailLoader still contains the scan/grid contention TODO. Scan and UI
  paths independently check caches and extract, so identical work is not
  coalesced. Work item 5 remains open.
- The similarity artifact implementation and its focused persistence tests are
  present. Work item 6 is primarily a regression gate unless a test or manual
  scenario fails.
- Dual single/double-click image gestures are intentional and must remain.
  Purely single-action rows in SavedFilesView are concrete candidates for the
  bounded accessibility change. Work item 7 remains an audit, not a mandatory
  refactor.
- The project already contains MARKETING_VERSION = 2.3.4,
  CURRENT_PROJECT_VERSION = 231, MACOSX_DEPLOYMENT_TARGET = 26.2, Swift 6,
  complete strict concurrency for the test target, Main Actor default isolation,
  and Approachable Concurrency. AboutRawCullView already reads bundle version
  values. Verify these items in built products rather than editing them again.
- Package.resolved contains RawParserKit 1.2.8 and RawCullCore 1.1.2, but the
  README table still says 1.2.6 and 1.1.0. The README correction remains open.

### Execution ledger

This ledger records work performed against the phase plan. A phase is marked
complete only after its focused verification and commit succeed.

| Phase | Status | Evidence |
|---|---|---|
| 0 — Baseline | Complete | Baseline captured on 3 August 2026; commit pending at time of entry |
| 1 — Actual Pixels | Pending | — |
| 2 — Histogram safety | Pending | — |
| 3 — Release gates | Pending | — |
| 4 — Thumbnail identity | Pending | — |
| 5 — Scan/grid contention | Pending | — |
| 6 — Similarity persistence | Pending | — |
| 7 — Accessibility | Pending | — |
| 8 — Metadata and documentation | Pending | — |
| 9 — Integrated regression | Pending | — |
| 10 — Release handoff | Pending | — |

#### Phase 0 baseline evidence

- Source commit: 9250d9f35e1f8f9d3bb6104c721ec31ade62fcc6
- Host: Apple Silicon arm64, macOS 26.6 build 25G72
- Toolchain: Xcode 26.6 build 17F113; Apple Swift 6.3.3
- Application language mode: Swift 6 with Main Actor default isolation and
  Approachable Concurrency
- Test target: complete strict concurrency checking
- Resolved-package SHA-256:
  2563e9f3e0d45448d2cb8f8042fd4e80d40fe77564b3a624f8c72a4e52d45fa9
- make test-smoke: passed. Output confirmed that several selected Swift
  Testing suites and cases executed twice.
- make test-full with Thread Sanitizer: failed on the known
  ZoomViewportMathTests mismatch. The unique failures were the fit-upscaled
  scale, focus-point transform, and missing-focus-point transform expectations;
  one focus-point failure was reported twice. No Thread Sanitizer data-race
  report appeared.
- make test-performance: passed the dedicated extreme concurrent-load test.
- Exact-package Release arm64 build: succeeded. The only observed warning was
  Xcode's App Intents metadata notice that no AppIntents.framework dependency
  was present; no new RawCull compiler warning was observed.
- Baseline result bundles were written by Xcode under DerivedData for the smoke,
  full, and performance runs. Final release evidence will use explicit,
  stable result-bundle paths after Phase 3 repairs the gate commands.

### Phase 0: establish the closure ledger and reproducible baseline

1. Create one tracked checklist with rows for work items 1–8 and columns for
   owner, implementation commit, focused test command, manual evidence,
   regression result, and closure decision. Link every failure to a work-item
   row instead of expanding the release scope informally.
2. Record the exact starting commit, Xcode build, Swift version, macOS version,
   architecture, and resolved package checksum. Keep the released 2.3.3 test
   fixture or installed application available for upgrade testing.
3. Confirm the worktree contains no unrelated edits before each implementation
   commit. Do not fold current loupe-view work or macOS 27/Core AI changes into
   the stabilization commits.
4. Run the current gates once and attach the result bundles:

   ~~~bash
   make test-smoke
   make test-full
   make test-performance
   ~~~

   The expected baseline is that the zoom mismatch makes the complete run red.
   Any additional failure gets its own ledger entry and is triaged as release
   blocking, pre-existing/non-blocking, or out of scope.
5. Save the enumerated tests and executed test count from each gate. This is the
   comparison point for detecting omitted or duplicated suites after the gate
   repair.
6. Capture a clean Release build log with exact resolved packages. Do not sign,
   notarize, or distribute this diagnostic build.

### Phase 1: close work item 1 — Actual Pixels

#### Product decision and code change

1. Record the product decision in the closure ledger: for 2.3.4, “Actual
   Pixels” means one source-image pixel per display point before backing-scale
   conversion, represented by 1.0 / fitScale in the existing fit-relative
   transform. If the intended definition is one source pixel per physical
   display pixel, stop and specify backing-scale behavior before changing code.
2. In RawCull/Views/ZoomViews/ZoomOverlayView.swift, change
   actualPixelsScale to return 1.0 / fitScale.
3. Strengthen input validation in aspectFitRect and actualPixelsScale: every
   image and viewport dimension must be positive and finite, and all derived
   scales and sizes must be finite. Return the documented fallback transform,
   scale 1 and zero offset, for invalid input.
4. Keep clampedOffset as the single edge-bounding function. Add guards if a
   non-finite focus point could otherwise produce a non-finite offset.
5. Search the project for “Actual Pixels”, “actual-pixels”, “60%”, 0.6, and the
   Z shortcut. Confirm menu text, tooltips, accessibility text, launch context,
   loupe actions, and help text all describe the 1:1 behavior.
6. Do not change ordinary zoom increments, pan gestures, source-selection
   behavior, or focus metadata interpretation in this commit.

#### Automated verification

1. Expand ZoomViewportMathTests in
   RawCullTests/ZoomOverlayKeyActionTests.swift. Prefer parameterized cases for
   landscape, portrait, fit-downscaled, fit-upscaled, and mismatched aspect
   ratios.
2. Correct both existing scale expectations and both transform expectations to
   the same 1:1 definition.
3. Add cases for zero, negative, infinity, NaN, and degenerate dimensions.
4. Add normalized focus points at the center and near all four corners. Verify
   both centerability and edge clamping.
5. Assert every returned scale and offset component is finite.
6. Run the focused suite first, then the smoke gate:

   ~~~bash
   xcodebuild test \
     -project RawCull.xcodeproj \
     -scheme RawCull \
     -destination 'platform=macOS' \
     -onlyUsePackageVersionsFromResolvedFile \
     -only-testing:RawCullTests/ZoomViewportMathTests
   make test-smoke
   ~~~

#### Manual closure

Run the seven manual scenarios listed in work item 1 on both a Retina display
and any available non-Retina/external display. Record image dimensions,
viewport dimensions, display scale, initial transform, and screenshots for one
landscape and one portrait file. Close the item only when the naming decision,
unit tests, and observed result agree.

### Phase 2: close work item 2 — histogram safety and stale publication

#### Code change

1. Replace the separate .task and .onChange loaders in
   RawCull/Views/Histogram/HistogramView.swift with one lifecycle path,
   preferably .task(id: imageIdentity). Use the NSImage object identity or a
   caller-supplied file/load identity that changes whenever the inspected image
   changes.
2. At the start of each task, set normalizedBins = []. A nil image or failed
   CGImage conversion should log once and return with empty bins.
3. Remove the fatalError. Treat conversion failure as a recoverable display
   failure and keep the inspector usable.
4. Perform histogram calculation away from the main actor. After awaiting it,
   check cancellation before assigning bins. This prevents the cancelled image
   A task from publishing after image B has started.
5. Prefer a structured async helper marked for concurrent execution over
   creating an additional unstructured task. If a detached task remains
   necessary because the image API is not safely transferable, document the
   ownership invariant and keep all CGImage use inside that task.
6. In FileInspectorView, make its owned @State private and clear the image when
   the selected file/load identity changes so a previous file cannot remain
   visible while the new thumbnail loads.
7. Keep the existing non-modal behavior. The structured log should include the
   operation and, where available, the file identity without exposing an entire
   user path unnecessarily.

#### Test seam and tests

1. Extract a small testable histogram-loading boundary that accepts an image
   conversion function and a histogram calculator. Production defaults use
   NSImage.cgImage and HistogramCalculator; tests inject failure and suspended
   calculations without requiring malformed fixture files.
2. Add RawCullTests/HistogramLoadingTests.swift with tests for nil input,
   conversion failure, valid normalized bins, valid-to-nil clearing, and
   superseded slow result A versus fast result B.
3. Avoid timing sleeps. Use an actor-backed gate or Swift Testing confirmation
   so the test controls exactly when A and B complete.
4. Run the focused tests repeatedly and with Thread Sanitizer. Close only when
   no fatalError remains in the histogram path and the supersession test is
   deterministic.

### Phase 3: close work item 3 — authoritative release gates

1. Enumerate every test carrying .tags(.smoke) and map it to its containing
   suite. Compare that inventory with SMOKE_ONLY_TESTING; preserve the inventory
   as review evidence.
2. First validate whether the installed Xcode version can reliably filter Swift
   Testing tests by tag from a checked-in test plan and from command line. Use a
   deliberately failing temporary smoke-tagged sentinel to prove selection; do
   not infer support merely because Xcode displays tags.
3. If tag filtering works, configure Smoke.xctestplan as the only smoke
   selector and remove the duplicate Makefile allow-list. If it does not work,
   make a checked-in suite manifest the only source of truth, include
   ZoomViewportMathTests, and add a lightweight validation script/test that
   fails when a source-level smoke tag belongs to a suite absent from the
   manifest.
4. Do not combine a target-wide test-plan inclusion with an incomplete
   -only-testing list and then describe the result as “all smoke tags.”
5. Use xcodebuild -enumerate-tests or the Xcode 26 equivalent to capture the
   resolved test list for Smoke, RawCull, and Performance. Compare identifiers
   and counts to find the duplicate suite reporting observed in review.
6. Inspect RawCull.xcodeproj/xcshareddata/xcschemes/RawCull.xcscheme and the
   three test plans. Ensure the test target is declared once per selected plan,
   only one plan is selected per command, and Makefile filtering does not cause
   a second invocation.
7. Keep tests parallelizable unless they share a real filesystem or singleton
   dependency. Give each filesystem test its own temporary directory. Use
   .serialized only for a narrowly documented suite that cannot yet be isolated.
8. Keep Thread Sanitizer exclusively in make test-full. Keep the dedicated
   extreme-load test in make test-performance, but clarify in the Makefile and
   test documentation that this target is a stress/data-race gate rather than a
   benchmark unless actual performance assertions are added.
9. Update RawCullTests/TEST_ARCHITECTURE.md and the README with the exact
   selection mechanism, the rule for adding a smoke test, and the expected role
   of each command.
10. Prove the gate by temporarily breaking one smoke test, observing
    make test-smoke fail, restoring it, and observing the gate pass. Attach both
    command excerpts to the ledger; do not commit the intentional failure.

### Phase 4: close work item 4 — thumbnail identity and size correctness

#### Define one identity model

1. Add an immutable, Hashable, Sendable ThumbnailSourceFingerprint containing
   standardized file URL/path, file size, modification date with documented
   precision, and cache schema version.
2. Add a ThumbnailRepresentation value containing purpose (grid or preview)
   and requested maximum pixel size. Combine source and representation into one
   ThumbnailRequestKey.
3. Decide size-reuse semantics explicitly: an artifact may satisfy an equal or
   smaller request only when its decoded maximum dimension is at least the
   requested dimension. A 200-pixel grid image must never satisfy a 1024/1616-
   pixel preview request.
4. Create fingerprints from existing FileItem.size and FileItem.dateModified
   for file-based UI calls. For URL-only calls, read .fileSizeKey and
   .contentModificationDateKey once at the boundary. If metadata cannot be
   read, bypass persistent reuse for that request rather than falling back to a
   path-only key that can return stale content.
5. Reuse the same source-fingerprint rules already proven by
   SimilarityArtifactSourceFingerprint, but keep thumbnail and analysis
   pipeline versions separate.

#### Apply the identity to every layer

1. Change DiskCacheManager.load/save to accept a request key. Bump the disk
   schema to v3 and hash the complete deterministic key. Keep atomic writes.
2. Change SharedMemoryCache preview and grid cache keys from bare NSURL to
   stable request-key objects. Update eviction diagnostics so recent eviction
   and boomerang metrics compare the same request identity.
3. Add a RequestThumbnail.requestThumbnail(for: FileItem, targetSize:purpose:)
   entry point and migrate ThumbnailLoader, ComparisonImageLoader,
   ZoomPreviewHandler, and FileInspectorView to it. Keep a URL overload only
   for callers that truly lack scanned metadata.
4. Update ScanAndCreateThumbnails to build the same key. Prefer passing the
   already scanned FileItem collection into preload rather than rediscovering
   URLs; if that is too invasive, collect size/date alongside discovery once.
5. Verify thumbnail setting changes. If thumbnailSizePreview changes, the new
   size key must miss an insufficient entry; sharpening settings must not be
   part of the extraction cache key because sharpening is applied after
   retrieval, unless a sharpened representation is itself persisted.
6. Preserve the full-size embedded/developed cache identity in this commit.
   Track it separately only if a focused reproduction proves the same bug.
7. Ensure cache clear deletes v2 and v3 disk artifacts and clears every
   in-memory key. Because thumbnails are disposable, do not migrate v2 files.

#### Tests and closure

1. Add pure key tests: same metadata produces the same key; standardized
   equivalent paths match; size, date, schema, purpose, and requested size each
   change the appropriate identity.
2. Use an isolated temporary catalog to test replacement at the same path.
   Write source A, cache its thumbnail, replace it with source B while changing
   size or modification date, and prove B cannot receive A's entry.
3. Test 200 to 1024 miss, 1024 to 200 permitted reuse if implemented, v2
   ignore, clear of both schemas, atomic write/cancellation, missing metadata
   bypass, and corrupt JPEG recovery.
4. Update existing disk-cache, scan-admission, provider, and memory diagnostic
   tests rather than leaving parallel URL-key and fingerprint-key behavior.
5. Manually replace a real RAW file at the same path while RawCull is closed
   and while it is open. Confirm the grid, preview, and zoom source refresh
   without altering ratings or saved records.

### Phase 5: close work item 5 — scan/grid contention

#### Measure first

1. Add counters or signposts around request admission, RAM hit, disk hit, cold
   extraction start/end, coalesced waiter, cancellation, and active extraction
   count. Keep this instrumentation low-cost and available in diagnostics.
2. Use one fixed uncached catalog and the four scenarios in work item 5. Run
   each scenario at least three times after clearing only disposable thumbnail
   caches. Record median scan duration and duplicate cold extractions by
   ThumbnailRequestKey.
3. Set the ship/no-ship threshold before implementing: ship coalescing when
   opening a grid causes repeat extraction of the same key or a material,
   repeatable scan regression. Otherwise retain the measurements and remove
   only the stale TODO wording.

#### Preferred implementation

1. Build coalescing on the Phase 4 request key. Keep a shared in-flight registry
   in the actor that owns thumbnail extraction and persistence, with one task
   per key and explicit waiter accounting.
2. Both scan and UI paths must call that coordinator after cache misses. The
   first caller creates work; later callers await the same result. Do not create
   separate scan and UI registries.
3. Define cancellation ownership before coding: cancelling one waiter removes
   only that waiter; underlying extraction is cancelled only when no scan or UI
   consumer remains. Cancelling a catalog load releases its waiters and does
   not cancel work still required by a UI consumer.
4. Remove the registry entry in one completion path for success, failure, and
   cancellation. Never leave a failed task reusable.
5. Keep the existing admission bound. Count an in-flight key once regardless
   of waiter count, and assert observed active extraction never exceeds the
   configured limit.
6. Because the project uses Swift 6, Main Actor default isolation, and strict
   test-target concurrency, pass immutable values across actors. Avoid
   @unchecked Sendable, detached tasks, or unsafe isolation solely to make
   coalescing compile. If image objects cannot cross the boundary safely, let
   the extraction owner encode a Data payload and decode it at the consumer.
7. Preserve cache-admission policy: scan fills the grid/disk layers; UI demand
   may promote to the preview-memory layer. Coalescing identical extraction
   must not make scan traffic pollute the UI LRU.

#### Low-risk fallback

If coalescing cannot be made cancellation-safe without broad architecture
change, disable normal and rated grid interaction only while thumbnail
extraction is active. Drive disabled/progress state from the active catalog-load
identity, and clear it in success, cancellation, supersession, and failure
paths. Document this as the 2.3.4 fallback and retain coalescing as follow-up
work.

#### Tests and closure

Add deterministic actor-gated tests for one extraction with scan plus UI
waiters, different-key concurrency bounds, single-waiter cancellation,
last-waiter cancellation, catalog cancellation, failure cleanup, retry after
failure, and no continuation leak. Re-run the same measurement matrix and
attach before/after results. Close only when duplicate extraction is removed or
the fallback demonstrably prevents it, cancellation stays prompt, and full TSan
passes.

### Phase 6: close work item 6 — similarity persistence regression

1. Map every required behavior to an existing test before adding tests.
   PerFileAnalysisArtifactStoreTests already covers round-trip identity,
   corruption isolation, invalid payload rejection, pruning/clear, and
   cancellation before replacement. SimilarityArtifactPersistenceTests covers
   model recreation, added/changed files, legacy migration, and partial
   generation failure. CullingModelTests covers structured cancellation and
   superseded generations.
2. Add only uncovered cases: persistence-write failure with usable in-memory
   results, cancellation after some records commit, analysis-cache clearing
   that proves ratings/settings remain untouched, and progress reset after each
   terminal outcome.
3. Give every persistence test its own temporary directory and immutable
   fixtures so Swift Testing can retain parallel execution.
4. Run the focused artifact, indexing, burst-cache, and culling suites before
   and after thumbnail changes. Thumbnail fingerprints must not change
   similarity artifact identities.
5. Execute the seven manual restart/change/refresh/clear scenarios in work item
   6 using a copy of 2.3.3 user data. Record artifact counts and provider request
   counts before and after each step.
6. Close this item as “verified, no production change” if all evidence passes.
   If a failure appears, make the smallest persistence fix in a separate commit
   and repeat the whole phase.

### Phase 7: close work item 7 — bounded accessibility audit

1. Inventory each remaining onTapGesture. Preserve double-click zoom and
   combined single/double selection in ImageItemView, RatedImageItemView,
   ComparisonImagePaneView, FileDetailView, and ZoomOverlayView.
2. Convert the catalog and file-record rows in SavedFilesView to borderless
   Button rows or an equivalent native selectable control. Preserve hover,
   selection, split-view navigation, and row-wide hit targets.
3. Add .isSelected accessibility traits to selected normal, rated, and
   comparison thumbnails without changing their visual selection logic.
4. Audit ImageSourceToggleView, rating/reject controls, focus-mask and
   focus-point controls, and burst-review controls for labels, values, enabled
   state, and keyboard operation. Hide decorative rating strips, dividers, and
   status glyphs when they duplicate spoken information.
5. Verify with VoiceOver: navigate every audited control, select a row, open an
   image with the keyboard, change rating/source, and return focus after
   dismissal. Also test normal keyboard navigation with VoiceOver off.
6. Revert any conversion that changes click-count or selection semantics.
   Accessibility work is closed when the bounded inventory is documented and
   every shipped change has manual evidence; unbounded redesign requests become
   separate post-2.3.4 issues.

### Phase 8: close work item 8 — metadata and documentation

1. Verify Debug and Release build settings resolve to 2.3.4 (231). Before
   upload, confirm build 231 has not already been consumed in App Store Connect;
   if it has, increment both configurations to the next unused build number.
2. Build the app and inspect CFBundleShortVersionString, CFBundleVersion,
   minimum system version, supported architecture, and the About window. Treat
   built-product values as authoritative.
3. Update the README package table to RawParserKit 1.2.8 and RawCullCore 1.1.2.
   Compare every other table row with
   RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved,
   not only the two known stale rows.
4. Update test documentation after the final gate design is known. Do not
   document tag filtering if the shipped Makefile uses an explicit manifest.
5. Write final release notes from shipped changes only. Include contention or
   accessibility claims only if those changes pass their closure phases.
6. Add the compatibility statement, known limitations if any, exact tested
   commit, DMG SHA-256, and minimum macOS version to the release record.

### Phase 9: integrated regression and compatibility pass

1. From a clean checkout of the proposed release commit, resolve only the
   checked-in package versions and run, in order:

   ~~~bash
   make test-smoke
   make test-full
   make test-performance
   xcodebuild \
     -project RawCull.xcodeproj \
     -scheme RawCull \
     -configuration Release \
     -destination 'platform=macOS,arch=arm64' \
     -onlyUsePackageVersionsFromResolvedFile \
     build
   ~~~

2. Save .xcresult bundles and logs. Confirm stable test enumeration, zero
   duplicate identifiers, no failure, no hang, and no new RawCull compiler or
   concurrency warning.
3. Run the full manual QA matrix above. For upgrade testing, duplicate the 2.3.3
   Application Support and cache directories first, then use the duplicate with
   2.3.4 so the original recovery fixture remains untouched.
4. Compare ratings, tags, sharpness/saliency, manual burst winners, review
   states, settings, and saved-file records before and after launch. Disposable
   thumbnail cache misses are expected; persistent decision loss is a release
   blocker.
5. Repeat critical cancellation and cache-replacement scenarios on the minimum
   supported macOS 26.2 machine and the latest available macOS 26 update.
6. File every failure against its owning phase, fix it in that phase's commit,
   and rerun that focused suite plus all later phases. Do not waive a red P0
   gate.

### Phase 10: package, release, and 3.0.0 handoff

1. Freeze the exact green commit. Build the Release archive from that commit
   without source changes between testing and packaging.
2. Verify code signing, hardened runtime, entitlements, notarization acceptance,
   stapling, Gatekeeper assessment, clean-account installation, launch, and
   upgrade from 2.3.3.
3. Compute and publish the DMG SHA-256. Verify the downloaded release artifact
   reproduces the published hash.
4. Upload the App Store build only after its bundle metadata and minimum system
   version are verified. Record the App Store build number in the ledger.
5. Tag the exact tested commit as 2.3.4 and confirm the tag resolves to that
   commit.
6. Create the separate 3.0.0 stabilization plan described at the end of this
   document. Reimplement each applicable requirement against the authoritative
   AI architecture rather than merging the 2.3.4 implementation.
7. Run the successor branch's AI and smoke tests after each independent 3.0.0
   change, and create a tracked follow-up for any intentionally deferred
   contention or accessibility work.

### Required evidence to mark the release plan complete

The release issue may be closed only when it contains:

- the exact tested commit and environment;
- implementation commit links for every changed work item;
- focused test results for work items 1–6;
- smoke failure-sentinel proof and final smoke enumeration;
- full TSan and stress-gate result bundles;
- before/after contention measurements or an explicit measured no-change
  decision;
- 2.3.3 persistence-upgrade comparison results;
- Actual Pixels, histogram, cache replacement, cancellation, accessibility, and
  core-workflow manual QA evidence;
- built-product version/minimum-system/architecture inspection;
- signed/notarized/stapled installation evidence and DMG SHA-256;
- the release tag and the tracked 3.0.0 stabilization-plan reference.

Any unchecked P0 row, unexplained test-count change, persistent-data mismatch,
reproducible crash, stale thumbnail after source replacement, stale async state
publication, or unresolved TSan report keeps 2.3.4 open.

## Suggested implementation order

1. Resolve the Actual Pixels product decision and fix the math/tests.
2. Remove the histogram crash and stale-result behavior.
3. Repair the smoke/full test gates and obtain a green baseline.
4. Implement and test thumbnail source fingerprinting.
5. Measure scan/grid contention and apply only the smallest verified fix.
6. Run the similarity persistence regression suite and manual restart tests.
7. Apply bounded accessibility corrections.
8. Update README, marketing version, and build number.
9. Run the complete automated and manual release gates.
10. Build, sign, notarize, staple, hash, and distribute the final artifacts.
11. Create the independent 3.0.0 stabilization plan and map every applicable
    requirement to an AI-native implementation.

## Suggested commit structure

Keep fixes independently reviewable and reversible:

1. `Fix actual-pixel viewport behavior and tests`
2. `Handle histogram conversion failures safely`
3. `Make smoke tests cover all release-critical suites`
4. `Fingerprint thumbnail cache entries by source`
5. `Coalesce scan and grid thumbnail requests` — only if measurement justifies shipping it
6. `Update RawCull 2.3.4 documentation and version metadata`

Avoid mixing these fixes with macOS 27 or Core AI changes.

## Draft release-note summary

> RawCull 2.3.4 is a maintenance and stabilization update for macOS 26. It improves zoom inspection consistency, safely handles image conversion failures, strengthens thumbnail cache correctness and release testing, and includes reliability improvements around catalog analysis. RawCull 2.3.4 requires macOS 26.2 or later and an Apple Silicon Mac.

## Post-release policy

After release:

1. Preserve the immutable 2.3.4 tag, source archive, and release artifacts. The
   maintenance branch may be removed after release.
2. Preserve 2.3.4 as the last compatible macOS 26 App Store version where App Store Connect permits it.
3. Monitor crash reports and user feedback during the macOS 27 transition.
4. Do not backport new AI or macOS 27 features.
5. Backport only critical fixes that meet the maintenance criteria at the start of this document.

## Create plan for version 3.0.0

Use the completed 2.3.4 plan as a behavioral reference when creating the
version 3.0.0 stabilization plan. Version 3.0.0 must receive independently
designed fixes that preserve its AI architecture. Do not merge the completed
2.3.4 branch into main or mechanically transplant its implementation.

The following instructions should be supplied with the request to create the
3.0.0 plan:

> Create a detailed stabilization plan for RawCull 3.0.0 using the version
> 2.3.4 plan as a behavioral and acceptance-criteria reference.
>
> This is a read-only planning task. Do not modify production code, tests,
> project settings, dependencies, or Git history. Only update the requested
> 3.0.0 planning document.
>
> Analyze the current main/version-3.0.0 implementation before proposing
> changes. The AI architecture is authoritative and must be preserved,
> including PhotoAIKit, Core AI models, CLIP similarity and semantic search,
> SAM 3 Deep Review, model downloads, typed similarity artifacts, multiple
> similarity backends, AI settings, diagnostics, and their tests.
>
> Do not merge, cherry-pick, copy wholesale, or mechanically transplant code
> from version-2.3.4. Do not replace AI implementations with the older
> Vision-only implementations. Treat version 2.3.4 as a source of behavioral
> requirements, regression scenarios, and acceptance criteria—not as the
> implementation for version 3.0.0.
>
> For every 2.3.4 work item, classify it as:
>
> - apply unchanged in behavior;
> - adapt to the 3.0.0 AI architecture;
> - already resolved—verification only;
> - superseded by a 3.0.0 implementation;
> - not applicable to macOS 27.
>
> For every applicable item, document:
>
> - the defect or invariant being carried forward;
> - the current 3.0.0 code paths involved;
> - the AI features and data that must remain intact;
> - the exact files likely to change;
> - the smallest safe implementation approach;
> - concurrency, cancellation, persistence, and cache implications;
> - focused automated tests;
> - AI-specific regression tests;
> - manual verification;
> - acceptance criteria;
> - rollback criteria and the safe rollback boundary.
>
> Preserve all persistent AI data formats and compatibility unless a migration
> is explicitly designed and tested. Do not invalidate model downloads,
> licence acceptance, semantic artifacts, similarity artifacts, ratings,
> settings, saved-file records, or burst decisions merely to simplify a fix.
>
> Treat changes to SimilarityScoringModel, PerFileAnalysisArtifactStore,
> BurstAnalysisCache, package dependencies, project metadata, test plans, cache
> clearing, model-resource management, and backend selection as high risk.
> Require an AI-specific regression matrix for these areas.
>
> Keep the 3.0.0 version metadata, macOS 27 deployment settings, AI
> dependencies, model resources, entitlements, and release documentation
> authoritative. Do not copy 2.3.4 version numbers, macOS 26 requirements,
> package lockfile, or release notes into version 3.0.0.
>
> Add a detailed new section to the 3.0.0 planning document. Clearly
> distinguish verified repository facts from proposed work, and do not claim
> tests have passed unless they were actually run.

### Required references for the 3.0.0 planning task

Specify these inputs when requesting the plan:

- Behavioral reference: version-2.3.4 at the immutable 2.3.4 release tag.
- Reference document: updatesforversion234.md from that release tag.
- Target implementation: the current main/version-3.0.0 branch.
- Target document: updatesforversion300.md, or the selected 3.0.0 planning
  document.

The plan must inspect the target branch rather than assume that file names,
types, cache identities, persistence formats, or tests still match 2.3.4.

### Forward-application policy

The following policy supersedes any earlier suggestion in this document to
forward-merge the 2.3.4 implementation:

1. Finish and verify each fix independently on version-2.3.4.
2. Record the behavioral requirement, test scenario, and acceptance evidence.
3. Evaluate the same requirement against the current 3.0.0 architecture.
4. Implement an AI-native 3.0.0 fix in a separate commit and review.
5. Run both the applicable stabilization tests and the complete AI regression
   suites.
6. Do not carry version-specific metadata, package resolution, deployment
   targets, release notes, or distribution configuration from 2.3.4 to 3.0.0.

After the 2.3.4 release, the maintenance branch may be removed from the active
branch list, but the immutable 2.3.4 tag, source archive, signed release
artifacts, SHA-256, release notes, and test evidence must be retained. The tag
becomes the permanent historical reference after the AI code is the only
active development line in the repository.
