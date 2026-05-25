# Swift Package Candidates — RawCull

> Deep analysis across all actors, models, parsers, and engine files.
> Scope: identify self-contained units that have a clean seam, are critical to RawCull's correct operation, would benefit from their own test suite, and would reduce complexity inside the main target.
>
> **Precedent:** the author has already shipped this pattern five times —
> `DecodeEncodeGeneric`, `RsyncProcessStreaming`, `RsyncArguments`, `ParseRsyncOutput`, `RsyncAnalyse` — all from `rsyncOSX`. The proposals below follow the same philosophy.

---

## Executive Summary

| # | Package | Files | Framework deps | Existing tests | Extraction effort |
|---|---|---|---|---|---|
| 1 | **RawParserKit** | 13 | Foundation, CoreGraphics, ImageIO, CoreImage, AppKit* | `SonyMakerNoteParserTests`, `NikonMakerNoteParserTests`, `CancellableImageIOWorkTests` | 🟢 Low |
| 2 | **BurstAnalysisKit** | 9 | Foundation only | `BurstAnalysisTests` (substantial) | 🟢 Low |
| 3 | **ThumbnailCacheKit** | 9 | AppKit, CryptoKit, Foundation, ImageIO | `DiskCacheAndScanAdmissionTests`, `ThumbnailLoaderConcurrencyTests` | 🟡 Medium |
| 4 | **RawFileDiscovery** | 5 | Foundation, ImageIO, AppKit* | `ScanFilesSortAndFormatTests` | 🟡 Medium |
| 5 | **CullingPersistence** | 5 | Foundation, `DecodeEncodeGeneric` | `CullingModelTests` | 🟢 Low |

*AppKit required only for `NSImage` / `CGImage` — the parsers themselves have zero AppKit dependency.

---

## Package 1 — `RawParserKit`

### Purpose

Everything that knows about camera vendor binary formats lives here: TIFF walking, MakerNote extraction, embedded-JPEG location, cancellable ImageIO work, and the vendor registry that ties them together. This is the most distinctive and critical knowledge in RawCull — nothing else in the macOS ecosystem provides Sony A1 / Nikon binary parsing at this level.

### Files that move

| File | Role | Line count |
|---|---|---|
| `Enum/RawFormat.swift` | Protocol defining vendor contract | ~45 |
| `Enum/RawFormatRegistry.swift` | Extension→vendor lookup | ~27 |
| `Enum/RawParserDiagnostics.swift` | Generic parse result + trace container | ~7 |
| `Enum/SonyMakerNoteParser.swift` | Sony ARW TIFF binary walker, AF focus extraction, JPEG offsets | ~539 |
| `Enum/NikonMakerNoteParser.swift` | Nikon NEF TIFF binary walker, AF focus extraction, JPEG offsets | ~633 |
| `Enum/SonyRawFormat.swift` | `RawFormat` conformer wiring Sony extractors | ~60 |
| `Enum/NikonRawFormat.swift` | `RawFormat` conformer wiring Nikon extractors | ~66 |
| `Enum/JPGSonyARWExtractor.swift` | ImageIO + binary fallback JPEG extraction from ARW | ~205 |
| `Enum/JPGNikonNEFExtractor.swift` | ImageIO + SubIFD fallback JPEG extraction from NEF | ~163 |
| `Enum/SonyThumbnailExtractor.swift` | ImageIO thumbnail builder with Sony JPEG re-render | ~152 |
| `Enum/NikonThumbnailExtractor.swift` | ImageIO thumbnail builder with Nikon interpolation | ~92 |
| `Enum/ThumbnailSharpener.swift` | `CIRAWFilter` sharpened preview builder | ~79 |
| `Enum/CancellableImageIOWork.swift` | Background-queue ImageIO with cooperative cancellation | ~120 |

**Total: ~2,188 lines → moves out of main target completely.**

### Framework dependencies

```
Foundation          — FileHandle, Data, URL
CoreGraphics        — CGImage
ImageIO             — CGImageSource
CoreImage           — CIRAWFilter (ThumbnailSharpener only)
AppKit              — NSImage (thumbnail extractors only; easy to isolate behind a typealias)
```

No SwiftUI. No `@MainActor`. No app-specific state.

### Key clean points

