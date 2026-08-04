# RawCull 3.0.0 AI-Preserving Stabilization Plan

## Scope and authority

This is a read-only implementation plan derived from RawCull 2.3.4 behavioral
requirements. It does not authorize merging, cherry-picking, or copying the
2.3.4 implementation into the AI code line.

Repository facts in this plan were inspected from local `main` and
`version-3.0.0` at commit `2857a6b3a095425b06bbe8c8f757e32f2cd07664`.
Those branches resolve to the same commit. No 3.0.0 tests were run while
creating this plan, and no claim below says otherwise.

The 3.0.0 architecture is authoritative. Preserve PhotoAIKit, Core AI model
resources, CLIP similarity and semantic search, Vision fallback, SAM 3 Deep
Review, typed similarity artifacts, model downloads and licence acceptance,
AI settings, diagnostics, and their tests. Reimplement accepted behavior in
that architecture; do not forward-merge `version-2.3.4`.

## Verified 3.0.0 facts

- `main` and `version-3.0.0` target macOS 27 and marketing version 3.0.0 for
  the application configurations. Their package graph includes PhotoAIKit and
  Apple Core AI model packages in addition to the shared 2.x dependencies.
- `ZoomViewportMath.actualPixelsScale` still returns `0.6 / fitScale`, and the
  current tests encode that behavior.
- `HistogramView` still has separate `.onChange` and `.task` loaders; its
  initial conversion failure calls `fatalError`.
- `DiskCacheManager` keys schema-v2 thumbnails from the standardized source
  path only. `ThumbnailLoader` still documents scan/grid competition and uses
  URL keys for grid memory-cache lookup.
- Similarity persistence is AI-native: `SimilarityArtifact` values carry
  backend descriptors and are stored per source/backend/pipeline by
  `PerFileAnalysisArtifactStore`. `SimilarityScoringModel` also owns semantic
  hydration/search, multiple generations, diagnostics, and Vision/CLIP
  backend selection.
- `SavedFilesView` still uses single-action `onTapGesture` rows. Image and
  comparison tiles intentionally combine single- and double-click gestures.
- `Smoke.xctestplan` does not select tags; the Makefile owns a long explicit
  AI-aware smoke allow-list. `RawCull.xctestplan` is parallelizable.
- The README already describes RawCull 3, macOS 27, PhotoAIKit, CLIP, SAM 3,
  model resources, and exact/revision package pins. Those facts must not be
  replaced with 2.3.4 documentation.

## Non-negotiable AI guardrails

1. Do not merge or cherry-pick the 2.3.4 branch.
2. Do not replace PhotoAIKit artifacts with `Data`-only Vision artifacts.
3. Do not change backend descriptors, artifact codecs, pipeline signatures,
   model identifiers, resource layouts, or licence keys without an explicit
   migration and backward-compatibility test.
4. Cache clearing must distinguish disposable thumbnails from similarity
   artifacts, semantic-search artifacts, subject masks, model downloads,
   licence acceptance, settings, ratings, and burst decisions.
5. Preserve CLIP-to-Vision fallback and backend-specific artifact separation.
6. Preserve latest-generation-wins and structured cancellation for image
   similarity, semantic hydration/search, grouping, ranking, and Deep Review.
7. Keep 3.0.0 metadata, macOS 27 settings, entitlements, packages, model
   notices, and release notes authoritative.
8. After each independent change, run its focused tests plus the AI smoke
   gate. Run the complete AI regression matrix before release.

## 2.3.4 requirement classification

| Item | 3.0.0 classification | Reason |
|---|---|---|
| 0 — reproducible baseline | Apply unchanged in behavior | Capture the AI branch and model/package inputs before edits |
| 1 — Actual Pixels | Apply unchanged in behavior | The same 60% mismatch is present; the fix is UI geometry, not AI replacement |
| 2 — histogram safety | Apply unchanged in behavior | The same crash and stale-publication paths are present |
| 3 — release gates | Adapt to AI architecture | 3.0.0 has additional AI suites and an explicit smoke manifest that must remain complete |
| 4 — thumbnail identity | Adapt to AI architecture | Source/representation identity is still needed, but thumbnail keys must not alter typed AI artifact identity |
| 5 — scan/grid contention | Adapt to AI architecture | The TODO remains; model download, inference, semantic hydration, and Deep Review add competing work |
| 6 — similarity persistence | Already resolved in design; verification and gap closure | The durable store is backend-aware and typed, but all terminal outcomes and AI data boundaries need proof |
| 7 — accessibility | Apply unchanged in behavior | Gesture inventory and missing row semantics remain; AI controls add scope |
| 8 — metadata/docs | Superseded by 3.0.0 values | Verify 3.0.0/macOS 27/AI facts; never copy 2.3.4 values |
| 9 — integrated regression | Adapt to AI architecture | Add backend/model/resource and migration combinations |
| 10 — release handoff | Apply with 3.0.0 artifacts | Freeze, sign, notarize, hash, and tag only the independently tested AI commit |

