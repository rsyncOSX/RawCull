# Modular AI Refactoring Plan

Status: active on the `version-3.2.0` development branch. Phases 0 and 1 were
completed on 2026-08-28 against the `version-3.1.1` baseline; Phases 2 through 12
have not started.

## Purpose

RawCull's CLIP-based similarity and semantic search are becoming defining product
capabilities. This plan does not turn CLIP into a secondary feature and does not
design a reduced "AI-off" edition of RawCull. Its purpose is to make the
intelligence code easier to understand, test, replace, and extend without changing
the current user experience.

The refactor must be incremental. Every phase must leave the application building
and must have its own testable exit condition. Compatibility forwarding should be
used temporarily where it lets one caller move at a time. Large renames, physical
file moves, persisted-format changes, and behavior changes must not be combined in
the same phase.

## Product position

- CLIP similarity and semantic search are core RawCull capabilities.
- Vision feature prints remain a runtime fallback, not a separate product mode.
- SAM 3 and EfficientSAM Deep Review are optional capabilities because they require
  additional model resources and are not needed for the primary CLIP workflow.
- Model discovery, validation, licensing, download, and caching are infrastructure.
  Views should present their state without knowing the concrete provider types.
- The goal is replaceability and clear ownership, not optionality everywhere.

## Goals

1. Keep all current CLIP, Vision fallback, semantic-search, burst-analysis, Deep
   Review, model-download, cache, and settings behavior.
2. Give the AI feature one clear application-level owner created at the app
   composition root.
3. Prevent SwiftUI views and general application code from depending on concrete
   PhotoAIKit backends.
4. Reduce the AI responsibilities currently held by `RawCullViewModel`.
5. Keep observable state lifetimes explicit and stable.
6. Preserve concurrency, cancellation, generation-token, and stale-result behavior.
7. Preserve cache paths, preference keys, persisted schemas, backend descriptors,
   and migration behavior until a separately planned migration is justified.
8. Make it possible to upgrade or replace a CLIP provider without rewriting views
   or the central application view model.
9. Make later AI capabilities fit behind the same dependency direction without
   turning one facade into another oversized view model.

## Non-goals

- Removing CLIP or producing a macOS 26 edition.
- Changing which CLIP model is selected by default.
- Changing ranking, burst grouping, sharpness, semantic-search admission, or Deep
  Review policy.
- Changing cache schemas or deleting legacy migration support during structural
  phases.
- Replacing PhotoAIKit.
- Rewriting the SwiftUI interface.
- Introducing runtime feature flags throughout views.
- Creating a new Swift package before the application-level boundary is proven.
- Renaming every type merely to remove `AI` from its name.

## Current architecture

The existing design already has several good seams:

- `PhotoAIKit` contains reusable contracts, storage, workflows, Vision, CLIP, and
  segmentation backends.
- `RawCullAIIntegration` is the composition root for concrete providers and model
  resources.
- `RawCullSimilarityServicing`, `RawCullSemanticSearchServicing`,
  `DeepAIReviewServicing`, `SubjectMaskFocusScoring`, and
  `RawCullAIModelDownloadServicing` already provide testable service boundaries.
- `SimilarityScoringModel`, `DeepAIReviewFeature`, and `RawCullAISettingsModel`
  expose typed observable state rather than raw provider objects to most views.
- Disk-facing work is already separated into actors such as
  `PerFileAnalysisArtifactStore` and `BurstAnalysisCache`.

The main weakness is above those seams. Intelligence state and orchestration are
distributed through the app rather than owned by one feature boundary:

- `RawCullApp` creates `RawCullAIIntegration`, `RawCullViewModel`, and
  `RawCullAISettingsModel` and wires callback closures between them.
- `RawCullViewModel` owns `SimilarityScoringModel`, `DeepAIReviewFeature`, AI task
  handles, cache closures, burst state, and backend-switch handling.
- `RawCullViewModel+BurstGrouping.swift` performs cache hydration, legacy migration,
  sharpness scoring, similarity indexing, grouping, ranking, persistence, Deep
  Review request construction, and user actions in one extension.
- Multiple views reach through `RawCullViewModel` to `similarityModel` or
  `deepAIReviewFeature`.
- Shared persistence structures expose `PhotoAIContracts` types directly.
- Settings, cache presentation, model downloads, semantic search, toolbar actions,
  selection, metadata overlays, and burst review all know some AI-specific state.

This is not a reason for a rewrite. The service boundaries exist; ownership and
dependency direction need to be consolidated around them.

## Target dependency direction

The intended dependency direction is:

```text
SwiftUI views
    -> RawCull intelligence presentation state and actions
    -> RawCull intelligence orchestration
    -> RawCull-owned service protocols and repositories
    -> PhotoAIKit contracts/workflows/backends
    -> Core AI model implementations
```

Dependencies must not point upward. In particular:

- A concrete CLIP, SAM, EfficientSAM, or Vision provider must never be visible to a
  SwiftUI view.
- `RawCullViewModel` may understand product concepts such as similarity, semantic
  selection, burst analysis, and Deep Review results. It should not construct model
  providers, validate model bundles, or select storage implementations.
