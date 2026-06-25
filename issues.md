# Burst Grouping Verification Report — RawCull

Date: 2026-06-25

## Scope

Verified the findings copied from the sibling `RawCullSAM3` project against the current RawCull source and its resolved `RawCullCore` 1.1.0 dependency.

RawCull uses Vision feature prints only and does not contain CLIP, SAM3 deep review, or the “Eye Detail” deep-review preset. Findings that depended exclusively on those features were removed. Findings shared by the burst grouping, ranking, cache, review queue, catalog lifecycle, and grid code were retained and rewritten for RawCull.

This was a static source verification. No production code was changed.

## Recommended closure order

Close the findings in this order because several later fixes depend on stable analysis ownership and identity:

1. Issues 1 and 2 together — establish one catalog-scoped analysis lifecycle.
2. Issues 3 and 8 together — define the cache signature and immutable analysis scope.
3. Issue 4 — restore review state by group membership after regrouping.
4. Issue 5 — remove singleton groups from review semantics.
5. Issue 6 — make embedding cancellation structured.
6. Issue 7 — make render-cache invalidation complete.
7. Issue 9 — move cache serialization off `MainActor`.

After each step, run the focused tests. After each priority group, run `make test-smoke`; after all P1/P2 fixes, run `make test-full`.

## Applicable findings

### 1. [P1] The stored burst-analysis task is not the task that performs the analysis

Locations:

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:25-75`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:405-417`

`analyzeBursts()` cancels `burstAnalysisTask`, then stores an empty `Task {}`. The actual analysis continues in the task that called `analyzeBursts()`.

Consequently, `clearLoadedBurstAnalysisForReindex()` cancels only the empty placeholder, not the active cache load, sharpness scoring, similarity indexing, grouping, ranking, or cache save. The cancellation guards also inspect the caller task rather than the stored placeholder.

Impact:

- Reanalysis can overlap a previous run.
- Clearing or reindexing can be followed by state and cache writes from the previous run.
- A cancelled exit can leave `burstAnalysisProgress` on a running step.

Recommendation: make one owned task execute the complete pipeline, add an analysis generation and catalog identity check before state commits, and clear task/progress state in a cancellation-safe cleanup path.

Closure steps:

1. Split the current method into an owner and a private pipeline, for example `analyzeBursts()` plus `runBurstAnalysis(catalog:files:generation:)`.
2. Increment an `@ObservationIgnored` analysis generation whenever analysis starts, is cancelled, is cleared, or the catalog changes.
3. Create exactly one task containing the complete pipeline, store that task in `burstAnalysisTask`, and have `analyzeBursts()` await its value. Propagate cancellation from the calling task to the owned task.
4. Before every state commit and cache save, verify all three conditions: the task is not cancelled, its generation is current, and `selectedSource?.url` still matches the captured catalog.
5. Put task-handle and progress cleanup in one cancellation-safe completion path. Only the current generation may clear the shared progress/task state.
6. Add narrow injectable collaborators for tests—at minimum cache load/save and long-running scoring/indexing gates—so tests can suspend and release stages without real RAW decoding or `Task.sleep`.
7. Add Swift Testing coverage that starts analysis A, starts or clears analysis B, releases A, and verifies A cannot change results, progress, or cache contents.

Done when:

- `burstAnalysisTask` is the task executing the pipeline, not a placeholder.
- Cancelling, clearing, or replacing an analysis prevents every later state and cache write from the old generation.
- `burstAnalysisProgress.isRunning` is false after success, cancellation, early return, and failure.

### 2. [P1] Catalog switching does not reset all burst-analysis state or cancel the analysis pipeline

Locations:

- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:9-76`
- `RawCull/Model/ViewModels/RawCullViewModel.swift:141-149,198`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:25-75`

`cancelCatalogLoad()` resets the sharpness and similarity models, but it does not cancel or reset:

- `burstAnalysisTask`
- `burstAnalysisProgress`
- `burstAnalysisResults`
- `burstReviewStates`
- `activeBurstComparisonGroupID`
- `lastBurstUndoEntry`
- `comparisonFileIDs`

The sharpness and similarity models cancel their own work, but the outer `analyzeBursts()` caller remains active and can continue into later pipeline stages because it was not cancelled.

Impact:

- Review counts and results can temporarily describe the previous catalog.
- An old analysis can continue grouping, ranking, or saving after a new catalog is selected.
- Integer group IDs can associate previous-catalog review state with unrelated groups.

Recommendation: use one catalog-scoped reset/cancellation method and require the selected catalog identity and analysis generation to match before applying or saving results.

Closure steps:

1. Add a single `cancelAndResetBurstAnalysis()` method on `RawCullViewModel`.
2. In that method, cancel the owned analysis task, invalidate its generation, reset progress/results/review states/filter/comparison/undo state, cancel sharpness work, and reset similarity work.
3. Call this method from `cancelCatalogLoad()` before releasing the old security-scoped URL and from any path that clears the selected catalog.
4. Keep the catalog URL captured by the analysis and use the Issue 1 identity guard before applying cached data, rankings, groups, or cache saves.
5. Ensure old catalog tasks cannot write a cache for the newly selected catalog; cache operations must always use the captured catalog URL and validated generation.
6. Add an isolated `@MainActor` test that suspends analysis for catalog A, switches to catalog B, releases A, and verifies all burst state remains empty or belongs only to B.
7. Extend the existing security-scope cancellation tests to assert burst state is reset when catalog loading is cancelled.

Done when:

- Switching or closing catalogs immediately clears all burst-specific UI and model state.
- Work started for catalog A cannot publish or save after catalog B becomes active.
- The catalog-switch regression test passes without timing sleeps.

### 3. [P1] The burst cache does not include burst sensitivity or a complete similarity signature

Locations:

- `RawCull/Actors/BurstAnalysisCache.swift:4-18`
- `RawCull/Actors/BurstAnalysisCache.swift:118-190`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:31-42`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift:305-322`

Cache validity includes file metadata, the `RawCullCore` grouping algorithm version, thumbnail size, and the sharpness signature. It does not include:

- `SimilarityScoringModel.burstSensitivity`
- the Vision feature-print request revision
- a version for the thumbnail extraction and embedding pipeline
- other grouping configuration values beyond the dependency’s broad algorithm version

`analyzeBursts()` returns immediately on a valid cache hit, so the current sensitivity is not reapplied.

Impact:

- Changing burst sensitivity can appear to work during live regrouping but be replaced by old cached groups on the next load or Analyze Bursts action.
- Changes to embedding generation can silently reuse incompatible or stale embeddings unless another schema/version is manually bumped.

Recommendation: persist and validate a complete similarity/grouping signature and increment the cache schema when adding it.

Closure steps:

1. Introduce a Codable, Equatable, Sendable `BurstSimilaritySignature` value.
2. Include at least the burst sensitivity, Vision feature-print revision, embedding thumbnail size, embedding/extraction pipeline version, and all grouping configuration values that affect boundaries.
3. Store the signature in `BurstAnalysisCacheSnapshot` and require exact equality in `BurstAnalysisCache.isValid`.
4. Centralize signature creation in `SimilarityScoringModel` or `RawCullViewModel` so cache load and save cannot construct it differently.
5. Increment `BurstAnalysisCache.schemaVersion`; allow old snapshots to fail validation and be recomputed rather than adding a compatibility path unless preserving old caches is a product requirement.
6. Decide whether live sensitivity changes should immediately persist regrouped results. Prefer saving the regrouped snapshot after successful ranking so the next launch matches the visible grouping.
7. Add parameterized cache-validity tests changing one signature field at a time and expecting a cache miss; include a control case where an identical signature loads successfully.

Done when:

- A cache created at one sensitivity is never accepted at another sensitivity.
- Any embedding or grouping behavior change has an explicit version field to bump.
- Cache signature tests cover every behavior-affecting field.

### 4. [P1] Review states can be reassigned to different bursts after live regrouping

Locations:

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:91-98`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:298-310`
- `RawCullCore/BurstGroupingEngine.swift:85-93` in resolved package 1.1.0

`RawCullCore` regenerates group IDs from array offsets whenever groups are rebuilt. `reGroupBursts()` then ranks the new groups while passing the existing `burstReviewStates` dictionary keyed by those offsets.

Impact:

- Reviewed, Deferred, Needs Review, Decision Applied, or Manual Winner state can move to a different membership after sensitivity changes.
- Cache loading already restores states by `BurstGroupSignature`, but live regrouping bypasses that protection.

