# Modular AI Refactoring Plan

Status: active on the `version-3.2.0` development branch. Phases 0 through 2 were
implemented on 2026-08-28 against the `version-3.1.1` baseline, and Phases 3 and 4
were implemented on 2026-08-29. Phases 5 and 6 were implemented on 2026-08-29,
and Phases 7 through 12 have not started. Phase 6's automated gates pass; its
manual acceptance matrix remains pending. Phase 4's model-
download path was manually verified on 2026-08-29 by successfully downloading both
the DataComp and OpenAI CLIP models. The broader manual regression matrix remains
available for later phases.

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

Status: implemented on 2026-08-28. This phase is an ownership and composition
change only. Phase 3, not Phase 2, will move configuration coordination into the
runtime. Automated validation passed; the manual acceptance checklist below has
not been claimed as automated coverage.

Implementation note: the caller audit found that
`RawCullViewModel.similarityModel` must remain a `var` because existing SwiftUI
controls form writable bindings through it. The instance-based initializer and
runtime identity tests still guarantee that app composition stores the exact shared
model; the observable model contents and all view call sites remain unchanged.

### Starting point

`RawCullApp.init` currently creates `RawCullAIIntegration`, asks it for the initial
Vision similarity service and semantic-search capability, creates
`RawCullViewModel`, and then creates `RawCullAISettingsModel`. The settings model
holds two weak-view-model callback closures. When a refresh or preference change is
applied, those callbacks run in this order:

1. call `RawCullViewModel.setSimilarityService`;
2. call `RawCullViewModel.setSemanticSearchCapability`.

The view model creates its own `SimilarityScoringModel`, while the integration
creates the `DeepAIReviewFeature` injected into the view model. The app stores the
view model and settings model in separate `@State` properties. Phase 2 must preserve
that behavior and callback order while making object identity explicit.

### Runtime shape and ownership

Add an `@MainActor` `RawCullIntelligenceRuntime` with immutable references to:

- `RawCullAIIntegration`;
- `SimilarityScoringModel`;
- `DeepAIReviewFeature`;
- `RawCullAISettingsModel`.

The runtime is a lifetime container in this phase. It has no mirrored observable
properties, backend-selection methods, worker tasks, repository operations, or
general application state. In particular, it must not forward every property of
the similarity, settings, or Deep Review models.

The resulting ownership graph is:

```text
RawCullApp private @State
    -> RawCullIntelligenceRuntime
        -> RawCullAIIntegration
        -> SimilarityScoringModel <--- RawCullViewModel compatibility property
        -> DeepAIReviewFeature  <--- RawCullViewModel compatibility property
        -> RawCullAISettingsModel

RawCullAISettingsModel callbacks --weak capture--> RawCullViewModel methods
```

Multiple strong references to one model are acceptable; multiple model instances
are not. The weak callback captures must remain weak so this graph cannot become a
retain cycle.

### Implementation sequence

#### Phase 2A: make shared model injection possible

1. Add a `RawCullViewModel` initializer that accepts an already-created
   `SimilarityScoringModel` and `DeepAIReviewFeature` and stores those exact
   instances.
2. Retain the current service-based initializer as a compatibility initializer for
   tests and non-app callers. It may construct a similarity model and delegate to
   the new initializer, but production app composition must use the instance-based
   initializer.
3. Make the stored similarity reference immutable if the caller audit confirms it
   is assigned only during initialization. Do not make the model's observable
   contents immutable.
4. Do not change `setSimilarityService`, `setSemanticSearchCapability`, their task
   handles, cancellation order, hydration calls, or generation behavior.

Suggested commit boundary: the initializer seam plus focused identity tests. The
app still uses its old construction path at the end of this commit.

#### Phase 2B: add the lifetime container

1. Add `RawCullIntelligenceRuntime.swift` beside the existing AI integration
   application types. Its stored references are `let` properties.
2. Give it an internal initializer suitable for isolated tests. Keep production
   assembly in one explicit construction function or one contiguous block at the
   app composition root; do not scatter partial runtime construction across views.
3. Assemble production objects exactly once and in this order:
   - create `RawCullAIIntegration`;
   - create `SimilarityScoringModel` with the integration's current Vision service,
     the current default-selection semantic capability, the same nil initial
     semantic service, and the same artifact store default;
   - use `integration.deepAIReviewFeature` rather than creating another feature;
   - create `RawCullViewModel` with those two existing model instances;
   - create `RawCullAISettingsModel` with the same integration and the existing two
     weak-view-model callbacks;
   - create the runtime from those four references.
4. Add a debug precondition or construction-time assertion if it can compare the
   shared similarity and Deep Review references without exposing backend objects to
   presentation code. The unit tests remain the authoritative identity check.

This order is deliberate. Creating the settings model before its callback target
or creating the view model through its service-based compatibility initializer
would permit a second similarity model.

Suggested commit boundary: the runtime type and production assembly, with no scene
or view initializer changes yet.

#### Phase 2C: give SwiftUI one stable owner

1. Replace `RawCullApp`'s settings-model state with
   `@State private var intelligenceRuntime`; keep the existing view-model `@State`
   because general application ownership is not moving in this phase.
2. Initialize both state values from the single assembly result in `RawCullApp.init`.
   Never reconstruct the runtime or a child model in `body`, a scene closure, a
   computed property, or an environment default.
3. Continue passing `intelligenceRuntime.settingsModel` to `SettingsView`. Continue
   injecting the same `RawCullViewModel` into the environment and passing it to
   `RawCullMainView`.
4. Leave both existing `.task` modifiers separate and behaviorally unchanged:
   `viewModel.applyStoredScoringSettings()` and
   `intelligenceRuntime.settingsModel.refresh()` must still start from the same
   scene locations they do now.
5. Leave `AppDelegate.configure(viewModel:)`, termination flushing, security-scoped
   access, all view initializers, and all `viewModel.similarityModel` and
   `viewModel.deepAIReviewFeature` call sites unchanged.

Suggested commit boundary: only the app-root ownership switch and its tests.

### Explicitly deferred

Phase 2 does not:

- replace the two settings callbacks with a runtime command;
- move similarity or semantic hydration tasks out of `RawCullViewModel`;
- inject the runtime into the SwiftUI environment;
- migrate a view to read a runtime child directly, except that `RawCullApp` obtains
  the already-existing settings model from the runtime;
- move burst analysis, caches, artifact stores, or Deep Review actions;
- change defaults, preference keys, provider validation, capability calculation,
  refresh timing, cache paths, persisted formats, logging, or error presentation;
- rename existing AI types or move existing files.

### Tests

Add focused `RawCullIntelligenceRuntimeTests` covering:

- runtime construction preserves reference identity with `===` for its integration,
  similarity, settings, and Deep Review children;
- the production assembly gives `RawCullViewModel` the runtime's exact similarity
  and Deep Review instances;
- settings similarity and semantic callbacks target that same view model and fire
  in the existing similarity-then-semantic order;
- a no-op service/capability application retains the current model instance and
  does not start replacement hydration;
- releasing a temporary app-composition harness releases the runtime and models,
  proving that callback wiring introduced no retain cycle;
- repeated access through a scene-content harness returns the same runtime and
  child identities rather than recreating them.

Keep existing constructor coverage for the compatibility initializer. Do not rewrite
unrelated tests to use the runtime merely to increase adoption.

Run:

- the new `RawCullIntelligenceRuntimeTests`;
- `RawCullAIIntegrationTests`;
- `RawCullSemanticSearchTests`;
- `DeepAIReviewFeatureTests`;
- `make verify-ai-import-boundary`;
- `make test-smoke`;
- `make test-full`, because observable ownership and task lifetimes changed;
- the exact-package Release build, because a production file and app composition
  changed.

Do not run `make test-performance`: no indexing, ranking, serialization, artifact
mapping, or package boundary changes are authorized in this phase.

If the new test identifiers are added to a checked-in manifest, update the manifest,
enumeration count, integrity expectation, and `RawCullTests/TEST_ARCHITECTURE.md` in
the same commit as required by the validation rules above.

### Manual acceptance

- Launch the app, open and close Settings several times, and confirm the selected
  model, validation result, and download state do not reset.
- Open the main, Settings, and About windows in different orders and confirm no
  extra model validation, similarity reset, or Deep Review reset occurs.
- Change the CLIP enablement and selected CLIP model and confirm the same visible
  fallback, refresh, and hydration behavior as the Phase 0 baseline.
- Quit during active culling persistence and confirm termination still waits for the
  flush and releases security-scoped access.

### Exit criteria

- There is exactly one runtime, integration, similarity model, settings model, and
  Deep Review feature per app session.
- `RawCullApp` owns the runtime in private `@State`; no runtime or feature model is
  created by `body` or a scene closure.
- `RawCullViewModel.similarityModel` and
  `RawCullViewModel.deepAIReviewFeature` are the runtime's exact instances.
- Settings callbacks still weakly target the view model and preserve their original
  ordering and behavior.
- All old view-model APIs and all existing view call sites remain in place.
- No task, cache, repository, provider-selection, persistence, or product behavior
  moved.
- The focused tests, import boundary, smoke suite, full suite, and exact-package
  Release build pass.

### Validation evidence (2026-08-28)

- `RawCullIntelligenceRuntimeTests`: 5 tests passed, covering shared identity,
  callback targeting and ordering, no-op task behavior, and weak-callback lifetime.
- `make verify-ai-import-boundary`: passed with the same 5 non-blocking
  `PhotoAIContracts` leakage warnings recorded by Phase 1.