- Persistence may continue to store PhotoAIKit artifacts internally, but callers
  outside the intelligence boundary should use repository operations and
  RawCull-owned summaries rather than artifact codecs.
- Concrete backend products such as `CoreAICLIPBackend`, `CoreAISAM3Backend`, and
  `CoreAIEfficientSAMBackend` should be imported only by the composition root and
  dedicated backend adapter files.

## Proposed ownership model

Introduce one stable, app-owned intelligence runtime. The final name can be chosen
during implementation; `RawCullIntelligenceRuntime` is used in this document.

The runtime should be `@MainActor` and own stable references to focused models and
coordinators rather than duplicating all their state:

- similarity and semantic-search model;
- Deep Review feature model;
- AI settings/model-management model;
- backend composition root;
- burst-analysis coordinator or pipeline;
- artifact and derived-analysis repositories.

It should not become a second `RawCullViewModel`. Avoid hundreds of forwarding
properties. Views should receive the narrowest stable observable model they need,
while cross-feature commands go through a small action surface.

The runtime must be created exactly once at the app root and retained with stable
SwiftUI ownership. An `@Observable` instance created by a view must be stored in a
private `@State`; an injected observable that needs bindings should be received with
`@Bindable`. Do not create feature models in `body`, computed properties, or
environment default expressions.

## Boundary types

Use three categories of types deliberately:

1. **Product-domain types**
   
   Similarity state, semantic matches, capability summaries, Deep Review results,
   and burst-analysis requests/results that RawCull uses directly. These should be
   RawCull-owned, `Equatable` where practical, and `Sendable` when crossing an
   isolation boundary.

2. **Backend types**
   
   PhotoAIKit artifacts, backend descriptors, model providers, segmentation
   repositories, and artifact codecs. These remain inside the intelligence and
   persistence boundary.

3. **Presentation types**
   
   Settings rows, progress snapshots, error messages, toolbar availability, and
   cache-usage summaries. These should not expose providers or repositories.

Do not replace every PhotoAIKit type at once. First stop new leakage. Existing
persisted and performance-sensitive types should be adapted only where doing so
removes a real dependency from a caller. Prefer small adapters over parallel object
graphs or repeated artifact copies.

## Invariants that every phase must preserve

- The selected CLIP model and the “use CLIP for similarity” preference retain the
  same keys and semantics.
- Vision remains the fallback when the selected CLIP provider is unavailable or
  invalid.
- Semantic search ranks only compatible cached CLIP artifacts and does not trigger
  image indexing implicitly.
- DataComp, OpenAI CLIP, and Vision artifacts never cross-load.
- Non-finite CLIP results keep their current retry, provider-reload, failure, and
  partial-success behavior.
- A cancelled or superseded task cannot publish stale results.
- Switching models invalidates or hydrates exactly the same state as before.
- Burst analysis retains its cache-first order: hydrate, migrate when needed, load
  compatible derived cache, score/index missing inputs, group, rank, then save.
- Burst review state and manual winner overrides survive regrouping and compatible
  cache restoration.
- Semantic selection continues to compose with rating filters, catalog ordering,
  thumbnail selection, burst scope, and comparison mode.
- Deep Review still validates the group signature before applying a recommendation.
- Model-download licence acceptance, cancellation, deletion, and Background Assets
  behavior remain unchanged.
- Cache-clearing operations remain independently scoped and do not remove ratings,
  settings, model licences, or unrelated caches.
- App termination continues to flush culling persistence and release security-scoped
  access correctly.

## Commit and phase rules

- Use one development branch, but make every numbered phase independently
  reviewable and revertible.
- Prefer one concern per commit. A phase may contain several commits when the
  compatibility shim, caller migration, and shim removal are easier to review
  separately.
- Do not mix file moves with logic edits. Git history must be able to distinguish
  movement from behavior changes.
- Do not change persisted data formats in a modularization commit.
- Do not rename tests and production symbols in the same commit unless the rename is
  the entire change.
- Add characterization tests before moving behavior whose contract is not already
  explicit.
- Keep old entry points as forwarding methods while callers migrate. Remove them only
  after `rg` confirms there are no callers and the phase gate passes.
- Stop a phase if its diff expands into unrelated cleanup. Record the cleanup as a
  separate future task.

## Validation commands

The following checked-in commands are the standard gates. They must be executable
from a clean checkout; a missing helper, fixture, manifest, or test plan is a failed
gate rather than an external prerequisite:

```sh
make test-smoke
make test-full
make test-performance
```

Use an exact resolved-package Release build after changes to composition, target
membership, package boundaries, extension embedding, or build settings:

```sh
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -onlyUsePackageVersionsFromResolvedFile \
  build
```

`make test-smoke` verifies the checked-in smoke manifest and its expected test
enumeration before running it. When a test identifier is intentionally added,
removed, or renamed, update the source, `TestManifests/SmokeTests.txt`, manifest
integrity expectations, the Make enumeration count, and
`RawCullTests/TEST_ARCHITECTURE.md` together. Apply the equivalent updates to the
performance manifest and count when performance coverage changes. Prefer generated
or verifier-reported counts over manually duplicated totals.