- `SonyMakerNoteParser` and `NikonMakerNoteParser` import **Foundation only**. They are pure binary-data processors — no framework side effects at all.
- `CancellableImageIOWork` imports Foundation + os. It is a self-contained concurrency utility with no dependency on any other project file.
- `RawFormat` protocol and `RawFormatRegistry` have no external app dependencies; they are a pure dispatch table.
- The only coupling to the rest of RawCull is `ThumbnailError` (a 3-case enum) and `Logger.process` (OSLog). Both are trivially re-housed inside the package.

### Existing tests that would move with it

| Test file | Coverage |
|---|---|
| `SonyMakerNoteParserTests.swift` | Synthetic ARW binary blobs; fast/slow path; SONY DSC header; focus tag variants |
| `NikonMakerNoteParserTests.swift` | Synthetic NEF binary blobs; version variants; AF coordinate extraction |
| `CancellableImageIOWorkTests.swift` | Cancellation before decode; Sony/Nikon extraction cancellation |

These tests use **only Foundation + synthetic binary data** — they already have no app dependency and would run in the package without modification.

### Why this package matters for RawCull

- The TIFF binary parsing is the hardest code in the app to get right, and the most likely source of regressions when Sony/Nikon release new camera bodies or firmware.
- Isolating it lets you run the parser tests in isolation without booting the full app model stack.
- A clean public API (`SonyMakerNoteParser.focusLocation(from:)`, `RawFormatRegistry.format(for:)`) makes it trivial to add a third vendor (e.g. Fujifilm RAF) without touching the main target.
- The tests already demonstrate the approach: synthetic binary blobs, no real files needed.

### Additional test cases the package should gain

- Real-world focus-location round-trip: read from a known good ARW, assert normalised `CGPoint` within expected crop.
- `RawFormatRegistry` round-trips all registered extensions.
- `CancellableImageIOWork` token behaviour under task group cancellation.
- `ThumbnailSharpener` produces non-nil output for a 1×1 synthetic RAW CGImage.

### Extraction blockers / risks

- `SonyThumbnailExtractor` and `NikonThumbnailExtractor` import AppKit for `NSImage`. This is fine — AppKit is available on macOS — but should be clearly declared in the package manifest.
- `Logger.process` is a project-level OSLog category. Replace with a package-local logger or accept a `Logger` parameter.
- Effort: rename `ThumbnailError` to stay inside the package; update the few call sites in `RequestThumbnail` and `ScanAndCreateThumbnails` to import the package.

---

## Package 2 — `BurstAnalysisKit`

### Purpose

The burst-grouping and burst-ranking engines are **pure deterministic algorithms** with no I/O, no framework side effects, and no UI coupling. They receive value-type inputs and return value-type outputs. This is textbook package material.

### Files that move

| File | Role | Line count |
|---|---|---|
| `Enum/BurstGroupingEngine.swift` | Groups adjacent frames by visual distance + time gap + metadata deltas | ~135 |
| `Enum/BurstRankingEngine.swift` | Ranks candidates inside a group by sharpness, saliency, and stability | ~254 |
| `Model/ViewModels/BurstAnalysisModels.swift` | All burst value types: `BurstGroup`, `BurstGroupingConfig`, `BurstPairKey`, `BurstBoundaryEvidence`, `BurstDecisionConfidence`, `BurstCandidateScore`, `BurstAnalysisResult`, `BurstReviewState`, `BurstWinnerOverride`, etc. | ~335 |
| `Actors/BurstAnalysisCache.swift` | Persists/loads burst analysis snapshots; validates against current catalog | ~118 |
| `Model/ARWSourceItems/FileItem.swift` | `FileItem` + `ARWSourceCatalog` + `ExifMetadata` — the input model | ~48 |
| `Extensions/extension+String+Date.swift` | Date formatting helper | ~19 |
| `Extensions/SupportedFileType.swift` | Supported extension enum | ~16 |

Also needs: `SaliencyInfo` (currently inside `FocusMaskModel.swift` — extract its definition into this package as a plain value type).

**Total: ~925 lines → moves out of main target completely.**

### Framework dependencies

```
Foundation   — Codable, FileManager (BurstAnalysisCache), Date
CoreGraphics — CGPoint (focus normalised coordinate in FileItem)
```

No AppKit. No SwiftUI. No `@MainActor` in the engines. `BurstAnalysisCache` uses `MainActor.run` for encode/decode, but this is removable with a straightforward actor refactor.

### Key clean points