- `make test-smoke`: verified 184 unique manifest identifiers; all passed.
- `make test-full`: passed with Thread Sanitizer enabled.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -destination
  'platform=macOS,arch=arm64' -configuration Release
  -onlyUsePackageVersionsFromResolvedFile build`: passed.
- `make test-performance` was intentionally not run because Phase 2 did not change
  indexing, ranking, serialization, artifact mapping, or package boundaries.
- The manual acceptance checklist remains pending an interactive session with the
  user's existing catalog and preferences; no automated result is presented as a
  substitute for it.

### Rollback

Revert Phase 2C to restore the separate settings-model `@State`, then revert the
runtime container and instance-based initializer commits. The compatibility
initializer keeps existing callers source-compatible throughout rollback. No cache,
preference, model licence, or persisted user data requires migration or cleanup.

## Phase 3: replace settings callbacks with one typed configuration path

Status: implemented on 2026-08-29. Phase 3 is a configuration-ingress change, not
a similarity-pipeline extraction. The existing hydration workers remain in
`RawCullViewModel` until Phase 6, and provider discovery remains in
`RawCullAIIntegration`.

### Starting point and caller audit

`RawCullApplicationState.make` currently constructs `RawCullAISettingsModel` with
two independent weak-view-model closures. `RawCullAISettingsModel` resolves the
selected similarity and semantic services in `applySimilarityPreference()`, then
invokes the closures in this observable order:

1. `RawCullViewModel.setSimilarityService`;
2. `RawCullViewModel.setSemanticSearchCapability`.

Segmentation does not use either callback. Its settings setter calls
`RawCullAIIntegration.setSelectedSegmentationModel` directly and then copies the
integration's capability snapshot back into the settings model. Configuration is
therefore split across three paths even though all three choices originate in one
settings model.

The downstream behavior that Phase 3 must preserve is also split deliberately:

- `RawCullAISettingsModel.refresh()` owns refresh cancellation through
  `refreshGeneration` and publishes only the newest accepted refresh;
- `RawCullViewModel.setSimilarityService` cancels and resets burst analysis before
  replacing the image-similarity service, cancels its old hydration task, snapshots
  the current files, and starts replacement hydration;
- `RawCullViewModel.setSemanticSearchCapability` replaces semantic capability and
  service state, cancels semantic hydration, snapshots the current files, and
  starts replacement hydration;
- `SimilarityScoringModel` independently checks its artifact- and semantic-
  hydration generations, backend descriptors, and task cancellation before it can
  publish loaded artifacts.

The production caller audit at the start of implementation must use `rg` to confirm
that `RawCullIntelligenceRuntime.swift` is still the only production site that
calls the two view-model setters for settings changes. Direct test calls to a
standalone `RawCullViewModel` or `SimilarityScoringModel` are not evidence of a
second production configuration path.

### Typed configuration contract

Add one RawCull-owned, main-actor configuration snapshot. The exact spelling may be
adjusted to fit the source, but its shape should be equivalent to:

```text
RawCullIntelligenceConfiguration
    revision
    similarity
        service: any RawCullSimilarityServicing
    semanticSearch
        capability: RawCullSemanticSearchCapabilityStatus
        service: (any RawCullSemanticSearchServicing)?
    segmentationModel: RawCullSegmentationModel
```

The snapshot may carry values conforming to RawCull-owned service protocols, but it
must not expose `CoreAICLIPBackend`, `CoreAISAM3Backend`,
`CoreAIEfficientSAMBackend`, `VisionFeaturePrintBackend`, or concrete provider
instances in its API. It is confined to `@MainActor`; do not add unchecked
`Sendable` conformance merely to move service existentials between tasks.

Give the snapshot a separate immutable identity value used for equality and no-op
decisions. That identity should be `Equatable` and `Sendable` and contain only:

- the similarity service's primary backend descriptor;
- its complete ordered `artifactBackendDescriptors`, because the current no-op
  guard compares both values;
- the complete semantic capability status;
- the semantic service backend descriptor, or `nil`;
- the selected `RawCullSegmentationModel`.

Do not compare existential object identity or concrete provider types. The existing
backend descriptors are the compatibility identity already used by hydration,
persistence, and backend-separation tests.

`revision` is ordering metadata, not part of configuration identity.
`RawCullAISettingsModel` increments it each time it publishes an accepted complete
snapshot. The runtime records the newest accepted revision so an older injected or
delayed snapshot cannot restore prior state. A newer revision with the same identity
must advance the accepted revision without restarting work.

### One weak, typed delivery path

Replace the two stored callback closures with one class-bound, `@MainActor` typed
consumer, for example `RawCullIntelligenceConfigurationApplying`. It exposes one
operation that accepts the complete snapshot and returns the integration's resulting
`RawCullAICapabilities`. `RawCullAISettingsModel` retains that consumer weakly and
supports a one-time internal binding performed by application assembly. The settings
model assigns the returned capabilities without emitting another command.

Mark both the weak consumer storage and the monotonically increasing configuration
revision storage with `@ObservationIgnored`. They are orchestration bookkeeping, not
settings presentation state, and changing them must not invalidate SwiftUI views.

This is intentionally not a closure, notification, `AsyncStream`, Combine
publisher, environment action, service locator, or general event bus. There is one
producer and one consumer, both main-actor isolated, and delivery is synchronous.
The weak edge is required because the runtime strongly owns the settings model.

The resulting Phase 3 ownership and command graph is:

```text
RawCullApplicationState
    -> RawCullIntelligenceRuntime
        -> RawCullAIIntegration
        -> SimilarityScoringModel
        -> DeepAIReviewFeature
        -> RawCullAISettingsModel
        --weak application target--> RawCullViewModel
    -> RawCullViewModel

