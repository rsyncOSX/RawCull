# CLIP architecture and enhancement plan

This document describes RawCull's current CLIP integration, the boundary
between RawCull and PhotoAIKit, and the implementation plan for durable
similarity indexing and semantic text search.

CLIP is a dual image-and-text encoder, not a generative language model. It maps
images and short text descriptions into the same embedding space. RawCull can
therefore index a photograph once and later rank it against either another
image or a text query without decoding and analysing that photograph again.

The initial semantic-search feature remains entirely on-device. It does not
require captions, a cloud service, an LLM, another CLIP checkpoint, or model
retraining.

## Current implementation status

| Capability | Status | Notes |
| --- | --- | --- |
| CLIP image embedding generation | Implemented | PhotoAIKit produces descriptor-complete `SimilarityArtifact` values. |
| Vision feature-print fallback | Implemented | Used when CLIP is unavailable; Vision vectors cannot be searched with CLIP text. |
| Image-to-image comparison | Implemented | RawCull delegates compatibility checks and distance semantics to the active PhotoAIKit backend. |
| Same-session artifact reuse | Implemented | `SimilarityScoringModel.embeddings` reuses current artifacts while the catalog remains loaded. |
| Persistence after **Analyze Bursts** | Implemented | Embeddings are included in the catalog-wide `BurstAnalysisCacheSnapshot`. |
| Source-fingerprint validation | Implemented | A stale artifact is rejected when its source or backend descriptor no longer matches. |
| Durable per-file artifact cache | Not implemented | Reusable artifacts are still coupled to the catalog-wide burst snapshot. |
| Durable **Index Similarity** action | Not implemented | The action updates in-memory state but does not write artifacts to disk. |
| CLIP text encoding | Not implemented | The model bundle contains the tokenizer and `text_embeds` output, but no Swift text-query API is exposed. |
| Semantic text-to-image search | Not implemented | RawCull has no text-query state, catalog ranking pipeline, or search UI. |

The presence of `SourceFingerprint` in a `SimilarityArtifact` is an important
prerequisite for a per-file cache, but it is not itself a cache. Likewise, a
catalog snapshot containing embeddings is persistent, but it does not provide
incremental reuse when the catalog changes.

## Ownership boundary

PhotoAIKit is a package loaded into the RawCull process; it is not a remote
service. The code still needs a clear package boundary so model-specific
details do not leak into the application.

### PhotoAIKit owns model-specific operations

PhotoAIKit should own:

- Model-bundle validation and provider construction.
- The CLIP tokenizer shipped with the selected model.
- Token IDs, attention masks, sequence length, padding, truncation, and static
  model-input shapes.
- Core AI inference and model input/output names.
- Extraction and validation of `image_embeds` and `text_embeds`.
- Embedding dimensions, normalization, model fingerprints, and configuration
  versions.
- Compatibility checks and the primitive distance or similarity calculation.
- Typed errors for invalid resources, input, model output, and incompatible
  embeddings.

RawCull should not directly interpret tokenizer files, `MLMultiArray` outputs,
or PhotoAIKit artifact payloads. Those are backend implementation details that
may change with a new model export.

### RawCull owns application behavior

RawCull should own:

- RAW preview decoding and source admission.
- Persistent per-file artifact storage and catalog-to-artifact lookup.
- Indexing orchestration, progress, cancellation, retry presentation, and
  diagnostics.
- Search query state, debounce, prompt policy, result ranking, filters, and UI.
- The policy for incomplete catalogs and failed image artifacts.
- Burst grouping, culling rules, review state, and other catalog-derived data.
- Product-level performance and retrieval-quality evaluation.

The same split already exists for image similarity: RawCull iterates over the
catalog and applies culling policy, while PhotoAIKit validates and compares the
artifacts. Text search should follow that pattern.

### Image-to-text comparison ownership

The comparison has two layers:

1. PhotoAIKit validates that a text embedding and image artifact share the same
   CLIP model, dimensions, representation, preprocessing, normalization, and
   configuration, then returns a primitive score or distance.
2. RawCull calls that operation for eligible catalog images, handles
   cancellation and failures, combines prompt variants if enabled, and sorts
   the results.

Consequently, the neural inference and comparison primitive belong in
PhotoAIKit, while catalog-wide ranking belongs in RawCull.

## Current image-artifact behavior

Each CLIP entry is a PhotoAIKit `SimilarityArtifact` containing:

- A normalized floating-point image embedding in the payload.
- Embedding dimensions.
- The backend and model fingerprint.
- The representation format.
- Preprocessing, normalization, and configuration versions.
- The artifact schema version.
- A source fingerprint used to detect stale work.

