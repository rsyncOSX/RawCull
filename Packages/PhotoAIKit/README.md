# PhotoAIKit

Reusable Core AI CLIP and SAM3 code extracted from RawCullSAM3. The package owns model inference, typed contracts, reusable indexing/segmentation workflows, and optional storage. It does not contain RawCull view models, UI, RAW-file decoding, helper-process behavior, or culling policy.

## Requirements

- Xcode 27 or newer (`swift-tools-version: 6.4`)
- macOS 27 or newer
- Swift 6 language mode

The package pins the same `apple/coreai-models` revision used by the source application. It does not embed any `.aimodel`, `.aimodelc`, tokenizer, or model metadata resources.

## Products

- `PhotoAIContracts`: model identities and verified fingerprints, capability/factory contracts, source values, typed image and text similarity values, segmentation/embedding types, provider/store/decoder protocols, and URL-based model-bundle validation.
- `CoreAICLIPBackend`: actor-owned CLIP image preprocessing, text tokenization, Core AI inference, and image/text comparison.
- `CoreAISAM3Backend`: actor-owned SAM3 tokenization, inference, and mask decoding.
- `VisionFeaturePrintBackend`: actor-owned Vision feature-print generation, opaque artifact coding, and native distance calculation.
- `PhotoAIWorkflows`: bounded vector/opaque artifact indexing, configurable fallback, cosine similarity, segmentation preprocessing/batching, versioned batch transport, mask cataloging, prompt fallback, best-mask selection, geometry, and quality classification.
- `PhotoAIStorage`: injected memory/disk mask stores, current descriptor-complete artifact codecs, and legacy embedding readers.

## Model URLs

The host application locates, downloads, bookmarks, or otherwise manages models. It then passes each bundle URL directly to the backend:

```swift
import CoreAICLIPBackend
import CoreAISAM3Backend

let clip = try CoreAICLIPProvider(modelBundleURL: clipBundleURL)
let sam3 = try CoreAISAM3Provider(modelBundleURL: sam3BundleURL)
```

Hosts with ordered candidate URLs can use the shared capability and factory API:

```swift
let capability = CoreAICLIPProvider.factory.capability(in: candidateURLs)
let clip = try CoreAICLIPProvider.factory.makeFirstAvailable(in: candidateURLs)
```

`ModelCapabilityStatus` contains no display wording or application path policy.

A bundle URL is expected to contain:

```text
ModelBundle/
├── metadata.json              # assets.main names the selected model asset
├── tokenizer/
│   └── tokenizer.json
└── selected-model.aimodel     # or .aimodelc
```

New exports also include `asset_fingerprints.main`. `ModelBundleResolver`
cryptographically verifies this value. Older bundles remain valid and receive a
size/modification-time fallback fingerprint; `ModelIdentity.cacheIdentifier`
keeps its existing behavior while `artifactIdentifier` is the fingerprinted key
for new artifacts.

No default Application Support path, `Bundle.main` lookup, or package resource fallback is used.

## Host integration

Map the app's photo type to `AIImageSource`, provide an `ImageDecoding` adapter, and inject model/cache URLs:

```swift
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows

let source = AIImageSource(
    id: photo.id,
    url: photo.url,
    displayName: photo.name
)

let memory = SubjectMaskMemoryStore()
let disk = try SubjectMaskDiskStore(cacheDirectory: appMaskCacheURL)
let maskConfiguration = SubjectMaskRepositoryConfiguration(
    defaultPrompt: .subject,
    modelIdentity: sam3.modelIdentity,
    inputMaxSide: 4_320
)
let cachedMasks = SubjectMaskRepository(
    configuration: maskConfiguration,
    stores: [memory, disk]
)
let service = SegmentationService(
    provider: sam3,
    stores: [memory, disk],
    maxSide: 4_320
)

let result = try await service.segment(
    image: decodedImage,
    source: source,
    prompt: .subject
)
```

For CLIP indexing, inject the host decoder and choose fallback explicitly:

```swift
let indexer = EmbeddingIndexer(
    primaryProvider: clip,
    fallbackProvider: optionalHostFallback,
    decoder: rawAwareDecoder,
    fallbackPolicy: .wholeBatch,
    concurrencyLimit: 2
)

let index = try await indexer.index(sources)
```

For a package-owned CLIP-to-Vision fallback, use descriptor-complete artifacts:

```swift
import VisionFeaturePrintBackend

let vision = VisionFeaturePrintBackend()
let indexer = SimilarityArtifactIndexer(
    primaryProvider: clip,
    fallbackProvider: vision,
    decoder: rawAwareDecoder,
    fallbackPolicy: .wholeBatch,
    concurrencyLimit: 2
)
let artifacts = try await indexer.index(sources)
```

`SimilarityArtifactDescriptor` records backend, model fingerprint, dimensions,
representation, preprocessing, normalization, configuration, source fingerprint,
and schema version. Vision observations stay opaque; comparison goes through
`VisionFeaturePrintBackend.distance(from:to:)`.

`EmbeddingCodec.encode(EmbeddingArtifact)` is the current CLIP persistence API.
The former identity-incomplete writers remain callable but are deprecated.
`decodeMigrating` accepts both version-1 formats against the real current model
identity and marks the result for immediate rewrite.

For semantic queries, encode text with the same provider that produced the
image artifacts, then compare through the backend-owned primitive:

```swift
let query = try await clip.embedding(for: "a bird in flight")
let score = try clip.similarity(image: persistedArtifact, text: query)
```

`TextEmbedding` is query-scoped and is not a file-backed
`SimilarityArtifact`. Its descriptor carries the complete backend identity,
dimensions, tokenizer version, and schema. The comparator rejects Vision
artifacts and every mismatched CLIP model/configuration field before decoding
the opaque image payload. Its result is cosine similarity in `-1 ... 1`, where
higher values are closer semantic matches.

The exported CLIP graph owns L2 normalization of `text_embeds`.
`CoreAICLIPProvider` validates that output as finite, non-empty, correctly
shaped, and normalized; it does not normalize the text vector again.

For SAM workflows, `SubjectMaskCatalogIndex` builds incremental package-owned
inventory, while `SubjectMaskSelector` implements ordered prompts, minimum
quality/confidence, best-mask selection, and cache-only or generate-if-missing
acquisition. `SegmentationBuildTransportCodec` provides a versioned JSON-lines
event schema for helper processes.

## Model export tools

Package-neutral developer tools live under `Tools`. Output locations are always
explicit and no script defaults to an application resource directory:

```sh
uv run Tools/export_clip.py --output-dir /path/to/models
uv run Tools/export_sam3.py --output-dir /path/to/models
python3 Tools/select_sam3_asset.py sam3_float16.aimodel \
  --bundle-dir /path/to/models/SAM3
```

Export and selection write the fingerprint manifest consumed by
`ModelBundleResolver`.

## Deliberate host responsibilities

- model download/install UI and model URL selection;
- security-scoped bookmarks and sandbox access;
- RAW decoding (for example RawParserKit) and ImageIO fallback;
- SwiftUI/Observation state and display text;
- “latest selection wins” behavior;
- burst grouping, saliency penalties, sharpness/rating decisions;
- SAM3 helper-process launch, parent-process coordination, and app restart.

See [Documentation/ExtractionMap.md](Documentation/ExtractionMap.md) for the complete source-to-package audit.