Do not run the expensive performance suite after documentation-only or pure-rename
commits. Run it whenever indexing, ranking, cache serialization, artifact mapping,
task isolation, or package boundaries change.

## Phase 0: establish a trustworthy baseline

### Changes

1. Create a clean refactoring branch from a commit where the current smoke, full,
   performance, and Release-build gates pass.
2. Record the commit, Xcode build, selected resolved package revisions, and test
   results in the branch notes or pull request.
3. Run the existing AI-focused suites and identify any important workflow without a
   characterization test.
4. Add only the missing characterization tests. Do not create new abstractions yet.

### Baseline validation record

Phase 0 is complete only when this record shows every gate passing. Update it in the
same commit that changes the Phase 0 status; do not rely on an unlinked local run.

| Input | Recorded value |
|---|---|
| Baseline branch | `version-3.1.1` |
| Baseline commit | `2cf926ba5069e3094807800714b7df1258d601ab` |
| Validation date | 2026-08-28 |
| Xcode | 27.0 (build `27A5252f`) |
| `Package.resolved` SHA-256 | `dcf8f3b02c9c847a918439624a61e99d86986614e172daf15883b404794d8c20` |

Selected resolved AI and image-analysis dependencies:

| Package | Resolved revision or version |
|---|---|
| `coreai-models` | `bffc38fe48f50e4e962ac9772b64a5b55a605286` |
| `PhotoAIKit` | `1e2eaccd00947fbadda300e4a617842479cae7b9` |
| `PhotoAnalysisKit` | `1.2.2` |
| `RawCullCore` | `1.1.2` |
| `RawParserKit` | `1.2.8` |

| Gate | Status | Evidence |
|---|---|---|
| Smoke enumeration | Pass | 179 unique identifiers verified on 2026-08-28 after restoring the checked-in verifier. |
| Performance enumeration | Pass | 2 unique identifiers verified on 2026-08-28. |
| `make test-smoke` | Pass | Checked-in smoke manifest passed on 2026-08-28 after correcting its three stale expectations. |
| `make test-full` | Pass | Full test plan passed with Thread Sanitizer on 2026-08-28; result bundle: `Test-RawCull-2026.08.28_15-37-34-+0200.xcresult`. |
| `make test-performance` | Pass | Checked-in performance manifest passed on 2026-08-28. |
| Exact-package Release build | Pass | Resolved-package arm64 Release build completed successfully on 2026-08-28. |

Baseline scenario traceability:

| Scenario | Automated characterization |
|---|---|
| App composition with Vision before CLIP validation | `RawCullAIIntegrationTests.Composition root reports the complete Phase 1 capability surface`; `RawCullAIIntegrationTests.Saved burst scan reads existing Vision cache evidence` |
| Settings refresh and provider switching | `RawCullAIIntegrationTests.Cancelling Settings refresh cancels its evidence scan`; `RawCullAIIntegrationTests.CLIP enablement and exclusive model selection persist`; `RawCullAIIntegrationTests.Model validation is reused until candidate metadata changes` |
| Semantic search with compatible, missing, partial, and stale indexes | `RawCullSemanticSearchTests.Literal query encodes once, excludes Vision, isolates failures, and ranks deterministically`; `RawCullSemanticSearchTests.Partial index, empty index, provider failure, and model switch remain distinct`; `RawCullSemanticSearchTests.Preparing a reindex resets selection and restores the full catalog` |
| Model switch during or after hydration | `TypedAIPersistenceMatrixTests.superseded semantic hydration cannot publish an older backend`; `TypedAIPersistenceMatrixTests.dataComp and OpenAI artifacts relaunch without cross-loading` |
| Burst cache hit, miss, migration, reindex, regroup, and cancellation | `RawCullViewModelCullingTests.restoring an existing full burst index never starts scoring or indexing`; `RawCullViewModelCullingTests.burst cache rejects a different similarity signature`; `PhotoAIKitSimilarityMigrationTests.Legacy burst artifacts migrate once into the per-file store`; `PhotoAIKitSimilarityMigrationTests.CLIP reindexes only missing or stale artifacts`; `RawCullViewModelCullingTests.live regroup review state follows membership instead of group id`; `RawCullViewModelCullingTests.cancelled burst analysis cannot apply a late cache result` |
| Deep Review completion, cancellation, unavailable provider, and recommendation application | `DeepAIReviewFeatureTests.Feature publishes a typed completed result`; `DeepAIReviewFeatureTests.Cancelling Deep Review cancels the owned in-process task`; `RawCullAIIntegrationTests.Composition root reports the complete Phase 1 capability surface`; `RawCullViewModelCullingTests.applying Deep Review winner rates it three stars and marks group reviewed` |
| Independent cache clearing | `AICacheBoundaryTests.independent cache clears preserve ratings settings decisions models and licences`; `RawCullViewModelCullingTests.burst cache reports usage and clears every catalog snapshot` |
| Model download and licence-state restoration | `RawCullAIModelDownloadsTests.Verified acceptance gates and unlocks a ready download`; `RawCullAIModelDownloadsTests.A changed licence checksum invalidates prior acceptance`; `RawCullAIModelDownloadsTests.Published CLIP models expose the Background Assets runtime failure` |

