# RawCull code review

Reviewed 2026-10-15. Goal: make RawCull a clear, reliable example of modern Swift and SwiftUI development. This is a source review, not a certification of every execution path. Performance costs require Instruments measurements. The initial Xcode test attempt failed during dependency fetching because GitHub was unreachable from the sandbox. Isolated production-model probes confirmed the tagging-date defect and mutation before loading.

Priorities: **P1** fix first; **P2** important correctness, responsiveness, or accessibility; **P3** maintainability and reference-code quality.

## Implementation plan

Commit each update before beginning the next:

1. Record this review and remediation details.
2. Fix keyboard admission and conflicting burst/rating routing; add regression coverage.
3. Separate embedded JPEG export from display-preview fallback.
4. Fix thumbnail request identity and stale publication.
5. Correct tagging dates, persistence initialization, and recovery projections.
6. Surface settings persistence failures.
7. Correct isolated thumbnail-provider storage dependencies.

Keep performance tuning, broader view decomposition, and other P3 refactoring as follow-up work. Do not combine unrelated architectural rewrites with correctness fixes. Update the status and validation notes below as changes land.

## Findings

### 1. P1 — Photo shortcuts can act in another window

**Status:** Implemented. Window anchors now reject other-window events, sheets, modal sessions, native editors/controls, and focused SwiftUI accessibility controls. Keyboard scope and existing zoom key-action regression suites passed in Xcode. **Location:** `RawCull/Views/ThumbnailComponents/ThumbnailKeyNavigationModifier.swift`, plus comparison, zoom, and loupe event monitors.

Local NSEvent monitors receive application-wide events before dispatch. Excluding NSText does not exclude Settings controls, sheets, the About window, or unrelated focused controls. Photo navigation and rating commands can therefore intercept keys outside the intended review surface.

**Fix:** Give each review surface an explicit window/focus admission boundary. Reject events for other windows, attached sheets, text editing, and controls that own keyboard input. Preserve intentional image-review shortcuts without making every button a competing focus target. Centralize admission across all existing monitors and remove monitors when their surface disappears.

**Verify:** Main photo window accepts intended shortcuts; Settings/About windows and sheets do not. Text input, sliders and native controls retain their keys. Closing/reopening review surfaces does not multiply handlers.

### 2. P2 — Competing keyboard handlers disagree about `2`

**Status:** Implemented. The thumbnail monitor reserves burst commands and delegates them to the grid before considering ratings; the competing SwiftUI burst handler was removed. Ineligible burst commands cannot fall through to rating 2. Routing regression cases passed. **Location:** `CullingGridView.handleBurstKeyPress` and `ThumbnailKeyNavigationModifier`.

The burst grid assigns `2` to keeping the top two candidates, while the application event monitor consumes it as rating 2 before SwiftUI receives it.

**Fix:** Resolve burst commands before ordinary ratings in the same active keyboard context. Have a single owner decide whether a key was handled; never consume a key and also dispatch a second action. Outside burst mode, preserve rating 2.

**Verify:** `2` invokes keep-top-two only in an eligible burst context; ordinary grids retain rating 2. Invalid burst actions must not silently become rating changes. Check B, R, U, Return and Escape alongside rating/navigation keys.

### 3. P2 — Embedded JPG export can export a sidecar

**Status:** Implemented. A dedicated ARW/NEF/DNG embedded-byte loader bypasses sidecars and display caches. Standalone JPEG bytes are preserved; JPEGs relying on RAW orientation are normalized and encoded explicitly. Synthetic RAW/sidecar tests and export destination-safety tests passed. **Location:** `Actors/ExtractAndSaveJPGs.swift`, `Model/FullSizePreviewLoader.swift`.

Export calls the display-preview loader, which prefers a sidecar JPEG. It then decodes and re-encodes the selected image, even though the action promises the embedded JPEG.

**Fix:** Introduce a dedicated export dependency that returns camera-authored JPEG data. Do not use sidecars or lossy preview-cache fallback for embedded export. Preserve orientation and metadata when copying original bytes; retain existing exclusive destination creation. Keep display-preview behavior independent.

**Verify:** A RAW file with a deliberately different sidecar exports embedded content. Original JPEG bytes survive export. Missing embedded JPEG is an explicit failure. Existing destination files remain protected.

### 4. P2 — Thumbnail task identity and publication are incomplete

**Status:** Implemented. Request identity now includes URL, target size, style, and available file size/modification date. A presentation model rejects cancelled and superseded loads before publishing to either the view or its image binding. New-source loads clear stale pixels. Thumbnail presentation and loader concurrency regression suites passed in Xcode. **Location:** `Views/ThumbnailComponents/ThumbnailImageView.swift`.

