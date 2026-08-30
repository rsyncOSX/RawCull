# RawCull intelligence dependency boundary

RawCull's intelligence dependencies point in one direction:

```text
SwiftUI views
    -> RawCull intelligence presentation state and actions
    -> RawCull intelligence orchestration
    -> RawCull-owned service protocols and repositories
    -> PhotoAIKit contracts, workflows, and storage
    -> concrete AI backends
```

Dependencies must not point upward. In particular, SwiftUI views and general view
models must not import or construct a concrete CLIP, SAM, EfficientSAM, or Vision
provider.

## Import policy

| Product | Permitted layer |
|---|---|
| `CoreAICLIPBackend` | Composition root or a dedicated backend adapter |
| `CoreAISAM3Backend` | Composition root or a dedicated backend adapter |
| `CoreAIEfficientSAMBackend` | Composition root or a dedicated backend adapter |
| `VisionFeaturePrintBackend` | Composition root or a dedicated backend adapter |
| `PhotoAIWorkflows` | Composition, intelligence orchestration, or a backend adapter |
| `PhotoAIStorage` | Composition or intelligence persistence |
| `PhotoAIContracts` | Intelligence composition, orchestration, and persistence; existing presentation and general-view-model imports are temporary leakage |

This note lives under `Docs/` because the `RawCull/` synchronized Xcode group copies
non-source files into the application bundle.

The concrete-backend rule is enforced by
`Scripts/VerifyAIImportBoundary.sh` using exact file/module allowlist entries. Adding
an adapter therefore requires a deliberate allowlist change alongside the adapter.
The check scans production sources under `RawCull/`; tests may import implementation
modules when they directly characterize those boundaries.

`PhotoAIContracts` is not a failing rule yet. Its imports outside
`RawCull/Intelligence` are reported as warnings so later phases can replace them
incrementally with RawCull-owned domain and presentation types. Do not broaden the
temporary leakage while making unrelated changes.

## Current import inventory

Inventory recorded on 2026-08-28 and refreshed after the Phase 10 physical move on
2026-08-30. Line numbers are intentionally omitted so this list remains useful as
files evolve; the repository check reports live locations.

### Production

| Importer | Product(s) | Classification | Disposition |
|---|---|---|---|
| `RawCull/Intelligence/Composition/RawCullAIIntegration.swift` | `CoreAICLIPBackend`, `CoreAIEfficientSAMBackend`, `CoreAISAM3Backend`, `PhotoAIContracts`, `PhotoAIStorage`, `PhotoAIWorkflows`, `VisionFeaturePrintBackend` | Composition | Allowed |
| `RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift` | `PhotoAIContracts`, `PhotoAIWorkflows`, `VisionFeaturePrintBackend` | Backend adapter and orchestration | Allowed |
| `RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift` | `PhotoAIContracts`, `PhotoAIWorkflows` | Orchestration | Allowed |
| `RawCull/Intelligence/SemanticSearch/RawCullSemanticSearchService.swift` | `PhotoAIContracts` | Orchestration | Allowed |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelResourceManager.swift` | `PhotoAIContracts` | Orchestration/infrastructure | Allowed |
| `RawCull/Intelligence/Contracts/RawCullAIModels.swift` | `PhotoAIContracts` | Intelligence domain bridge | Allowed for now |
| `RawCull/Intelligence/Similarity/SimilarityScoringModel.swift` | `PhotoAIContracts` | Intelligence orchestration | Allowed |
| `RawCull/Intelligence/Persistence/BurstAnalysisCache.swift` | `PhotoAIContracts` | Persistence | Allowed for now |
| `RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift` | `PhotoAIContracts`, `PhotoAIStorage` | Persistence | Allowed |
| `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift` | `PhotoAIContracts` | Accidental leakage into the general view model | Warning only |
| `RawCull/Model/Accessibility/RawCullAccessibilityPresentation.swift` | `PhotoAIContracts` | Presentation leakage | Warning only |
| `RawCull/Views/CullingGrid/DeepAIReviewSheetView.swift` | `PhotoAIContracts` | Presentation leakage | Warning only |
| `RawCull/Intelligence/Presentation/SemanticSearchUIPresentation.swift` | `PhotoAIContracts` | Intelligence presentation state | Allowed |

### Tests

Test imports are classified separately and are not part of the production
concrete-backend allowlist.

| Product(s) | Test importers |
|---|---|
| `PhotoAIContracts`, `PhotoAIStorage` | `RawCullTests/AICacheBoundaryTests.swift` |
| `PhotoAIContracts` | `RawCullTests/AccessibilityPresentationTests.swift`, `RawCullTests/CullingModelTests.swift`, `RawCullTests/DeepAIReviewFeatureTests.swift`, `RawCullTests/PerFileAnalysisArtifactStoreTests.swift`, `RawCullTests/PhotoAIKitSimilarityMigrationTests.swift`, `RawCullTests/RawCullAIIntegrationTests.swift`, `RawCullTests/RawCullSemanticSearchTests.swift`, `RawCullTests/RawCullSemanticSearchUITests.swift`, `RawCullTests/ThumbnailCacheIdentityTests.swift`, `RawCullTests/TypedAIPersistenceMatrixTests.swift` |

## Changing the boundary

When adding or changing an import:

1. Prefer a RawCull-owned protocol or value type over exposing a backend type.
2. If a concrete backend import is necessary, place it in the composition root or
   a focused adapter and add that exact file/module pair to the verifier.
3. Update this inventory when an import is introduced, removed, or reclassified.
4. Run `make verify-ai-import-boundary` and `make test-smoke`.