### Tests

- `make test-smoke`
- `make test-full`
- `make test-performance`
- exact-package Release build

### Exit criteria

- All gates are green before production refactoring begins.
- Every behavior listed above is either covered by a named test or explicitly
  recorded as a manual acceptance check.
- No production code changed.

### Rollback

Drop only the new characterization-test commits. No production state is affected.

## Phase 1: define and enforce the dependency boundary

Status: completed on 2026-08-28. The policy and import inventory are recorded in
`Docs/ai-dependency-boundary.md`; the repository rule is implemented by
`Scripts/VerifyAIImportBoundary.sh` and `make verify-ai-import-boundary`.

### Changes

1. Add a short architecture note near the intelligence code describing which layers
   may import each PhotoAIKit product.
2. Inventory every `PhotoAIContracts`, `PhotoAIStorage`, `PhotoAIWorkflows`,
   `CoreAICLIPBackend`, `CoreAISAM3Backend`, `CoreAIEfficientSAMBackend`, and
   `VisionFeaturePrintBackend` import.
3. Classify each importer as composition, orchestration, persistence, presentation,
   or accidental leakage.
4. Add a lightweight repository check that rejects concrete backend imports outside
   the approved composition files. Initially report `PhotoAIContracts` leakage
   without rejecting it, because that cleanup will be incremental.
5. Make no runtime behavior changes.

The first enforced rule should be narrow and uncontroversial: concrete backend
modules are allowed only in `RawCullAIIntegration` and backend adapter files. Do not
block `PhotoAIContracts` globally until persistence and burst orchestration have
moved.

### Tests

- Run the new import-boundary check.
- `make test-smoke`

### Exit criteria

- The dependency direction is documented and mechanically checked.
- No concrete model provider is imported by a view or general view model.
- No production runtime code changed, persisted compatibility fixtures are
  unchanged, and the existing characterization gates remain green.

### Rollback

Remove the boundary check and documentation commit.

## Phase 2: introduce a stable intelligence runtime without moving behavior

### Changes

1. Introduce `RawCullIntelligenceRuntime` as the stable owner of the existing
   `SimilarityScoringModel`, `DeepAIReviewFeature`, `RawCullAISettingsModel`, and
   `RawCullAIIntegration` references.
2. Construct the runtime once in `RawCullApp` and retain it with correct SwiftUI
   state ownership.
3. Keep `RawCullViewModel`'s existing properties and methods as compatibility
   forwarders to the same model instances. Do not create duplicate models or copy
   observable state.
4. Preserve the existing callback sequence used when settings select a new
   similarity or semantic-search service.
5. Add identity tests proving that the app, settings, and central view model use the
   same similarity and Deep Review instances.

This phase changes ownership only. It must not alter task creation, cache access,
backend selection, or view call sites.

### Tests

- Runtime identity and lifetime tests.
- `RawCullAIIntegrationTests`
- `RawCullSemanticSearchTests`
- `DeepAIReviewFeatureTests`
- `make test-smoke`
- `make test-full`, because observable ownership and task lifetimes changed.

### Exit criteria

- There is exactly one runtime, similarity model, settings model, and Deep Review
  feature per app session.
- Closing/reopening SwiftUI content does not recreate feature state.
- All old APIs still forward to the same instances.
- No view has been migrated yet.

### Rollback

Restore direct construction in `RawCullApp`; forwarding means no caller changes need
to be reverted.

## Phase 3: replace settings callbacks with one typed configuration path

### Changes

1. Define a RawCull-owned configuration-change value that describes the selected
   similarity service, semantic-search capability/service, and segmentation model
   without exposing concrete providers.
2. Give the intelligence runtime one method for applying a complete configuration
   snapshot.
3. Move backend-selection coordination out of callback closures in `RawCullApp` and
   into the runtime.
4. Keep the current `RawCullViewModel.setSimilarityService` and
   `setSemanticSearchCapability` methods as forwarders while behavior migrates.
5. Preserve cancellation order: cancel stale burst work, replace the service,
   cancel old hydration, hydrate current files, and publish only if the generation is
   still current.
6. Preserve the settings preference keys and refresh order.

Avoid a general event bus. There is one source of configuration changes and one
runtime owner, so a typed command or snapshot is easier to reason about and test.

### Tests

- Existing settings persistence and refresh-cancellation tests.
- Existing model validation reuse and restoration tests.
- Existing superseded hydration and backend separation tests.
- Add a test for repeated application of the same configuration being a no-op.
- Add a test for changing the CLIP model while hydration is in flight.
- `make test-smoke`
- `make test-full`

### Exit criteria

- `RawCullApp` no longer contains backend-change callback wiring.
- Only the runtime applies intelligence configuration.
- A stale settings refresh or hydration cannot replace newer runtime state.
- No preference or capability behavior changed.