The task identity contains only the URL, so representation-size changes do not reload. A cancelled request can still publish to local state or the caller's image binding.

**Fix:** Define a request identity containing URL, target pixel size, style/purpose, and available source revision metadata. Snapshot the request when starting work. Clear stale presentation when switching sources and reject cancellation/stale identities before updating any state or binding.

**Verify:** Changing size for the same URL reloads. A slow old request cannot overwrite a newer image or clear its binding. Cancellation does not publish a result.

### 5. P2 — Saved sharpness restoration repeats expensive main-actor work

**Status:** Implemented. Restoration indexes records once, preserves first-duplicate behavior, validates source/signature metadata, and publishes score dictionaries once. A 100-file regression verifies one score revision and correct normalization. Recovery, sharpness and culling presentation suites passed; no measured timing improvement is claimed. **Location:** `RawCullViewModel+Sharpness.loadPersistedScoringandSaliency`, `SharpnessScoringModel.scores.didSet`.

Each file linearly searches saved records. Each score insertion sorts the accumulated scores to recompute a percentile.

**Fix:** Index saved records by name once. Build score/saliency/AF dictionaries locally and publish each once. Compute normalization once per batch. Preserve source/signature validation and define duplicate-record handling explicitly.

**Verify:** Existing restoration tests still pass; compare large-catalog timings and main-thread traces before/after. No per-item percentile recomputation.

### 6. P2 — Grid caching still walks the catalog during view updates

**Status:** Open. **Location:** `Views/CullingGrid/CullingGridView.swift`, `CullingGridRenderCache.swift`.

Cache-key construction hashes complete membership on body evaluation; rendered groups and selection projections are rebuilt repeatedly. Unrated filtering also performs per-file record searches.

**Fix:** Own derived grid projections in a model with explicit source revisions. Recompute only when membership, ordering, filters or analysis semantics change. Use existing rating indexes for unrated checks. Keep selection-only changes independent of catalog reconstruction.

**Verify:** Regression tests for ordering/filter invalidation; Instruments evidence showing selection does not trigger full reconstruction. Avoid replacing correct invalidation with an incomplete cache key.

### 7. P2 — Metadata scan task admission is unbounded

**Status:** Implemented. Metadata scans use bounded task-group admission (configurable; conservative default at most eight), await coalesced monotonic progress, and stop admitting work after cancellation. A 65-file test enforces a three-read limit and exact progress batches; cancellation drains the admitted workers. Scan, sort and catalog concurrency suites passed. Storage-specific tuning remains a profiling task. **Location:** `Actors/ScanFiles.swift`.

One child task and one UI progress task are admitted per file before results are collected.

**Fix:** Use bounded task-group admission with a measured concurrency limit. Coalesce progress reporting. Preserve cancellation and catalog access for work still performing native I/O.

**Verify:** Instrument a synthetic large scan; assert maximum active workers and cancellation behavior. Preserve deterministic final sorting.

### 8. P2 — Preload gate blocks ready visible thumbnails

**Status:** Open. **Location:** `Actors/ThumbnailPreloadGate.swift`, `ScanAndCreateThumbnails.swift`.

Waiters are released at catalog completion rather than when their image becomes available.

**Fix:** Share per-file in-flight requests or notify per-file readiness. Retain duplicate-decode protection, cancellation handling and separation from AI workflows.

**Verify:** A visible early file appears before the final catalog item completes, with no duplicate decode or leaked continuation.

### 9. P2 — Unloaded persistence is treated as empty and writable

**Status:** Implemented. Live stores start unread, coalesce asynchronous background initialization, and block edits until ready. Startup loads history without a catalog; flush waits for initialization. Failed loads require explicit retry. Injected writer-only stores are explicitly empty and never read production data. Initialization, culling, saved-history, catalog concurrency and quit-recovery suites passed in Xcode. **Location:** `Model/ViewModels/CullingModel.swift`, `RawCullViewModel+Catalog.swift`.

The store starts empty and writable; it is loaded only after a nonempty catalog scan. Saved history can appear empty at startup, and callers can save before discovering existing/corrupt data.

**Fix:** Introduce explicit unloaded/loading/ready/failed state, load independently of catalog scanning, and block mutations until loading succeeds. Keep temporary/in-memory test stores explicit. Preserve damaged-store recovery and quit flushing; do not overwrite an unread store.

**Verify:** History is available without opening a photo catalog. Mutation before readiness is blocked. Missing, existing, corrupt, empty-catalog and quit-during-load paths are covered with isolated stores.

### 10. P2 — Recovery does not refresh derived presentation