RawCull validates CLIP payloads as non-empty finite `ImageEmbedding` vectors and
checks the artifact descriptor against the current source and active backend.
Application features should use PhotoAIKit's comparator instead of decoding the
payload or implementing cosine distance independently.

An image artifact can be reused for:

- **Find Similar** from a selected image.
- Nearest-neighbour ranking.
- Near-duplicate detection.
- Visual clustering.
- Burst or catalog outlier detection.
- Semantic text search after a compatible text encoder is available.

It does not contain captions, keywords, detected objects, EXIF metadata,
thumbnails, masks, or original pixels.

## Current persistence behavior and limitation

The **Index Similarity** action calls `SimilarityScoringModel.indexFiles`. It
creates or refreshes the in-memory `embeddings` dictionary, but does not save
those results to disk.

The complete **Analyze Bursts** pipeline currently:

1. Attempts to load a compatible catalog snapshot.
2. Scores missing sharpness results.
3. Indexes missing similarity artifacts.
4. Groups images into bursts.
5. Ranks burst candidates.
6. Writes one catalog-wide snapshot.

The snapshot is stored as JSON under:

```text
~/Library/Application Support/RawCull/BurstAnalysis/
```

It contains per-file similarity, sharpness, and saliency results together with
derived groups, boundary evidence, rankings, and review state. Its filename is
derived from the catalog path.

Validation is intentionally catalog-wide. The snapshot is rejected when the
catalog file count changes or any file path, size, or modification date differs.
This protects derived results, but it also discards reusable artifacts for all
unchanged files. The target design separates these two lifetimes:

- Per-file analysis artifacts survive unrelated catalog changes.
- Catalog-derived groups and rankings are recomputed whenever their catalog
  inputs change.

Arbitrary all-pairs distances and distances from the current similarity anchor
should remain runtime values. They are inexpensive to recompute from compact
embeddings and should not be persisted.

## Target architecture

### Per-file artifact layer

Introduce a RawCull-owned actor, referred to here as
`PerFileAnalysisArtifactStore`. The final name may differ, but its
responsibility should remain narrow.

The lookup identity must include:

- The source fingerprint.
- The artifact schema version.
- The backend and model fingerprint.
- The representation format.
- Preprocessing, normalization, and configuration versions.
- RawCull's embedding pipeline version and preview-size policy.

A source fingerprint alone is not enough because the same source can be
reprocessed by a different model or pipeline.

The first version needs to persist similarity artifacts. Its record format
should allow later addition of compact sharpness, saliency, or quality results
without making those fields mandatory now.

Required store operations:

- Load current artifacts for a collection of sources and an allowed set of
  backend descriptors.
- Upsert successful artifacts from a partial indexing run.
- Remove a stale or corrupt entry without clearing unrelated entries.
- Report size and entry count for Settings.
- Clear all stored per-file analysis data.
- Prune superseded records by a documented policy.

Writes must be atomic. Cancellation may stop future writes, but it must not
damage records committed earlier in the run. A single corrupt record must be
treated as a cache miss rather than invalidating the entire store.

### Catalog-derived layer

`BurstAnalysisCacheSnapshot` should continue to own:

- Catalog identity and algorithm signatures.
- Burst groups and group lookup inputs.
- Adjacent boundary evidence.
- Candidate rankings and recommendations.
- Review-state snapshots.

It may temporarily retain embedded artifacts for migration compatibility, but
the long-term source of reusable per-file artifacts should be the per-file
store. Loading a catalog should hydrate reusable artifacts first, then validate
or recompute the derived snapshot against the current artifact set.

### Semantic-query layer

PhotoAIKit should expose a typed CLIP text capability. An illustrative shape is:

```swift
public protocol TextEmbeddingProviding: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    func embedding(for text: String) async throws -> TextEmbedding
}

public protocol ImageTextSimilarityComparing: Sendable {
    func similarity(
        image: SimilarityArtifact,
        text: TextEmbedding
    ) throws -> Float
}
```

The exact names are not prescribed. The important properties are:

- `TextEmbedding` is not presented as a file-backed `SimilarityArtifact`.
- It carries enough descriptor information for strict compatibility checking.
- The provider, not RawCull, owns tokenization and model-output decoding.
- The comparator rejects Vision artifacts and mismatched CLIP models.
- The returned value has documented ordering and range semantics.

RawCull should wrap this in a narrow semantic-search service so the UI and view
model do not depend directly on PhotoAIKit implementation types beyond the
shared contracts.

## Detailed implementation plan