### Rollback

Restore the app-level callbacks; compatibility methods remain available.

## Phase 4: migrate settings and model management first

Settings is the safest first UI slice because `RawCullAISettingsModel` is already a
narrow presentation boundary.

### Changes

1. Pass the stable settings model directly from the runtime to `SettingsView`.
2. Keep `AISettingsTab` and `AIModelDownloadsView` dependent on
   `RawCullAISettingsModel`, not the runtime or `RawCullViewModel`.
3. Move cache-usage and saved-burst-evidence presentation behind settings-facing
   summaries when a view currently reaches into a store directly.
4. Do not change tab layout, labels, preference defaults, download UI, or model
   inclusion policy.
5. Remove only the settings-related compatibility paths that have no callers.

### Tests

- `RawCullAIIntegrationTests`
- `RawCullAIModelDownloadsTests`
- `AICacheBoundaryTests`
- `ReleaseMetadataTests`
- `make test-smoke`
- exact-package Release build if extension or target wiring changed

### Manual acceptance

- Open Settings repeatedly and confirm the model is not recreated.
- Validate missing, corrupt, restored, and installed model presentation.
- Change CLIP and segmentation selections and relaunch.
- Start and cancel a model download using the configured production/staging source
  or an explicitly injected debug service, and record which source was used.
- Verify licence acceptance and model removal state.

### Exit criteria

- Settings views know only their presentation model.
- Model provider and storage objects remain invisible to SwiftUI.
- Model downloader extension packaging is unchanged.

### Rollback

Restore the old settings initializer. Runtime ownership remains valid and can stay.

## Phase 5: migrate semantic search as an isolated vertical slice

### Changes

1. Define a narrow semantic-search presentation/action surface owned by the
   intelligence runtime or the existing similarity model.
2. Migrate semantic-search state views, query controls, toolbar controls, and result
   count presentation one caller at a time.
3. Keep catalog admission, rating filters, comparison-mode transitions, and
   thumbnail selection in the application layer. Pass explicit inputs or invoke
   explicit application actions rather than giving the semantic model the entire
   `RawCullViewModel`.
4. Keep forwarding methods such as `searchSemantically`,
   `setSemanticSearchShowsAllResults`, `adjustSemanticSearchSelection`,
   `clearSemanticSearch`, and `cancelSemanticSearch` until every caller has moved.
5. Remove forwarding only after an `rg` caller audit and green tests.

Do not combine this phase with similarity indexing or burst extraction. Semantic
search already has a cached-only contract, which makes it a clean first workflow.

### Tests

- `RawCullSemanticSearchTests`
- `RawCullSemanticSearchUITests`
- relevant thumbnail/navigation tests
- `make test-smoke`
- `make test-full` if task ownership or generation tokens move

### Manual acceptance

- Search with empty, successful, partial, and failed indexes.
- Expand/collapse results and adjust the ranked selection.
- Combine results with rating filters.
- Clear/cancel and confirm ordinary catalog order and selection return.
- Enter comparison and burst views from a semantic result set.

### Exit criteria

- Semantic-search views do not traverse `RawCullViewModel.similarityModel`.
- No search action receives the entire central view model.
- Cached-only behavior and all selection interactions remain unchanged.

### Rollback

Switch migrated views back to the compatibility forwarding methods. No persistence
changes are involved.

## Phase 6: place similarity indexing and ranking behind one feature API

### Changes

1. Consolidate indexing, hydration, ranking, cancellation, backend replacement, and
   indexing progress into a focused similarity feature surface.
2. Preserve `SimilarityScoringModel` as the observable state owner unless a concrete
   problem requires splitting it. Do not introduce a second mirrored state model.
3. Make the artifact repository an injected dependency of the feature rather than a
   dependency reached through `RawCullViewModel`.
4. Convert view callers such as sharpness controls, similarity-grid controls,
   metadata overlays, and progress overlays incrementally.
5. Keep catalog selection and general filter application in the application layer.
6. Preserve backend descriptor, artifact compatibility, partial indexing,
   force-refresh, and cache commit behavior.

### Tests

- `PhotoAIKitSimilarityMigrationTests`
- `PerFileAnalysisArtifactStoreTests`
- `TypedAIPersistenceMatrixTests`
- similarity cancellation tests in `CullingModelTests`
- `AICacheBoundaryTests`
- `make test-smoke`
- `make test-full`
- `make test-performance`

### Exit criteria

- A caller can request index, hydrate, rank, or cancel without knowing an artifact
  codec or provider.
- `RawCullViewModel` no longer owns similarity worker tasks that belong to the
  feature.
- Performance remains within the existing benchmark expectations.
- Cache payloads and paths are unchanged.

### Rollback

Restore feature forwarding to the old methods. Because the cache schema is
unchanged, no user-data rollback is necessary.

## Phase 7: extract the burst-analysis pipeline in small subphases

This is the highest-risk part and must not be done in one commit.

### Phase 7A: introduce pure request and result values

- Capture catalog identity, ordered files, sharpness signature, similarity
  signature, generation, and relevant configuration in an immutable request.
