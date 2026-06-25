# Burst Grouping Verification Report — RawCull

Date: 2026-06-25

## Scope

Verified the findings copied from the sibling `RawCullSAM3` project against the current RawCull source and its resolved `RawCullCore` 1.1.0 dependency.

RawCull uses Vision feature prints only and does not contain CLIP, SAM3 deep review, or the “Eye Detail” deep-review preset. Findings that depended exclusively on those features were removed. Findings shared by the burst grouping, ranking, cache, review queue, catalog lifecycle, and grid code were retained and rewritten for RawCull.

This was a static source verification. No production code was changed.

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

### 9. [P3] Large burst-cache JSON encoding and decoding runs on MainActor

Locations:

- `RawCull/Actors/BurstAnalysisCache.swift:118-155`

The cache actor performs file access itself but explicitly moves `JSONDecoder.decode` and `JSONEncoder.encode` to `MainActor`. Snapshots can contain all embedding blobs, scores, saliency data, groups, results, and review states for a catalog.

Impact:

- Large catalogs can block the UI while loading or saving the cache.
- Every review-state save re-encodes the complete snapshot on the main actor.

Recommendation: make the cache DTO boundary safely `Sendable`/nonisolated and serialize within the cache actor or another cancellable background context.

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