Phases 1 and 2 can be developed independently. RawCull semantic search depends
on both: it needs durable image artifacts and a PhotoAIKit text-query
capability.

### Phase 1: Durable per-file similarity artifacts in RawCull

#### 1.1 Define the storage contract

- Define a versioned `Codable` record containing the `SimilarityArtifact`,
  source identity needed for diagnostics, RawCull pipeline signature, and
  timestamps needed for pruning.
- Derive a stable cache key from the complete lookup identity described above.
- Decide whether records are stored individually or in bounded shards. Avoid
  rewriting every cached embedding after one image completes.
- Put the store under a RawCull-owned Application Support directory distinct
  from catalog-derived burst snapshots.
- Document whether moved or renamed files are cache hits. The initial
  implementation should follow `SourceFingerprint` semantics rather than add
  content hashing implicitly.

#### 1.2 Implement the actor-backed store

- Serialize all mutation through an actor.
- Use atomic replacement for each committed record or shard.
- Validate the record schema before decoding the artifact payload.
- Reuse `RawCullSimilarityArtifactValidation` for backend and source checks.
- Convert missing, stale, incompatible, and corrupt records into typed cache
  misses where practical.
- Provide usage, clear, and bounded pruning APIs for the existing cache
  Settings surface.

#### 1.3 Integrate loading

- After file scanning and similarity-provider selection, request valid cached
  artifacts for the catalog sources.
- Merge only validated artifacts into `SimilarityScoringModel.embeddings`.
- Keep UUID remapping at the RawCull boundary when a catalog reload creates new
  in-memory `FileItem` identifiers.
- Do not load Vision artifacts into a CLIP-only semantic search, or CLIP
  artifacts into an incompatible CLIP model.
- Treat partial hits normally and index only misses.

#### 1.4 Make **Index Similarity** durable

- Have indexing expose the successfully validated artifact delta, rather than
  requiring persistence code to infer which dictionary entries changed.
- Persist each successful artifact even when other files fail.
- Return only after the successful artifacts are durably committed, unless the
  action was cancelled before commit.
- Preserve failure diagnostics separately; a failed image must not erase its
  previously valid artifact unless that artifact is known to be stale.
- Update progress text to distinguish generating artifacts from saving them
  when the write is measurable.

#### 1.5 Decouple the burst snapshot

- Hydrate per-file artifacts before attempting burst grouping.
- Recompute boundaries, groups, and rankings when catalog membership or order
  changes.
- Keep review-state restoration tied to a stable burst signature.
- Add a migration path that can import compatible artifacts from an existing
  `BurstAnalysisCacheSnapshot` into the new store.
- Advance relevant cache schema or algorithm versions when the read path
  changes.
- After a migration period, remove duplicate embedding payloads from new burst
  snapshots if doing so does not complicate recovery.

#### 1.6 Tests and acceptance criteria

Unit tests:

- Round-trip a valid CLIP and Vision artifact.
- Reject a changed source fingerprint.
- Reject backend, model, representation, normalization, configuration, schema,
  preview-size, and pipeline-version mismatches.
- Treat truncated JSON, an invalid payload, and a non-finite CLIP vector as
  isolated misses.
- Verify atomic replacement and cancellation behavior.
- Verify clear, usage, and pruning operations.

Integration tests:

- Run **Index Similarity**, recreate the model, and restore artifacts without
  running **Analyze Bursts**.
- Add one file to a catalog and verify that only the new file is indexed.
- Modify one file and verify that only that file is reindexed.
- Remove one file and verify that remaining artifacts are reused while burst
  results are recomputed.
- Preserve successful artifacts from a partially failed CLIP indexing run.
- Switch between Vision and CLIP without cross-loading incompatible artifacts.
- Import compatible artifacts from the legacy burst snapshot.

Phase 1 is complete when **Index Similarity** survives application relaunch and
catalog membership changes cause work only for missing or stale files.

### Phase 2: CLIP text capability in PhotoAIKit

The existing export includes `image_embeds`, `text_embeds`,
`logits_per_image`, and `logits_per_text`, and copies the tokenizer into the
model bundle. `CoreAICLIPProvider` currently uses the tokenizer to supply text
input during image inference but exposes only image embeddings and
image-to-image comparison.

#### 2.1 Add text contracts

- Add a descriptor-complete `TextEmbedding` value with finite normalized
  values and explicit dimensions.
- Add text-encoding and image-to-text-comparison protocols to the appropriate
  PhotoAIKit contract module.
- Define whether the primitive returns cosine similarity, cosine distance, or
  another score. Do not leave ordering semantics implicit.
- Define typed incompatibility and invalid-output errors.

#### 2.2 Implement text inference