**Status:** Implemented. Application-level retry/reset rebuilds ratings, scoring, filters, selection and copy admission. Failed reads preserve presentation; reset refreshes memory even when persisting the empty store fails. Recovery regressions and affected sharpness/culling suites passed. **Location:** `Main/RawCullMainView.swift` persistence recovery actions.

Retry can replace savedFiles while ratingCache, tagged names, filtering and scoring presentation remain stale.

**Fix:** Route retry/reset through application-level recovery operations. After successful reload, rebuild ratings and scoring projections, reapply filters and reconcile selection. Failed recovery must preserve current error state and data.

**Verify:** Repair a failed store, retry, and verify saved rows, tiles, filters and copy selections agree immediately. Reset clears the same projections.

### 11. P2 — Existing records lose tagging-date updates

**Status:** Implemented. Existing records now receive the tagging date when rated; scoring-only merges preserve it and restoring an unrated state clears it. ReviewPersistenceTests and CullingModelTests passed in Xcode. **Location:** `CullingModel.upsertRecord`.

Updating an existing record's rating ignores dateTagged. A scored-then-rated photo retains a nil date.

**Fix:** Update dateTagged when applying an explicit rating. Scoring-only updates must preserve existing tagging metadata. Keep explicit clearing/undo behavior coherent.

**Verify:** Scored-then-rated and re-rated records have tagging dates; scoring alone leaves nil untouched; rating-state clearing still clears the date.

### 12. P2 — Settings persistence errors are hidden

**Status:** Implemented. Load/save failures are observable; save returns success/failure while retaining edits. Settings presents an item-bound alert with operation-specific retry and a warning that load retry replaces current values. Failure/retry, malformed/missing settings and existing concurrency tests passed. **Location:** `Model/ViewModels/SettingsViewModel.swift`, Settings views.

Save catches and logs errors, so callers cannot distinguish persistence success. Load failures similarly lack user-visible state.

**Fix:** Expose observable load/save failure state or a throwing/result API. Present errors and retry in Settings. Do not imply success after failure; preserve current edits. Distinguish absent settings from malformed/unreadable settings.

**Verify:** Isolated unwritable/malformed stores produce visible failure state. Successful retry clears errors and persists the intended values. Existing callers handle the chosen API consistently.

### 13. P2 — Settings sliders lack explicit accessible names

**Status:** Implemented. Sliders now use explicit labels plus formatted accessibility values and descriptive hints. The Settings UI compiles and keyboard admission regressions pass; manual VoiceOver verification remains a release check. **Location:** `Views/Settings/SettingsSliderRow.swift`.

A sibling visual label does not explicitly name the slider.

**Fix:** Use a labeled Slider initializer or accessibilityLabel, plus a formatted accessibilityValue and suitable hint. Hide redundant visual labels from accessibility only when necessary.

**Verify:** VoiceOver announces each setting and its units/value; keyboard adjustment works without triggering photo navigation.

### 14. P2 — Important animations ignore Reduce Motion

**Status:** Open. **Location:** `RawCullMainView.startMemoryWarningFlash`, thumbnail hover and scrolling.

**Fix:** Read accessibilityReduceMotion at the consuming views. Replace perpetual flashing/scale motion with a stable warning or restrained nonmoving emphasis; disable animated programmatic scrolling when requested. Apply the policy consistently rather than removing all feedback.

**Verify:** Toggle Reduce Motion while the app is running; warnings remain understandable and photo navigation stays immediate.

### 15. P2 — Isolated thumbnail test helper uses production disk storage

**Status:** Implemented. Helper-created thumbnail providers explicitly receive a disk cache under their unique temporary root, and accept an injected RAW loader. A real disk-hit/miss regression proves two providers cannot see each other’s cache entries. Isolation, thumbnail provider and image-loading integration suites passed. **Location:** `RawCullTests/TestIsolationHelpers.swift`.

makeIsolatedThumbnailProvider injects memory storage but omits RequestThumbnail's disk cache. The default initializer uses production paths and performs legacy-cache cleanup.

**Fix:** Construct and inject a disk cache under the same unique temporary test root. Audit neighboring helpers for implicit production storage; do not test by touching the user's real directories.

**Verify:** A helper-created provider's disk path is inside its temporary root, disk-hit/write tests use that path, and parallel tests have distinct roots.

### 16. P3 — Major view sections share observation boundaries

**Status:** Open. **Location:** `BurstCullingWorkspaceView`, `ZoomOverlayView`, `LoupeMainImageView`.

Computed view properties organize source but do not create independent update boundaries.

**Fix:** Extract substantial independently updating sections into View types with focused inputs. Keep tiny helpers where they improve clarity. Profile first when claiming performance gains.

**Verify:** Behavior/layout remain stable; body-update diagnostics demonstrate narrower invalidation where intended.