RawCullAISettingsModel --weak typed configuration--> runtime.apply(configuration:)
runtime --ordered compatibility calls--> RawCullViewModel configuration methods
```

The runtime's application target should remain weak so the intelligence lifetime
container does not take ownership of general application state. Do not inject the
runtime into SwiftUI's environment in this phase.

### Runtime application rules

Add exactly one runtime entry point for a complete configuration snapshot. Its
application algorithm must be explicit and synchronous on `@MainActor`:

1. Reject a revision older than the last accepted revision. Treat an equal revision
   with a different identity as an invalid producer state in debug builds.
2. Derive similarity, semantic, and segmentation changes by comparing the incoming
   identity with the last applied identity.
3. If no identity component changed, record the newer revision and return without
   cancelling burst work, replacing a service, or starting hydration.
4. Apply a changed segmentation selection through
   `RawCullAIIntegration.setSelectedSegmentationModel` and return
   `integration.capabilities()` to the settings model. The no-op and stale-revision
   paths return the same current capability snapshot.
5. Apply a changed similarity configuration through the existing
   `RawCullViewModel.setSimilarityService` compatibility seam.
6. Apply changed semantic capability/service through
   `RawCullViewModel.setSemanticSearchCapability` only after the similarity call.
7. Record the accepted identity and revision in the runtime.

Steps 5 and 6 preserve the existing similarity-then-semantic observable order. The
view-model methods remain the downstream compatibility seam in this phase; they are
not an alternative app-level settings ingress. Add comments marking the runtime as
their only production settings caller. Moving their task handles or their
application-specific burst reset into the runtime is deferred to Phase 6.

This scope preserves the current similarity replacement sequence exactly:

1. compare primary and artifact backend descriptors;
2. cancel and reset stale burst analysis;
3. replace the service and reset incompatible similarity state;
4. cancel the previous similarity hydration task;
5. snapshot `RawCullViewModel.files`;
6. hydrate that snapshot;
7. allow publication only when the model generation, service descriptors, and task
   cancellation checks are still current.

Semantic replacement likewise retains its current capability/backend comparison,
semantic search cancellation, semantic hydration generation increment, state reset,
old-task cancellation, file snapshot, and stale-result guards. Do not combine the
two hydration tasks, make either task detached, or add a second copy of their
generation state.

### Settings publication and refresh order

`RawCullAISettingsModel` remains the only owner of preference persistence and
settings-facing capability state. Replace `applySimilarityPreference()` with one
helper that resolves and publishes a complete configuration snapshot from the
current settings and integration state.

Preserve each setter's existing validation and persistence order:

- reject an excluded CLIP or segmentation model;
- return immediately when the selected value is unchanged;
- update the observable selection;
- write the existing `UserDefaults` key and raw value;
- resolve and publish exactly one complete configuration snapshot.

For segmentation, remove the direct settings-to-integration mutation. The runtime
applies the selection and the settings model then receives the resulting capability
snapshot so `inProcessMaskGeneration` still changes immediately. This capability
copy must not recursively emit another configuration.

Preserve the accepted `refresh()` sequence:

1. increment and capture `refreshGeneration` and begin the saved-evidence scan
   presentation;
2. read the model-download snapshot;
3. check cancellation and install the managed model locations;
4. refresh provider capabilities and scan saved evidence concurrently;
5. check cancellation and reject a superseded refresh generation;
6. publish capabilities, download states, managed locations, and accepted licence
   IDs;
7. resolve and publish one complete configuration snapshot;
8. publish the saved-evidence success or failure;
9. clear the scanning presentation only for the still-current refresh generation.

No snapshot may be assembled before an `await` and delivered after it. Assemble it
only after the post-await cancellation and refresh-generation guards, using the
then-current selections. If the user changes a preference while refresh is in
flight, that setter publishes immediately; the accepted refresh may later publish a
newer revision using the same latest preference and newly validated capabilities.
An older overlapping refresh publishes nothing.

Retain these exact preference keys and defaults:

- `RawCullAI.useCLIPForSimilarity`;
- `RawCullAI.selectedCLIPModel`;
- `RawCullAI.selectedSegmentationModel`;
- CLIP enabled by default when its key is absent;
- the existing inclusion-filtered default CLIP and segmentation selections.

### Assembly sequence

Revise `RawCullApplicationState.make` without creating a second model or changing
SwiftUI scene ownership:

1. create `RawCullAIIntegration` as today;
2. create `RawCullAISettingsModel` without callbacks or an applied configuration
   side effect; it may read preferences and resolve an initial snapshot;
3. create the one `SimilarityScoringModel` from that initial snapshot's similarity
   service and semantic capability/service, using the same artifact store;
4. reuse `integration.deepAIReviewFeature`;
5. create `RawCullViewModel` with those exact model instances;
6. create `RawCullIntelligenceRuntime` with the integration, child models, settings
   model, and weak application target;
7. bind the settings model's weak typed consumer to that runtime exactly once;
8. synchronously publish the initial complete snapshot. Similarity and semantic
   application should be no-ops because the model was built from that snapshot;
   segmentation applies the saved selection and refreshes settings readiness;
9. retain the runtime and view model in the existing private `@State` properties.

This construction must not validate model bundles, start settings refresh, or
hydrate an empty catalog. Leave the main-window `.task` that calls
`settingsModel.refresh()` in its current scene location, and leave
`applyStoredScoringSettings()` as a separate task.

### Implementation sequence and commit boundaries

#### Phase 3A: characterize the complete current contract

1. Extend focused tests to record similarity-before-semantic ordering, segmentation
   readiness update, no-op setter behavior, preference writes, and the accepted
   refresh publication point.
2. Add a controlled in-flight hydration fixture if the existing persistence matrix
   cannot drive the view-model-level service switch deterministically.
3. Make no production changes in this commit.

#### Phase 3B: introduce the value and runtime command

1. Add the configuration snapshot, equatable identity, revision handling, and weak
   typed consumer protocol inside the RawCull application boundary.
2. Add `RawCullIntelligenceRuntime.apply(configuration:)` and a weak application
   target while leaving settings callbacks temporarily connected.
3. Prove the runtime command's ordering, no-op, stale-revision, and lifetime behavior
   with direct tests before switching the producer.

#### Phase 3C: switch settings and composition atomically

1. Replace both callbacks and the direct segmentation mutation with the single
   typed publication helper.
2. Change assembly to the sequence above and bind the settings model once.
3. Update settings tests to use a typed consumer spy rather than closure counters.
4. Run `rg` to prove no production callback initializer arguments or alternative
   settings configuration calls remain.

#### Phase 3D: remove only obsolete callback surface

1. Remove `similarityServiceDidChange` and
   `semanticSearchCapabilityDidChange` storage and initializer parameters after all
   callers have moved.
2. Keep the two view-model compatibility methods and their current worker behavior
   for Phase 6.
3. Update `RawCullTests/TEST_ARCHITECTURE.md` and checked-in manifests/counts only if
   test identifiers were added, removed, or renamed.

### Explicitly deferred

Phase 3 does not:

- move similarity or semantic hydration task ownership out of `RawCullViewModel`;
- merge similarity and semantic hydration or change task priority/isolation;
- move provider validation or resource managers out of `RawCullAIIntegration`;
- move preference storage, download state, licence handling, or saved-evidence scans
  out of `RawCullAISettingsModel`;
- change backend descriptors, artifact compatibility, cache paths, schemas, or
  persisted payloads;
- inject the runtime into the environment or migrate any view call site;
- change CLIP fallback, default selection, semantic cached-only behavior,
  segmentation availability, or error wording;
- rename or physically move AI files.

### Automated tests

Add or update focused coverage for:

- application assembly still shares one integration, similarity model, settings
  model, and Deep Review feature by reference identity;
- the settings model emits one complete snapshot for a preference change, and the
  runtime applies similarity before semantic;
- a segmentation-only change does not reset similarity, semantic search, or burst
  analysis, but does immediately update the selected Deep Review capability;
- a newer revision with identical identity is a no-op for burst cancellation,
  service replacement, hydration task creation, and child-model identity;
- an older revision arriving after a newer configuration is ignored;
- changing the CLIP model while similarity and semantic hydration are suspended
  cancels or supersedes the old work, and releasing that work cannot publish the old
  backend;
- overlapping settings refreshes allow only the newest accepted generation to emit
  configuration;
- a preference change during refresh is not replaced by a snapshot assembled from
  pre-await selections;
- initial assembly performs no validation or hydration and the scene refresh still
  performs the first resource validation;
- releasing an application-state harness releases the runtime, settings model,
  similarity model, and view model, proving both weak edges prevent cycles;
- the three existing preference keys, absent-key defaults, inclusion filtering, and
  relaunch restoration are unchanged.

Run:

- `RawCullIntelligenceRuntimeTests`;
- the settings and model-validation tests in `RawCullAIIntegrationTests`;
- `RawCullSemanticSearchTests`;
- the superseded-hydration and backend-separation cases in
  `TypedAIPersistenceMatrixTests`;
- relevant `PhotoAIKitSimilarityMigrationTests` backend-switch cases;
- `make verify-ai-import-boundary`;
- `make test-smoke`;
- `make test-full`, because configuration ordering and cancellation paths changed;
- the exact-package Release build, because app composition changed.

Do not run `make test-performance` if the implementation stays within this scope:
indexing, ranking, serialization, artifact mapping, and task ownership are
unchanged. Run it if the implementation exceeds that boundary.

### Manual acceptance

- Launch with each saved CLIP selection and with CLIP similarity both enabled and
  disabled; confirm the same active backend and Vision fallback presentation after
  refresh.
- Change CLIP selection repeatedly while a catalog is open and confirm stale burst
  results disappear, the current catalog hydrates, and an old backend never
  reappears.
- Start semantic search, change CLIP selection, and confirm stale semantic results
  clear and only the selected model's compatible cached index is reported.
- Change between SAM 3 and EfficientSAM and confirm readiness and Deep Review
  availability update without disturbing similarity or semantic selection.
- Open main, Settings, and About windows in different orders and confirm no extra
  runtime, child model, validation, or hydration is created.
- Relaunch and confirm all three preferences restore with their existing keys and
  defaults.

Status: pending an interactive app session. The automated coverage below exercises
the same configuration identities, persistence keys, replacement ordering, and
stale-work guards, but it does not replace this user-visible acceptance pass.

### Implementation and validation evidence (2026-08-29)

The completed implementation follows the planned ownership boundary:

- `RawCullAISettingsModel` now publishes one revisioned
  `RawCullIntelligenceConfiguration` through one weak, main-actor typed consumer;
  the two callback properties and direct segmentation mutation are gone;
- `RawCullIntelligenceRuntime.apply(configuration:)` is the only production
  settings ingress and compares immutable descriptor-based configuration identity
  before applying segmentation, similarity, and semantic changes;
- stale revisions are ignored, newer identical revisions advance without restarting
  work, and changed similarity is still applied before changed semantic capability;
- application assembly creates the settings snapshot first, constructs one shared
  similarity model from it, binds the runtime once, and retains weak edges to both
  the configuration consumer and application target;
- similarity and semantic hydration workers, cancellation, generations, burst
  reset behavior, provider discovery, persistence schemas, and cache locations stay
  in their pre-Phase-3 owners as planned.

Production searches found no remaining `similarityServiceDidChange` or
`semanticSearchCapabilityDidChange` symbols. The only production invocations of
the two `RawCullViewModel` compatibility setters are the ordered calls from
`RawCullIntelligenceRuntime`; their underlying model methods remain for Phase 6.

Automated results:

- `RawCullIntelligenceRuntimeTests`: 8 tests passed, covering shared assembly
  identity, the typed settings path, similarity-before-semantic ordering, identical
  and stale revisions, segmentation-only changes, in-flight hydration
  supersession, and weak-edge release;
- `RawCullAIIntegrationTests`: 7 tests passed, including model validation,
  refresh cancellation, capability assembly, preference defaults/persistence, and
  relaunch restoration through the assembled runtime;
- `make verify-ai-import-boundary`: passed with the same five non-blocking
  `PhotoAIContracts` leakage warnings tracked outside the intelligence/persistence
  boundary;
- `make test-smoke`: enumeration verified exactly 187 unique identifiers and all
  smoke tests passed;
- `make test-full`: the complete RawCull test plan passed with Thread Sanitizer
  enabled, including semantic search, typed persistence, backend separation, and
  PhotoAIKit migration coverage;
- the exact resolved-package arm64 Release build passed with
  `-configuration Release -destination 'platform=macOS,arch=arm64'`;
- `git diff --check` and SwiftFormat lint for the touched Phase 3 production and
  runtime-test sources passed.

`make test-performance` was not run because Phase 3 did not change indexing,
ranking, serialization, artifact mapping, or hydration task ownership.

### Exit criteria

- `RawCullAISettingsModel` has no similarity or semantic callback properties and no
  direct segmentation-selection mutation of the integration.
- `RawCullApplicationState.make` contains no backend-change callback wiring and
  binds exactly one weak typed configuration consumer.
- Every production settings change enters
  `RawCullIntelligenceRuntime.apply(configuration:)` as one complete snapshot.
- The runtime is the only production configuration ingress; the two view-model
  methods remain documented downstream compatibility seams for Phase 6.
- Repeated identical configuration is a no-op, and an older revision cannot replace
  newer runtime state.
- Similarity-before-semantic ordering, burst cancellation, hydration cancellation,
  generation checks, and stale-result rejection match the Phase 0/2 behavior.
- Segmentation selection and settings readiness remain synchronous from the user's
  perspective.
- Preference keys/defaults, provider validation, fallback policy, cache formats,
  and all visible settings behavior are unchanged.
- Focused tests, import boundary, smoke, full TSan suite, and exact-package Release
  build pass.

### Rollback

Revert Phase 3C/3D first to restore the two weak settings callbacks and direct
segmentation application, then remove the unused runtime command and configuration
types from Phase 3B. The Phase 2 runtime, shared object identities, compatibility
view-model methods, preference files, caches, model licences, and downloaded models
remain valid; no user-data migration or cleanup is required.

## Phase 4: migrate settings and model management first

Status: implemented and verified on 2026-08-29. The focused model-management
boundary, weak managed-location synchronization, runtime identity, and SwiftUI
migration are in place. Automated validation passes, and the model-download path
was manually verified with both supported CLIP models.

Settings is the safest first UI slice because `RawCullAISettingsModel` is already a
narrow presentation boundary. Phase 4 completes that boundary instead of moving
provider discovery or download infrastructure into SwiftUI.

### Starting point and caller audit

Phases 2 and 3 already completed two mechanical steps that the earlier Phase 4
outline expected:

- `RawCullApp` retains one `RawCullIntelligenceRuntime` in private `@State` and
  passes `intelligenceRuntime.settingsModel` directly to `SettingsView`;
- `SettingsView` and `AISettingsTab` receive that stable model rather than resolving
  it from `RawCullViewModel` or constructing it in a view body.

The remaining ownership problem is inside `RawCullAISettingsModel`. It currently
combines two independently changing responsibilities:

1. preference, capability, configuration-publication, and saved-burst-evidence
   state used by `AISettingsTab`;
2. model catalog, licence acceptance, download/removal state, task cancellation,
   and managed-model locations used by `AIModelDownloadsView`.

The production caller audit must confirm that `AIModelDownloadsView` is the only
SwiftUI consumer of model-download actions and that the AI settings and model-
download subtree does not import or hold `RawCullAIModelDownloadCoordinator`, a
model provider, a storage repository, or `RawCullAIIntegration`. The current
saved-burst presentation already satisfies that subtree's storage boundary:
`AISettingsTab` reads RawCull-owned evidence values from the settings model, while
the injected `RawCullSavedBurstEvidenceScanner` alone reads the AI cache directory.
The separate general `CacheSettingsTab` and its existing cache-maintenance access
are outside this phase. Phase 4 must not add a duplicate cache summary merely to
make this phase larger.

### Focused presentation ownership

Introduce one `@MainActor @Observable` `RawCullAIModelManagementModel`. It is a
focused settings-facing model, not a service and not another application facade.
It owns:

- the prepared, stable-identity `RawCullAIModelDownloadPresentation` collection;
- the model download catalog and coordinator;
- accepted-licence and managed-location snapshots needed to prepare that
  collection;
- one task per model download and their existing cancellation behavior;
- licence acceptance, start, cancel, retry, and managed-model removal actions.

Keep the coordinator, service, acceptance store, raw model locations, and task
dictionary observation-ignored and private. SwiftUI receives only the prepared
presentation collection and action methods. Store the presentation collection as
an observable value and rebuild it only when a snapshot or explicit transition
changes, rather than making every row repeatedly derive it from several observed
collections.

`RawCullAISettingsModel` continues to own:

- the three existing preference keys and their exact defaulting behavior;
- selected CLIP and segmentation choices;
- capability/readiness state and the complete typed configuration publication;
- saved-burst-evidence scan state and cancellation generation.

The settings model retains the exact model-management child supplied at assembly
and exposes it as a stable `let` reference. This is lifetime composition, not
forwarding: download and licence methods must be removed from the settings model
after callers migrate.

### Managed-location synchronization contract

Model installation and removal change provider readiness, so the two focused
models need one narrow, typed edge. Add a main-actor, class-bound consumer protocol
whose only command applies a complete managed-model-location snapshot.

`RawCullAIModelManagementModel` holds that consumer weakly and binds it exactly
once. `RawCullAISettingsModel` implements the command in this order:

1. apply the complete location dictionary to `RawCullAIIntegration`;
2. refresh integration capabilities and saved-burst evidence using the existing
   refresh generation;
3. publish the complete typed intelligence configuration through the Phase 3 path.

The weak edge prevents `settings model -> model-management model -> settings model`
from becoming a retain cycle. A cancelled or superseded refresh must still be
unable to publish stale readiness or evidence.

### Runtime and SwiftUI wiring

`RawCullApplicationState.make` must assemble Phase 4 in one order:

1. create `RawCullAIModelManagementModel` with the existing catalog, coordinator,
   paths, and RawCull version inputs;
2. create `RawCullAISettingsModel` with that exact child;
3. construct the existing similarity model, view model, and runtime;
4. bind the settings configuration consumer as in Phase 3;
5. retain the exact model-management child on the runtime and assert its identity.

`AISettingsTab` continues to depend only on `RawCullAISettingsModel`. When it opens
the download sheet, it passes the stable child to `AIModelDownloadsView`.
`AIModelDownloadsView`, its rows, and its licence sheet then depend only on
`RawCullAIModelManagementModel`; they must not receive the runtime, application
view model, integration, coordinator, or provider objects. Continue to use stable
download IDs for `ForEach` and sheet identity.

### Implementation sequence and commit boundaries

#### Phase 4A: characterize ownership and lifecycle

1. Confirm all production download/licence callers and the absence of direct store
   access from settings views with `rg`.
2. Add focused presentation-model tests for initial checking state, snapshot
   refresh, managed-location delivery, licence transitions, download progress,
   cancellation, removal, and error presentation where existing coordinator tests
   do not already establish the behavior.
3. Extend runtime tests to assert the exact model-management identity and weak-edge
   lifetime.

Suggested commit boundary: tests and this expanded plan only.

#### Phase 4B: extract the model-management presentation model

1. Move the download presentation value and all catalog/coordinator/task state and
   actions out of `RawCullAISettingsModel` without renaming persisted keys or
   backend types.
2. Add the weak managed-location consumer and preserve the existing operation
   order for refresh, successful installation, cancellation, failure, and removal.
3. Leave `RawCullAISettingsModel.refresh()` as the settings-facing refresh entry
   point; it delegates the model snapshot refresh and accepts the resulting
   complete location snapshot through the typed consumer.

Suggested commit boundary: focused model extraction with compatibility forwarding
still available if required by compiling callers.

#### Phase 4C: switch runtime and views atomically

1. Update application assembly and runtime identity to retain the extracted model.
2. Pass the child from `AISettingsTab` into `AIModelDownloadsView` and update all
   download/licence row actions to target it.
3. Remove obsolete download forwarding, observed collections, and the unused
   settings deletion flag only after `rg` reports no callers.

Suggested commit boundary: runtime and SwiftUI migration plus obsolete-surface
removal.

#### Phase 4D: validate without widening scope

1. Run the focused suites, import-boundary verification, smoke and full tests, and
   the exact-package Release build.
2. Do not run the performance suite: Phase 4 does not alter indexing, ranking,
   artifact mapping, cache serialization, or a package boundary.
3. Record automated results here and leave interactive checks explicitly pending
   when no app session was performed.

### Explicitly unchanged

Phase 4 does not change:

- Settings tab layout, labels, help, accessibility copy, sheets, or confirmation
  dialogs;
- preference keys, defaults, model selection, fallback policy, model inclusion,
  download source, catalogue metadata, licence checksums, or release readiness;
- Background Assets service behavior, extension target membership, entitlements,
  asset-pack identifiers, or packaging;
- provider discovery, bundle validation, cache paths/formats, saved evidence scan
  rules, or configuration ordering;
- similarity/semantic hydration ownership, burst analysis, or Deep Review actions.

### Automated tests

Run:

- `RawCullAIIntegrationTests`, including Settings refresh cancellation and
  persisted model-selection behavior;
- `RawCullAIModelDownloadsTests`, including coordinator policy and the extracted
  presentation-model lifecycle;
- `RawCullIntelligenceRuntimeTests`, including exact shared identity and weak-edge
  release;
- `AICacheBoundaryTests`;
- `ReleaseMetadataTests`;
- `make verify-ai-import-boundary`;
- `make test-smoke`;
- `make test-full`, because observable ownership and task lifetime changed;
- the exact-package Release build, because a new production source and app
  composition changed.

If test identifiers change, update the smoke count and test-architecture record in
the same change. The model downloader extension does not need a separate wiring
build unless its target membership or packaging changes.

### Manual acceptance

- Open Settings repeatedly and confirm neither focused model is recreated.
- Validate missing, corrupt, restored, and installed model presentation.
- Change CLIP and segmentation selections and relaunch.
- Start and cancel a model download using the configured production/staging source
  or an explicitly injected debug service, and record which source was used.
- Verify licence acceptance, retry, model removal, and post-removal fallback state.
- Close the download and Settings sheets during active refresh/download work and
  confirm no stale presentation or crash appears when they reopen.

Verification record (2026-08-29): both supported CLIP model bundles, DataComp and
OpenAI, were downloaded successfully through the Phase 4 model-management UI. This
satisfies the Phase 4 model-download qualification. Cancellation, removal, corrupt-
bundle recovery, and repeated-window checks remain in the shared regression matrix
and must be repeated when a later phase changes those paths.

### Exit criteria

- `AISettingsTab` knows only `RawCullAISettingsModel`, and download/licence views
  know only `RawCullAIModelManagementModel` plus presentation values.
- The runtime and settings model retain the same exact model-management instance;
  no view constructs an observable model.
- Provider, coordinator, acceptance-store, AI cache-store, and concrete backend
  objects remain invisible to the AI settings and model-download SwiftUI subtree.
- Managed-location changes travel through one weak typed edge and then through the
  Phase 3 configuration path.
- Download cancellation, retry, removal, licence, and refresh behavior are
  unchanged, and stale refreshes cannot publish.
- No persisted key, format, path, catalogue inclusion decision, extension wiring,
  or product behavior changed.
- Focused tests, import boundary, smoke, full TSan suite, and exact-package Release
  build pass.

### Validation evidence (2026-08-29)

- `RawCullAIModelDownloadsTests`, `RawCullIntelligenceRuntimeTests`, and
  `RawCullAIIntegrationTests` passed together, including extracted-model progress,
  installation, cancellation, removal, exact shared identity, weak-edge release,
  refresh cancellation, and persisted-selection coverage.
- `make verify-ai-import-boundary` passed with the same 5 non-blocking
  `PhotoAIContracts` leakage warnings recorded by earlier phases.
- `make test-smoke` verified exactly 189 unique manifest identifiers; all passed.
- `make test-full` passed with Thread Sanitizer enabled: 356 tests passed with no
  failures, skips, or runtime warnings.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -destination
  'platform=macOS,arch=arm64' -configuration Release
  -onlyUsePackageVersionsFromResolvedFile build` passed.
