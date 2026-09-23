# RawCull

**Cull faster. Keep the sharpest frame. Keep your photos private.**

[![macOS 27](https://img.shields.io/badge/macOS-27-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](Licence.MD)

RawCull is a native macOS app for reviewing and culling RAW photographs. It combines fast embedded previews, camera focus points, sharpness scoring, burst comparison, natural-language search, and optional on-device AI—without sending your photos to an external inference service.

> Built for Apple Silicon with Swift 6 and SwiftUI.

## Highlights

| | Feature | What it gives you |
|---|---|---|
| ⚡️ | **Fast RAW review** | Scan catalogs and browse cached thumbnails or full-size embedded previews. |
| 🎯 | **Focus intelligence** | See Sony and Nikon AF points, focus masks, saliency, and sharpness evidence. |
| 🏆 | **Burst ranking** | Group similar frames and surface the strongest candidate with confidence and cautions. |
| 🔎 | **Search by meaning** | Find photos with natural-language queries using local CLIP embeddings. |
| 🧠 | **Deep Review** | Use SAM 3 to isolate the subject and compare detail where it matters. |
| ✨ | **AI photo critique** | Ask Qwen3-VL to assess composition, exposure, visibility, expression, strengths, and problems. |
| ⭐️ | **A complete culling flow** | Tag, reject, rate, filter, compare, and persist your decisions. |
| 📦 | **Flexible export** | Export JPEG previews or copy selected RAW files with live rsync progress. |

RawCull also reads core EXIF data, supports developed RAW previews, caches compatible analysis across sessions, and monitors cache usage and memory pressure.

## Local AI, three different jobs

RawCull's AI features run locally on the Mac. Model downloads and validation are managed by the app; photographs, masks, prompts, and results stay on the device.

| Model | Purpose | Used for |
|---|---|---|
| **DataComp CLIP** | Understands image/text similarity | Semantic search, visual similarity, burst grouping, and coarse subject labels |
| **SAM 3** | Finds where a prompted subject is | Subject masks, AF-point checks, and detail-aware Deep Review |
| **Qwen3-VL** | Describes and evaluates a photograph | Structured photo assessment against editable criteria |

CLIP image embeddings are computed once and reused for later searches. SAM 3 masks and compatible analysis artifacts can also be cached. Qwen assessments are advisory: RawCull validates their structure, but the photographer remains the final judge.

## Workflow

```text
Open a RAW catalog
       ↓
Review previews, metadata, focus points, and sharpness
       ↓
Group bursts or search the catalog by description
       ↓
Compare candidates with Deep Review or Qwen analysis
       ↓
Rate, tag, reject, and export the keepers
```

## Requirements

- Apple Silicon Mac
- macOS 27
- Xcode 27 and Swift 6 for development

RawCull is focused on Sony ARW workflows. Its parsing layer also contains Nikon MakerNote support for normalized AF-point extraction.

## Architecture

The app keeps UI, workflow, caching, persistence, and culling policy in RawCull while focused Swift packages own reusable functionality:

| Package | Responsibility |
|---|---|
| [RawParserKit](https://github.com/rsyncOSX/RawParserKit) | RAW discovery, metadata, embedded JPEGs, previews, and MakerNotes |
| [PhotoAnalysisKit](https://github.com/rsyncOSX/PhotoAnalysisKit) | Sharpness, focus masks, saliency, classification, and calibration |
| [PhotoAIKit](https://github.com/rsyncOSX/PhotoAIKit) | CLIP, SAM 3, Qwen, model validation, similarity, and mask storage |
| [RawCullCore](https://github.com/rsyncOSX/RawCullCore) | Shared catalog, EXIF, burst grouping, ranking, and review models |
| [RsyncArguments](https://github.com/rsyncOSX/RsyncArguments) + [RsyncProcessStreaming](https://github.com/rsyncOSX/RsyncProcessStreaming) | Safe copy configuration and streaming execution |
| [DecodeEncodeGeneric](https://github.com/rsyncOSX/DecodeEncodeGeneric) | Codable persistence helpers |

Remote dependencies are pinned in `Package.resolved`. The exact resolved versions and revisions are:

| Package identity | Resolved pin |
|---|---|
| `coreai-models` | `475c585fdb0fe82a83c8f777f259e9414bd44c98` |
| `decodeencodegeneric` | `1.0.0` |
| `eventsource` | `1.5.1` |
| `parsersyncoutput` | `1.0.0` |
| `photoaikit` | `4be7c0187848838ba9cebf19a678139262f53133` |
| `photoanalysiskit` | `1.3.1` |
| `rawcullcore` | `1.1.2` |
| `rawparserkit` | `1.3.0` |
| `rsyncarguments` | `1.0.0` |
| `rsyncprocessstreaming` | `1.0.0` |
| `swift-asn1` | `1.7.3` |
| `swift-collections` | `1.6.0` |
| `swift-crypto` | `4.5.2` |
| `swift-huggingface` | `0.11.0` |
| `swift-jinja` | `2.5.1` |
| `swift-transformers` | `1.3.4` |
| `xgrammar` | `0.2.2` |
| `yyjson` | `0.12.0` |

Model manifests, licence notices, and provenance records live in [`ModelAssets`](ModelAssets/README.md).

## Build

Build and export a Debug archive:

```bash
make debug
```

Or build the Xcode scheme directly:

```bash
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=OS X,arch=arm64'
```

## Test

```bash
make test-smoke        # Fast integration and critical-path coverage
make test-full         # Full suite with Thread Sanitizer
make test-performance  # Performance and extreme-concurrency coverage
```

The Swift Testing suites cover RAW parsing, focus and sharpness metrics, similarity and semantic search, Deep Review, Qwen responses, downloads, caches, persistence, cancellation, concurrency, and copy workflows.

## Release

Validate the AI boundary and release inputs before building:

```bash
make verify-ai-import-boundary
make release-preflight
make build
```

`make build` creates the signed, notarized, and stapled app and DMG. It requires the configured Developer ID identity, notarytool keychain profile, and `create-dmg` at `../create-dmg/create-dmg`.

After publishing, verify the downloaded artifact against the generated SHA-256 file:

```bash
make verify-downloaded-dmg \
  DOWNLOADED_DMG=/path/to/downloaded/RawCull.3.2.5.dmg
```

## License

RawCull is available under the [MIT License](Licence.MD). The optional AI models retain their respective licences and attribution requirements; see [`ModelAssets/Notices`](ModelAssets/Notices).
