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
- Camera and lens names.
- Display-formatted shutter speed, focal length, aperture, and ISO.
- Numeric aperture and ISO values.
- RAW compression/type and size class.
- Pixel dimensions.
- A normalized AF focus point when RawParserKit can obtain one.

There are two important limitations in the current handoff:

- RawParserKit reads EXIF `DateTimeOriginal` into its `capturedAt` value, but
  RawCull does not copy that value into `ExifMetadata` or `FileItem`. Burst
  grouping therefore uses the filesystem modification date as its capture-time
  proxy. Copying, restoring, or otherwise touching files can make that proxy
  inaccurate.
- Shutter speed and focal length reach RawCull as display strings. Burst
  grouping parses the focal-length string and treats any shutter-string or ISO
  difference as an exposure change. Small automatic-exposure adjustments can
  therefore split a genuine burst.

The capture timestamp exposed in the future should be a machine-readable,
precise value rather than only a localized display string. Preserve EXIF
subseconds and offset/time-zone information when available. A filesystem
modification date remains a useful fallback, but its provenance should be known
so grouping can treat it as lower-confidence evidence.

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

## Recommended follow-up work

The highest-value improvement is better use and persistence of compact data,
not collecting every EXIF field or making the initial catalog scan AI-heavy.

### 1. Preserve precise capture and numeric exposure metadata

Extend the RawParserKit-to-RawCull handoff and the RawCullCore models with
optional machine-readable values for:

- Capture date, including subseconds and UTC offset when present.
- Exposure time in seconds.
- Focal length in millimetres.
- Exposure compensation in EV.
- Aperture and ISO, retaining the numeric values already available.

Use capture date for shot ordering and burst time gaps, with filesystem
modification date as an explicit fallback. Continue deriving localized strings
only for presentation.

Update burst grouping to compare numeric exposure values with tolerances. An
ordinary small auto-exposure change should normally be soft boundary evidence,
not an unconditional burst split. Numeric shutter speed can also inform
candidate ranking as motion-risk evidence, while ISO can inform noise risk.

### 2. Separate per-file analysis artifacts from catalog-derived results

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

### 3. Reuse the existing CLIP artifacts in user-facing features

The existing image embeddings can support useful features without another
image-analysis pass:

- **Find Similar** from the selected image.
- Near-duplicate detection.
- Visual clusters beyond the current sequential burst grouping.
- Outlier detection within a burst or catalog.

These features should consume a typed RawCull accessor and PhotoAIKit's
comparator. They should not decode the cache JSON directly or calculate vector
distance using assumptions about a particular backend.

### 4. Add targeted visual quality signals only where they improve culling

Potential later signals include:

- Highlight clipping, crushed shadows, and subject exposure.
- Face and eye detection, including likely blinks or closed eyes.
- Motion-risk or motion-blur evidence.
- Alignment between the camera AF point and the detected salient subject.

Prefer computing these from an already decoded preview during burst analysis,
or only for likely finalists. Persist compact results with their algorithm and
configuration versions. Embedded-JPEG measurements are useful for relative
culling but should not be presented as raw-sensor measurements.

### 5. Keep low-value or expensive data out of the initial scan

Complete EXIF dumps, GPS, captions, SAM masks, an all-pairs distance matrix, and
full RAW histograms are not first-priority culling inputs. GPS and sidecar/XMP
metadata may later be useful for organization and workflow interoperability,
but they should be optional and purpose-driven.

Any expanded scan-time parsing should reuse the existing per-file metadata pass
and remain bounded. Preview decoding, model inference, and vendor-specific deep
MakerNote work should stay deferred so opening a catalog remains responsive.

## Suggested implementation order

1. Add precise capture date and numeric exposure/focal-length values across
   RawParserKit, RawCullCore, and RawCull.
2. Add tests for capture-date fallback, ordering, and tolerant burst boundaries.
3. Split per-file reusable artifacts from catalog-derived burst state and make
   **Index Similarity** durable.
4. Expose a typed similarity-artifact accessor and add **Find Similar**,
   near-duplicate, cluster, or outlier features.
5. Measure culling benefit and processing cost before adding further visual
   quality signals.

Relevant implementation files:

- `RawCull/Actors/BurstAnalysisCache.swift`
- `RawCull/Model/AIIntegration/RawCullVisionSimilarityService.swift`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`
