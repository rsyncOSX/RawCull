# CLIP cache contents and reuse

RawCull's CLIP integration produces a reusable image embedding for each
successfully indexed image. The embedding is persisted as part of the burst
analysis cache when the complete **Analyze Bursts** pipeline finishes.

## CLIP similarity artifact

Each cached CLIP entry is a PhotoAIKit `SimilarityArtifact`. It contains:

- A normalized floating-point image embedding in the artifact payload.
- The embedding dimensions.
- The backend and model fingerprint.
- The representation format.
- Preprocessing, normalization, and configuration versions.
- The artifact schema version.
- A source fingerprint used to detect stale artifacts.

RawCull currently validates CLIP payloads by decoding them as an
`ImageEmbedding` and checking that the vector is non-empty and contains only
finite values. Artifact descriptors are also checked against the active model,
pipeline configuration, and source fingerprint before an artifact is reused.

The embedding can be reused for:

- Image-to-image similarity ranking.
- Nearest-neighbour search.
- Visual clustering and alternative grouping strategies.
- Near-duplicate detection.
- Finding visual outliers in a catalog or burst.

Code should normally use PhotoAIKit's distance comparator instead of making
assumptions about the payload or calculating distance directly. This preserves
the backend's compatibility checks and distance semantics.

The CLIP artifact does **not** contain captions, keywords, detected objects,
EXIF metadata, thumbnails, or original image pixels. Semantic text search would
also require a compatible text encoder that produces vectors in the same CLIP
embedding space. The current RawCull integration exposes image embeddings and
image-to-image comparison, but it does not expose a CLIP text-encoding path.

## Additional burst-analysis cache contents

The containing `BurstAnalysisCacheSnapshot` stores more than the CLIP artifact:

- Catalog path and cache/algorithm versions.
- Sharpness and similarity configuration signatures.
- Per-file UUID, path, file size, and modification date.
- Per-file CLIP or Vision similarity artifacts.
- Per-file sharpness scores.
- Per-file Vision saliency information, including the subject label and
  confidence when classification produced them.
- Computed burst groups.
- Boundary evidence between adjacent indexed images, including visual distance
  and the metadata-based boundary evidence used by grouping.
- Burst candidate rankings, component scores, confidence, reasons, cautions,
  recommended frame, and second-best frame.
- Persisted burst review-state snapshots.

This makes the sharpness score, subject classification, groups, adjacent-image
distances, and ranking evidence available for other RawCull features without
rerunning their analyses.

## Data that is not persisted in this cache

The burst-analysis cache does not store:

- The original image or a thumbnail.
- Complete EXIF metadata.
- A complete all-pairs similarity-distance matrix.
- Distances from the most recently selected similarity anchor. Those are
  runtime state and can be recomputed from the embeddings.
- Detailed sharpness breakdowns and focus evidence. Only the final sharpness
  score and saliency information are restored from this cache.
- SAM masks. Subject masks use a separate cache.
- CLIP indexing failure details as part of the snapshot.

Only adjacent visual distances used by burst grouping are retained in
`boundaryEvidence`; arbitrary pairwise distances are calculated on demand.

## Persistence behavior

The **Index Similarity** action calls `SimilarityScoringModel.indexFiles` and
creates or refreshes embeddings in memory. It does not itself save a burst
analysis snapshot to disk. Those embeddings remain available during the current
loaded session but are not made durable by that action alone.

The complete **Analyze Bursts** pipeline:

1. Loads an existing compatible cache when possible.
2. Scores sharpness when scores are missing.
3. Indexes similarity when artifacts are missing.
4. Groups images into bursts.
5. Ranks burst candidates.
6. Writes the complete snapshot to disk.

The cache is stored as JSON under:

```text
~/Library/Application Support/RawCull/BurstAnalysis/
```

Each filename is derived from the catalog path. `Data` payloads, including the
serialized embedding payload, are JSON encoded rather than stored as separate
binary files.

## Cache validity and integration guidance

RawCull only loads a snapshot when its schema, algorithms, catalog path,
thumbnail settings, sharpness signature, similarity signature, backend/model
descriptors, and artifact schema still match. The catalog file count must also
match, and every file must have the same path, size, and modification date.
Groups and derived results are additionally checked to ensure they reference
files with valid similarity artifacts.

Consequently, features should not treat the JSON format as a permanent public
database schema or bypass these validity checks. Inside RawCull, the preferred
approach is to expose a typed, read-only accessor over the loaded snapshot or
`SimilarityScoringModel.embeddings`, keyed by stable file identity or path.
This lets new features reuse embeddings and other evidence while retaining the
existing invalidation and compatibility rules.

Relevant implementation files:

- `RawCull/Actors/BurstAnalysisCache.swift`
- `RawCull/Model/AIIntegration/RawCullVisionSimilarityService.swift`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`