- Load the tokenizer declared by the validated model bundle.
- Read sequence length, batch shape, attention-mask requirements, and model
  input names from validated configuration rather than duplicating constants
  in RawCull.
- Apply deterministic padding and truncation.
- Run the model and extract the requested `text_embeds` rows.
- Reject empty, incorrectly shaped, non-finite, zero-norm, or unexpected
  outputs.
- Normalize in exactly one documented layer and record the normalization
  version.
- Check cancellation before tokenization, before inference, and before
  returning a large result.

The current joint image-and-text function may require dummy image input and
unused batch rows. A first implementation may use that path. A later exporter
can provide a text-only function if measurements show that executing the vision
branch materially harms query latency or memory use.

#### 2.3 Implement the comparison primitive

- Accept only image artifacts produced by the same compatible CLIP backend.
- Check model fingerprint, dimensions, representation, preprocessing,
  normalization, and configuration before calculating a score.
- Reject Vision feature prints explicitly.
- Avoid exposing raw artifact-payload decoding as the public API.

#### 2.4 Tests and acceptance criteria

Tests should cover:

- Known tokenizer fixtures, including empty input, punctuation, Unicode,
  truncation, and maximum-length input.
- Static input shapes, padding, attention masks, and multi-row batches.
- Finite, normalized `text_embeds` output with the expected dimensions.
- Deterministic output for the same model and query.
- Compatible image/text scoring and rejection of every descriptor mismatch.
- Cancellation and malformed model-output errors.
- A small fixed retrieval fixture where related image/text pairs outrank
  unrelated pairs.

Phase 2 is complete when a consumer can encode a query and compare it safely
with a compatible image artifact without knowing tokenizer, Core AI, or payload
details.

### Phase 3: RawCull semantic-search service and ranking

#### 3.1 Add a capability boundary

- Add a semantic-search protocol separate from the Vision-compatible
  image-similarity requirement, or expose text support as an explicit optional
  capability.
- Construct the capability in `RawCullAIIntegration` only when a validated CLIP
  provider supports text.
- Represent unavailable, checking, ready, and failed states explicitly.
- Keep Vision available for burst similarity while reporting that semantic
  search requires CLIP.

#### 3.2 Implement query execution

- Trim and validate the query without silently changing its meaning.
- Start with the literal query. Treat prompt variants such as
  `a photo of {query}` as a versioned, measurable policy rather than an
  invisible constant.
- Encode each distinct query once per model and prompt-policy version.
- Compare the text embedding with a snapshot of eligible cached CLIP artifacts
  off the main actor.
- Use a linear scan initially. Add an approximate nearest-neighbour index only
  after profiling demonstrates a need.
- Sort by the documented score with a stable filename or catalog-order
  tie-breaker.
- Keep scoring failures isolated to individual artifacts and report aggregate
  diagnostics.

#### 3.3 Implement cancellation and state

- Debounce typing or execute on Return.
- Give each query a generation identifier.
- Cancel superseded work and check the generation before committing results.
- Clear results immediately when the query is cleared.
- Keep original catalog order available.
- Do not persist query embeddings initially. If a memory cache is added, key it
  by exact text, prompt-policy version, tokenizer/configuration version, and
  model fingerprint.

#### 3.4 Integrate filters

- Rank only files that pass the current catalog and metadata admission rules,
  or apply existing filters after ranking with clearly documented behavior.
- Preserve ratings, labels, metadata filters, and ordinary selection behavior.
- Handle partially indexed catalogs explicitly: show results for indexed
  images and disclose the excluded count.
- Never compare a CLIP query with Vision artifacts.

#### 3.5 Tests and acceptance criteria

- A newer query cannot be overwritten by an older cancelled query.
- Clearing the query restores the previous non-semantic ordering.
- Ranking is deterministic for equal scores.
- Existing metadata filters compose with semantic ranking.
- Vision-only, missing-model, empty-index, partial-index, and provider-failure
  states are distinct.
- A model switch invalidates query state and incompatible results.
- Ranking does not decode RAW files or regenerate image embeddings.

Phase 3 is complete when the view model can produce cancellable, deterministic
text-ranked catalog results entirely from a query and cached CLIP artifacts.

### Phase 4: Semantic-search UI

- Add a search field to the similarity workflow only when the capability is
  available, while providing an actionable explanation when it is not.
- Offer **Index Similarity** when compatible CLIP artifacts are missing.
- Display indexing coverage and the number of images excluded from results.
- Show a relative match indicator or result ordering, not a confidence claim.
- Provide example queries without constraining users to a fixed taxonomy.
- Keep clearing the query, changing filters, selecting images, and returning to
  catalog order immediate.
