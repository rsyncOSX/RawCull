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

## Current scan-time metadata behavior

RawCull already performs a useful single-pass metadata scan. For each supported
RAW file, `ScanFiles` asks RawParserKit for EXIF and MakerNote focus information
in the same per-file task. The resulting `FileItem` retains:

- File URL, name, size, and filesystem modification date.
- The precise EXIF capture date when available, including subseconds. The
  source UTC offset is applied to the absolute date and retained separately.
- Camera and lens names.
- Display-formatted shutter speed, focal length, aperture, and ISO.
- Numeric exposure time in seconds, focal length in millimetres, exposure
  compensation in EV, aperture, and ISO.
- RAW compression/type and size class.
- Pixel dimensions.
- A normalized AF focus point when RawParserKit can obtain one.

Burst analysis orders shots by capture date and uses it for time gaps.
Filesystem modification date is an explicit fallback. Boundary evidence
records when that fallback was used, and fallback timing receives a wider
tolerance than EXIF timing because copying or restoring files can change it.

Exposure comparisons use the numeric values. Small automatic-exposure
adjustments are retained as soft `exposureAdjustmentEV` evidence, while only
changes beyond the configured tolerances create an exposure boundary.

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

The current snapshot validation is intentionally strict and catalog-wide. A
file-count change, or a path, size, or modification-date change for any file,
invalidates the complete snapshot. This protects derived groups and rankings,
but it also prevents unchanged per-file embeddings and scores from being reused
after a catalog gains or changes one image. The source fingerprints already
carried by similarity artifacts make more incremental reuse possible.

## Completed follow-up work

### Preserve precise capture and numeric exposure metadata

RawParserKit, RawCullCore, and RawCull now carry precise capture time, source
UTC offset, exposure time, focal length, exposure compensation, aperture, and
ISO through the scan pipeline. Localized strings remain available for display.

Burst grouping now:

- Orders shots by effective capture time, with filename as a stable tie-breaker.
- Uses a two-second EXIF time-gap threshold and a lower-confidence ten-second
  filesystem-date fallback threshold.
- Compares shutter speed, aperture, ISO, and exposure compensation in EV with
  tolerances, instead of splitting on any string or ISO difference.
- Records the largest exposure adjustment and capture-time fallback provenance
  in boundary evidence.

Candidate ranking now uses numeric shutter speed and focal length as motion-risk
evidence and applies a graduated high-ISO noise-risk penalty. The grouping
algorithm version was advanced so older derived burst results are invalidated.

## Recommended follow-up work

The highest-value improvement is better use and persistence of compact data,
not collecting every EXIF field or making the initial catalog scan AI-heavy.

### 1. Separate per-file analysis artifacts from catalog-derived results

Introduce a source-fingerprint-keyed per-file cache for compact reusable work:

- Similarity artifacts.
- Sharpness score and any explanation data worth restoring.
- Saliency classification.
- Parsed capture metadata.
- Optional future quality signals.

Keep burst groups, adjacent-boundary evidence, rankings, and review state in a
catalog-level snapshot. When a catalog changes, reuse valid per-file artifacts
and recompute only affected ordering, boundaries, groups, and rankings.

The **Index Similarity** action should make successfully produced artifacts
durable without requiring the complete **Analyze Bursts** pipeline to finish.
Writes should remain atomic, and partial indexing should preserve successful
entries alongside failure diagnostics.

### 2. Reuse the existing CLIP artifacts in user-facing features

The existing image embeddings can support useful features without another
image-analysis pass:

- **Find Similar** from the selected image.
- Near-duplicate detection.
- Visual clusters beyond the current sequential burst grouping.
- Outlier detection within a burst or catalog.

These features should consume a typed RawCull accessor and PhotoAIKit's
comparator. They should not decode the cache JSON directly or calculate vector
distance using assumptions about a particular backend.

### 3. Add targeted visual quality signals only where they improve culling

Potential later signals include:

- Highlight clipping, crushed shadows, and subject exposure.
- Face and eye detection, including likely blinks or closed eyes.
- Motion-risk or motion-blur evidence.
- Alignment between the camera AF point and the detected salient subject.

Prefer computing these from an already decoded preview during burst analysis,
or only for likely finalists. Persist compact results with their algorithm and
configuration versions. Embedded-JPEG measurements are useful for relative
culling but should not be presented as raw-sensor measurements.

### 4. Keep low-value or expensive data out of the initial scan

Complete EXIF dumps, GPS, captions, SAM masks, an all-pairs distance matrix, and
full RAW histograms are not first-priority culling inputs. GPS and sidecar/XMP
metadata may later be useful for organization and workflow interoperability,
but they should be optional and purpose-driven.

Any expanded scan-time parsing should reuse the existing per-file metadata pass
and remain bounded. Preview decoding, model inference, and vendor-specific deep
MakerNote work should stay deferred so opening a catalog remains responsive.

## Suggested remaining implementation order

1. Split per-file reusable artifacts from catalog-derived burst state and make
   **Index Similarity** durable.
2. Expose a typed similarity-artifact accessor and add **Find Similar**,
   near-duplicate, cluster, or outlier features.
3. Measure culling benefit and processing cost before adding further visual
   quality signals.

Relevant implementation files:

- `RawCull/Actors/BurstAnalysisCache.swift`
- `RawCull/Model/AIIntegration/RawCullVisionSimilarityService.swift`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`
