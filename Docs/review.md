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

**Status:** Open. **Location:** `RawCull/Views/ThumbnailComponents/ThumbnailKeyNavigationModifier.swift`, plus comparison, zoom, and loupe event monitors.

Local NSEvent monitors receive application-wide events before dispatch. Excluding NSText does not exclude Settings controls, sheets, the About window, or unrelated focused controls. Photo navigation and rating commands can therefore intercept keys outside the intended review surface.

**Fix:** Give each review surface an explicit window/focus admission boundary. Reject events for other windows, attached sheets, text editing, and controls that own keyboard input. Preserve intentional image-review shortcuts without making every button a competing focus target. Centralize admission across all existing monitors and remove monitors when their surface disappears.

**Verify:** Main photo window accepts intended shortcuts; Settings/About windows and sheets do not. Text input, sliders and native controls retain their keys. Closing/reopening review surfaces does not multiply handlers.

### 2. P2 — Competing keyboard handlers disagree about `2`

**Status:** Open. **Location:** `CullingGridView.handleBurstKeyPress` and `ThumbnailKeyNavigationModifier`.

The burst grid assigns `2` to keeping the top two candidates, while the application event monitor consumes it as rating 2 before SwiftUI receives it.

**Fix:** Resolve burst commands before ordinary ratings in the same active keyboard context. Have a single owner decide whether a key was handled; never consume a key and also dispatch a second action. Outside burst mode, preserve rating 2.

**Verify:** `2` invokes keep-top-two only in an eligible burst context; ordinary grids retain rating 2. Invalid burst actions must not silently become rating changes. Check B, R, U, Return and Escape alongside rating/navigation keys.

### 3. P2 — Embedded JPG export can export a sidecar

**Status:** Open. **Location:** `Actors/ExtractAndSaveJPGs.swift`, `Model/FullSizePreviewLoader.swift`.

Export calls the display-preview loader, which prefers a sidecar JPEG. It then decodes and re-encodes the selected image, even though the action promises the embedded JPEG.

**Fix:** Introduce a dedicated export dependency that returns camera-authored JPEG data. Do not use sidecars or lossy preview-cache fallback for embedded export. Preserve orientation and metadata when copying original bytes; retain existing exclusive destination creation. Keep display-preview behavior independent.

**Verify:** A RAW file with a deliberately different sidecar exports embedded content. Original JPEG bytes survive export. Missing embedded JPEG is an explicit failure. Existing destination files remain protected.

### 4. P2 — Thumbnail task identity and publication are incomplete

**Status:** Open. **Location:** `Views/ThumbnailComponents/ThumbnailImageView.swift`.

The task identity contains only the URL, so representation-size changes do not reload. A cancelled request can still publish to local state or the caller's image binding.

**Fix:** Define a request identity containing URL, target pixel size, style/purpose, and available source revision metadata. Snapshot the request when starting work. Clear stale presentation when switching sources and reject cancellation/stale identities before updating any state or binding.

**Verify:** Changing size for the same URL reloads. A slow old request cannot overwrite a newer image or clear its binding. Cancellation does not publish a result.

### 5. P2 — Saved sharpness restoration repeats expensive main-actor work

**Status:** Open. **Location:** `RawCullViewModel+Sharpness.loadPersistedScoringandSaliency`, `SharpnessScoringModel.scores.didSet`.

Each file linearly searches saved records. Each score insertion sorts the accumulated scores to recompute a percentile.

**Fix:** Index saved records by name once. Build score/saliency/AF dictionaries locally and publish each once. Compute normalization once per batch. Preserve source/signature validation and define duplicate-record handling explicitly.

**Verify:** Existing restoration tests still pass; compare large-catalog timings and main-thread traces before/after. No per-item percentile recomputation.

### 6. P2 — Grid caching still walks the catalog during view updates

**Status:** Open. **Location:** `Views/CullingGrid/CullingGridView.swift`, `CullingGridRenderCache.swift`.

Cache-key construction hashes complete membership on body evaluation; rendered groups and selection projections are rebuilt repeatedly. Unrated filtering also performs per-file record searches.

**Fix:** Own derived grid projections in a model with explicit source revisions. Recompute only when membership, ordering, filters or analysis semantics change. Use existing rating indexes for unrated checks. Keep selection-only changes independent of catalog reconstruction.

**Verify:** Regression tests for ordering/filter invalidation; Instruments evidence showing selection does not trigger full reconstruction. Avoid replacing correct invalidation with an incomplete cache key.

### 7. P2 — Metadata scan task admission is unbounded

**Status:** Open. **Location:** `Actors/ScanFiles.swift`.