- Preserve accessibility labels, keyboard navigation, focus behavior, and
  localization.

UI tests should cover ready, unavailable, indexing, partial, empty-result,
failure, cancellation, and clear-query states.

Phase 4 is complete when users can understand why search is or is not
available, start the required indexing, execute and cancel searches, and return
to the normal catalog view without losing selection or filters.

### Phase 5: Retrieval-quality and performance validation

Build a fixed evaluation set from several representative RawCull catalogs,
including wildlife, people, landscapes, events, low-light work, and visually
similar bursts. Keep it private if the photographs cannot be redistributed,
but version the query list and expected relevance judgements.

Measure:

- Useful-result rate or ranking metrics for representative queries.
- Query-encoding latency, full-catalog ranking latency, and time to first
  visible result.
- Peak and steady-state memory.
- Cold and warm behavior.
- Direct-query versus prompt-template quality.
- Partial-index behavior.
- Failure and exclusion rates.
- Obvious domain, language, and sensitive-attribute failure cases.

Do not present softmax output as a stable confidence percentage. It changes
with the candidate set. Product decisions should be based on measured ranking
quality, not an arbitrary score threshold alone.

Phase 5 is complete when RawCull has recorded baselines and release criteria
for supported catalog sizes and can identify regressions in both quality and
performance.

### Phase 6: Later enhancements

Consider these only after basic text retrieval is useful and reliable:

- Saved semantic smart collections combined with metadata and ratings.
- Positive and negative concept ranking.
- Zero-shot relative labels over a controlled vocabulary.
- Hybrid semantic and structured search.
- Visual clusters, near-duplicate groups, and catalog outliers.
- A measured text-only model export.
- Approximate nearest-neighbour indexing for catalogs where linear scans miss
  the latency target.

An LLM could later translate a conversational request into a CLIP query and
structured filters, but it is not required for semantic search. Captioning and
visual question answering would require different model capabilities.

## Product and model limits

CLIP is useful for broad visible concepts, scenes, style, and composition. It
is not a dependable replacement for specialized culling analysis. It can
struggle with counting, small details, fine-grained distinctions, spatial
relationships, unusual photography domains, and facts that are not visually
evident.

Semantic similarity should not decide whether an eye is critically sharp,
whether highlights are recoverable from RAW data, or whether a person blinked.
Results involving people and sensitive attributes must be presented as
relative retrieval results, not facts. The released model was primarily
evaluated with English text and inherits biases from internet image-text
training data.

See the [CLIP paper](https://arxiv.org/abs/2103.00020), the
[OpenAI CLIP implementation](https://github.com/openai/CLIP), and the
[CLIP model card](https://github.com/openai/CLIP/blob/main/model-card.md).

## Non-goals for the initial enhancement

- Caption generation or conversational answers.
- Cloud inference.
- Persisting original images, thumbnails, or query text in the artifact store.
- Persisting an all-pairs distance matrix.
- Running CLIP inference during the initial catalog metadata scan.
- Treating Vision feature prints as text-compatible embeddings.
- Adding complete EXIF dumps, SAM masks, full RAW histograms, or unrelated
  quality signals to the CLIP cache.
- Introducing approximate nearest-neighbour infrastructure before measuring
  the linear implementation.

## Expected implementation areas

RawCull:

- `RawCull/Actors/BurstAnalysisCache.swift`
- A new per-file analysis-artifact store under `RawCull/Actors` or
  `RawCull/Model/Cache`
- `RawCull/Model/AIIntegration/RawCullAIIntegration.swift`
- `RawCull/Model/AIIntegration/RawCullVisionSimilarityService.swift`
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- Similarity and cache Settings views
- Similarity-grid and search views
- `RawCullTests/PhotoAIKitSimilarityMigrationTests.swift`
- New artifact-store and semantic-search tests

PhotoAIKit:

- Shared contracts for text embeddings and image-to-text comparison
- `CoreAICLIPProvider`
- CLIP model-bundle validation and tokenizer integration
- Export fixtures or tools if a text-only function is later adopted
- Provider, compatibility, cancellation, and retrieval-fixture tests

## Recommended delivery order

1. Implement and migrate to the RawCull per-file artifact store.
2. Make **Index Similarity** durable and verify incremental catalog reuse.
3. Add and test PhotoAIKit's typed CLIP text capability.
4. Add RawCull's semantic-search service, ranking, and cancellation.
5. Add the user-facing search workflow and availability guidance.
6. Measure retrieval quality and performance on representative catalogs.
7. Add advanced retrieval features only when the baseline meets its release
   criteria.
