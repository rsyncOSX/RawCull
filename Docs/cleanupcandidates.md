# Cleanup Candidates After Diagnostics Removal

This report identifies remaining cleanup candidates after removal of the
Diagnostics menu and its supporting code. It is an inspection report only;
none of the candidates described here have been implemented.

## High-confidence cleanup

### Remove the write-only indexing diagnostic state

`SimilarityScoringModel.indexingDiagnostic` is reset and assigned, but never
read. The property and its assignments can be removed while retaining the
existing warning log for `primaryFailureDiagnostic`.

- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`

### Remove unused imports

The following imports have no remaining usages:

- `OSLog` in `RawCull/Main/RawCullApp.swift`
- `OSLog` in `RawCull/Main/RawCullMainView.swift`
- `OSLog` in `RawCull/Model/ViewModels/RawCullViewModel.swift`
- `Foundation` in `RawCull/Views/Tools/MenuCommands.swift`

### Update stale README documentation

The repository structure in `README.md` still lists the deleted
`Model/Diagnostics` directory. The README also describes cache diagnostics
that were removed. In particular, review:

- The `SharedMemoryCache` responsibility description
- The `Model/Cache` directory description
- The deleted `Model/Diagnostics` directory entry

### Remove commented-out logging

There are approximately a dozen commented-out logger statements in:

- `RawCull/Actors/SharedMemoryCache.swift`
- `RawCull/Actors/RequestThumbnail.swift`
- `RawCull/Actors/ScanAndCreateThumbnails.swift`

These are inactive comment debris and can be removed without changing
behavior. Active debug logging should not be removed as part of this cleanup.

### Rename the burst preparation source file

`RawCull/Views/SimilarityGridView/BurstCatalogPreparationView.swift` no longer
contains a SwiftUI view. It now contains only the burst catalog preparation
presentation types. A name such as
`BurstCatalogPreparationPresentation.swift` would reflect its current role.

## Additional dead-code candidates

Periphery identified the following production APIs as unused. Some remain in
use by tests, so removing them would require corresponding test updates.

### Empty saved-data deletion placeholder

`RawCullAISettingsModel.deleteSavedBurstData()` is intentionally empty and is
only called by a test. Unless it is being retained as a planned API, the
placeholder and its test can be removed.

- `RawCull/Model/ViewModels/RawCullAISettingsModel.swift`

### Unused burst-analysis wrapper

`RawCullViewModel.analyzeBursts()` is only called by tests. Production code
uses the current restore/re-index workflow and `reindexBurstAnalysis()`.
The wrapper is a removal candidate after its tests are updated to exercise the
active production entry points.

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`

### Test-only burst preparation cancellation

`RawCullViewModel.cancelBurstCatalogPreparation()` has no production caller
and is only exercised by tests. It can be removed if cancellation is not meant
to return to the UI.

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`

### Test-only semantic selection wrapper

`RawCullViewModel.setSemanticSearchSelectionCount(_:)` is only called by
tests. The underlying `SimilarityScoringModel` method remains active and is
used by production code.

- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift`

### Unused zoom navigation context

`ZoomOverlayNavigationContext` is created and stored by production code, but
none of its navigation methods are read by production code. Its methods are
only used by the dedicated test suite. The stored view-model property, context
type, assignment, and tests should either be connected to the actual zoom
navigation implementation or removed together.

- `RawCull/Views/ZoomViews/ZoomOverlayView.swift`
- `RawCull/Model/ViewModels/RawCullViewModel.swift`

### Artifact pruning needs a keep-or-remove decision

`PerFileAnalysisArtifactPruningPolicy`, its prune-result type, and
`PerFileAnalysisArtifactStore.prune(policy:now:)` are tested but never invoked
by production code. This should not be removed blindly. Either:

1. Connect pruning to application lifecycle or cache maintenance, or
2. Remove the unused policy, implementation, and tests if automatic pruning is
   no longer planned.

- `RawCull/Actors/PerFileAnalysisArtifactStore.swift`

## Items to retain

Most of the other Periphery findings are intentional test-support APIs, such
as deterministic cache paths, cache reset methods, concurrency slot snapshots,
and test cache configurations. They should not be treated as ordinary dead
code solely because the application target does not call them.

Active `debugMessageOnly` and `debugThreadOnly` logging also remains useful
operational instrumentation and compiles out of Debug-only logging paths as
designed. A bulk removal of active logging is not recommended.

## Validation performed

- A Debug macOS application build succeeded after the Diagnostics removal.
- Periphery completed and reported 28 warnings; the relevant candidates were
  manually separated from intentional test-support APIs.
- The inspection itself made no source changes.