### 17. P3 — Redundant state and forwarding obscure ownership

**Status:** Open. **Location:** `GridThumbnailViewModel`, `ZoomOverlayView` session forwarding properties.

**Fix:** Remove unused copies of selectedSource/filteredFiles and replace availability-only containers with explicit derived capability. Read session-owned state directly, using local @Bindable only where bindings are needed. Retain meaningful feature boundaries and test seams.

**Verify:** Catalog changes, view switching and navigation use one authoritative projection; previews/tests no longer require redundant setup.

### 18. P3 — Typed AI sanitization uses force-cast dictionaries

**Status:** Open. **Location:** `Intelligence/ObjectAnalysis/ObjectAnalysisResponseDecoder.swift`.

Validated values are encoded, converted to [String: Any], force-cast and mutated, then decoded again. Current casts rely on known encoded shapes; this is a schema-maintenance concern rather than a demonstrated input crash.

**Fix:** Transform typed assessment values and their paired claim/evidence arrays directly. Retain strict external JSON validation and explicit-null requirements at the serialization boundary.

**Verify:** Existing abstention/schema tests pass; add coverage for removal of unsupported focus claims while preserving unrelated evidence and ownership.

## Guidance and validation

- Apple: [Local event monitors](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)), [SwiftUI task identity](https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)), [app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- Installed guidance: SwiftUI Expert, Apple's SwiftUI Specialist, Swift Concurrency, and Swift Testing Expert.
- Prefer regression tests against production behavior; do not substitute source-text assertions for behavioral coverage.
- Initial worktree was clean. No production data was touched by isolated review probes.

## Implementation checkpoint

Completed and committed in order: review/plan, keyboard routing (findings 1–2), embedded JPEG export (3), and thumbnail request/publication correctness (4). Every code update includes this document's status and validation notes. Remaining correctness work starts with persistence initialization/recovery and tagging dates (9–11), followed by settings errors (12) and test storage isolation (15). Performance and broader cleanup remain open.

At the user's request, check account usage immediately after the thumbnail commit and stop further fixes if the remaining allowance is insufficient. Do not begin the next update without that check.

### Usage checkpoint after thumbnail commit

Checked account usage after commit `27d63039`: 90% of the five-hour allowance consumed (10% remaining), 26% of the weekly allowance consumed (74% remaining), and zero additional credits. Ordinary usage is still allowed, but the remaining short-window allowance was judged insufficient for the larger persistence update plus regression verification. Further fixes stopped at the user's requested checkpoint. The worktree was clean after the thumbnail commit; only this checkpoint documentation was subsequently changed.

Validation completed before stopping: Xcode passed the keyboard scope/key-action suites, embedded JPEG export/destination-safety suites, and thumbnail presentation/concurrency suites. No full-suite or manual UI verification is claimed. Resume with plan step 5, keeping one verified update and its review-status change per commit.

### Continued P2 work — tagging dates

Resumed after checking usage: 99% of the five-hour allowance and 74% of the weekly allowance remained. Fixed finding 11 and verified its regression tests plus the culling model suite before committing. Further updates continue to require their own document update, tests, commit, and allowance check.

### Persistence initialization

Fixed finding 9. Saved JSON value types are explicitly nonisolated and Sendable so reading/decoding runs off the main actor. Tests cover unread-store mutation rejection, concurrent initialization, corrupt-file preservation and explicit retry. Existing in-memory test assembly now injects its culling store. Allowance before this update: 92% of the five-hour window, 73% weekly.

### Recovery and batched restoration

Fixed findings 5 and 10 in one persistence-presentation update. Tests cover repaired history, filtered selection/copy admission, archive/reset followed by write failure, duplicate record policy, stale metadata, and single-batch normalization. Allowance before this update: 82% of the five-hour window, 71% weekly. Xcode passed all selected suites; its unrelated no-AppIntents metadata-extraction warning remains.

### Settings errors and accessible controls

Fixed findings 12 and 13. New tests cover failed writes preserving edits, retry after alert dismissal, repaired malformed settings, and normal missing-file defaults. Xcode passed settings persistence/concurrency and keyboard scope suites. Allowance before this update: 68% of the five-hour window, 69% weekly.

### Test storage isolation

Fixed finding 15. The shared view-model helper already received an in-memory culling store in the persistence update; the thumbnail helper now injects every storage dependency too. Selected Xcode suites passed. Allowance before this update: 58% of the five-hour window, 67% weekly.

### Bounded catalog metadata scanning

Fixed finding 7. Xcode passed scan admission/progress/cancellation and existing sort/catalog concurrency suites. No per-file unstructured progress tasks remain. Allowance before this update: 53% of the five-hour window, 67% weekly.
