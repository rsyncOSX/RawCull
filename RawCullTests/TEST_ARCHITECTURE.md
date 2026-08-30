# RawCullVerify Test Architecture

RawCullVerify tests use the Swift Testing framework. The suite is intended to stay
small enough to run regularly and strict enough that passing tests represent
real application behavior, not test-framework setup checks.

## Test Categories and Manifests

- Smoke tests: fast deterministic checks selected by `make test-smoke` through
  `TestManifests/SmokeTests.txt`.
- Full tests: all test files with Thread Sanitizer enabled through `make test-full`.
- Performance / stress tests: long-running thread-safety stress checks and the
  PhotoAIKit Vision similarity benchmark selected by `make test-performance`
  through `TestManifests/PerformanceTests.txt`.

Xcode 27 does not expose Swift Testing tags as a command-line selector, so the
checked-in response files are the selection authority. `make test-smoke` and
`make test-performance` enumerate their response files before execution. The
enumeration verifier rejects duplicate identifiers and count changes; the
current baselines are 206 unique smoke identifiers and 2 unique performance
identifiers. `SmokeManifestIntegrityTests` also rejects selector edits and any
source `.smoke` declaration whose containing suite is absent from the manifest.
An intentional addition, removal, or rename therefore requires one reviewable
update to the source test, response file, expected selector inventory, and Make
enumeration count.

The smoke manifest deliberately selects whole suites for every source smoke
declaration, plus exact identifiers for core culling cancellation and the
non-benchmark PhotoAIKit migration matrix. Mandatory AI coverage maps as follows:

- PhotoAnalysisKit integration and Vision fallback:
  `PhotoAnalysisKitIntegrationTests` and the exact Vision migration tests.
- DataComp/OpenAI CLIP selection, model validation, downloads, and licence:
  `RawCullAIIntegrationTests` and `RawCullAIModelDownloadsTests`.
- Stable intelligence ownership, shared model identity, typed configuration
  ordering, stale-revision rejection, and retain-cycle safety:
  `RawCullIntelligenceRuntimeTests`.
- Semantic hydration/search and UI state: `RawCullSemanticSearchTests` and
  `RawCullSemanticSearchUITests`.
- Deep Review controller availability/request construction, operation lifecycle,
  and SAM 3 subject-mask behavior: `DeepAIReviewFeatureTests`.
- Typed persistence, backend separation, partial results, and legacy migration:
  `BurstAnalysisCoordinatorTests`, `PerFileAnalysisArtifactStoreTests`, plus the exact non-benchmark
  `PhotoAIKitSimilarityMigrationTests` identifiers.
- Core culling, zoom, histogram, and comparison behavior: the corresponding
  suite selectors and three exact `CullingModelTests` cancellation identifiers.

The smoke and full plans remain parallelizable. The migration suite uses unique
temporary stores and has no serialization trait. The Performance plan alone is
non-parallel because its deliberate shared-cache TSan stress test exercises the
production singleton while the Vision benchmark measures whole-operation timing.

## Historical Phase 3 Gate Verification — 2026-08-04

The counts below record the Phase 3 commit and are not the current manifest
baseline shown above.

- Red sentinel: a temporary 158th identifier failed intentionally;
  `make test-smoke` propagated Xcode failure 65 and returned nonzero. The
  sentinel source and selectors were then removed.
- Green smoke: 157 unique identifiers, 170 concrete invocations, zero failures,
  zero skips, and zero runtime warnings.
- Full Thread Sanitizer plan: passed with no TSan diagnostics.
- Performance plan: both enumerated identifiers ran and passed. The Vision
  benchmark indexed 12 images and computed 500 distances; the shared-cache
  stress test also passed.
- Exact-package Release build: arm64 macOS build passed. The known app-extension
  build-number mismatch (230 versus parent 231) remains assigned to Phase 8.

## Shared Test Base

All tests should start from an explicit, isolated base rather than the app's
production singletons or user-visible directories. The shared helpers live in
`TestIsolationHelpers.swift`:

- `makeIsolatedCache()` creates a `SharedMemoryCache` with thumbnail and full-size
  JPEG disk caches rooted under a unique `RawCullVerifyTests/<test-name>-<UUID>`
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

- Tests should assert RawCullVerify behavior or state transitions directly.
- Manual diagnostics, local-path RAW-file probes, templates, and console-only checks
  do not belong in the automated target.
- Placeholder assertions such as `#expect(true)` should be removed or replaced with
  assertions against production APIs.
- Shared state tests should use isolated temporary caches/settings unless they are
  deliberately exercising the singleton under Thread Sanitizer.
- Unit tests should target parser, math, cache, concurrency, persistence, and
  view-model behavior. Pure SwiftUI rendering/layout, the `RawCullVerifyApp` entry
  point, simple display-only models, and live process integrations belong outside
  this unit target unless they gain meaningful business logic.

## Current Focus Areas

- RawCullVerify integration behavior around imported RAW parsing packages.
- Thumbnail request/cache behavior, cancellation, and loader concurrency bounds.
- Sharpness and similarity scoring numeric behavior, including PhotoAIKit CLIP,
  targeted non-finite recovery, partial-artifact exclusion, and typed-artifact
  cache migration.
- View-model navigation, zoom overlay, and security-scoped path behavior.
- TSan-oriented stress tests for RawCullVerify shared cache state.

## Current Test Files

- `CullingModelTests.swift`: rating/tagging state transitions, file selection, and
  culling model behavior.
- `DiskCacheAndScanAdmissionTests.swift`: thumbnail/full-size disk cache behavior
  and scan admission decisions using temporary cache roots.
- `RawCullVerifyTestsConcurrencyTests.swift`: isolated shared cache counters and settings
  persistence/concurrency behavior.
- `RawCullVerifyTestsDataRaceDetectionTests.swift`: TSan-focused shared cache stress
  coverage that deliberately exercises concurrent access paths.
- `PhotoAIKitSimilarityMigrationTests.swift`: CLIP batch/fallback behavior, real
  Vision artifact generation, RawCull ranking-policy parity, schema-6
  invalidation/schema-8 rebuild, and the indexing/ranking performance benchmark.
- `RawCullAIIntegrationTests.swift`: canonical AI paths, Phase 1 capability state,
  saved burst evidence scanning, model validation reuse, Settings cancellation,
  and persisted CLIP preference behavior.
- `RawCullIntelligenceRuntimeTests.swift`: stable application assembly, shared
  similarity, model-management, and Deep Review identity, typed Settings
  configuration ordering, no-op and stale-revision behavior, in-flight hydration
  supersession, segmentation isolation, and weak-edge lifetime behavior.
- `RawCullSimilarityFeatureTests.swift`: shared feature/model identity, RawCull-owned
  backend and progress projections, backend replacement ordering, and stale catalog
  hydration rejection.
- `RawCullVerifyViewModelSecurityScopeTests.swift`: security-scoped catalog access
  lifecycle behavior on the `@MainActor` `RawCullViewModel`.
- `ScanAndExtractJPGsTests.swift`: scan/extraction coordination behavior.
- `ScanFilesSortAndFormatTests.swift`: file sorting and display formatting rules.
- `SharpnessScoringTests.swift`: sharpness scoring, focus-mask numeric helpers,
  aperture hints, and ISO scaling.
- `ThumbnailLoaderConcurrencyTests.swift`: thumbnail loader concurrency bounds and
  cancellation under stress.
- `ThumbnailProviderTests.swift`: thumbnail request/cache behavior, cache config,
  and cached thumbnail cost.
