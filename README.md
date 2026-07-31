# RawCull AI

[![GitHub license](https://img.shields.io/github/license/rsyncOSX/RawCull)](https://github.com/rsyncOSX/RawCull/blob/main/Licence.MD)

RawCull AI is a native macOS photo review and culling application for Sony ARW RAW files. It is built for Apple Silicon and combines fast embedded-preview loading with focus-point extraction, sharpness analysis, visual similarity, burst grouping, ratings, and selective export.

The application is written in Swift 6 with SwiftUI. Image parsing, analysis, shared culling models, JSON encoding, and rsync execution are separated into focused Swift packages so that RawCull primarily owns application state, workflow, caching, persistence, and presentation.

## Requirements

- macOS 27 or newer
- Apple Silicon Mac
- Xcode 27 or newer for development
- Swift 6 language mode

## AI features

RawCull's AI-assisted culling runs locally on Apple Silicon. Photos are not uploaded to an external inference service. Both are trained neural networks. The precise difference is primarily what they produce and what they were trained to do.

| | CLIP: vision-language encoder | SAM 3: vision-language segmentation |
|---|---|---|
| Question answered | “How well does this text match this image?” | “Where are the pixels belonging to this concept?” |
| Inputs | Image or text | Image plus text/visual prompt |
| Output | One fixed-length vector per image or text | Masks, boxes, presence and confidence scores |
| Spatial information | Mostly compresses the whole image into one vector | Preserves detailed spatial information |
| Training objective | Match related image-caption vectors | Detect and segment prompted objects |
| RawCull use | Search and similarity ranking | Isolate the subject for detailed analysis |

Their simplified pipelines are:

```text
CLIP

Image ── image encoder ──► vector ─┐
                                   ├─► similarity score
Text  ── text encoder  ──► vector ─┘
```

```text
SAM 3

Image ── image encoder ─────────────┐
                                    ├─► detector + mask decoder ─► masks and boxes
Prompt ── text/visual encoder ──────┘
```

CLIP compresses an entire image into a global semantic summary. It might determine that an image closely matches “a bird in flight,” but it does not identify precisely which pixels form the bird.

SAM 3 retains spatial image features. Given the prompt “bird,” it finds relevant instances and produces pixel masks around them. SAM 3 therefore contains encoders too, but its complete system includes detection and segmentation components.

Both require neural-network inference initially, but caching changes how frequently they run:

- CLIP image encoding runs once per photograph. Later searches reuse the cached image vectors and only run the text-query path.
- Comparing cached CLIP vectors is ordinary mathematical computation, not another neural-network pass.
- SAM 3 normally runs for each image and prompt, but RawCull can cache the resulting mask.
- Reusing a cached SAM 3 mask also avoids another neural-network run.

The shortest distinction is:

> CLIP determines **what an image is related to**; SAM 3 determines **where that thing is in the image**.

- CLIP: vision-language encoder. It converts images and text into comparable vectors for search, similarity, and classification.
- SAM 3: vision-language segmentation model. It uses an image plus text or visual prompts to locate objects and produce masks and boxes.

### Requirements to run AI

- Vision feature-print similarity is built into macOS and works without an additional model download.
- CLIP similarity supports validated PhotoAIKit-compatible DataComp and OpenAI
  CLIP Core AI model bundles. RawCull uses the one selected in **Settings > AI**
  and safely falls back to Vision feature prints when that bundle is missing or
  invalid.
- Deep Review requires a validated PhotoAIKit-compatible SAM 3 Core AI model bundle. The feature remains unavailable when the model is missing or invalid.
- CLIP and SAM 3 model bundles must contain `metadata.json`, the selected `.aimodel` or `.aimodelc` asset, and any resources declared by the model manifest.
- Models are not bundled with RawCull. **Settings > AI > Download AI Models**
  now provides the Managed Background Assets download, licence review,
  progress, cancellation, and removal flow. The current server address is a
  non-routable placeholder, and every production model remains blocked until
  its audited licence and provenance requirements are complete.
- Manual installation remains available while distribution is blocked. Install
  the resources, then open **Settings > AI** and select **Check Again** to
  validate them. The standard non-sandboxed locations are:

  ```text
  ~/Library/Application Support/RawCull/Models/CLIP-DataComp/
  ~/Library/Application Support/RawCull/Models/CLIP-OpenAI/
  ~/Library/Application Support/RawCull/Models/SAM3/
  ```

  Sandboxed builds use:

  ```text
  ~/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP-DataComp/
  ~/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/CLIP-OpenAI/
  ~/Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models/SAM3/
  ```

  **Settings > AI** displays the exact expected paths.
- The first use of a portable Core AI model can take longer while macOS specializes the model for the current Mac.

See [AI model download service](Documentation/AIModelDownloads.md) for hosting,
licence gates, security boundaries, and release configuration.

### What the AI functions do

- **Similarity and burst grouping:** CLIP image embeddings, or Vision feature prints as the fallback, measure visual similarity and help group neighboring frames into bursts for comparison.
- **Sharpness and subject evidence:** PhotoAnalysisKit combines sharpness, saliency, classification, focus-mask, and camera AF-point evidence to rank burst candidates and explain cautions.
- **Deep Review:** SAM 3 isolates the subject, evaluates detail inside the mask, checks whether the AF point falls within the subject, and recommends a winner with confidence and supporting reasons. Choosing **Mark Winner & Close** saves the winner, gives it a three-star rating, and marks the burst reviewed.
- **Local caching:** Embeddings, masks, scores, and burst decisions are cached locally so compatible results can be reused in later sessions.

To use CLIP, choose exactly one of **DataComp** or **OpenAI** and enable **Use
selected CLIP model for similarity** under **Settings > AI** after the model is
validated. To use SAM 3, analyze a catalog into burst groups, select **Deep
Review** on a burst, choose the review target, and run the review.

## Installation

Not yet avaliable for download, compile your own version until macOS 27 and Xcode 27 are released. 

## Main capabilities

- Discover and scan supported RAW files in a selected catalog.
- Read EXIF metadata, dimensions, camera/lens information, ISO, and aperture.
- Extract normalized camera AF points from Sony MakerNotes.
- Display cached thumbnails, embedded full-size JPEG previews, or developed RAW
  previews.
- Render AF-point overlays and GPU-generated focus masks.
- Score image sharpness using full-frame, salient-subject, and AF-region
  evidence.
- Apply photo-type presets and fast, balanced, or high-precision scoring.
- Generate validated CLIP image embeddings for similarity ranking and burst
  grouping, with targeted retry/provider recovery and safe per-image exclusion.
- Compare burst candidates with sharpness, similarity, and caution details.
- Tag, reject, or assign star ratings to selected images.
- Persist ratings, sharpness results, saliency labels, burst decisions, and
  cache signatures.
- Export embedded or developed JPEG files.
- Copy tagged or rated RAW files with streaming rsync progress.
- Monitor thumbnail-cache usage and macOS memory-pressure events.

## Architecture overview

```mermaid
flowchart LR
    Catalog["RAW catalog"] --> Parser["RawParserKit"]
    Parser --> Adapter["RawCull decoding adapters"]
    Adapter --> Domain["RawCullCore models"]
    Adapter --> Analysis["PhotoAnalysisKit"]
    Adapter --> PhotoAI["PhotoAIKit"]
    Models["CLIP / SAM 3 Core AI models"] --> PhotoAI
    Analysis --> Sharpness["Sharpness, focus mask, saliency"]
    PhotoAI --> Similarity["CLIP embeddings / Vision fallback"]
    PhotoAI --> Masks["SAM 3 segmentation / mask storage"]
    Domain --> Bursts["RawCullCore burst grouping"]
    Similarity --> Bursts
    Sharpness --> Ranking["RawCull ranking and review policy"]
    Bursts --> Ranking
    Masks --> DeepReview["Deep Review subject-detail evidence"]
    Sharpness --> DeepReview
    Domain --> ViewModels["@Observable view models"]
    Ranking --> ViewModels
    DeepReview --> ViewModels
    ViewModels --> UI["SwiftUI views"]
    ViewModels --> Cache["RAM and disk caches"]
    ViewModels --> Persistence["JSON and burst persistence"]
    ViewModels --> Copy["rsync copy workflow"]
```

RawCull keeps application-specific policy outside the packages:

- RAW source selection and decoding size
- security-scoped folder access
- settings and user preferences
- progress and cancellation presentation
- cache locations and file identity
- ratings, tagging, burst decisions, and culling workflow

The imported packages own reusable parsing, sharpness analysis, AI inference,
model validation, similarity artifacts, segmentation, mask storage, domain,
serialization, and process-execution concerns.

## Imported Swift packages

All package requirements are pinned to exact versions or revisions in the Xcode
project and are recorded in `Package.resolved`.

| Package | Pinned requirement | Responsibility | Main APIs used by RawCull |
|---|---:|---|---|
| [PhotoAIKit](https://github.com/rsyncOSX/PhotoAIKit) | revision `2cb07d6` | AI contracts, validated Core AI model resources, DataComp and OpenAI CLIP inference, SAM 3 inference, Vision similarity fallback, segmentation workflows, and subject-mask storage | `CoreAICLIPProvider`, `CoreAISAM3Provider`, `VisionFeaturePrintBackend`, `SimilarityArtifactIndexer`, `SegmentationService`, `SubjectMaskSelector`, `SubjectMaskMemoryStore`, `SubjectMaskDiskStore` |
| [PhotoAnalysisKit](https://github.com/rsyncOSX/PhotoAnalysisKit) | 1.2.0 | Sharpness scoring, focus masks, Vision saliency/classification, calibration, batch analysis, and cache identity | `PhotoAnalyzer.analyzeBatch`, `PhotoAnalyzer.calibrate`, `PhotoAnalyzer.focusMask`, `PhotoAnalyzer.analyzeWithFocusMask`, `PhotoAnalyzer.sharpnessDescriptor`, `SharpnessPreset`, `SharpnessQuality` |
| [RawParserKit](https://github.com/rsyncOSX/RawParserKit) | 1.2.6 | RAW discovery, metadata parsing, embedded JPEG extraction, previews, and manufacturer MakerNote parsing | `RawFormatRegistry`, `RawImageLoader.metadata`, `thumbnailCGImage`, `thumbnail`, `previewImage`, `SonyMakerNoteParser`, `NikonMakerNoteParser`, `SupportedFileType` |
| [RawCullCore](https://github.com/rsyncOSX/RawCullCore) | 1.1.0 | Shared file, catalog, EXIF, burst-grouping, ranking, and review-state value types | `RawCullFileItem`, `RawCullSourceCatalog`, `ExifMetadata`, `BurstGroupingConfig`, `BurstGroupingEngine.group`, `BurstAnalysisResult`, `BurstCandidateScore`, `BurstReviewState` |
| [RsyncArguments](https://github.com/rsyncOSX/RsyncArguments) | 1.0.0 | Type-safe construction of rsync parameters and synchronization arguments | `Parameters`, `BasicRsyncParameters`, `OptionalRsyncParameters`, `SSHParameters`, `PathConfiguration`, `RsyncParametersSynchronize.argumentsForSynchronize`, `computedArguments` |
| [RsyncProcessStreaming](https://github.com/rsyncOSX/RsyncProcessStreaming) | 1.0.0 | Starts and cancels rsync processes and streams file/progress output | `ProcessHandlers`, `RsyncProcess`, `executeProcess`, `cancel` |
| [ParseRsyncOutput](https://github.com/rsyncOSX/ParseRsyncOutput) | 1.0.0 | Parses rsync summary output into counts and formatted transfer statistics | `ParseRsyncOutput`, `getstats`, `numbersonly`, and the formatted file/size properties |
| [DecodeEncodeGeneric](https://github.com/rsyncOSX/DecodeEncodeGeneric) | 1.0.0 | Generic Codable helpers for persistent JSON data | `DecodeGeneric.decodeArray`, `EncodeGeneric.encode` |

## Main package integrations

### PhotoAnalysisKit

PhotoAnalysisKit owns the complete reusable focus and sharpness pipeline:

1. RawCull selects an embedded preview or a Core Image demosaiced RAW image.
2. `RawCullPhotoAnalysisAdapter` supplies asynchronous `PhotoAnalysisInput` providers.
3. `PhotoAnalyzer.analyzeBatch` performs bounded concurrent analysis and reports completion progress.
4. `SharpnessScoringModel` publishes scores, saliency summaries, focus breakdowns, and estimated time to the UI.
5. `PhotoAnalyzer.calibrate` derives a visual focus threshold from a catalog or burst.
6. `PhotoAnalyzer.focusMask` and `analyzeWithFocusMask` generate the focus overlay and its supporting evidence.

Per-image ISO, aperture, and normalized AF position are passed through `PhotoAnalysisInput`. Photo-type and quality choices map to package-owned `SharpnessPreset` and `SharpnessQuality` values.

Persistent sharpness results use `PhotoAnalyzer.sharpnessDescriptor(for:)`. RawCull layers the scoring source, decoded image size, source-file size, and modification date around that descriptor. This invalidates stale scores when either the package algorithm or the input file changes.

PhotoAnalysisKit deliberately does not know about `FileItem`, RAW formats, security-scoped URLs, application settings, cache directories, or ratings.

### PhotoAIKit

PhotoAIKit is RawCull's reusable AI runtime boundary. RawCull imports six of its
products: `PhotoAIContracts`, `PhotoAIWorkflows`, `PhotoAIStorage`,
`CoreAICLIPBackend`, `CoreAISAM3Backend`, and `VisionFeaturePrintBackend`.

The package provides the model-backed and fallback services used by the AI
features:

- `CoreAICLIPProvider` creates normalized CLIP image embeddings and cosine distances.
- `VisionFeaturePrintBackend` creates and compares Codable Vision feature prints.
- `CoreAISAM3Provider` performs in-process subject segmentation with a validated
  SAM 3 Core AI model.
- `SegmentationService` and `SubjectMaskSelector` acquire and select masks, while
  `PhotoAIStorage` supplies memory and disk mask stores.
- Persisted settings select exactly one of the DataComp and OpenAI CLIP
  bundles and enable CLIP when that selected model is available.
  Non-finite output is retried once, then retried with a replacement provider;
  unresolved images are excluded from automatic burst analysis.
- Adjacent distances are passed to `BurstGroupingEngine.group` from RawCullCore.

`RawCullAIIntegration` validates both CLIP model bundles, selects the requested
CLIP provider or the Vision fallback, constructs SAM 3 mask services, and
injects narrow services into the application models. RawCull retains ownership
of RAW decoding, model locations, settings, subject-detail scoring,
recommendation policy, ratings, and review state.

### RawParserKit

RawParserKit is the boundary between camera RAW files and RawCull's application models.

`RawParserKitImageLoader` adapts package results to RawCull:

- `RawImageLoader.metadata(for:)` becomes RawCullCore `ExifMetadata`.
- `RawImageLoader.thumbnailCGImage` feeds thumbnail caching, sharpness scoring, and feature-print generation.
- `RawImageLoader.thumbnail` supplies AppKit thumbnail images.
- `RawImageLoader.previewImage` supplies embedded full-size previews.
- MakerNote focus coordinates are converted to normalized `CGPoint` values.

`RawFormatRegistry` is used for supported-file discovery. The diagnostic tools also call the Sony and Nikon MakerNote parsers directly to report embedded JPEG locations and focus metadata.

### RawCullCore

RawCullCore contains application-neutral domain types shared across RawCull workflows. RawCull uses aliases for its central models:

```swift
typealias FileItem = RawCullFileItem
typealias ARWSourceCatalog = RawCullSourceCatalog
typealias ExifMetadata = RawCullCore.ExifMetadata
```

The package also owns the burst-grouping contracts and algorithm. RawCull provides ordered files and adjacent visual distances, then stores and presents the resulting groups, candidate scores, confidence, cautions, and review state.

### Rsync packages

The RAW copy workflow is divided into three package responsibilities:

1. `RsyncArguments` builds the base rsync argument list.
2. RawCull adds a NUL-separated `--files-from` list containing the selected tagged or rated filenames and appends security-scoped source/destination paths.
3. `RsyncProcessStreaming` executes `/usr/bin/rsync`, streams progress, and supports cancellation.
4. `ParseRsyncOutput` converts the final output into file counts, transferred sizes, created/deleted counts, and display-ready statistics.

### DecodeEncodeGeneric

RawCull persists its saved catalog records as Codable JSON. `DecodeGeneric` loads the stored array, while `EncodeGeneric` creates the encoded data written atomically to Application Support.

## Apple framework imports

| Framework | Main use |
|---|---|
| `SwiftUI` | Application scenes, navigation, grids, comparison views, settings, overlays, and controls |
| `Observation` | `@Observable` view models and application state |
| `AppKit` | `NSImage`, macOS windows, panels, pasteboard, and image bridging |
| `Foundation` | URLs, file management, Codable, tasks, dates, collections, and persistence |
| `CoreGraphics` | `CGImage`, normalized AF coordinates, image sizes, and drawing |
| `CoreImage` | Optional `CIRAWFilter` demosaicing for developed-RAW previews and high-precision scoring |
| `ImageIO` | JPEG properties, orientation, image-source diagnostics, and cache encoding/decoding |
| `CryptoKit` | Stable MD5-derived disk-cache keys |
| `Dispatch` | macOS memory-pressure monitoring |
| `OSLog` and `os` | Structured logging and lock-backed cache diagnostics |
| `UniformTypeIdentifiers` | RAW/JPEG file selection and export types |

Vision and Metal sharpness analysis are encapsulated by PhotoAnalysisKit. Core
AI inference, AI-side Vision feature prints, and subject-mask storage are
encapsulated by PhotoAIKit rather than implemented directly in RawCull.

## Application flow

### Catalog loading

1. The user selects a security-scoped catalog.
2. `ScanFiles` identifies supported files through RawParserKit.
3. Metadata and AF information are read concurrently.
4. RawCullCore `FileItem` values are created and published to the main actor.
5. Ratings and persisted sharpness results are restored when their file and
   analysis signatures still match.

### Thumbnail and preview loading

RawCull uses a two-tier thumbnail cache:

1. `SharedMemoryCache` provides the RAM layer through `NSCache`.
2. `DiskCacheManager` stores JPEG thumbnails below
   `~/Library/Caches/no.blogspot.RawCull/Thumbnails/`.
3. A cache miss is decoded through RawParserKit.

Full-size embedded and developed previews use a separate disk cache. Memory pressure is monitored with `DispatchSourceMemoryPressure`, allowing RawCull to reduce cache pressure while keeping diagnostics available in the Memory Console.

### Sharpness and focus

1. RawCull creates package batch requests for the selected files.
2. PhotoAnalysisKit invokes RawCull's decoding providers with bounded concurrency and analyzes the resulting inputs.
3. The package runs saliency, classification, Gaussian blur, Metal Laplacian analysis, regional scoring, and failure classification.
4. RawCull stores the scalar score, subject summary, and detailed breakdown.
5. Focus-mask views request a package-rendered mask using existing evidence when possible.

### Similarity and burst review

1. RawParserKit supplies 512-pixel thumbnails.
2. PhotoAIKit creates CLIP image embeddings. RawCull validates each artifact,
   performs targeted recovery for non-finite output, and excludes unresolved
   images; Vision remains the catalog backend when CLIP is unavailable.
3. RawCull calculates adjacent distances and passes them to RawCullCore.
4. RawCullCore groups the ordered images into bursts.
5. RawCull ranks candidates using sharpness, similarity, and review rules.
6. Burst artifacts and decisions are cached for later sessions.

### Ratings, persistence, and copying

Ratings, tags, saliency labels, sharpness signatures, and manual burst winners are stored in:

```text
~/Library/Application Support/RawCull/savedfiles.json
```

Settings are stored separately in:

```text
~/Library/Application Support/RawCull/settings.json
```

When copying selected RAW files, RawCull creates a temporary `--files-from` list, starts rsync with streaming handlers, updates progress, parses the final statistics, and releases both security-scoped folders during cleanup.

## Concurrency model

- View models are `@Observable`, `final`, and `@MainActor`.
- Background concerns use actor-per-responsibility isolation.
- Package boundary values and providers conform to `Sendable`.
- Dynamic parallel work uses structured task groups with bounded concurrency.
- Long-running scans, analysis, extraction, grouping, and copy operations
  support cooperative cancellation.
- Results are committed to observable state only after successful completion.
- Superseded similarity and grouping generations cannot publish stale results.

Important actors include:

| Actor | Responsibility |
|---|---|
| `SharedMemoryCache` | RAM thumbnails, grid-cache admission, memory-pressure handling, and diagnostics |
| `DiskCacheManager` | Thumbnail JPEG persistence |
| `FullSizeJPGDiskCache` | Embedded and developed full-size preview persistence |
| `ScanFiles` | Catalog scanning, metadata extraction, and AF-point collection |
| `ScanAndCreateThumbnails` | Bounded thumbnail preloading |
| `ExtractAndSaveJPGs` | Batch JPEG extraction |
| `BurstAnalysisCache` | Burst groups, embeddings, sharpness results, signatures, and review-state snapshots |
| `WriteSavedFilesJSON` | Atomic persistence of culling records |

## Repository structure

```text
RawCull/
├── Actors/                 Background scanning, caching, extraction, and persistence
├── Main/                   App entry point and shared type aliases
├── Model/
│   ├── Cache/              Cache configuration and diagnostics
│   ├── Diagnostics/        RAW and ImageIO diagnostics
│   ├── Handlers/           App and streaming callbacks
│   ├── JSON/               Codable persistence models
│   ├── ParametersRsync/    RAW copy configuration and execution
│   └── ViewModels/         MainActor application and workflow state
├── Views/                  SwiftUI catalog, grid, comparison, settings, and zoom UI
└── Assets.xcassets

RawCullTests/
├── TEST_ARCHITECTURE.md
└── Swift Testing suites
```

## Build

Debug build without notarization:

```bash
make debug
```

Release archive, signing, notarization, stapling, and DMG generation:

```bash
make build
```

Clean generated build output:

```bash
make clean
```

The Xcode scheme builds for Apple Silicon:

```bash
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=OS X,arch=arm64'
```

## Tests

Tests use Apple's Swift Testing framework. Fast package-integration and critical smoke coverage:

```bash
make test-smoke
```

Full suite with Thread Sanitizer:

```bash
make test-full
```

Performance and extreme-concurrency coverage:

```bash
make test-performance
```

The test suites cover package integration, sharpness and focus metrics, structured cancellation, latest-run-wins behavior, memory-cache counters, security-scoped access, disk caches, burst persistence, RAW parsing adapters, and copy startup/cleanup.