- `BurstGroupingEngine.group(files:adjacentDistances:config:)` is a pure static function. Input: `[FileItem]` + `[String: Float]` distance dictionary + config. Output: `BurstGroupingOutput`. Zero side effects.
- `BurstRankingEngine.rankGroup(_:filesByID:scores:maxScore:saliencyInfo:boundaryEvidence:)` is identical in character — pure static, value-type in, value-type out.
- `BurstGroupingConfig` controls all thresholds (time gap, visual distance, focal-length delta), making behaviour fully parameterisable from tests.

### Existing tests that would move with it

| Test file | Coverage |
|---|---|
| `BurstAnalysisTests.swift` | Groups adjacent frames below threshold; splits on visual distance; splits on time gap + metadata; ranking by sharpness; high/medium/low confidence; manual override state; undo entry construction |

The test suite already uses synthetic `FileItem` construction helpers — no real files, no network, no disk. Tests would compile and pass inside the package with zero changes.

### Why this package matters for RawCull

- `BurstGroupingEngine` and `BurstRankingEngine` are called inside `SimilarityScoringModel` which already has ~498 lines. Extracting the engines removes the most complex logic from an already large file.
- Burst analysis correctness is directly visible to users (wrong "best" pick in a burst is immediately noticed). Owning a rich test suite in the package gives confidence when tuning thresholds.
- `BurstAnalysisModels.swift` at 335 lines defines types referenced from at least six other files in the main target. A package forces a clean import boundary.
- The pure-function nature makes property-based testing trivially applicable: random sequences of `FileItem` timestamps → assert group membership is deterministic and stable.

### Additional test cases the package should gain

- `BurstGroupingEngine`: single-file input produces one singleton group.
- `BurstGroupingEngine`: identical timestamps still produce exactly one group.
- `BurstRankingEngine`: when all scores are equal, recommendation is stable (same file ID each run).
- `BurstRankingEngine`: saliency label mismatch penalty actually reduces score of the penalised candidate.
- `BurstAnalysisCache`: round-trip encode/decode preserves all fields.
- `BurstAnalysisCache`: stale snapshot (file count mismatch) is rejected.

### Extraction blockers / risks

- `SaliencyInfo` is currently a nested type inside `FocusMaskModel.swift`. Extract its `struct SaliencyInfo: Codable, Sendable` definition into this package (it is a plain value type with no framework dependency).
- `FileItem` imports SwiftUI for `CGPoint` colour — replace with `CoreGraphics` import only.
- `BurstAnalysisCache` calls `MainActor.run` during JSON decode. This can be replaced with a straightforward `actor BurstAnalysisCache` without `@MainActor` and calling with `await` at the call site.

---

## Package 3 — `ThumbnailCacheKit`

### Purpose

The two-tier cache (RAM `NSCache` + disk JPEG cache) is performance-critical infrastructure. Concurrency bugs here cause thumbnail corruption or stale images. Isolating it into a package with a focused test suite — separate from the full app model — is the most effective way to harden it.

### Files that move

| File | Role | Line count |
|---|---|---|
| `Actors/DiskCacheManager.swift` | JPEG disk cache; load/save/prune; keyed by MD5(path) | ~147 |
| `Actors/FullSizeJPGDiskCache.swift` | Full-size JPEG disk cache; separate directory; prune/size utilities | ~151 |
| `Actors/SharedMemoryCache.swift` | `NSCache` singleton wrapper; `nonisolated(unsafe)` for sync reads | ~? |
| `Actors/SaveJPGImage.swift` | Encodes and saves JPEG data next to a RAW file | ~56 |
| `Actors/RequestThumbnail.swift` | Resolves a thumbnail: RAM → disk → cold RAW extraction; promotes to RAM | ~146 |
| `Model/Cache/CacheConfig.swift` | Capacity presets (production / testing) | ~36 |
| `Model/Cache/CacheStatistics.swift` | Hit/miss/eviction counters | ~16 |
| `Model/Cache/CachedThumbnail.swift` | `NSImage` wrapper with cost metadata | ~65 |
| `Model/Cache/CacheDelegate.swift` | `NSCache` eviction tracker | ~106 |

**Total: ~723+ lines → moves out of main target.**

### Framework dependencies

```
Foundation          — URL, FileManager, Data
AppKit              — NSCache, NSImage
CryptoKit           — MD5 for cache key derivation
ImageIO             — JPEG encoding/decoding
os / OSLog          — logging
UniformTypeIdentifiers — UTType.jpeg
```