- Return a typed result containing groups, rankings, review-state restoration,
  cache outcome, and diagnostics.
- Keep the existing `RawCullViewModel+BurstGrouping` implementation and adapt its
  inputs/outputs to these values.
- Do not move any work yet.

Gate: focused burst tests, smoke tests, and equality tests proving old and new input
snapshots match.

### Phase 7B: extract cache hydration and compatibility decisions

- Move per-file artifact hydration, legacy import, derived-cache loading, artifact
  digest comparison, and cache-hit decisions behind a burst repository/coordinator.
- Preserve schema versions, descriptors, remapping, and migration-once semantics.
- Have the existing view-model method call the extracted operation and apply its
  result.

Gate: `PerFileAnalysisArtifactStoreTests`, migration tests, typed persistence matrix,
cache boundary tests, smoke, full, and performance tests.

### Phase 7C: extract compute orchestration

- Move missing sharpness scoring, missing similarity indexing, grouping, ranking,
  and cache-save sequencing into `BurstAnalysisCoordinator`.
- Preserve progress steps and cancellation checkpoints exactly.
- Use immutable snapshots across task boundaries and apply results on the main actor
  only after checking generation and catalog identity.
- Do not move rating changes, selection, navigation, manual overrides, undo, or
  review commands.

Gate: burst preparation, coordinator, grouping, cancellation, cache, full TSan, and
performance suites.

### Phase 7D: reduce the central view model

- Replace extracted worker state in `RawCullViewModel` with one stable coordinator
  reference and minimal application-facing progress/result projections.
- Keep rating, navigation, selection, manual winner overrides, and culling commands
  in `RawCullViewModel`; those are application responsibilities, not AI backend work.
- Remove old private helpers only after caller and test audits.

Gate: full smoke and TSan suites plus manual end-to-end burst qualification.

### Exit criteria for Phase 7

- Burst computation and persistence can be tested without constructing the full
  `RawCullViewModel`.
- The view model applies typed results and retains application commands.
- Cache-hit and fresh-compute paths produce equivalent published state.
- Cancellation and stale-generation protection remain explicit and tested.

### Rollback

Each subphase is independently revertible because persisted formats remain
unchanged and the old application entry point is retained until 7D.

## Phase 8: isolate Deep Review as the optional capability

### Changes

1. Keep `DeepAIReviewFeature` as its focused observable operation model.
2. Move request construction and pipeline availability behind a Deep Review
   controller owned by the intelligence runtime.
3. Pass a narrow Deep Review model/actions surface to `DeepAIReviewSheetView`.
4. Keep group-signature validation, rating updates, winner overrides, and review
   state application in the application/culling layer.
5. Represent unavailable, checking, running, failed, cancelled, and completed states
   without optional-provider checks scattered through views.
6. Preserve the current candidate limit, prompt policy, subject-mask scoring,
   segmentation-provider selection, and cache behavior.

### Tests

- `DeepAIReviewFeatureTests`
- burst coordinator and review-state tests
- AI integration capability tests
- `make test-smoke`
- `make test-full`
- targeted performance qualification if image decoding or mask scoring moves

### Manual acceptance

- Missing selected segmentation model.
- SAM 3 and EfficientSAM selection.
- Start, cancel, retry, failure, and successful recommendation.
- Apply recommendation only to the matching burst and confirm rating/override state.

### Exit criteria

- General culling and similarity code does not know concrete segmentation types.
- Deep Review can be unavailable without conditional provider logic outside its
  capability surface.
- Applying a recommendation remains an explicit application action.

### Rollback

Restore request construction to the existing view-model extension. No persisted
format changes are required.

## Phase 9: hide persistence implementation types

This phase should begin only after feature ownership is stable.

### Changes

1. Keep `PerFileAnalysisArtifactStore` and `BurstAnalysisCache` as actors.
2. Introduce repository operations expressed in terms of feature requests and
   summaries rather than exposing codecs and storage records to views or the central
   view model.
3. Keep PhotoAIKit artifacts internal to the intelligence/persistence boundary.
4. Preserve on-disk encoding exactly. If an adapter is needed, translate at the
   repository edge without re-encoding or copying large payloads unnecessarily.
5. Keep cache usage and purge presentation as RawCull-owned summary values.
6. Tighten the import-boundary check so `PhotoAIContracts` is allowed only inside
   approved intelligence and persistence files.

Do not use this phase to create a new schema. Any desirable schema redesign must be
planned separately with backward/forward compatibility, migration, rollback, and
release-version policy.

### Tests

- `PerFileAnalysisArtifactStoreTests`
- `TypedAIPersistenceMatrixTests`
- all legacy migration cases
- `AICacheBoundaryTests`
- `make test-smoke`
- `make test-full`
- `make test-performance`

### Exit criteria

- Views and `RawCullViewModel` do not import `PhotoAIStorage` or use artifact codecs.
- Existing installations reuse current artifacts and burst caches without rebuilds.
- Corrupt-record isolation and partial writes behave exactly as before.

### Rollback