Recommendation: snapshot review state by `BurstGroupSignature` before regrouping and restore it by membership signature afterward. Treat integer group IDs as transient.

Closure steps:

1. Before calling `groupBursts`, build `[BurstGroupSignature: BurstReviewState]` from the current groups, current files, selected catalog, and `burstReviewStates`.
2. Regroup using the current sensitivity.
3. Rebuild `burstReviewStates` for the new groups by matching each new membership signature against the saved signature dictionary.
4. Discard states whose membership no longer exists; do not fall back to matching integer IDs.
5. Recompute rankings only after the restored review-state dictionary is ready.
6. Reapply persisted manual winner overrides after ranking, since those are already membership-based and may intentionally supersede the restored algorithm/review state.
7. Save the regrouped analysis using the immutable analysis scope introduced for Issue 8.
8. Add tests for unchanged membership with changed group ID, changed membership with reused group ID, split groups, merged groups, and reordered groups.

Done when:

- Review state follows exact catalog-relative membership through regrouping.
- Reused integer group IDs never transfer state to different members.
- Split or merged groups receive no stale state unless their exact signature existed before regrouping.

### 5. [P2] Singleton groups pollute review queues but have no group review UI

Locations:

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:192-201,298-310`
- `RawCull/Model/ViewModels/BurstReviewQueueModels.swift:21-76`
- `RawCull/Views/CullingGrid/CullingGridView.swift:405-427`
- `RawCullCore/BurstGroupingEngine.swift:23-24,85-93` in resolved package 1.1.0
- `RawCullCore/BurstRankingEngine.swift:13-23,74-105` in resolved package 1.1.0

The grouping engine emits isolated images as one-file groups. The ranking engine creates a result for every group, and the review policy can classify singleton results as Needs Review. The grid deliberately hides the group header and review actions for groups containing only one visible file.

Impact:

- Needs Review can include ordinary isolated photos.
- Queue items can be displayed without controls to review, defer, or mark them reviewed.
- Queue counts can substantially overstate actual bursts.

Recommendation: exclude groups with fewer than two members from burst ranking and review queues, or add explicit singleton behavior and UI.

Closure steps:

1. Adopt one product rule: a reviewable burst contains at least two files. Keep singleton groups in `burstGroups` only if they are needed to preserve grid ordering.
2. Filter singleton groups before calling `BurstRankingEngine.rank`, or filter their results immediately afterward so `burstAnalysisResults` represents reviewable bursts only.
3. Make `burstReviewQueueCounts` and `filteredBurstGroupsForReviewQueue` operate on the same reviewable-group definition.
4. Keep singleton photos visible in the grid as ordinary images, without a burst header or burst keyboard actions.
5. Ensure selection and zoom navigation still include singleton photos.
6. Add tests showing a singleton produces no review result/count, mixed singleton and multi-file groups count only the multi-file groups, and `.all` still displays every photo.

Done when:

- Needs Review, Deferred, and Reviewed counts include only groups with two or more members.
- Every item shown by a review filter has visible review controls.
- Singleton images remain accessible in the culling grid.

### 6. [P2] Similarity cancellation does not cancel detached per-file embedding workers

Locations:

- `RawCull/Model/ViewModels/SimilarityScoringModel.swift:108-195`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift:380-405`

The structured indexing task group calls `computeEmbedding()`, which immediately creates an unstructured `Task.detached`. Cancelling the group child does not propagate cancellation into that detached worker.

Impact:

- Cancel can clear indexing UI while RAW thumbnail decoding and Vision inference continue.
- Starting another index can overlap expensive work with the cancelled pass.
- Results are discarded, but CPU, memory, and decoder resources remain occupied until workers finish.

Recommendation: remove the nested detached task and execute cancellable work directly in the structured child task, with cancellation checks around decode and Vision inference.

Closure steps:

1. Remove the `Task.detached` created inside `computeEmbedding`.
2. Mark the CPU-bound embedding function `@concurrent nonisolated` so it leaves `MainActor` while remaining part of the calling task’s structured cancellation tree.
3. Add `Task.checkCancellation()` or equivalent guards before decode, after asynchronous RAW thumbnail extraction, before Vision inference, and before archiving the result.
4. Keep the existing bounded task group as the sole owner of per-file workers.
5. On cancellation, call `group.cancelAll()`, stop adding replacement tasks, and do not merge partial local embeddings unless partial-result retention is explicitly desired and tested.
6. Preserve indexing-state cleanup in `defer`, but guard shared state updates so an older indexing generation cannot clear progress for a newer run.
7. Add a test embedding implementation that suspends at a deterministic gate; cancel indexing and verify all workers observe cancellation and no embeddings are committed afterward.

Done when:

- There is no unstructured task inside the per-file indexing path.
- Cancelling indexing stops workers cooperatively and prevents late commits.
- Starting a new indexing pass cannot have its progress cleared by the cancelled pass.

### 7. [P2] Grid cache invalidation can leave stale membership and best-frame labels

Locations:

- `RawCull/Views/CullingGrid/CullingGridRenderCache.swift:9-53`
- `RawCull/Views/CullingGrid/CullingGridRenderCache.swift:61-103`
- `RawCull/Views/CullingGrid/CullingGridView.swift:589-610`

The cache key hashes:

- each group ID and member count, but not member IDs
- file count plus first and last ID, but not the complete visible file set
- score count, but not score values or `maxScore`

It does include recommended IDs and review states, which is slightly stronger than the sibling report described, but the remaining omissions still allow stale cache reuse.

Impact:

- Regrouping can change members without changing group/member counts.
- Filtering can replace middle files while preserving count and endpoints.
- Recalculation with the same number of scores can leave stale best-frame names or percentages.

Recommendation: key the cache with deterministic signatures of all group member IDs, visible file IDs, relevant score values or a score-generation token, and `maxScore`.

Closure steps:

1. Replace count/endpoint-only fields with deterministic value signatures for the complete ordered visible file IDs and each group’s complete ordered member IDs.
2. Include every result field used by `rebuild`, currently the recommended file ID and review state.
3. Add a sharpness revision counter to `SharpnessScoringModel` that increments whenever scores or `maxScore` are replaced, reset, or recalibrated; use that revision in the cache key. This avoids hashing every score during SwiftUI body evaluation.
4. Include the score revision and `maxScore` in `CullingGridRenderCacheKey`.
5. Keep key creation pure and inexpensive; do not perform image or scoring work from the SwiftUI view.
6. Add unit tests comparing keys where only a middle visible file, a group member, a score revision, `maxScore`, recommended ID, or review state changes.
7. Add rebuild tests verifying the expected visible membership, best filename, percentage, and manual-winner label after each invalidation.

Done when:

- Every input consumed by `CullingGridRenderCache.rebuild` is represented directly or by a reliable revision token in the key.
- Changing middle membership or score values triggers exactly one rebuild.
- Existing selection, scrolling, and review-filter behavior remains unchanged.

### 8. [P2] Saving review state can overwrite the cache with a different analysis scope