### Key clean points

- `DiskCacheManager` has only one project dependency: `Logger.process`. Replace with a package-local logger.
- `FullSizeJPGDiskCache` has only `Logger.process`. Same fix.
- `SaveJPGImage` has only `Logger.process`.
- `CacheConfig` and `CacheStatistics` have **zero** project dependencies — they compile standalone today.
- `CachedThumbnail` couples to `SharedMemoryCache` only for a cost constant. Move the constant into `CacheConfig`.
- The cache actors do not reference `SettingsViewModel`, `RawCullViewModel`, or any SwiftUI type.

### Existing tests that would move with it

| Test file | Coverage |
|---|---|
| `DiskCacheAndScanAdmissionTests.swift` | Save + load round-trip; overwrite; pruning; size reporting; scan admission logic |
| `ThumbnailLoaderConcurrencyTests.swift` | Slot saturation → waiter queues; cancelled waiter does not consume slot; max observed active tasks |

### Why this package matters for RawCull

- The cache is the primary path for every image shown in the grid. A regression here produces blank thumbnails, stale images, or memory blow-ups — all highly visible.
- `ThumbnailLoader` manages concurrency slots; `RequestThumbnail` manages three-tier fallback. Both have subtle cancellation semantics. The existing concurrency tests for `ThumbnailLoader` are a strong starting point, but they currently live in the monolithic test target that compiles the entire app.
- Isolating the cache package dramatically reduces cold-compile time for the cache tests: no `FocusMaskModel`, no `SharpnessScoringModel`, no Metal kernel.
- A `CacheConfig` with a test preset (tiny limits, temp directory) is already there — the package just needs to surface it as a public testing helper.

### Additional test cases the package should gain

- `DiskCacheManager`: cache miss returns `nil`.
- `DiskCacheManager`: prune removes oldest entries when over limit.
- `SharedMemoryCache`: concurrent reads from multiple tasks don't corrupt the count.
- `RequestThumbnail`: RAM hit skips disk load (verify with a spy/stub `DiskCacheManager`).
- `CacheDelegate`: eviction increments the eviction counter exactly once per evicted object.
- Memory-pressure simulation: inject a `.warning` pressure event; assert the cache is cleared.

### Extraction blockers / risks

- `RequestThumbnail` depends on `RawFormatRegistry` (from Package 1) for cold extraction. Either accept **RawParserKit** as a dependency of ThumbnailCacheKit, or make the cold-extraction path injectable via a closure/protocol to keep the packages independent.
- `ThumbnailLoader` reads settings via `SettingsViewModel.shared`. Inject `maxConcurrentThumbnails: Int` as a constructor parameter instead.
- `CachedThumbnail` references `SharedMemoryCache.costPerPixel`. Move this constant to `CacheConfig`.

---

## Package 4 — `RawFileDiscovery`

### Purpose

Enumerating a directory, filtering by supported extension, and reading EXIF + MakerNote metadata into `FileItem` values. This is the entry point to every session in RawCull. Clean extraction means the scan layer can be tested with a temporary directory of synthetic files, with no app model involved.

### Files that move

| File | Role | Line count |
|---|---|---|
| `Actors/DiscoverFiles.swift` | Lists supported file URLs in a catalog folder | ~34 |
| `Actors/ScanFiles.swift` | Scans ARW/NEF files; reads EXIF; extracts AF focus via MakerNote | ~245 |
| `Model/ARWSourceItems/FileItem.swift` | `FileItem`, `ARWSourceCatalog`, `ExifMetadata` | ~48 |
| `Extensions/SupportedFileType.swift` | Supported extension enum | ~16 |
| `Extensions/ThumbnailError.swift` | 3-case error enum | ~? |

Depends on **RawParserKit** (Package 1) for `RawFormatRegistry` and the vendor parsers.

**Total: ~343 lines → moves out of main target.**

### Framework dependencies

```
Foundation  — FileManager, URL, FileHandle
ImageIO     — EXIF metadata extraction
AppKit      — minor (DiscoverFiles uses NSWorkspace for UTType resolution; replaceable with UTType directly)
```

### Key clean points