Restore direct repository forwarding. On-disk data is still compatible.

## Phase 10: perform physical organization separately

Only after the logical boundary is green should files be moved into a clearer
layout, for example:

```text
RawCull/Intelligence/
  Composition/
  Contracts/
  Similarity/
  SemanticSearch/
  BurstAnalysis/
  DeepReview/
  ModelManagement/
  Persistence/
  Presentation/
```

### Changes

1. Move files without changing symbols or behavior.
2. Commit file moves separately from import cleanup.
3. Update documentation and any path-based checks.
4. Run an unused-code/import audit only after the move commit is green.

### Tests

- import-boundary check
- `make test-smoke`
- exact-package Release build

### Exit criteria

- File placement matches dependency ownership.
- Git can recognize the moves without mixed logic edits.
- No target membership or resource packaging changed accidentally.

### Rollback

Revert the move commit.

## Phase 11: decide whether a new Swift package is justified

A new `RawCullIntelligence` Swift package is optional and should be the final
architectural decision, not the first implementation step.

Create it only if the established boundary has all of these properties:

- inputs and outputs are independent of SwiftUI views;
- package code does not need the complete `RawCullViewModel`;
- file and catalog types come from `RawCullCore` or package-owned contracts;
- persistence paths and application policy are injected;
- app-only resources and Background Assets extension wiring can stay in the app;
- moving the code creates compile-time dependency enforcement rather than circular
  adapters.

If those conditions are not met, keep an app-local module/folder. PhotoAIKit already
provides the reusable backend package; another package is not automatically better.

### Decision record

Record one explicit architecture decision before this phase is considered complete:

1. **Keep the boundary app-local.** Document which package criteria are not met,
   why an app-local boundary is preferable, and what evidence would justify
   revisiting the decision.
2. **Extract `RawCullIntelligence`.** Record the accepted dependency graph, target
   ownership, injected application concerns, resource ownership, and the commit for
   each extraction step.

Choosing to keep the boundary app-local is a valid completion of this phase. Do not
leave the phase indefinitely pending merely because package extraction was rejected.

### Package extraction sequence, if chosen

1. Move pure contracts only and pass all gates.
2. Move pure similarity/semantic policy and pass all gates.
3. Move repositories with injected paths and pass all gates.
4. Move burst compute orchestration and pass all gates.
5. Keep SwiftUI presentation and app composition in the application target unless
   there is a demonstrated reason to move them.

Run smoke and Release builds after every target-membership change. Run full and
performance suites after moving executable logic.

### Tests

- import-boundary check
- `make test-smoke`
- exact-package Release build after every target-membership change
- `make test-full` and `make test-performance` after moving executable logic

### Exit criteria

- The decision and its evidence are recorded in contributor documentation.
- If the boundary stays app-local, all final dependency rules can still be
  mechanically enforced.
- If a package is extracted, it has no SwiftUI, app-composition, Background Assets,
  or implicit application-path dependencies, and all gates are green after each
  extraction step.

### Rollback

If extraction is attempted, revert its independently reviewable commits in reverse
order while retaining the decision record and lessons learned. Persisted formats
must remain compatible throughout, so no user-data rollback is required.

## Phase 12: remove compatibility forwarding and finalize enforcement

### Changes

1. Use `rg` to prove old forwarding methods, compatibility initializers, and leaked
   backend imports have no callers.
2. Remove shims in small commits grouped by feature.
3. Tighten the import-boundary check to the final allowed paths.
4. Update `README.md`, `RawCullTests/TEST_ARCHITECTURE.md`, and architecture diagrams.
5. Record the final dependency rules and ownership model in contributor
   documentation.
6. Run unused-code analysis only after all shims are gone.

### Final gates

- `make test-smoke`
- `make test-full`
- `make test-performance`
- exact-package Release build
- manual acceptance matrix below

### Exit criteria

- CLIP remains the primary implementation with unchanged behavior.
- Vision fallback and optional Deep Review behavior remain intact.
- Concrete model providers are visible only to composition/backend adapters.
- Views consume narrow stable observable models and actions.
- `RawCullViewModel` no longer owns provider construction, model validation,
  artifact codecs, or feature-owned worker tasks.
- Burst computation can be tested separately from application navigation and rating
  commands.
- No compatibility shims remain without a documented reason.

## Manual acceptance matrix

Run this matrix at the end of phases 3, 6, 7, 8, and 12 as applicable:

### Repeatable prerequisites and evidence

- Use a versioned test catalog with a recorded file inventory and checksum. Keep a
  pristine copy for add, replace, rename, remove, and corrupt-cache scenarios.
- Record the application commit, macOS and Xcode builds, selected model manifests and
  fingerprints, preference setup, and cache state for every run.
- Use validated DataComp, OpenAI CLIP, SAM 3, and EfficientSAM bundles where the
  scenario requires them. Record a manual check as unavailable rather than silently
  skipping it when a licensed model resource is not available.
- Exercise model download through the configured production/staging source or an
  explicitly injected debug service; never substitute live network behavior for a
  deterministic cancellation or failure fixture.