- `git diff --check` passed, and the AI settings/model-download caller audit found
  no direct coordinator, integration, provider, or AI cache-store dependency.
- `make test-performance` was intentionally not run because Phase 4 did not change
  indexing, ranking, serialization, artifact mapping, or a package boundary.
- The model-download acceptance path was manually verified on 2026-08-29 with both
  DataComp and OpenAI CLIP. The remaining broader manual scenarios are retained as
  regression coverage for later phases and were not inferred from the two
  successful downloads.

### Rollback

Restore `AIModelDownloadsView` to the settings model, move the extracted download
state/actions back into `RawCullAISettingsModel`, then remove the child and weak
consumer from runtime assembly. The Phase 2 runtime and Phase 3 configuration path
remain valid. No preference, cache, model licence, downloaded asset pack, or other
user data requires migration or cleanup.

## Phase 5: migrate semantic search as an isolated vertical slice

Status: implemented on 2026-08-29. The semantic-search ownership and caller
migration is complete, while similarity indexing task ownership remains unchanged
for Phase 6. Automated gates pass; the manual acceptance matrix remains available
for an interactive regression pass.

### Starting point and caller audit

The semantic workflow currently crosses three ownership layers:

- `SimilarityScoringModel` owns capability, cached semantic artifacts, ranking
  task/generation state, progress, matches, scores, selected-result order, and the
  default top-20 policy;
