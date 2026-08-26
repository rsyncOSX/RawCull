# Cleanup Plan After Diagnostics Removal

This document tracks cleanup following removal of the Diagnostics menu and its
supporting code. The unused-function phase is complete. Remaining work is
limited to documentation, imports, comments, and a source-file rename.

## Completed: remove unused production APIs

The following APIs were reachable only from tests, or were never read at all,
and have been removed with their obsolete test coverage:

- `RawCullAISettingsModel.deleteSavedBurstData()`, an empty placeholder with
  no production caller.
- `RawCullViewModel.analyzeBursts()`, a legacy wrapper superseded by
  `restoreExistingFullCatalogBurstAnalysis()` and `reindexBurstAnalysis()`.
  The affected tests now exercise the production restore workflow.
- `RawCullViewModel.cancelBurstCatalogPreparation()`, which had no UI or other
  production caller.
- `RawCullViewModel.setSemanticSearchSelectionCount(_:)`, a test-only wrapper.
  Semantic-search tests now use the production adjustment API.
- `ZoomOverlayNavigationContext.destinationID(from:delta:)`,
  `canNavigatePrevious(from:)`, and `canNavigateNext(from:)`. These helpers
  were tested but unused by the overlay.
- `PerFileAnalysisArtifactStore.prune(policy:now:)` and its policy/result
  types, plus the private `Duration` helpers used only by pruning. Automatic
  pruning had no application-lifecycle integration. The active `usage()` and
  `clear()` maintenance APIs remain covered.
- `SimilarityScoringModel.indexingDiagnostic`, a write-only property. The
  warning log for `primaryFailureDiagnostic` remains active.

Related tests and the smoke-test count were updated with the removals.

## Retained after re-audit

`ZoomOverlayNavigationContext` itself is active production state. The zoom
overlay reads `orderedFileIDs` to constrain navigation to the launch context,
and the initializer still removes duplicate IDs. The context and its focused
deduplication test must remain.

Intentional test-support APIs, including deterministic cache paths, cache
reset methods, concurrency-slot snapshots, and test cache configurations, also
remain. They should not be treated as dead code solely because the application
target does not call them.

Active `debugMessageOnly` and `debugThreadOnly` logging remains useful
operational instrumentation and should not be removed in bulk.

## Remaining cleanup plan

Complete the non-functional cleanup in small, reviewable steps:

1. Remove imports confirmed unused by the compiler:
   - `OSLog` from `RawCull/Main/RawCullApp.swift`
   - `OSLog` from `RawCull/Main/RawCullMainView.swift`
   - `OSLog` from `RawCull/Model/ViewModels/RawCullViewModel.swift`
   - `Foundation` from `RawCull/Views/Tools/MenuCommands.swift`
2. Remove commented-out logger statements from:
   - `RawCull/Actors/SharedMemoryCache.swift`
   - `RawCull/Actors/RequestThumbnail.swift`
   - `RawCull/Actors/ScanAndCreateThumbnails.swift`
3. Rename
   `RawCull/Views/SimilarityGridView/BurstCatalogPreparationView.swift` to
   `BurstCatalogPreparationPresentation.swift`, because it contains
   presentation types rather than a SwiftUI view. Update the Xcode project
   reference if it is not file-system synchronized.
4. Refresh `README.md` by removing the deleted `Model/Diagnostics` directory
   and revising the `SharedMemoryCache` and `Model/Cache` descriptions so they
   no longer promise removed diagnostics.
5. Run a Debug build, the focused cleanup suites, smoke-manifest enumeration,
   and Periphery. Review new findings manually so test-support hooks and
   framework-driven entry points are not removed.

## Validation

- Debug macOS application build: passed.
- Focused suites passed: `CullingModelTests`,
  `RawCullSemanticSearchTests`, `BurstCatalogPreparationPresentationTests`,
  `ZoomOverlayNavigationContextTests`,
  `PerFileAnalysisArtifactStoreTests`, and `RawCullAIIntegrationTests`.
- Native Xcode smoke enumeration succeeded with 177 enabled tests and no
  duplicate identifiers; `SMOKE_EXPECTED_TESTS` now matches that count.
- Periphery completed after the cleanup with no findings.
- `make verify-smoke-manifest` remains unavailable because the Makefile refers
  to the missing `Scripts/VerifyTestEnumeration.swift`. Native Xcode
  enumeration was used for this cleanup instead.
