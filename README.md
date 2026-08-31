# RawCull

RawCull is a native macOS application for quickly reviewing and culling RAW photographs. It keeps catalog, rating, comparison, thumbnail, export, sharpness, focus, similarity, burst-grouping, and manual-review workflows local to the Mac.

Image similarity uses Apple Vision feature prints through `PhotoAnalysisKit`. Vision is the single similarity backend; no separately downloaded model assets or downloader extension are required.

## Requirements

- Apple Silicon Mac
- Xcode 27 beta and Swift 6 for the current development branch

The Tahoe deployment-target conversion is tracked in [Docs/macOS26version.md](Docs/macOS26version.md).

## Architecture

```text
RawCull views and view model
    -> similarity and burst orchestration
        -> RawCull-owned Vision artifact store
            -> PhotoAnalysisKit.VisionFeaturePrintBackend
                -> Apple Vision
```

The Vision index is cache data. It is stored per source file, validated against the source fingerprint and Vision representation, and may be safely regenerated. Catalogs, ratings, source photographs, and exported files are outside that cache boundary.

## Resolved packages

| Package | Version | Purpose |
| --- | --- | --- |
| `decodeencodegeneric` | `1.0.0` | Codable support |
| `parsersyncoutput` | `1.0.0` | rsync output parsing |
| `photoanalysiskit` | `1.2.2` | Focus, sharpness, saliency, and Vision feature prints |
| `rawcullcore` | `1.1.2` | Shared RawCull domain types |
| `rawparserkit` | `1.2.9` | RAW parsing and thumbnail extraction |
| `rsyncarguments` | `1.0.0` | rsync argument construction |
| `rsyncprocessstreaming` | `1.0.0` | rsync process execution and streaming |

## Build and test

Open `RawCull.xcodeproj` in Xcode, or build from the command line:

```sh
xcodebuild -project RawCull.xcodeproj -scheme RawCull -destination 'platform=macOS' build
```

The test suite covers retained culling workflows, PhotoAnalysisKit integration, Vision artifact persistence, similarity orchestration, cache boundaries, and release metadata.

## License

RawCull is available under the MIT License. See [Licence.MD](Licence.MD).