- `RawCullViewModel+Similarity.swift` owns application coordination around a query:
  rating/filename admission, scoped-burst invalidation, selection clearing,
  comparison-mode exit, catalog re-sorting, and thumbnail-selection reconciliation;
- SwiftUI views read semantic properties by traversing
  `RawCullViewModel.similarityModel` and invoke a mixture of view-model forwarding
  methods and direct model cancellation.

The initial production audit must enumerate, at minimum:

- `SemanticSearchControlsView`, `SemanticSearchQueryEntryView`, and
  `SimilarityGridSelectionView` for query entry and workflow-state switching;
- `SharedMainToolbarContent` for result-count adjustment and review admission;
- `CullingGridView` for per-thumbnail semantic rank and score;
- `ZoomCullingMetadata` and accessibility presentation for semantic result evidence;
- `RawCullViewModel+Catalog.swift` for admission, result ordering, rating-filter
  composition, active-catalog scope, and thumbnail reconciliation;
- sharpness, burst, thumbnail, and comparison call sites that consume
  `activeCatalogFiles` after a semantic selection is established.

Before production changes, use `rg` to record every direct read of
`semanticSearchState`, `semanticSearchProgress`, `semanticResultOrder`,
`semanticScores`, `semanticIndexedFileCount`, `semanticCatalogFileCount`, and every
call to the five view-model semantic forwarding methods. Tests that deliberately
exercise `SimilarityScoringModel` in isolation are not UI leakage and should remain
direct model tests.

### Focused semantic-search feature surface

Introduce one stable, `@MainActor` `RawCullSemanticSearchFeature` owned by the
intelligence runtime. The exact name may be adjusted during implementation, but it
must have these properties:

- it retains the runtime's exact `SimilarityScoringModel` instance and never copies
  semantic state into a second observable store;
- its presentation properties are computed projections of that model, so a state,
  progress, score, or selection value has one source of truth;
- it exposes semantic-only actions and result metadata rather than the complete
  similarity/burst model;
- it has no model provider, artifact codec, repository, `UserDefaults`, navigation,
  rating, or culling dependency;
- it does not store query text, focus state, sheet state, or a SwiftUI submission
  task. Those remain local UI concerns.

The minimum presentation surface should include:

- the existing `SemanticSearchUIPresentation`, constructed in the feature rather
  than independently by each view;
- the current search state and progress needed to select the content state;
- the current result summary and selected/ranked counts;
- a read-only selected-file-ID set or ordered result IDs for application filtering;
- a semantic result-evidence operation returning RawCull-owned rank and score for a
  file ID, so thumbnail and zoom views do not read score dictionaries directly;
- capability/backend presentation sufficient for accessibility and readiness copy,
  without exposing the concrete semantic provider.

Keep `RawCullSemanticSearchState`, `RawCullSemanticSearchResultSummary`,
`RawCullSemanticSearchProgress`, and `SemanticSearchUIPresentation` as the existing
value contracts unless a focused characterization test demonstrates that a change
is necessary. Do not rename them as part of caller migration.

### Narrow application coordination contract

The semantic feature cannot own catalog, rating, navigation, or selection policy.
Give it one weak, class-bound, main-actor application target whose protocol contains
only the operations required by the current workflow. Its responsibilities should
be equivalent to:

1. return the current semantic admission snapshot after filename, rating, and
   sharpness policy has been applied;
2. prepare the application for a new semantic result by discarding an incompatible
   scoped burst result, clearing multi-selection, leaving burst mode, and clearing
   an active burst comparison;
3. apply a changed semantic selection by restoring the similarity-grid context,
   recomputing the catalog projection, and reconciling thumbnail selection;
4. restore ordinary catalog order after clear or cancel.

`RawCullViewModel` may implement this protocol, but the feature must retain only the
protocol existential weakly. No feature method takes a `RawCullViewModel` parameter,
and the protocol must not grow generic access to files, navigation, ratings, or
other application state.

Bind the target exactly once during `RawCullApplicationState.make`. The runtime and
view model may both retain the same feature reference for compatibility during the
migration; a second feature or second similarity model is prohibited. Add identity
and release tests for this graph.

### Action ordering and cancellation contract

Move the existing orchestration into semantic feature actions without changing its
observable order.

For a non-empty query:

1. trim whitespace and route an empty result to `clear`;
2. await the application target's admitted-file snapshot;
3. stop if the caller task was cancelled;
4. ask the application target to prepare for semantic results;
5. call the existing cached-only `SimilarityScoringModel.rankSemantically` with the
   literal query and admitted snapshot;
6. stop if the caller task was cancelled or the model rejected the generation;
7. ask the application target to apply the current semantic selection.

For show-all and selection-count adjustment:

1. invalidate only scoped burst presentation that is incompatible with the changed
   semantic scope;
2. update the existing model selection count without rerunning text encoding or
   cosine scoring;
3. recompute the application projection and reconcile thumbnail selection.

For clear and cancel:

1. cancel the model's semantic task exactly once;
2. clear semantic result/order/score presentation using the existing generation
   guard;
3. restore ordinary catalog filtering and ordering;
4. preserve compatible burst-analysis data exactly as today.

The current query view cancels its local `searchTask`, directly cancels the model,
and then calls the view-model cancellation method. Characterize that path first,
then replace it atomically with one feature cancellation command so generation
advancement is owned in one place. A cancelled older query must never replace a
newer query, even if its provider or progress callback resumes late.

The semantic feature must not call `indexFiles`, decode an image, or silently make
missing files searchable. The "Index Similarity" button remains an explicit bridge
to the existing application indexing action throughout Phase 5; Phase 6 moves that
action behind the similarity feature API.

### Runtime and SwiftUI wiring

Revise application assembly in this order:

1. create the existing single `SimilarityScoringModel` from the initial Phase 3
   configuration;
2. create one semantic feature with that exact model and no application target;
3. create `RawCullViewModel`, retaining the semantic feature only if compatibility
   forwarding requires it;
4. create the runtime and retain the exact semantic feature on it;
5. bind the feature's weak application target to the view model once;
6. pass the runtime-owned semantic feature from `RawCullApp` to `RawCullMainView`
   and then only to views that present or act on semantic search.

Do not inject the entire runtime into the SwiftUI environment merely to avoid
initializer changes. Explicit initializer dependencies make the migrated boundary
reviewable and prevent unrelated views from discovering model-management or Deep
Review state.

Migrate callers in this order:

1. `SemanticSearchControlsView` and its query-entry child receive the semantic
   feature plus an explicit temporary `onIndexSimilarity` action;
2. `SimilarityGridSelectionView` switches workflow states, progress, readiness, and
   result expansion through the feature;
3. `SharedMainToolbarContent` reads result summary and sends adjustment commands
   through the feature while continuing to use the application view model for
   catalog count, review navigation, ratings, and busy state outside semantic
   search;
4. `CullingGridView` and `ZoomCullingMetadata` consume the RawCull-owned semantic
   result-evidence projection rather than dictionaries on the similarity model;
5. accessibility presentation receives the same deterministic presentation value;
6. remove all semantic-search view traversal through
   `viewModel.similarityModel` after `rg` confirms the migration is complete.

Application filtering may continue to inspect the semantic feature/model through
its private boundary during this phase. Moving general catalog ownership into the
intelligence runtime is explicitly not a goal.

### Implementation sequence and commit boundaries

#### Phase 5A: characterize the vertical slice

1. Add focused tests for the exact application transitions around submit, result,
   show-all, incremental selection, clear, cancel, rating changes, comparison exit,
   and thumbnail reconciliation.
2. Add a suspended-query test proving that a direct cancel followed by a new query
   cannot publish stale progress, results, selected IDs, or catalog order.
3. Record the production caller inventory and make no production changes.

Suggested commit boundary: characterization tests and this plan only.

#### Phase 5B: add the feature and weak application edge

1. Add the stable semantic feature, computed presentation projections, result-
   evidence value, and narrow application-target protocol.
2. Implement the ordered actions above using the existing model methods.
3. Add assembly identity, no-mirrored-state, and weak-edge release tests.
4. Leave all production SwiftUI callers on their current entry points.

Suggested commit boundary: feature boundary and direct unit tests, with no view
migration.

#### Phase 5C: migrate the semantic UI one caller at a time

1. Switch query controls and state views first.
2. Switch result headers, toolbar adjustment, result badges, zoom metadata, and
   accessibility presentation next.