## Phase 0 — freeze the AI baseline

1. Work on a dedicated branch from the current `main`/`version-3.0.0` commit.
   Record the commit, Xcode/Swift/macOS versions, architecture, resolved-package
   checksum, model-manifest checksum, and ModelAssets notice checksum.
2. Record available model states: no models, valid DataComp CLIP, valid OpenAI
   CLIP, valid SAM 3, corrupt/incomplete model, unaccepted licence, and Vision
   fallback. Use disposable model directories and `UserDefaults` suites.
3. Run and save the existing smoke, full TSan, performance, Release build, and
   AI-specific suites before changing code. Record unique and concrete test
   counts. A pre-existing failure gets an owner and is not normalized away.
4. Snapshot 3.0.0 persistence fixtures for ratings/settings, saved files,
   backend-typed similarity artifacts, burst cache, semantic state, subject
   masks, model-download records, and licence acceptance.
5. Commit only the baseline ledger. Roll back this phase if it changes code,
   packages, project settings, models, or persistent data.

## Phase 1 — correct Actual Pixels without touching AI image selection

### Current paths

- `RawCull/Views/ZoomViews/ZoomOverlayView.swift`
- `RawCullTests/ZoomOverlayKeyActionTests.swift`
- zoom launch paths from normal, similarity, semantic-result, comparison, and
  Deep Review views

### Smallest safe implementation

1. Define Actual Pixels as one source-image pixel per display point before
   backing-scale conversion. Replace `0.6 / fitScale` with `1.0 / fitScale`.
2. Move or retain the math in a pure helper with finite, positive input guards,
   clamped focus offsets, and a centered fallback.
3. Do not change embedded/developed source selection, CLIP/SAM inputs, focus
   masks, semantic ordering, Deep Review recommendations, or model state.

### Verification and rollback

- Add landscape, portrait, fit-upscaled, aspect-mismatch, four-edge clamp,
  absent focus, and non-finite input cases.
- Manually launch Actual Pixels from every AI and non-AI entry point and verify
  the selected file/source does not change.
- Accept only finite transforms and consistent 1:1 behavior. Revert the phase
  if it changes backend selection, source selection, or AI result ordering.

## Phase 2 — make histogram loading recoverable and latest-wins

### Current paths

- `RawCull/Views/Histogram/HistogramView.swift`
- `RawCull/Views/FileViews/FileDetailView.swift`
- new focused `HistogramLoadingTests.swift`

### Smallest safe implementation

1. Replace the two loaders with one task keyed by image identity.
2. Clear bins for nil and conversion failure; log conversion failure without
   `fatalError`.
3. Calculate off the main actor through structured work, then publish only if
   the task is current and not cancelled.
4. Keep histogram work display-only. It must not write PhotoAIKit artifacts,
   semantic state, subject masks, sharpness data, or model resources.

### Verification and rollback

- Deterministically test nil clearing, conversion failure, success, and a
  controlled slow-A/fast-B supersession with and without TSan.
- Rapidly navigate Vision results, CLIP results, and Deep Review candidates.
- Revert if the change retains stale bins, blocks navigation, or changes any AI
  pipeline input or state.

## Phase 3 — repair gates while retaining complete AI coverage

### Current paths

- `Makefile`, `Smoke.xctestplan`, `RawCull.xctestplan`,
  `Performance.xctestplan`, `RawCullTests/TEST_ARCHITECTURE.md`
- all `RawCullTests`, especially AI integration, downloads, semantic search,
  Deep Review, migration, artifact-store, and diagnostics suites

### Smallest safe implementation

1. Inventory every smoke declaration and every Makefile allow-list entry.
   Prefer one tag selector only if Xcode 27 proves stable for all AI suites;
   otherwise keep one explicit manifest and add a test that detects drift.
2. Preserve mandatory smoke coverage for PhotoAIKit integration, both CLIP
   models, Vision fallback, semantic search, model validation/download/licence,
   Deep Review/SAM 3, typed artifact persistence/migration, and core culling.