- Use injected test/debug services for precise cancellation points, corrupt results,
  provider failures, and partial candidate failures that cannot be reproduced
  reliably through the release UI. Such scenarios must also have a named automated
  test.
- Store the dated result or link it from the phase record before advancing to the
  next phase.

### Startup and settings

- Launch with no optional model resources.
- Launch with valid DataComp CLIP.
- Launch with valid OpenAI CLIP.
- Launch with both CLIP models and confirm persisted selection.
- Corrupt, remove, and restore each model bundle.
- Refresh settings repeatedly and cancel by closing Settings.
- Relaunch and confirm preferences, licences, and capability presentation.

### Similarity and semantic search

- Index a new catalog and a partially indexed catalog.
- Force reindex and cancel at different progress points.
- Switch CLIP models before, during, and after hydration.
- Rank by visual similarity.
- Search using empty, successful, no-match, partial-index, and failure cases.
- Expand/collapse results and adjust result selection.
- Combine semantic results with rating filters and comparison mode.
- Clear/cancel search and verify catalog order, selection, and burst state.

### Burst analysis

- New analysis with empty caches.
- Compatible derived-cache restoration.
- Legacy artifact migration.
- Add, replace, rename, and remove source files.
- Cancel during hydration, sharpness, indexing, grouping, ranking, and save.
- Reindex, regroup, change sensitivity, and restore review states.
- Apply keep-best, keep-top-two, manual winner, undo, defer, and reviewed actions.

### Deep Review

- Missing segmentation model.
- SAM 3 and EfficientSAM runs.
- Cancel, retry, pipeline failure, partial candidate failure, and completion.
- Apply a matching recommendation and reject a stale/mismatched recommendation.

### Persistence and release

- Clear each cache independently.
- Relaunch and reuse compatible artifacts.
- Isolate a corrupt record without losing valid records.
- Verify model download, licence, app-group, and extension state.
- Build Release using the resolved package graph.
- Confirm app termination flushes persistence and releases security scope.

## Risk register

### Observable lifetime or invalidation regression

Risk: a feature model is recreated by SwiftUI, stored in the wrong wrapper, or one
large observable facade causes unrelated views to update excessively.

Mitigation: one app-root owner, stable model references, private `@State` for owned
observable instances, `@Bindable` only where bindings are needed, narrow models per
view, and identity tests before caller migration.

### Stale async results

Risk: moving task ownership loses cancellation handlers or generation checks.

Mitigation: characterize every cancellation path first; move a task and its
generation token together; validate task cancellation, generation, and catalog/model
identity before publishing on the main actor.

### Cache invalidation or unnecessary rebuild

Risk: apparently neutral wrappers change backend descriptors, schema versions,
digests, pipeline signatures, or encoded payloads.

Mitigation: no schema changes; equality/round-trip fixtures for current descriptors
and payloads; run migration and performance suites after repository changes.

### Duplicate state

Risk: a new runtime mirrors `SimilarityScoringModel` or Deep Review state and the two
copies diverge.

Mitigation: the runtime owns existing model instances and exposes references; it
does not copy their observable properties.

### Oversized facade

Risk: the intelligence runtime becomes another central view model with every field
forwarded through it.

Mitigation: runtime owns focused models/coordinators; views receive narrow models;
cross-feature actions remain explicit; avoid generic event buses and dynamic service
locators.

### Accidental product behavior change

Risk: modularization is used to alter defaults, error wording, fallback policy,
ranking, or view flow.

Mitigation: treat those as separate product changes after this refactor. Compare
against characterization tests and the manual acceptance matrix at every major gate.

### Premature package split

Risk: target boundaries expose circular dependencies, resource problems, longer
builds, or a large adapter layer.

Mitigation: prove the logical boundary inside the application target first. Package
only pure, stable code that gains real compile-time enforcement.

## Recommended stopping points

The refactor does not need to complete every phase to deliver value:

- **After Phase 3:** composition and configuration ownership are clear.
- **After Phase 6:** CLIP and semantic-search code have a coherent feature API and
  views no longer know storage/provider details. This is the best first milestone.
- **After Phase 8:** burst and Deep Review orchestration are independently testable,
  substantially reducing `RawCullViewModel` complexity.
- **After Phase 10:** physical organization matches logical ownership.
- **After Phase 12:** dependency rules are fully enforced and temporary shims are
  removed.

The recommended initial project is Phases 0 through 6. Reassess code size, test
clarity, build time, and remaining `RawCullViewModel` complexity before committing to
burst extraction or a new Swift package.

## Checklist for resuming this plan later

1. Read this document and confirm that CLIP is still a core required capability and
   Deep Review is still optional.
2. Re-run the import inventory because file names and dependencies may have changed.
3. Reconcile the plan with current tests and Make manifest counts.
4. Re-run the Phase 0 baseline gates against the current commit before resuming
   production refactoring, even if Phase 0 was completed previously.
5. Implement only one numbered phase or subphase at a time.
6. Record test results and manual checks before beginning the next phase.
7. Do not skip directly to file moves or a package split.
