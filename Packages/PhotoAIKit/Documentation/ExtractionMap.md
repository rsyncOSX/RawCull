# Extraction map

This map records how the CLIP and SAM3 code reviewed in `RawCullSAM3/isolateai.md` is represented in PhotoAIKit. It distinguishes reusable AI behavior from integration code that intentionally stays in the host application.

## SAM3

| RawCullSAM3 source | Package destination | Result |
|---|---|---|
| `SubjectSegmentationTypes.swift` | `PhotoAIContracts/SubjectSegmentation.swift`, `SubjectMaskStorage.swift` | Public, UI-neutral, typed, `Sendable` request/result/diagnostic/progress contracts and provider/store protocols. Prompt display labels stay in RawCull. |
| `CoreAISAM3Provider.swift` | `CoreAISAM3Backend/CoreAISAM3Provider.swift` | Full tokenizer, lazy load, inference, query selection, sigmoid conversion, bilinear resize, threshold, feather, diagnostics, and flat-bundle shim. Model bundle URL is required. |
| `SAM3ModelIdentity.swift` | `ModelIdentity.swift`, `ModelAssetFingerprint.swift`, `ModelBundleResolver.swift` | Generic identity plus verified manifest fingerprints, metadata fallback, an additive fingerprinted artifact identifier, and the existing SAM3-compatible cache identifier. No static installed-model lookup. |
| `SAM3ModelResourceManager.swift` | `ModelBundleResolver.swift`, `ModelResource.swift`, and the `.sam3` descriptor | Validation, capability state, ordered candidate resolution, and provider construction are reusable and URL-driven. RawCull paths, bundle fallback policy, and display strings are removed. |
| `SubjectSegmentationActor.swift` | `PhotoAIWorkflows/SegmentationService.swift` | Preprocessing, resizing, cache lookup/persistence, provider invocation, partitioning, prefetch, cancellation, and progress use `AIImageSource`. Global cache and `FileItem` dependencies are removed. “Latest request wins” is deliberately left to the host. |
| `SubjectMaskCache.swift` | `PhotoAIStorage/SubjectMaskMemoryStore.swift` | Public injected actor store. |
| `SAM3MaskDiskCache.swift` | `PhotoAIStorage/SubjectMaskDiskStore.swift` | PNG/JSON load, validation, save, size, pruning, clear, modification date, and fast metadata check. Cache directory is required; logging is package-local. |
| `SAM3MaskGenerationPipeline.swift` | `PhotoAIWorkflows/SegmentationBatchPipeline.swift` | Package-owned sources, summary/events, translated cached/generated/failed progress. |
| `SAM3MaskBuildTypes.swift` | `SegmentationBatchPipeline.swift` | Transport-neutral summary/event values plus a versioned JSON-lines envelope. RawCull helper request fields are host-only. |
| `SAM3MaskInventoryEntry.swift` | `SubjectMaskGeometry.swift` | Alpha extraction, coverage, normalized bounds, centroid, and freshness. |
| `SubjectQualityBadgeModel.swift` | `SubjectMaskQuality.swift` | Geometry thresholds, clipped-edge detection, and quality classification. RawCull badge labels/help text remain host presentation. |
| `SAM3SubjectMaskCacheReader.swift` | `PhotoAIWorkflows/SubjectMaskRepository.swift` | Injected cache facade with explicit prompt/model/size configuration. RawCull's static reader is removed. |
| `SAM3MaskCatalogIndex.swift` | `SubjectMaskCatalogIndex.swift` | Package-owned sources, incremental batches, cache metadata, geometry, confidence, and quality are reusable. RawCull maps the result to view-ready state. |
| Deep-review prompt/mask fallback | `SubjectMaskSelection.swift` | Ordered prompts, minimum quality/confidence, cache/generate policy, and best-mask selection are generic. Candidate and culling winner policy stay in RawCull. |
| `SAM3MaskHelperController.swift` | Not packaged | AppKit process launch, executable lookup, security scope, parent PID, app path, and restart are RawCull-specific per `isolateai.md`. |
| `SAM3MaskHelperProgressView.swift`, segmentation controls/settings/views | Not packaged | SwiftUI and app display state stay in RawCull. |
| SAM3 consumers in sharpness, burst review, comparison, thumbnails, and zoom | Not packaged | These remain app adapters/policy and now receive a narrow mask facade from RawCull's `RawCullAIContainer`. |