3. Prove a temporary failing smoke test makes the command fail, then remove it.
4. Detect duplicated identifiers and unexplained count changes. Serialize only
   suites with documented shared model/resource or singleton state.

### Verification and rollback

- Run smoke, full TSan, performance, and exact-package Release builds.
- Require an AI smoke red/green sentinel and stable enumeration.
- Roll back any gate edit that omits an AI suite, executes it twice, mutates
  model resources, or permits a failing test to return success.

## Phase 4 — introduce thumbnail source and representation identity

### Current paths

- `RawCull/Actors/DiskCacheManager.swift`
- `RawCull/Actors/SharedMemoryCache.swift`
- `RawCull/Actors/RequestThumbnail.swift`
- `RawCull/Actors/ScanAndCreateThumbnails.swift`
- `RawCull/Actors/ThumbnailLoader.swift`
- `RawCull/Model/ViewModels/GridThumbnailViewModel.swift`
- normal/rated/similarity/semantic/Deep Review thumbnail consumers

### Smallest safe implementation

1. Create a RawCull-owned immutable thumbnail key containing standardized URL,
   available source size/modification metadata, purpose, requested pixel size,
   orientation policy, and a new thumbnail-only schema.
2. Use the same key across disk, memory, scan admission, grid, preview, and AI
   presentation paths. A missing metadata fingerprint bypasses reuse.
3. Migrate by cache miss or explicit disposal of old thumbnail schemas only.
   Do not reuse `PhotoAIKit.SourceFingerprint` as a thumbnail filename contract.
4. Do not change `SimilarityArtifactDescriptor`, backend descriptors,
   `SimilarityArtifactPipelineSignature`, subject-mask keys, or model-resource
   identity. Thumbnail invalidation must not clear AI artifacts.

### Verification and rollback

- Test same-path replacement, purpose/size separation, cancellation-safe atomic
  writes, corrupt JPEG recovery, old-schema clearing, and orientation.
- Add an independence test proving thumbnail-key changes do not change typed
  Vision/CLIP artifact or SAM subject-mask identities.
- Manually replace RAWs while semantic results and Deep Review data exist.
- Roll back if ratings, AI artifacts, masks, model downloads, or licence state
  are invalidated.

## Phase 5 — bound scan/grid/AI contention

### Current paths

- scan/request/loader/cache actors from Phase 4
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- `RawCull/Model/AIIntegration/DeepAIReviewFeature.swift`
- model download/resource services and diagnostics

### Smallest safe implementation

1. Instrument cold decodes, duplicate keys, coalesced waiters, cancellations,
   active/peak thumbnail work, inference starts, semantic hydration, model
   downloads, and time to first usable grid.
2. Measure fixed small/medium/large catalogs in normal grid, rated grid,
   similarity indexing, semantic search, and Deep Review states.
3. Prefer a typed request coalescer only if ownership and cancellation are
   clear. Otherwise gate only thumbnail grids for the actively preloading
   selected catalog. Never pause/cancel a user-requested model download or
   silently switch similarity backends to improve timing.
4. Keep scan, CLIP, SAM 3, semantic, and Deep Review cancellation independent.

### Verification and rollback

- Require no material duplicate cold decode, prompt cancellation, bounded
  concurrency, no continuation leaks, and unchanged AI outputs.
- Run TSan plus simultaneous scan/index/search/review/model-download scenarios.
- Roll back if coalescing crosses backend/purpose/source identity, cancellation
  ownership becomes ambiguous, or AI progress/result state becomes stale.

## Phase 6 — verify typed AI persistence and close only proven gaps

### Current paths

- `RawCull/Actors/PerFileAnalysisArtifactStore.swift`
- `RawCull/Actors/BurstAnalysisCache.swift`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- PhotoAIKit migration, semantic-search, integration, and diagnostics tests

### Required matrix

1. Relaunch with Vision artifacts, each CLIP backend, mixed backends, semantic
   artifacts, partial indexes, and legacy burst artifacts.
2. Add/change/remove/rename a source and replace bytes at the same path.
3. Cancel each generation before work, after partial commit, during semantic
   hydration/search, during ranking/grouping, and during persistence.
4. Force per-record persistence failure while retaining usable session results.
5. Switch CLIP models, disable CLIP, remove/corrupt a model, decline licence,
   and restore the model; verify documented fallback and artifact separation.
6. Clear thumbnail cache, similarity cache, subject-mask cache, and model
   resources independently. Ratings/settings/saved records/burst decisions must
   survive every unrelated clear.

