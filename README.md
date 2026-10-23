# RawCull

Current project version: **3.3.5**.

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
| 🖼️ | **Combined Review** | Review selected or tagged photos with retained images, findings, supporting crops, coverage limits, and a structured technical record. |
| ✨ | **AI photo critique** | Ask Qwen3-VL to assess composition, exposure, visibility, expression, strengths, and problems. |
| 🔢 | **Objects analysis** | Ask Qwen to suggest visible concepts, segment their instances with SAM 3, and assess a numbered review board. |
| ⭐️ | **A complete culling flow** | Tag, reject, rate, filter, compare, and persist your decisions. |
| 📦 | **Flexible export** | Export JPEG previews or copy selected RAW files with live rsync progress. |

RawCull also reads core EXIF data, supports developed RAW previews, caches compatible analysis across sessions, and monitors cache usage and memory pressure.

## Local AI

RawCull's AI features run locally on the Mac. Model downloads and validation are managed by the app; photographs, masks, prompts, and results stay on the device.

| Model | Purpose | Used for |
|---|---|---|
| **DataComp CLIP** | Understands image/text similarity | Semantic search, visual similarity, burst grouping, and coarse subject labels |
| **SAM 3** | Finds where a prompted subject is | Subject masks, AF-point checks, and detail-aware Deep Review |
| **Qwen3-VL** | Describes and evaluates a photograph | Structured photo assessment against editable criteria |

In **AI Analysis › Objects**, RawCull uses Qwen to identify photographically relevant concepts, SAM 3 to segment matching visible instances, and Qwen to assess those numbered subjects locally on your Mac. Specific concepts can be entered manually. Results describe matches for the requested concepts; they are not a guaranteed inventory of every object in the scene.

CLIP image embeddings are computed once and reused for later searches. SAM 3 masks and compatible analysis artifacts can also be cached. Qwen assessments are advisory: RawCull validates their structure, but the photographer remains the final judge.

## Combined Review

Open **Combined Review** from the dedicated toolbar button beside **AI Analysis**, then choose selected or tagged images as the input.

The default Photo-first workspace pairs the retained overview with concise findings, coverage limits, and optional reviewed-region overlays. **Inspect evidence** opens the supporting crop and observations in the Evidence workspace. You can return to Photo-first while keeping the selected image and region.

Saved reviews remain available outside the current input selection. Review settings, retention cleanup, selection comparison, and run diagnostics are available through disclosure controls. The complete structured record can be inspected and copied as JSON.

Findings retain their evidence limits and conflicts. If synthesis fails, available observations are labeled as observations only. Missing retained images do not erase the report or measurements.

## Workflow

```text
Open a RAW catalog
       ↓
Review previews, metadata, focus points, and sharpness
       ↓
Group bursts or search the catalog by description
       ↓
Compare candidates with Deep Review, Qwen, or Combined Review
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

Remote dependencies are pinned in [`Package.resolved`](RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). The current resolved versions are:

| Package identity | Resolved pin |
|---|---|
| `coreai-models` | `1.0.0` |
| `decodeencodegeneric` | `1.0.0` |
| `eventsource` | `1.5.1` |
| `parsersyncoutput` | `1.0.0` |
| `photoaikit` | `1.0.0` |
| `photoanalysiskit` | `1.3.1` |
| `rawcullcore` | `1.1.2` |
| `rawparserkit` | `1.3.2` |
| `rsyncarguments` | `1.0.0` |
| `rsyncprocessstreaming` | `1.0.0` |
| `swift-asn1` | `1.7.3` |
| `swift-collections` | `1.7.3` |
| `swift-crypto` | `4.5.2` |
| `swift-huggingface` | `1.0.0` |
| `swift-jinja` | `2.5.1` |
| `swift-transformers` | `1.3.5` |
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
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile
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
  DOWNLOADED_DMG=/path/to/downloaded/RawCull.3.3.5.dmg
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

### Local release integration tests

Run `make releaseaiobjectstest` to analyze the ARW files directly in Downloads using installed
Qwen and SAM 3 models, without launching RawCull's UI. A run report
identified by UUID is written as `RawCull-AI-Objects-<UUID>.md` in Downloads.
See [release integration instructions](RawCullReleaseTests/README.md) for model
paths, overrides, and result semantics. The linked guide also contains historical baseline details; use the current Makefile target above for AI Objects.

Additional opt-in checks are available:

```bash
make releasesharpnesstest  # Catalog sharpness report; no Qwen or SAM 3 required
make combinedinputstest   # Combined Review input-contract probes with installed models
make combinedselectiontest # Six-file Sony source/crop probe and selection comparison
```

The catalog-based checks default to `$HOME/Downloads`; override it with
`RELEASE_CATALOG=/path/to/photos`. AI Objects defaults to model bundles under
`$HOME/ModelAssets/Release/Models`; override them with `RELEASE_MODELS`,
`RELEASE_QWEN`, or `RELEASE_SAM3`. Input-contract probes use `INPUT_PROBE_MODELS`
and write to `INPUT_PROBE_OUTPUT` (default `/tmp/rawcull-combined-input-probe`).

## License

RawCull is available under the [MIT License](Licence.MD). The optional AI models retain their respective licences and attribution requirements; see [`ModelAssets/Notices`](ModelAssets/Notices).