## CLIP

| RawCullSAM3 source | Package destination | Result |
|---|---|---|
| `CoreAICLIPProvider.swift` | `CoreAICLIPBackend/CoreAICLIPProvider.swift` | Full lazy Core AI load, descriptor validation, image resize/normalization, text tokenization/padding/attention masks, joint image/text inference, typed output validation, cancellation, and compatible image/text cosine similarity. Model bundle URL is required. |
| CLIP semantic-query contracts | `PhotoAIContracts/TextEmbedding.swift` | Query-scoped descriptor-complete text vectors plus text-provider and image/text-comparator protocols. Vision and every incompatible CLIP descriptor field are rejected before payload decoding. |
| `CLIPModelResourceManager.swift` | `ModelBundleResolver.swift`, `ModelAssetFingerprint.swift`, `ModelResource.swift`, and `.clip` descriptor | URL validation, fingerprinted identity, capability state, and factory mechanics are reusable. RawCull paths, bundle fallback policy, and display text are removed. |
| `SimilarityEmbeddingEnvelope` normalization/cosine helpers | `ImageEmbedding.swift`, `SimilarityMetric.swift` | Typed normalized vectors and backend/model-compatible cosine distance. |
| Version-1 CLIP JSON persistence | `LegacyCLIPEmbeddingCodec.swift`, `EmbeddingCodec.swift` | Legacy readers remain for staged integration; identity-incomplete writers are deprecated. Current artifacts require backend/model/source/preprocessing/normalization/configuration/schema identity and migration reports when rewrite is required. |
| Bounded indexing loop and progress | `EmbeddingIndexer.swift` | Package-owned sources, injected decoder/provider, configurable concurrency, per-item or whole-batch fallback, typed failures/results. |
| RawParserKit and ImageIO thumbnail decoding | Host `ImageDecoding` adapter | RAW format behavior remains owned by the integrating app. |
| Vision feature-print generation/archive/distance | `VisionFeaturePrintBackend` | Separate package product with typed opaque artifacts and backend-owned native distance. No `VNFeaturePrintObservation` enters host persistence APIs. |
| CLIP/Vision whole-batch fallback | `SimilarityArtifactIndexer.swift` | Bounded package-owned indexing works consistently across vector and opaque backends. |
| `SimilarityScoringModel` observable state, settings, estimation/status strings | Not packaged | UI/presentation state stays in RawCull. Settings/model URL selection now occurs in the RawCull integration layer, and burst grouping work is delegated to a separate RawCull policy model. |
| Burst adjacency cache/grouping, saliency mismatch, review/rating decisions | Not packaged | Culling policy consumes embeddings but is not CLIP functionality. |

## Non-runtime sources and assets

- `Tools/export_clip.py`, `Tools/export_sam3.py`, and `Tools/select_sam3_asset.py` are package-neutral exporter/developer tools. They require explicit output/bundle paths and emit verified fingerprint metadata.
- `RawCullSAM3/Resources/Models/CLIP` and `RawCullSAM3/Resources/Models/SAM3` are not copied.
- The package manifest declares no resource target and no model files.

## Boundary checks

The package source contains no imports or references to `RawCullCore`, `RawParserKit`, `FileItem`, `SharedMemoryCache`, `SettingsViewModel`, SwiftUI, Observation, AppKit, or `Bundle.main`. Public contract tests import the modules normally and use fake host source/decoder/provider implementations; focused backend tests use `@testable` only for token-batch and output-shape validation. RawCull constructs package providers, stores, workflows, helper paths, and host adapters once in `RawCullAIContainer`.