- `DiscoverFiles` is 34 lines of `FileManager` enumeration. Its only project dependency is `RawFormatRegistry`.
- `ScanFiles` uses a `@MainActor` progress callback. This is the only coupling to the main actor — convert to an `AsyncStream<Int>` or a plain `(Int) -> Void` on `nonisolated` context for a cleaner API.
- `FileItem` already has no SwiftUI dependency if `CGPoint` is imported from CoreGraphics (noted in Package 2 above).
- `ExifMetadata` is a plain `Codable, Sendable` struct — no framework deps beyond Foundation.

### Existing tests that would move with it

| Test file | Coverage |
|---|---|
| `ScanFilesSortAndFormatTests.swift` | Sort ordering; date formatting; file-format round-trips |

### Why this package matters for RawCull

- `ScanFiles` reads the first 4 MB of every ARW/NEF. Getting the byte-range wrong causes focus-point extraction to fail silently. A package with its own test fixtures (tiny synthetic TIFF files) catches this class of bug in isolation.
- Decoupling `FileItem` and `ExifMetadata` into a shared package also removes the SwiftUI import from the data model — a correctness improvement.
- When adding a third camera vendor, the only files to change are in RawParserKit and RawFileDiscovery, not the main app.

### Additional test cases the package should gain

- `DiscoverFiles`: only returns files with supported extensions; ignores `.DS_Store`, `.xmp`, etc.
- `ScanFiles`: returns an empty array for an empty directory.
- `ScanFiles`: synthetic ARW (from Package 1's test helpers) produces a `FileItem` with a non-nil `afFocusNormalized`.
- `FileItem`: EXIF aperture string `"f/5.6"` round-trips to `apertureValue: 5.6`.

### Extraction blockers / risks

- `ScanFiles` calls a `@MainActor` progress closure. Refactor to an async-friendly callback before extracting.
- `DiscoverFiles` imports AppKit only for `NSWorkspace`. Replace with `UTType(filenameExtension:)` from UniformTypeIdentifiers — removes the AppKit dependency entirely.
- `FileItem` moves from ARWSourceItems into this package's public interface; all other packages/the main target import it from here.

---

## Package 5 — `CullingPersistence`

### Purpose

JSON-backed persistence of ratings, keepers, and rejections — the user's entire curation session. This layer is small, well-defined, and already tested. Extracting it removes all JSON serialisation code from the main target and makes the persistence contract explicit and independently verifiable.

### Files that move

| File | Role | Line count |
|---|---|---|
| `Model/JSON/SavedFiles.swift` | `SavedFiles` + `FileRecord` Codable models | ~119 |
| `Model/JSON/ReadSavedFilesJSON.swift` | Reads `savedfiles.json` from Application Support | ~64 |
| `Model/JSON/WriteSavedFilesJSON.swift` | Writes `savedfiles.json` to Application Support | ~78 |
| `Model/JSON/DecodeSavedFiles.swift` | Decodes legacy `DecodeFileRecord` format | ~67 |
| `Model/ViewModels/CullingModel.swift` | Manages in-memory rating state; debounced save; `updateRating`/`toggleTag` | ~220 |

Depends on: `DecodeEncodeGeneric` (already a package — reuse the same dep), `BurstAnalysisKit` (for `BurstWinnerOverride` stored in `SavedFiles`).

**Total: ~548 lines → moves out of main target.**

### Framework dependencies

```
Foundation          — Codable, FileManager, JSONEncoder/Decoder, Application Support path
DecodeEncodeGeneric — rsyncOSX package (already in use)
```

No AppKit. No SwiftUI. No `@MainActor` in the persistence layer itself.

### Key clean points

- `ReadSavedFilesJSON` and `WriteSavedFilesJSON` each have one job: read or write a single JSON file. No project type dependencies beyond `SavedFiles`.
- `CullingModel` uses a debounced save pattern (`Task.sleep` + snapshot capture) that is already tested in `CullingModelTests`. Its only framework needs are Foundation and a `Task` call.
- `SavedFiles` / `FileRecord` are `Codable, Sendable` value types — ideal package surface types.

### Existing tests that would move with it

| Test file | Coverage |
|---|---|
| `CullingModelTests.swift` | `updateRating` creates catalog record + debounced save snapshot; multiple rapid updates debounce to a single save |

### Why this package matters for RawCull

- Data loss in this layer (ratings not saved, or corrupted JSON on merge) directly destroys user work. Tests that run the full save/load cycle against a temp directory — without the full app model — are the most reliable regression guard.
- `CullingModel` at 220 lines is currently compiled inside the main target alongside Metal kernels, Vision requests, and SwiftUI views. Moving it to a package that only needs Foundation makes it much faster to iterate on persistence logic.
- `DecodeSavedFiles` handles a legacy format. Keeping this in a package with a dedicated round-trip test prevents silent decode failures when the format evolves.

### Additional test cases the package should gain

- `WriteSavedFilesJSON` + `ReadSavedFilesJSON`: full round-trip with a temp directory; loaded data equals saved data.
- `DecodeSavedFiles`: legacy format (missing `burstWinnerOverrides` key) decodes without crashing.
- `CullingModel.toggleTag`: toggling twice returns to original unrated state.
- `CullingModel.mergeRatings`: merge of two catalogs with overlapping file names keeps the newest rating.
- Concurrent `updateRating` calls from multiple tasks: final saved state is consistent (thread-safety check).

### Extraction blockers / risks

- `CullingModel` references `BurstWinnerOverride` from `BurstAnalysisModels`. Either declare `BurstAnalysisKit` as a dependency of `CullingPersistence`, or move `BurstWinnerOverride` here (it's a `Codable` enum — it belongs with persistence).
- Application Support path is hardcoded (`no.blogspot.RawCull`). Inject the base directory as a constructor parameter so tests can redirect to a temp directory (already done in `CullingModelTests` indirectly — formalise it).

---

## Dependency Graph

```
Foundation / CoreGraphics / ImageIO / AppKit
        │
        ▼
 ┌─────────────────┐
 │  RawParserKit   │  ← SonyMakerNoteParser, NikonMakerNoteParser,
 │  (Package 1)    │    RawFormat protocol, extractors, CancellableImageIOWork
 └────────┬────────┘
          │ used by
          ▼
 ┌─────────────────┐
 │ RawFileDiscovery│  ← DiscoverFiles, ScanFiles, FileItem, ExifMetadata
 │  (Package 4)    │
 └────────┬────────┘
          │ FileItem used by
          ▼
 ┌─────────────────┐        ┌──────────────────┐
 │ BurstAnalysisKit│        │ CullingPersistence│
 │  (Package 2)    │        │   (Package 5)     │
 └────────┬────────┘        └────────┬──────────┘
          │                          │
          │       both used by       │
          └──────────┬───────────────┘
                     │
          ┌──────────▼───────────┐
          │  ThumbnailCacheKit   │  ← DiskCacheManager, SharedMemoryCache,
          │    (Package 3)       │    ThumbnailLoader, RequestThumbnail
          └──────────┬───────────┘
                     │
                     ▼
              RawCull.app (main target)
              FocusMaskModel, SharpnessScoringModel,
              SimilarityScoringModel, SwiftUI Views,
              Metal kernels, Vision/Accelerate pipelines
```

---

## What Stays in the Main Target

These are explicitly not package candidates because they carry framework side effects that cannot be cleanly separated without a large refactor:

| Component | Why it stays |
|---|---|
| `FocusMaskModel` (~1,150 lines) | `Accelerate`, `CoreImage`, `Vision`, `Metal`, `@Observable`, `@MainActor` — every Apple framework |
| `SharpnessScoringModel` (~307 lines) | `@Observable @MainActor`, Metal pipeline, Vision saliency — tightly coupled to the rendering loop |
| `SimilarityScoringModel` (~498 lines) | Vision embedding, ImageIO decode, `@MainActor`, async task group — mixed pure/impure; pure parts (`computeAdjacentDistances`) *could* move to BurstAnalysisKit later |
| `ZoomPreviewHandler` | SwiftUI window management |
| All `Views/` | SwiftUI — by definition |
| `RawCullViewModel` and its extensions | App state hub, `@Observable @MainActor` |
| `SettingsViewModel` | `@Observable @MainActor` singleton |

---

## Suggested Implementation Order

1. **RawParserKit** first — zero app dependencies, existing tests pass immediately, unblocks all other packages.
2. **BurstAnalysisKit** second — pure logic, substantial test coverage already written, no AppKit.
3. **CullingPersistence** third — small, standalone, `DecodeEncodeGeneric` dep already managed.
4. **RawFileDiscovery** fourth — depends on RawParserKit being published first.
5. **ThumbnailCacheKit** last — largest refactor (settings injection, RawParserKit dep decision).
