# RawCull Test Architecture

RawCull tests use the Swift Testing framework. The suite is intended to stay
small enough to run regularly and strict enough that passing tests represent
real application behavior, not test-framework setup checks.

## Test Categories

- Smoke tests: fast deterministic checks selected by `make test-smoke`.
- Full tests: all test files with Thread Sanitizer enabled through `make test-full`.
- Performance / stress tests: long-running thread-safety stress checks selected by
  `make test-performance`.

## Shared Test Base

All tests should start from an explicit, isolated base rather than the app's
production singletons or user-visible directories. The shared helpers live in
`TestIsolationHelpers.swift`:

- `makeIsolatedCache()` creates a `SharedMemoryCache` with thumbnail and full-size
  JPEG disk caches rooted under a unique `RawCullTests/<test-name>-<UUID>`
  temporary directory.
- `makeIsolatedThumbnailProvider()` returns a `RequestThumbnail` wired to an
  isolated cache for request/cache tests.
- `makeIsolatedSettingsViewModel()` returns a `SettingsViewModel` backed by a
  unique temporary `settings.json` path and skips production settings loading.

Use these helpers whenever a test touches shared cache, disk cache, thumbnail,
or settings state. Tests that need lower-level fixtures may define private
factory functions in their own file, but those factories should follow the same
base rule: unique temporary paths, synthetic data, and no dependency on a user's
real photo library, settings, cache, or Documents folder.

The only tests that should intentionally touch singleton-like shared state are
Thread Sanitizer stress tests, and those tests must make that intent obvious in
the suite name, tag, or test body.

## Quality Bar

- Tests should assert RawCull behavior or state transitions directly.
- Manual diagnostics, local-path RAW-file probes, templates, and console-only checks
  do not belong in the automated target.
- Placeholder assertions such as `#expect(true)` should be removed or replaced with
  assertions against production APIs.
- Shared state tests should use isolated temporary caches/settings unless they are
  deliberately exercising the singleton under Thread Sanitizer.
- Unit tests should target parser, math, cache, concurrency, persistence, and
  view-model behavior. Pure SwiftUI rendering/layout, the `RawCullApp` entry
  point, simple display-only models, and live process integrations belong outside
  this unit target unless they gain meaningful business logic.

## Current Focus Areas

- RAW metadata parsers using synthetic fixture data.
- Thumbnail request/cache behavior, cancellation, and loader concurrency bounds.
- Sharpness and similarity scoring numeric behavior.
- View-model navigation, zoom overlay, and security-scoped path behavior.
- TSan-oriented stress tests for RawCull shared cache state.

## Current Test Files

- `CancellableImageIOWorkTests.swift`: cancellation, success, failure, and cleanup
  behavior around cancellable ImageIO work.
- `CullingModelTests.swift`: rating/tagging state transitions, file selection, and
  culling model behavior.
- `DiskCacheAndScanAdmissionTests.swift`: thumbnail/full-size disk cache behavior
  and scan admission decisions using temporary cache roots.
- `NikonMakerNoteParserTests.swift`: Nikon MakerNote parsing and embedded JPEG
  locator behavior from synthetic fixture data.
- `RawCullTestsConcurrencyTests.swift`: isolated shared cache counters and settings
  persistence/concurrency behavior.
- `RawCullTestsDataRaceDetectionTests.swift`: TSan-focused shared cache stress
  coverage that deliberately exercises concurrent access paths.
- `RawCullViewModelSecurityScopeTests.swift`: security-scoped catalog access
  lifecycle behavior on the `@MainActor` view model.
- `ScanAndExtractJPGsTests.swift`: scan/extraction coordination behavior.
- `ScanFilesSortAndFormatTests.swift`: file sorting and display formatting rules.
- `SharpnessScoringTests.swift`: sharpness scoring, focus-mask numeric helpers,
  aperture hints, and ISO scaling.
- `SimilarityScoringTests.swift`: similarity ordering, empty/missing anchors,
  subject mismatch penalties, and cancellation.
- `SonyMakerNoteParserTests.swift`: Sony MakerNote parsing and embedded JPEG
  locator behavior from synthetic ARW fixture data.
- `ThumbnailLoaderConcurrencyTests.swift`: thumbnail loader concurrency bounds and
  cancellation under stress.
- `ThumbnailProviderTests.swift`: thumbnail request/cache behavior, cache config,
  and cached thumbnail cost.