One child task and one UI progress task are admitted per file before results are collected.

**Fix:** Use bounded task-group admission with a measured concurrency limit. Coalesce progress reporting. Preserve cancellation and catalog access for work still performing native I/O.

**Verify:** Instrument a synthetic large scan; assert maximum active workers and cancellation behavior. Preserve deterministic final sorting.

### 8. P2 — Preload gate blocks ready visible thumbnails

**Status:** Open. **Location:** `Actors/ThumbnailPreloadGate.swift`, `ScanAndCreateThumbnails.swift`.

Waiters are released at catalog completion rather than when their image becomes available.

**Fix:** Share per-file in-flight requests or notify per-file readiness. Retain duplicate-decode protection, cancellation handling and separation from AI workflows.

**Verify:** A visible early file appears before the final catalog item completes, with no duplicate decode or leaked continuation.

### 9. P2 — Unloaded persistence is treated as empty and writable

**Status:** Open. **Location:** `Model/ViewModels/CullingModel.swift`, `RawCullViewModel+Catalog.swift`.

The store starts empty and writable; it is loaded only after a nonempty catalog scan. Saved history can appear empty at startup, and callers can save before discovering existing/corrupt data.

**Fix:** Introduce explicit unloaded/loading/ready/failed state, load independently of catalog scanning, and block mutations until loading succeeds. Keep temporary/in-memory test stores explicit. Preserve damaged-store recovery and quit flushing; do not overwrite an unread store.

**Verify:** History is available without opening a photo catalog. Mutation before readiness is blocked. Missing, existing, corrupt, empty-catalog and quit-during-load paths are covered with isolated stores.

### 10. P2 — Recovery does not refresh derived presentation

**Status:** Open. **Location:** `Main/RawCullMainView.swift` persistence recovery actions.

Retry can replace savedFiles while ratingCache, tagged names, filtering and scoring presentation remain stale.

**Fix:** Route retry/reset through application-level recovery operations. After successful reload, rebuild ratings and scoring projections, reapply filters and reconcile selection. Failed recovery must preserve current error state and data.

**Verify:** Repair a failed store, retry, and verify saved rows, tiles, filters and copy selections agree immediately. Reset clears the same projections.

### 11. P2 — Existing records lose tagging-date updates

**Status:** Open; reproduced in an isolated probe. **Location:** `CullingModel.upsertRecord`.

Updating an existing record's rating ignores dateTagged. A scored-then-rated photo retains a nil date.

**Fix:** Update dateTagged when applying an explicit rating. Scoring-only updates must preserve existing tagging metadata. Keep explicit clearing/undo behavior coherent.

**Verify:** Scored-then-rated and re-rated records have tagging dates; scoring alone leaves nil untouched; rating-state clearing still clears the date.

### 12. P2 — Settings persistence errors are hidden

**Status:** Open. **Location:** `Model/ViewModels/SettingsViewModel.swift`, Settings views.

Save catches and logs errors, so callers cannot distinguish persistence success. Load failures similarly lack user-visible state.

**Fix:** Expose observable load/save failure state or a throwing/result API. Present errors and retry in Settings. Do not imply success after failure; preserve current edits. Distinguish absent settings from malformed/unreadable settings.

**Verify:** Isolated unwritable/malformed stores produce visible failure state. Successful retry clears errors and persists the intended values. Existing callers handle the chosen API consistently.

### 13. P2 — Settings sliders lack explicit accessible names

**Status:** Open. **Location:** `Views/Settings/SettingsSliderRow.swift`.

A sibling visual label does not explicitly name the slider.

**Fix:** Use a labeled Slider initializer or accessibilityLabel, plus a formatted accessibilityValue and suitable hint. Hide redundant visual labels from accessibility only when necessary.

**Verify:** VoiceOver announces each setting and its units/value; keyboard adjustment works without triggering photo navigation.

### 14. P2 — Important animations ignore Reduce Motion

**Status:** Open. **Location:** `RawCullMainView.startMemoryWarningFlash`, thumbnail hover and scrolling.

**Fix:** Read accessibilityReduceMotion at the consuming views. Replace perpetual flashing/scale motion with a stable warning or restrained nonmoving emphasis; disable animated programmatic scrolling when requested. Apply the policy consistently rather than removing all feedback.

**Verify:** Toggle Reduce Motion while the app is running; warnings remain understandable and photo navigation stays immediate.

### 15. P2 — Isolated thumbnail test helper uses production disk storage

**Status:** Open. **Location:** `RawCullTests/TestIsolationHelpers.swift`.

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