Locations:

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:272-296`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:357-386`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:419-451`

Review-state persistence rebuilds the snapshot using the current `burstAnalysisTargetFiles`. That target changes with selected thumbnails and star filters, while the current groups, results, and embeddings can still represent the scope used by the previous analysis.

Impact:

- Marking a group after changing selection or filtering can replace a valid full-catalog cache with a filtered manifest while retaining full-scope groups/results.
- The next full-catalog load rejects the cache and recomputes unnecessarily.
- A later matching filtered scope can accept a snapshot containing groups whose members are absent from its file manifest.

Recommendation: retain the immutable file scope/signature of the completed analysis and use it for later review-state saves.

Closure steps:

1. Add an `@ObservationIgnored` completed-analysis context containing the captured catalog URL, ordered file IDs/paths, similarity signature, and analysis generation.
2. Set this context only after a cache snapshot is successfully applied or a fresh analysis reaches the completed ranking stage.
3. Clear the context during catalog reset, reindex, or analysis invalidation.
4. Change review-state persistence to resolve files from the completed context instead of recomputing `burstAnalysisTargetFiles`.
5. Before saving, verify every current group member and result belongs to that completed scope; if not, skip the save and require a new analysis rather than writing a mixed snapshot.
6. Coalesce rapid review-state changes into one pending cache save, and cancel that save when the analysis context becomes invalid.
7. Add tests that analyze the full catalog, change selection or star filters, persist a review state, and verify the cache manifest and group membership remain full-scope.
8. Add the inverse test for an intentionally selected-subset analysis and verify later UI filter changes do not broaden or shrink its saved scope.

Done when:

- Review-state saves always use the exact scope that produced the current groups/results.
- UI selection and rating-filter changes cannot alter the cache manifest.
- No saved snapshot contains group members absent from its file manifest.

### 9. [P3] Large burst-cache JSON encoding and decoding runs on MainActor

Locations:

- `RawCull/Actors/BurstAnalysisCache.swift:118-155`

The cache actor performs file access itself but explicitly moves `JSONDecoder.decode` and `JSONEncoder.encode` to `MainActor`. Snapshots can contain all embedding blobs, scores, saliency data, groups, results, and review states for a catalog.

Impact:

- Large catalogs can block the UI while loading or saving the cache.
- Every review-state save re-encodes the complete snapshot on the main actor.

Recommendation: make the cache DTO boundary safely `Sendable`/nonisolated and serialize within the cache actor or another cancellable background context.

Closure steps:

1. Declare cache DTOs and signatures `nonisolated` and `Sendable` where their stored members allow compiler-checked conformance.
2. Propagate `Sendable` conformance to local value types used by the snapshot. Do not use `@unchecked Sendable` or `@preconcurrency` to bypass diagnostics.
3. Remove `MainActor.run` around `JSONDecoder.decode` and `JSONEncoder.encode`; perform serialization inside `BurstAnalysisCache` actor isolation.
4. Add cancellation checks before reading, after decoding, before encoding, and before the atomic write where the calling workflow can be cancelled.
5. Keep atomic file replacement and the existing per-catalog cache location.
6. Consider a review-state-only persistence format only if profiling still shows full-snapshot writes are expensive after serialization leaves the main actor.
7. Add a large synthetic snapshot test that round-trips embeddings, scores, groups, and review states from an isolated temporary directory.
8. Structure encode/decode as `nonisolated` helpers and exercise them from a detached test task; use compiler isolation checks plus Instruments to verify the production path does not return to `MainActor`.
9. Profile one realistically large catalog before and after the change; close the performance issue only when the main-thread stall is absent or materially reduced.

Done when:

- Cache encode/decode has no `MainActor.run`.
- Swift 6 strict-concurrency compilation succeeds with checked `Sendable` boundaries.
- Round-trip tests pass in parallel with isolated temporary cache directories.
- A large-cache profile no longer attributes JSON serialization time to the main thread.

## Findings from RawCullSAM3 that do not apply to RawCull

The following original findings were excluded:

1. Per-image CLIP fallback creates mixed embeddings — RawCull has no CLIP backend or mixed-backend fallback.
2. Deep-AI results use unstable group IDs — RawCull has no SAM3/deep-review model or result store.
3. “Eye Detail” is identical to “Head / Face” — RawCull has no deep-review preset with those options.

CLIP and deep-AI portions of the original cache and catalog-lifecycle findings were also removed while retaining the RawCull-relevant portions.

## Missing regression coverage

Add tests for:

- cancelling an active analysis and proving no later state or cache mutation occurs
- switching catalogs during burst analysis
- cache invalidation after sensitivity or embedding-version changes
- review-state restoration after live regrouping by membership signature
- singleton exclusion from review counts and queues
- complete render-cache invalidation when middle members, score values, or `maxScore` change
- review-state persistence after changing selection or rating filters following analysis
- cache serialization staying off `MainActor`

## Final verification before closing all findings

1. Run the focused burst/cache/grid test files while iterating.
2. Run `make test-smoke`.
3. Run `make test-full` with Thread Sanitizer.
4. Run `make debug` and manually verify:
   - cancel and restart Analyze Bursts
   - switch catalogs during scoring, indexing, grouping, and cache saving
   - change burst sensitivity, relaunch, and confirm grouping persists
   - change review state after selection and rating-filter changes
   - inspect singleton photos under every review filter
   - rescore and confirm best-frame labels and percentages refresh
5. Profile cache load/save with a large catalog and verify JSON work is not blocking `MainActor`.
6. Update each finding with the implementing commit and test names, then mark it closed only after its “Done when” conditions pass.
