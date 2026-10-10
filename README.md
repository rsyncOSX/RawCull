# RawCull

Current release: **3.2.9**.

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
| 🔢 | **Objects analysis** | Ask Qwen to suggest visible concepts, segment their instances with SAM 3, and assess a numbered review board. |
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

In **AI Analysis › Objects**, RawCull uses Qwen to identify photographically relevant concepts, SAM 3 to segment matching visible instances, and Qwen to assess those numbered subjects locally on your Mac. Specific concepts can be entered manually. Results describe matches for the requested concepts; they are not a guaranteed inventory of every object in the scene.

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
| `coreai-models` | `1953c4f90ba0214c1abc7bebcb9be5107e329a46` |
| `decodeencodegeneric` | `1.0.0` |
| `eventsource` | `1.5.1` |
| `parsersyncoutput` | `1.0.0` |
| `photoaikit` | `7f9adfcd69661c6bae4a640c16a4056dfc7393df` |
| `photoanalysiskit` | `1.3.1` |
| `rawcullcore` | `1.1.2` |
| `rawparserkit` | `1.3.1` |
| `rsyncarguments` | `1.0.0` |
| `rsyncprocessstreaming` | `1.0.0` |
| `swift-asn1` | `1.7.3` |
| `swift-collections` | `1.7.2` |
| `swift-crypto` | `4.5.2` |
| `swift-huggingface` | `0.13.0` |
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
  DOWNLOADED_DMG=/path/to/downloaded/RawCull.3.2.9.dmg
```

### App Store Connect and TestFlight uploads

Build, sign, and upload in one command:

```bash
./Scripts/release.sh internal   # Internal TestFlight testing only
./Scripts/release.sh appstore   # TestFlight and eligible for App Store submission
```

The Makefile equivalents are `make upload-internal` and `make upload-app-store`.
Sign in to your Apple Developer account in **Xcode Settings > Accounts** first.
Both commands use the `AppStore` configuration, automatic signing, and pinned
package versions. They preserve archives and export diagnostics under `build/releases/`.
They do not submit for App Review or publish the app.

Preview either command by adding `--dry-run`. Xcode manages upload build numbers
by default. To specify one explicitly for both the app and its extension, use
`BUILD_NUMBER=400 ./Scripts/release.sh appstore`; choose an unused build number.
For API authentication, set `ASC_KEY_PATH` to your `.p8` file and also set
`ASC_KEY_ID` and `ASC_ISSUER_ID`. Keep the key outside the repository.

After Apple processes the upload, check the build in App Store Connect and assign
it to an internal TestFlight group if automatic distribution is not enabled.
An `internal` upload cannot be used for external TestFlight or App Store submission;
use `appstore` if you want to submit that same tested build later.

### Local AI Objects release test

Run `make releastest` to analyze the ARW files directly in Downloads using installed
Qwen and SAM 3 models, without launching RawCull's UI. A run report
identified by UUID is written as `RawCull-AI-Objects-<UUID>.md` in Downloads.
See [release integration instructions](RawCullReleaseTests/README.md) for model
paths, overrides, and result semantics.

## License

RawCull is available under the [MIT License](Licence.MD). The optional AI models retain their respective licences and attribution requirements; see [`ModelAssets/Notices`](ModelAssets/Notices).
