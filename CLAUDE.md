# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RawCull is a native macOS photo culling application for Sony A1 mk I/II ARW raw files. It is written in **Swift 6.0** with **SwiftUI**, targets **macOS 26 (Tahoe)+**, and runs exclusively on **Apple Silicon (arm64)**. Bundle ID: `no.blogspot.RawCull`.

## Skills

Use these skills for the relevant work in this repo:

- `/swift-concurrency` — when writing or reviewing Swift concurrency code (actors, async/await, Sendable, task groups)
- `/swift-testing-expert` — when writing or reviewing Swift Testing framework tests
- `/swiftui-expert-skill` — when writing or reviewing SwiftUI views

## Build Commands

```bash
# Release build (notarized + DMG)
make build

# Debug build (no notarization)
make debug

# Clean
make clean
```

The Makefile calls `xcodebuild -scheme RawCull -destination 'platform=OS X,arch=arm64'`.

## Testing

Tests use the **Swift Testing framework** (not XCTest), with tags: `@Tag.critical`, `@Tag.smoke`, `@Tag.performance`, `@Tag.threadSafety`, `@Tag.integration`.

```bash
# Quick smoke tests (~30s)
xcodebuild test -scheme RawCull -testFilter smoke

# Full suite with Thread Sanitizer (~5 min)
xcodebuild test -scheme RawCull -destination 'platform=macOS' -enableThreadSanitizer YES

# Performance benchmarks (~10 min)
xcodebuild test -scheme RawCull -testFilter performance
```

See `RawCullTests/TEST_ARCHITECTURE.md` for test architecture detail.

## Architecture

### Project-wide Concurrency Rules (Critical)

The build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes **all types implicitly `@MainActor`** unless explicitly annotated otherwise. Background work must explicitly opt out with `nonisolated`, `actor`, `Task.detached`, or `@concurrent`. The project complies with **Swift 6 strict concurrency** throughout — do not introduce `@preconcurrency` imports or silence concurrency errors without understanding the isolation model.

### MVVM with `@Observable`

All ViewModels are `@Observable final class` + `@MainActor`. Views receive them via `@Environment`. Use `@Bindable` when two-way binding is needed on an `@Observable` object.

**Central ViewModel:** `RawCullViewModel` is the state hub — it holds the selected catalog, file list, filtered files, selected file, zoom state, and progress. It is split across extension files: `+Catalog`, `+Culling`, `+Thumbnails`, `+Sharpness`.

**Settings singleton:** `SettingsViewModel.shared` (`@MainActor`). Actors that need settings call `await SettingsViewModel.shared.asyncgetsettings()`, which returns a `SavedSettings` value type (Codable, Sendable).

### Actor-per-Concern Concurrency

Each major background concern has its own Swift actor:

| Actor | Responsibility |
|---|---|
| `SharedMemoryCache` | Singleton NSCache wrapper; exposes cache `nonisolated(unsafe)` for sync reads (NSCache is thread-safe) |
| `ScanAndCreateThumbnails` | Batch-preloads thumbnails; RAM cache → disk cache → extraction; bounded concurrency via `withTaskGroup` |
| `DiskCacheManager` | JPEG thumbnail disk cache in `~/Library/Caches/no.blogspot.RawCull/Thumbnails/`; keyed by MD5 of source path |
| `ScanFiles` | Scans directory for ARW files, reads EXIF + Sony AF focus points |
| `DiscoverFiles` | Lightweight ARW file discovery |
| `ExtractAndSaveJPGs` | Batch-extracts embedded full-res JPEGs |

Actors communicate results back to `@MainActor` ViewModels via `Task { @MainActor in }` callbacks (the `FileHandlers` struct pattern).

### Two-Tier Thumbnail Cache

RAM (`NSCache` via `SharedMemoryCache`) → Disk (`DiskCacheManager`). Memory pressure is monitored via `DispatchSource.makeMemoryPressureSource`. The NSCache is `nonisolated(unsafe)` to allow synchronous reads without `await`.

### Sony-Specific Parsers

- **`SonyMakerNoteParser`** — Pure Swift TIFF binary parser. Walks IFD0 → ExifIFD → Sony MakerNote to extract AF focus point (tag 0x2027) from ARW files (first 4 MB only). Handles A1 and A1 II.
- **`SonyThumbnailExtractor`** — Uses ImageIO `CGImageSourceCreateThumbnailAtIndex`. Hops to `DispatchQueue.global` to avoid serializing the caller.

### Sharpness Scoring Pipeline

`FocusMaskModel` (`@Observable @unchecked Sendable`, NOT `@MainActor` — called from detached tasks): ImageIO thumbnail decode → `CIRAWFilter` (NR/sharpen disabled) → Gaussian blur → Metal Laplacian kernel (`focusLaplacian` in `Kernels.ci.metal`) → energy amplification → threshold/morphology → score as p95 tail mean. `SharpnessScoringModel` owns the batch scoring task and aperture filter.

### Multi-Window Architecture

Four SwiftUI `Scene`s defined in `RawCullApp`: main navigation window, Settings window, and two zoom preview windows (one for `CGImage`, one for `NSImage`). Zoom window focus state lives in `RawCullViewModel`.

### Rsync Copy Integration

`ExecuteCopyFiles` uses the `RsyncProcessStreaming` SPM package (from `rsyncOSX/RsyncProcessStreaming`) to copy tagged/rated ARWs. It generates a dynamic `--include-from` filter file. Source/destination paths use security-scoped URL bookmarks in `UserDefaults`.

### Persistence

- Tagged selections and ratings: JSON at `~/Documents/` or Application Support via `ReadSavedFilesJSON`/`WriteSavedFilesJSON`
- Settings: JSON at `~/Library/Application Support/RawCull/settings.json`
- Thumbnail disk cache: `~/Library/Caches/no.blogspot.RawCull/Thumbnails/`

### Logging

All logging uses `OSLog` via a `Logger` extension that adds `debugMessageOnly`, `errorMessageOnly`, `debugThreadOnly`. Logging is compiled out in Release builds (`#if DEBUG` guards). Most debug logging is commented out for performance — re-enable when debugging.