3. Keep indexing as the explicit temporary callback to `indexSimilarity`.
4. After each caller group, run focused tests and use `rg` to prove no new direct
   model traversal was introduced.

Suggested commit boundaries: query/state UI, then toolbar/result metadata.

#### Phase 5D: collapse compatibility forwarding

1. Change `searchSemantically`, `setSemanticSearchShowsAllResults`,
   `adjustSemanticSearchSelection`, `clearSemanticSearch`, and
   `cancelSemanticSearch` into thin feature forwarders while any tests or callers
   still require them.
2. Migrate remaining production callers and tests that are intended to exercise the
   application boundary.
3. Remove each forwarding method only after `rg` reports no caller. Retain direct
   model tests for cached ranking policy.
4. Update smoke manifests, counts, and `RawCullTests/TEST_ARCHITECTURE.md` together
   if test identifiers change.

### Explicitly unchanged

Phase 5 does not change:

- image indexing, artifact hydration, repository ownership, cache schemas, paths,
  or payload validation;
- CLIP model selection, capability validation, Vision fallback, or configuration
  revision handling;
- literal-query handling, default result limit, ranking order, score semantics,
  failure wording, or partial-result policy;
- filename, rating, or sharpness admission policy;
- burst grouping/indexing, Deep Review, culling actions, or persisted review state;
- SwiftUI layout, example queries, labels, accessibility copy, focus restoration,
  or keyboard shortcuts except where initializer wiring is required.

### Automated tests

Add or update focused coverage for:

- semantic feature and runtime share the exact similarity model by identity;
- computed feature presentation changes when the underlying model changes and no
  mirrored observable semantic state exists;
- an empty query clears without calling the semantic provider;
- submit preserves the admitted snapshot and literal query;
- unavailable, empty-index, partial-success, empty-result, provider-failure, and
  successful-result states map to the existing UI presentation;
- show-all and incremental selection never rerun text encoding or scoring;
- rating and filename filters compose with semantic ordering;
- adjustment exits comparison mode, prunes multi-selection, and selects a visible
  thumbnail exactly as before;
- clear and cancel restore catalog order without deleting compatible scoped burst
  analysis;
- cancelled and superseded queries cannot publish late progress or results;
- thumbnail and zoom semantic badges use the same rank and score projection;
- releasing an application harness releases the feature and view model.

Run:

- `RawCullSemanticSearchTests`;
- `RawCullSemanticSearchUITests`;
- `AccessibilityPresentationTests`;
- `ZoomCullingMetadataTests`;
- relevant `CullingGridCoordinatorTests`, comparison, thumbnail-selection, and
  keyboard-navigation tests;
- `RawCullIntelligenceRuntimeTests`;
- `make verify-ai-import-boundary`;
- `make test-smoke`;
- `make test-full`, because orchestration and cancellation entry points move even
  though the underlying ranking task remains in the same model;
- the exact-package Release build, because app and view initializer composition
  changes.

Do not run `make test-performance` if Phase 5 remains within scope. Cached scoring,
indexing, serialization, artifact mapping, and package boundaries are unchanged.

### Manual acceptance

- Launch with DataComp selected, then OpenAI selected, and confirm capability and
  readiness presentation for both downloaded models.
- Search with an empty index, a complete index, a partial index, no results, a
  scoring failure, and a successful result set.
- Submit and immediately cancel, then submit a different query and confirm the old
  query and progress never reappear.
- Expand to all results, collapse to the top 20, and adjust the selected result count
  one image at a time without visible re-indexing or rescoring.
- Change rating and filename filters while results are active and confirm semantic
  order remains primary among admitted files.
- Enter and leave comparison and burst review from a semantic result set; confirm
  selection and review scope match the current result IDs.
- Clear search and confirm ordinary catalog order, thumbnail selection, rating
  filter, compatible burst cache, and review state return unchanged.
- Relaunch and confirm semantic search does not persist transient query/results or
  trigger implicit indexing.

### Exit criteria

- The runtime owns one semantic feature backed by the runtime's exact similarity
  model, and its application edge is weak and narrow.
- Semantic-search SwiftUI views do not traverse
  `RawCullViewModel.similarityModel` and receive neither the full runtime nor a
  provider/repository object.
- No semantic action accepts the entire central view model; application policy is
  invoked only through the narrow target contract.
- Semantic result rank and score presentation has one RawCull-owned projection.
- Query text and UI task lifetime remain local to the query view, while model task
  cancellation and generation advancement occur exactly once through the feature.
- The cached-only contract is mechanically evident: semantic actions cannot reach
  image indexing or source decoding.
- Rating/filter composition, comparison transitions, selection reconciliation,
  burst scope, default result limit, failures, and accessibility output match the
  baseline.
- Focused tests, import boundary, smoke, full TSan suite, and exact-package Release
  build pass.

### Validation evidence (2026-08-29)

- The focused semantic, runtime, accessibility, zoom-metadata, culling-grid,
  comparison-navigation, and keyboard-navigation test selection passed.
- Runtime tests verify that the runtime, view model, and semantic feature share the
  exact `SimilarityScoringModel`, and that the weak application edge does not keep
  the application graph alive.
- Semantic tests cover computed feature projections, whitespace-only clearing,
  show-all without rescoring, cached-only ranking, filtering and ordering,
  cancellation, and superseded-query rejection.
- The production caller audit found no semantic-search view traversal through
  `RawCullViewModel.similarityModel`. The five temporary view-model semantic
  forwarders were removed after their tests migrated to the feature boundary, and
  the feature has no indexing or source-decoding entry point.
- `make verify-ai-import-boundary` passed with the same 5 non-blocking
  `PhotoAIContracts` leakage warnings recorded by earlier phases.