### Acceptance and rollback

- Progress returns to idle for every terminal outcome; older generations never
  publish into newer backend/search state.
- No opaque artifact is decoded by the wrong backend or pipeline descriptor.
- Do not change production formats if existing coverage passes. Any migration
  must be versioned, reversible at the file boundary, and tested from fixtures.

## Phase 7 — bounded accessibility including AI controls

### Current paths

- Saved-file rows; normal/rated/comparison thumbnails; rating/source/focus and
  burst-review controls from the 2.3.4 inventory
- AI settings/model downloads, semantic-search views, Deep Review sheet, model
  status/error/licence controls

### Smallest safe implementation

1. Preserve all genuine single/double-click image gestures.
2. Convert SavedFiles single-action rows to native plain buttons without
   changing split-view selection, hover, or row-wide hit testing.
3. Add names, values, actions, enabled state, and selected traits. Hide only
   decorative duplicates.
4. Announce AI backend/model availability, download progress/failure, licence
   requirement, semantic-search state/count, Deep Review progress/confidence,
   and whether an action will use CLIP, Vision fallback, or SAM 3.

### Verification and rollback

- VoiceOver and keyboard-test every audited state, including missing/corrupt
  models and cancellation. Verify focus return after sheets and model prompts.
- Revert any change that alters click counts, selection, backend choice,
  licence consent, or destructive cache/model actions.

## Phase 8 — verify 3.0.0 metadata and AI documentation

1. Verify built Debug/Release values for 3.0.0, the chosen unused build number,
   macOS 27, arm64, bundle identifier, entitlements, and About. Do not copy
   2.3.4 build 231 automatically; confirm availability in App Store Connect.
2. Compare every README package row with the 3.0.0 `Package.resolved`, including
   revision-pinned PhotoAIKit/Core AI dependencies and transitive model tooling.
3. Verify ModelAssets manifests, notices, provenance, download destinations,
   licence text, and Managed Background Assets documentation.
4. Release notes must distinguish built-in Vision fallback from optional local
   CLIP/SAM 3 features and state model/storage/system requirements accurately.
5. Record known limitations, tested models/checksums, exact commit, minimum OS,
   signing/notarization state, and final artifact hash.

## Phase 9 — complete AI and compatibility regression

Run from a clean checkout in this order:

```bash
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
```

Then execute this model/backend matrix:

| State | Similarity | Semantic search | Deep Review | Required result |
|---|---|---|---|---|
| No downloaded model | Vision fallback | Unavailable with reason | Unavailable with reason | Core culling remains usable |
| Valid DataComp CLIP | DataComp CLIP | Available | Depends on SAM 3 | Correct descriptor and results |
| Valid OpenAI CLIP | OpenAI CLIP | Available | Depends on SAM 3 | No DataComp artifact reuse |
| Corrupt/incomplete CLIP | Documented Vision fallback | Unavailable | Unchanged | Diagnostic, no crash/data loss |
| Valid SAM 3 | Current similarity backend | As above | Available | Progress, masks, result, cancellation |
| Corrupt/missing SAM 3 | Unchanged | Unchanged | Unavailable with reason | No stale Deep Review result |
| Backend switch during work | New backend wins | New service wins | Independent | Old generation cannot publish |

Also verify upgrade fixtures, cache independence, real RAW replacement,
minimum/latest macOS 27, low/high-memory Apple Silicon, model download resume,
licence acceptance, VoiceOver, and clean-account installation. Any persistent
decision loss, backend confusion, stale async publication, hang, or TSan report
blocks release.

## Phase 10 — independent 3.0.0 release handoff

1. Freeze the exact green AI commit; do not merge 2.3.4 into it.
2. Archive with checked-in package/model manifests and no source edit after the
   final gates. Verify signing, hardened runtime, entitlements, model-resource
   access, notarization, stapling, Gatekeeper, clean install, and upgrade.
3. Verify App Store metadata/build-number availability before upload.
4. Hash the signed DMG, publish the hash, download it, and reproduce the hash.
5. Tag the exact tested commit as 3.0.0 and verify the tag target.
6. Retain the immutable 2.3.4 tag and artifacts as historical behavior and
   migration references; remove its active branch only after release evidence
   is preserved.

## Commit and rollback policy

Use one independently reviewable commit per phase. Never combine thumbnail
identity, typed AI persistence, package/model changes, or metadata in one
commit. A failed phase rolls back at its commit boundary, then reruns its
focused tests and every later completed phase. No red P0/AI gate is waived.
