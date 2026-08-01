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
11. Merge the verified fixes into `RawCullAIModels`.

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

1. Keep the 2.3.4 source branch and release artifacts available.
2. Preserve 2.3.4 as the last compatible macOS 26 App Store version where App Store Connect permits it.
3. Monitor crash reports and user feedback during the macOS 27 transition.
4. Do not backport new AI or macOS 27 features.
5. Backport only critical fixes that meet the maintenance criteria at the start of this document.