- `make test-smoke` verified exactly 189 unique manifest identifiers; all passed.
- `make test-full` passed with Thread Sanitizer enabled and no reported sanitizer
  failures.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -destination
  'platform=macOS,arch=arm64' -configuration Release
  -onlyUsePackageVersionsFromResolvedFile build` passed.
- `git diff --check` passed.
- `make test-performance` was intentionally not run because Phase 5 did not change
  cached scoring, indexing, serialization, artifact mapping, or a package boundary.
- The manual acceptance matrix was not run and is not inferred from the automated
  results.

### Rollback

Revert Phase 5D forwarding cleanup, switch the migrated views back to their prior
view-model entry points, then remove the semantic feature and weak binding from
runtime assembly. The same `SimilarityScoringModel`, cached artifacts, preferences,
and persisted burst state remain valid; no user-data migration or cleanup is
required.

## Phase 6: place similarity indexing and ranking behind one feature API

Status: implemented on 2026-08-29 after Phase 5 verification. Automated gates
pass; the manual acceptance matrix remains pending. Similarity-owned work and
presentation now sit behind a coherent API without extracting burst orchestration
or redesigning persistence.

### Starting point and ownership audit

`SimilarityScoringModel` already owns most of the correct low-level state:

- the active RawCull-owned similarity and semantic service protocols;
- the injected `SimilarityArtifactStoring` repository;
- image and semantic artifact hydration generations;
- indexing, image-ranking, semantic-ranking, and burst-grouping worker tasks;
- indexing progress/failures, embeddings, distances, anchor identity, backend
  descriptors, and similarity sort state.

The remaining ownership leak is above it:

- `RawCullViewModel` owns `similarityHydrationTask` and
  `semanticSimilarityHydrationTask` for backend changes;
- Phase 3 runtime configuration still calls
  `RawCullViewModel.setSimilarityService` and
  `setSemanticSearchCapability` through the temporary application-target bridge;
- catalog load directly hydrates image and semantic artifacts;
- `indexSimilarity` sequences two hydrations and indexing;
- `findSimilarToSelected` combines feature work with selected-anchor, catalog-
  identity, saliency, and application-sort policy;
- burst preparation and re-indexing call model hydration/indexing directly;
- several views mutate similarity sort state or read backend descriptors,
  embeddings, distances, indexing progress, and ranking cancellation directly.

Start Phase 6 with separate `rg` inventories for production calls to
`hydrateArtifacts`, `hydrateSemanticArtifacts`, `indexFiles`, `rankSimilar`,
`cancelIndexing`, `cancelSimilarityRanking`, `setSimilarityService`, and
`setSemanticSearchCapability`, and for direct view reads of `embeddings`,
`distances`, `anchorFileID`, backend descriptors, indexing progress, and
`sortBySimilarity`.

Classify each caller as configuration, catalog lifecycle, user-initiated indexing,
image-to-image ranking, burst preparation, persistence/migration, or presentation.
Do not treat burst artifact access as Phase 6 UI work: it remains a compatibility
consumer until Phases 7 and 9.

### Similarity feature shape

Introduce one stable, `@MainActor` `RawCullSimilarityFeature`. It is a focused
orchestrator around the existing model, not a replacement observable model.

The feature must:

- own the runtime's exact `SimilarityScoringModel` and expose it only where a
  temporary application compatibility path still requires it;
- receive the artifact repository through production/test assembly and construct,
  or be constructed with, the one model that uses that repository;
- own the top-level hydration tasks and configuration/catalog generations that
  currently live in `RawCullViewModel`;
- delegate indexing and ranking computation to `SimilarityScoringModel`, which
  retains its existing worker tasks and state publication;
- expose focused presentation values and commands so views never need artifacts,
  codecs, providers, or backend descriptor comparison logic;
- share the same model with the Phase 5 semantic feature. Neither feature may copy
  embeddings, progress, capability, or result state.

All similarity-owned task handles must end the phase inside
`RawCullSimilarityFeature` or `SimilarityScoringModel`. The central view model may
await a feature operation as part of application coordination, but it must not own
the worker task, generation token, repository, or provider replacement.

### Typed requests and presentation values

Use immutable RawCull-owned request values at the feature boundary. Exact names may
be refined, but the contracts should cover:

1. **Catalog hydration request** — ordered file snapshot and a catalog identity or
   generation supplied by the application.
2. **Index request** — ordered file snapshot, thumbnail maximum size, and explicit
   `forceRefresh`; the default remains false.
3. **Ranking request** — anchor file ID, ordered catalog snapshot, saliency labels,
   and application catalog identity/generation needed to reject a stale completion.
4. **Configuration replacement** — similarity service plus semantic capability and
   service from the already-revisioned Phase 3 snapshot.

Do not put a provider, artifact codec, store record, view model, binding, or SwiftUI
type in these values. They should be `Equatable`/`Sendable` where their contents
allow it; service existentials remain main-actor confined as in Phase 3.

Expose small presentation projections for:

- backend display kind/name without requiring views to compare descriptor strings;
- index completeness for an explicit file snapshot;
- indexing phase, completed/total counts, estimate, failures, and operation failure;
- whether image similarity sorting is active and which anchor is active;
- per-file similarity evidence expressed as RawCull-owned anchor/distance metadata,
  with CLIP/Vision presentation decided inside the feature;
- cancellation commands for hydration and ranking; indexing cancellation continues
  to propagate through the caller task and model reset paths. Do not retain separate
  availability projections unless a presentation caller needs them.

`SemanticSearchUIPresentation` should consume the same indexing projection rather
than reintroducing direct model reads. Do not create copied progress properties on
the runtime or semantic feature.

### Configuration replacement and hydration ownership

Remove the temporary Phase 3 setter bridge from `RawCullViewModel`. Replace it with
one narrow weak application context used only for application policy that the
similarity feature cannot own. It should provide:

- a synchronous current catalog snapshot and catalog identity while on the main
  actor;
- one command to cancel/reset burst analysis before an image-similarity backend
  identity changes.

The runtime remains the only configuration ingress and keeps its revision/identity
checks. For an accepted changed configuration, preserve this exact order:

1. compare primary and complete ordered artifact backend descriptors;
2. if image similarity changed, ask the application context to cancel/reset stale
   burst analysis;
3. tell the similarity feature to replace the image service, which resets
   incompatible image similarity state through the existing model method;
4. cancel the feature-owned prior image hydration task;
5. snapshot the current catalog and start replacement image hydration;
6. only after the image change has been applied, compare semantic capability and
   backend identity;
7. replace semantic capability/service through the feature, cancel its prior
   semantic hydration task, snapshot the current catalog, and start replacement
   semantic hydration;
8. retain existing model generation, descriptor, and task-cancellation checks
   before either hydration publishes.

An identical newer configuration revision remains a complete no-op. A segmentation-
only change cannot touch similarity tasks. An older revision cannot cancel current
work. Do not merge image and semantic hydration into one task: the configurations
can change independently and currently have separate cancellation/generation
semantics.

After migration, remove `similarityHydrationTask`,
`semanticSimilarityHydrationTask`, `setSimilarityService`, and
`setSemanticSearchCapability` from `RawCullViewModel`, along with the old setter-
shaped application-target protocol. The runtime should call the similarity feature
directly for feature changes and the weak application context only for the two
application-owned inputs above.

### Catalog lifecycle contract

Replace direct model hydration during catalog load with one feature operation while
preserving the current catalog-load sequence:

1. scan and sort files;
2. publish the accepted `files` snapshot for the still-current security-scoped
   catalog;
3. hydrate compatible image artifacts;
4. hydrate compatible semantic artifacts;
5. reject cancellation or a changed catalog identity after each await;
6. publish catalog display candidates, filters, selection, and later thumbnail/
   persisted-culling state exactly as today.

`cancelCatalogLoad` must cancel feature-owned hydration for that catalog without
allowing a late store load to publish. A new catalog, a backend switch during load,
and a catalog close must each invalidate the relevant generations. `reset()` must
retain the existing distinction between image similarity, semantic state, burst
grouping, and user-visible progress; do not broaden a catalog cancellation into
model-download, settings, sharpness, or culling cancellation.

### Indexing contract

The feature's normal index action must preserve the existing sequence:

1. hydrate compatible image artifacts for the requested files;
2. stop if cancelled or superseded;
3. hydrate compatible semantic artifacts for the same accepted snapshot;
4. stop if cancelled or superseded;
5. generate only missing or invalid image artifacts unless `forceRefresh` is true;
6. retain homogeneous-batch behavior for services that require it;
7. validate every returned artifact against source, descriptor, payload, and
   pipeline identity;
8. enter the existing saving phase and commit valid artifacts through the injected
   actor repository;
9. retain successfully committed records when cancellation interrupts later
   writes;
10. merge only accepted artifacts, update semantic coverage when the active CLIP
    backend matches, publish partial failures, and return to idle.

Keep the embedding thumbnail size, pipeline version, source fingerprint behavior,
retry/fallback policy, progress wording, and failure aggregation unchanged. A force
refresh must not delete the last compatible durable record before its replacement
is committed.

Burst preparation and legacy migration may call the feature through temporary
application-only methods that expose current artifacts or import results. Do not
redesign their requests or persistence records here; Phase 7 extracts burst
orchestration and Phase 9 hides remaining artifact implementation types.

### Image-to-image ranking contract

Keep selection and catalog policy in `RawCullViewModel`, but move the feature work
behind one request:

1. the application snapshots the selected anchor, ordered catalog files, saliency
   labels, and catalog identity;
2. the feature ensures the requested snapshot has a complete compatible index,
   indexing missing files when necessary;
3. after indexing, reject cancellation, anchor changes, catalog changes, or backend
   changes before ranking;
4. compute distances with the existing PhotoAIKit service and subject-label
   mismatch penalty;
5. publish anchor/distances/sort state only for the current ranking generation;
6. return a completion identity that lets the application decide whether to call
   `handleSortOrderChange`;
7. cancellation retains the last completed displayed order exactly as today, while
   selecting a different anchor prepares a new ranking without a late old result.

The feature does not select files, mutate rating filters, or reorder
`RawCullViewModel.filteredFiles` directly. The application action that applies a
successful ranking may remain on `RawCullViewModel` because it owns those policies;
the indexing/ranking tasks and their cancellation do not.

### SwiftUI migration

Pass the runtime-owned similarity feature explicitly through `RawCullMainView` to
the views that need it. Do not inject the whole runtime into the environment.

Migrate in this order:

1. `SharpnessControlsView` reads backend name, completeness, indexing, sort, and
   ranking cancellation through the feature. It may keep explicit application
   closures for selected-anchor ranking and catalog re-sort.
2. The Phase 5 semantic views replace their temporary `onIndexSimilarity` bridge
   with the feature's index command and shared indexing presentation.
3. `CullingGridProgressOverlay`, `BurstGroupsHomeView`, and toolbar busy-state checks
   consume focused progress/busy projections.
4. `ZoomCullingMetadata`, thumbnails, sidebar rows, and navigation modifiers consume
   RawCull-owned similarity evidence/sort projections instead of embeddings,
   distances, or backend descriptor strings.
5. Migrate any remaining non-burst view access. Burst-group sensitivity, group
   lookup, group lists, and burst-mode application commands may remain behind
   temporary application projections until Phase 7, but views must not gain new
   artifact access.

When a toggle needs a binding, use a deliberate `Binding` whose setter invokes a
feature/application action. Do not expose broad writable model state simply to make
`$viewModel.similarityModel` compile.

### Runtime assembly

Revise `RawCullApplicationState.make` in one atomic composition change:

1. create integration, model-management, settings, and the initial configuration as
   in Phase 4;
2. create one similarity feature with the initial similarity/semantic configuration
   and the injected artifact repository;
3. obtain its exact `SimilarityScoringModel` state owner;
4. create or rebind the Phase 5 semantic feature to that same exact model;
5. create `RawCullViewModel` and the runtime with those stable references;
6. bind the weak semantic application target and similarity application context;
7. bind settings configuration once and synchronously publish the initial snapshot;
8. assert identity among runtime, similarity feature, semantic feature, and any
   temporary view-model compatibility references.

Initial assembly must still perform no validation, hydration, indexing, or ranking.
The scene refresh and catalog lifecycle remain the first triggers for those
operations.

### Implementation sequence and commit boundaries

#### Phase 6A: characterize task and persistence behavior

1. Add deterministic suspension points for image hydration, semantic hydration,
   indexing generation, persistence commit, and ranking.
2. Characterize backend switch during each operation, catalog replacement, force
   refresh, partial failure, whole-batch fallback, and cancellation after partial
   commit.
3. Add view-level characterization for similarity toggle, anchor change, progress,
   and metadata evidence.
4. Make no production changes.

Suggested commit boundary: characterization tests and the final caller inventory.

#### Phase 6B: introduce the feature API without moving callers

1. Add request/completion/presentation values and the stable similarity feature.
2. Route its operations to the existing model and repository behavior.
3. Add identity and direct feature tests, including shared identity with the
   semantic feature.
4. Keep current view-model methods and runtime setter bridge in place.

Suggested commit boundary: new feature boundary plus tests only.

#### Phase 6C: move configuration and hydration task ownership

1. Move the two hydration task handles and their cancellation into the feature.
2. Switch runtime configuration application from view-model setters to direct
   feature replacement in the required similarity-then-semantic order.
3. Replace the old application-target protocol with the narrow catalog/burst
   context.
4. Switch catalog load and cancellation to the feature hydration API.
5. Remove obsolete view-model task handles and setters only after focused runtime,
   catalog, and stale-hydration tests pass.

Suggested commit boundary: task-ownership transfer and Phase 3 bridge removal.

#### Phase 6D: migrate indexing, ranking, and views

1. Convert `indexSimilarity` to a temporary feature forwarder, then move each UI and
   application caller to the typed feature action.
2. Keep the application-owned selected-anchor validation and filter refresh around
   the typed ranking request; remove only the worker implementation from the view
   model.
3. Migrate progress, backend, completeness, sort, cancellation, and metadata reads
   in the order listed above.
4. Convert burst-preparation direct calls to temporary feature entry points without
   changing burst sequencing or data structures.

Suggested commit boundaries: indexing callers, ranking controls, then presentation
and metadata.

#### Phase 6E: audit, remove shims, and validate

1. Use `rg` to prove there are no production calls to the removed view-model
   hydration/service setters and no non-approved view access to artifact/provider
   state.
2. Remove thin compatibility forwarding only when no caller remains. Retain any
   explicitly documented burst compatibility surface for Phases 7/9.
3. Update the import-boundary policy if a new feature/composition file needs an
   approved backend-contract import; do not widen concrete backend allowances.
4. Update test manifests/counts and architecture documentation with any identifier
   changes.
5. Run all correctness, TSan, performance, and Release gates and record results in
   this phase.

### Explicitly unchanged

Phase 6 does not change:

- selected model defaults, preference keys, model resources, licence state, or
  provider validation;
- Vision fallback, CLIP retry/reload/partial-success policy, descriptor identity,
  artifact schema, pipeline signature, source fingerprints, cache paths, or atomic
  commit behavior;
- similarity distance semantics, subject-mismatch penalty, tie-breaking, default
  semantic limit, or UI copy;
- catalog rating/filename/sharpness filters, selection, navigation, comparison,
  culling, or security-scoped access policy;
- burst grouping/ranking/cache orchestration, Deep Review, or persisted review
  state;
- physical file layout or Swift package boundaries.

### Automated tests

Add or update focused coverage for:

- runtime, similarity feature, semantic feature, and view model share the expected
  exact model/feature identities and release without cycles;
- initial assembly starts no validation, hydration, indexing, or ranking;
- identical or stale configuration does not cancel or restart feature work;
- a similarity backend change resets burst state before replacement and hydrates
  only the accepted catalog/backend;
- a semantic-only change leaves image similarity/index/ranking state intact and
  cannot publish an older semantic backend;
- catalog close/switch and backend switch during suspended hydration reject late
  publication;
- compatible artifacts hydrate, corrupt/incompatible artifacts are removed or
  excluded exactly as before, and DataComp/OpenAI/Vision never cross-load;
- normal indexing reuses current artifacts, indexes only misses, preserves partial
  success, and updates semantic coverage for a matching CLIP backend;
- homogeneous-batch fallback and `forceRefresh` keep their existing request scope;
- cancellation during generation or saving retains only valid completed commits and
  leaves progress/task state idle;
- ranking rejects a changed anchor, catalog, generation, or backend; cancellation
  retains the last completed display order;
- similarity presentation and metadata never require direct artifact/provider
  access from a view;
- burst cache signatures and payload bytes remain unchanged;
- benchmark results remain within the checked-in expectations.

Run:

- new focused `RawCullSimilarityFeatureTests`;
- `RawCullIntelligenceRuntimeTests`;
- `PhotoAIKitSimilarityMigrationTests`;
- `PerFileAnalysisArtifactStoreTests`;
- `TypedAIPersistenceMatrixTests`;
- `RawCullSemanticSearchTests` and `RawCullSemanticSearchUITests`;
- relevant similarity, cancellation, catalog, zoom-metadata, thumbnail-navigation,
  and burst cases in `CullingModelTests`, `CullingGridCoordinatorTests`, and the
  existing culling suites;
- `AICacheBoundaryTests`;
- `make verify-ai-import-boundary`;
- `make test-smoke`;
- `make test-full`, because task ownership, configuration application, and
  observable caller wiring change;
- `make test-performance`, because indexing/ranking orchestration and repository
  access move behind a new boundary;
- the exact-package Release build, because app composition and production source
  membership change.

### Manual acceptance

- With DataComp selected, open an unindexed and partially indexed catalog, index,
  cancel during generation and saving, resume, and verify durable partial reuse.
- Repeat the same qualification with OpenAI CLIP, then switch between the two before,
  during, and after hydration/indexing; an old backend must never reappear.
- Disable CLIP similarity and verify Vision fallback indexing/ranking, then re-enable
  the selected CLIP model without cross-loading artifacts.
- Force re-index and confirm the existing index remains usable until accepted
  replacements are committed.
- Select an anchor, rank by similarity, change the anchor during work, cancel, and
  verify only the current completed order is displayed.
- Confirm similarity progress, backend labels, failure presentation, thumbnail and
  zoom metadata, keyboard navigation, and toolbar busy state match the baseline.
- Run semantic search after partial and complete indexing and confirm only compatible
  cached CLIP artifacts are searched; no semantic action starts image indexing.
- Run, cancel, restore, and regroup burst analysis to confirm the Phase 6 forwarding
  boundary did not change burst cache hits, progress, rankings, or review state.
- Clear each AI cache independently, relaunch, and verify preferences, licences,
  ratings, and unrelated caches remain intact.

### Exit criteria

- A caller can hydrate, index, rank, or cancel through one focused similarity API
  without knowing a provider, artifact codec, repository record, or store path.
- The runtime applies configuration directly to the similarity feature; the Phase 3
  view-model setter bridge is gone.
- `RawCullViewModel` has no similarity or semantic hydration task handles and owns
  no indexing/ranking worker task or generation token.
- `SimilarityScoringModel` remains the single observable state owner shared with the
  semantic feature; no runtime or view model mirrors its state.
- Catalog admission, selected-anchor validation, general filtering, selection, and
  navigation remain application responsibilities.
- Non-burst views consume focused presentation/actions and do not read embeddings,
  distances, providers, repositories, or backend descriptor strings directly.
- Any remaining burst artifact compatibility access is documented for Phases 7/9
  and has not leaked into SwiftUI.
- Backend compatibility, partial indexing, force refresh, atomic cache commit,
  cancellation, stale-result rejection, and cache bytes/paths match the baseline.
- Focused tests, import boundary, smoke, full TSan, performance, and exact-package
  Release gates pass, followed by the Phase 6 manual acceptance matrix.

### Validation evidence (2026-08-29)

- Added the stable `@MainActor` `RawCullSimilarityFeature`, typed catalog/index/
  ranking requests, completion identity, backend/indexing/evidence projections,
  and feature-owned top-level hydration and configuration generations.
- Production assembly now shares one exact `SimilarityScoringModel` and similarity
  feature across the runtime, view model, and semantic feature. The Phase 3
  view-model setter bridge and its two hydration task handles are removed.
- Catalog hydration, normal indexing, image-to-image ranking, configuration
  replacement, cancellation, and non-burst SwiftUI presentation use the feature
  boundary. Burst persistence/grouping retains only the explicitly deferred
  compatibility access for Phases 7 and 9.
- The Phase 5 semantic view-model forwarders and unused Phase 6 presentation/
  cancellation projections were removed after the final caller audit. Shared busy
  presentation is consumed through `RawCullSimilarityFeature.isBusy`.
- Post-cleanup validation on 2026-08-29 passed Periphery with no unused code,
  import-boundary verification, the 193-test smoke manifest, the full Thread
  Sanitizer suite, the two-test performance manifest, and the exact-package arm64
  Release build. The performance rerun indexed 12 benchmark images in 0.099
  seconds and computed 500 distances in 0.022 seconds; the existing non-failing
  LMDB map-size warnings remained.
- `RawCullSimilarityFeatureTests` covers shared identity, focused presentation,
  backend-reset ordering, and stale catalog rejection. The smoke manifest baseline
  is 193 tests.
- `make verify-ai-import-boundary` passed with the same five documented,
  non-blocking `PhotoAIContracts` leakage warnings.
- `make test-smoke`, `make test-full` with Thread Sanitizer, and
  `make test-performance` passed. The performance run indexed 12 benchmark images
  in 0.068 seconds and computed 500 distances in 0.019 seconds; it also emitted
  non-failing LMDB map-size warnings.
- The exact-package Debug and Release builds passed with
  `-onlyUsePackageVersionsFromResolvedFile`; `git diff --check` also passed.
- The manual acceptance matrix above has not yet been run and remains the final
  Phase 6 acceptance item.

### Rollback

Revert Phase 6E shim removal, switch views and callers back to the compatibility
entry points, restore the two view-model hydration handles and Phase 3 setter bridge,
then remove the feature wrapper and typed requests. Because service descriptors,
artifact schemas, pipeline signatures, cache paths, and encoded payloads never
change, existing artifacts and burst caches require no migration or deletion.

## Phase 7: extract the burst-analysis pipeline in small subphases

This is the highest-risk part and must not be done in one commit.

### Phase 7A: introduce pure request and result values

Status: implemented on 2026-08-29. The existing view-model orchestration now
accepts one immutable, `Sendable` request snapshot and publishes one immutable,
`Sendable` pipeline result; no worker, cache, or persistence ownership moved.

- Capture catalog identity, ordered files, sharpness signature, similarity
  signature, generation, and relevant configuration in an immutable request.
- Return a typed result containing groups, rankings, review-state restoration,
  cache outcome, and diagnostics.
- Keep the existing `RawCullViewModel+BurstGrouping` implementation and adapt its
  inputs/outputs to these values.
- Do not move any work yet.

Gate: focused burst tests, smoke tests, and equality tests proving old and new input
snapshots match.

Validation evidence (2026-08-29): `BurstAnalysisPipelineValuesTests` verifies exact
equality with the prior catalog/files/signature/generation/configuration reads,
snapshot immutability, result equality, and compile-time sendability. The focused
`RawCullViewModelCullingTests` suite and Debug build pass. The smoke manifest now
enumerates 196 unique tests and includes the three Phase 7A tests. Smoke execution
reaches an unrelated existing `ReleaseMetadataTests` failure because the checked-in
README package-pin table and its expected 21-pin count do not match the checked-in
18-pin `Package.resolved`; the failing metadata test passes in isolation, while the
Phase 7A and burst tests pass consistently.

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
