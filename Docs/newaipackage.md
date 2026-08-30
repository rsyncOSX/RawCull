# Evaluation and plan for a RawCull AI package

Date: 2026-08-30  
Scope: architecture evaluation only; no source, target-membership, dependency, or
runtime changes are authorized by this document.

## Executive decision

Do **not** extract the complete `RawCull/Intelligence` directory into a Swift
package in its current state.

The completed modular-AI phases prove that RawCull now has a coherent intelligence
boundary. They do not yet prove that the complete boundary is an application-neutral
module. The package conditions in Phase 11 are only partly satisfied:

- SwiftUI and concrete provider construction have been removed from views and the
  general application model.
- Similarity, semantic search, burst analysis, and Deep Review now have focused
  owners, narrow application callbacks, explicit cancellation, and tested stale-
  result protection.
- The source import verifier already provides exact mechanical enforcement inside
  the application target.
- However, Phase 9 was deliberately deferred. Persistence APIs still expose
  PhotoAIKit artifacts and several repositories still choose live RawCull paths.
- Nine candidate files refer to the application-only `FileItem` typealias rather
  than spelling the `RawCullCore.RawCullFileItem` contract at the module boundary.
- `RawCullIntelligenceRuntime.swift` also contains `RawCullApplicationState`, which
  constructs the complete `RawCullViewModel`.
- Model-management files still own `Bundle.main`, `UserDefaults.standard`, default
  filesystem discovery, licence resources, production manifest policy, and
  `BackgroundAssets` integration.
- There is currently one executable consumer. No demonstrated second client needs
  the RawCull-specific orchestration.

The recommended decision is therefore:

1. Keep the current boundary app-local now.
2. Finish the package prerequisites as behavior-preserving, independently useful
   work, especially Phase 9.
3. Re-evaluate a **scoped** package containing reusable intelligence contracts,
   features, persistence, and PhotoAIKit adapters. Keep app composition, settings
   policy, model downloads, app resources, and `RawCullViewModel` wiring in RawCull.
4. Create the package only when every mandatory gate in this document is met and a
   concrete benefit—preferably a second consumer, independently testable build
   boundary, or materially faster focused build/test loop—is demonstrated.

This is not a rejection of packaging forever. It is a rejection of moving files
before their public contract is ready.

## Evidence from the completed phases

The package decision is based on the repository after Phases 0–8, 10, 11, and 12.
Phase 9 remains deferred.

| Evidence | Effect on the decision |
|---|---|
| One `RawCullIntelligenceRuntime` is retained at the app root. | Proves stable ownership, but the runtime source file still includes app assembly. |
| `RawCullSimilarityFeature`, `RawCullSemanticSearchFeature`, `BurstAnalysisCoordinator`, and `DeepAIReviewController` own focused behavior. | Strong evidence that a package-sized core can exist. |
| Views no longer import restricted PhotoAIKit products or traverse the low-level similarity model. | Satisfies the UI-independence condition. |
| Application callbacks are narrow, weak, and feature-specific. | Avoids a hard dependency on the complete view model in the feature implementations. |
| `RawCullViewModel` no longer constructs providers or owns feature worker tasks. | Removes the largest original obstacle. |
| Exact import allowlists and compatibility scans pass. | Compile-target separation would improve enforcement, but it would not be the first enforcement mechanism. |
| Smoke, full Thread Sanitizer, performance, Debug, and Release gates passed at Phase 12. | Provides a trustworthy behavioral baseline for a future move. |
| Phase 9 is deferred. | Blocks clean public persistence and artifact contracts. |
| Manual acceptance still lacks a versioned catalog and licensed model resources. | Makes a large target move harder to qualify interactively; automated evidence is good but incomplete. |

## Phase 11 criteria assessment

| Phase 11 condition | Current result | Evidence and required action |
|---|---|---|
| Inputs and outputs are independent of SwiftUI views. | **Met** | No file under `RawCull/Intelligence` imports SwiftUI. `Observation` is acceptable in a non-UI feature module. |
| Package code does not need the complete `RawCullViewModel`. | **Partly met** | Feature code uses narrow protocols, but `RawCullApplicationState` in `RawCullIntelligenceRuntime.swift` constructs and exposes `RawCullViewModel`. Split app assembly from the reusable runtime. |
| File and catalog types come from `RawCullCore` or package-owned contracts. | **Partly met** | The underlying type is `RawCullCore.RawCullFileItem`, but package candidates refer to the app-local `FileItem` alias. Public contracts must use `RawCullFileItem` explicitly. |
| Persistence paths and application policy are injected. | **Not met** | Both persistence actors contain default live-directory selection. Model management also owns live paths, bundle and manifest policy, and defaults. Complete Phase 9 and require explicit production construction. |
| App-only resources and Background Assets wiring stay in the app. | **Not met by a wholesale move** | `RawCullAIModelDownloadService.swift` imports `BackgroundAssets`; licence/catalog/model-management code uses app-bundle resources. Those files must remain app-local or be split into pure contracts plus app adapters. |
| The move creates compile-time enforcement rather than circular adapters. | **Potentially met for a scoped core** | Core features can point to `RawCullCore` and injected services. Moving the complete directory now would require app adapter cycles around runtime, settings, paths, and resources. |
| Reuse or independent release/build value is demonstrated. | **Not met** | RawCull is the only known consumer, and PhotoAIKit already owns reusable backend capability. Measure or demonstrate a second need before accepting API and maintenance cost. |

## Motivation for creating a package

A package becomes worthwhile when it buys more than a different folder layout.
For RawCull, the meaningful benefits would be:

- **Compiler-enforced dependency direction.** App and view-model sources could only
  use the package's public API. Package internals and PhotoAIKit artifacts would be
  inaccessible without an explicit API change.
- **A deliberately small public surface.** Access control would force decisions
  about which requests, results, feature actions, and repositories are stable
  RawCull contracts.
- **Independent testing.** Similarity, semantic ranking, burst orchestration,
  cancellation, migration, and Deep Review could build and test without compiling
  the entire application UI.
- **Safer backend replacement.** PhotoAIKit and concrete Core AI/Vision providers
  could remain behind an adapter target, while the app imports package-owned values
  and actions.
- **Potential reuse.** A command-line index verifier, migration utility, benchmark
  executable, extension, or future RawCull client could share orchestration without
  importing the app target.
- **Clearer ownership for persistence compatibility.** Package tests could make
  schema, backend-descriptor, corruption-isolation, and migration promises explicit.

The strongest motivation is not “AI code belongs in a package.” It is that a second
consumer or an independent verification tool needs the same stable orchestration
and storage behavior.

## Motivation for not creating a package now

Keeping the boundary app-local currently has real advantages:

- The existing directory layout and import verifier already communicate and enforce
  ownership without publishing an API.
- Internal types can evolve with RawCull without source-compatibility obligations.
- The app can use `RawCullFileItem`, settings policy, bundle resources, download
  coordination, and cache locations directly without adapter duplication.
- There is one dependency resolver and one application target graph to diagnose.
- Refactoring does not need simultaneous edits to `Package.swift`, package access
  levels, Xcode linkage, test target imports, and application assembly.
- PhotoAIKit already provides the reusable AI contracts, workflows, storage, and
  concrete backends. Duplicating that role in `RawCullIntelligence` would create an
  unclear layer rather than a useful boundary.
- The manual qualification matrix is not currently reproducible in this workspace.
  That increases the risk of a broad physical extraction whose value is primarily
  structural.

## Benefits and disadvantages

| Area | New package benefit | New package disadvantage |
|---|---|---|
| Dependency control | The compiler prevents app code from reaching internal AI implementation. | A poorly designed public API merely moves leakage into exported types. |
| Build/test workflow | Focused package tests can be faster and independent. | Xcode and SwiftPM integration adds another target graph and can increase clean-build work. |
| Reuse | Enables tools or additional clients. | No current second consumer exists; speculative reuse can distort the API. |
| Access control | Forces a small, reviewed public surface. | Public declarations, documentation, compatibility, and deprecation become ongoing work. |
| PhotoAIKit isolation | The app can depend on one RawCull adapter rather than seven PhotoAIKit products. | The local package must still resolve and maintain those products; complexity has moved, not disappeared. |
| Persistence | Can centralize schema compatibility and migration tests. | Phase 9 must first hide artifacts and inject locations; otherwise storage details become public API. |
| Concurrency | Module boundaries encourage explicit `Sendable` values and actor ownership. | Cross-module actor annotations become API, so mistakes are harder to change. |
| Resources | Package resources can be versioned when truly reusable. | RawCull licence text, manifests, Background Assets, and app policy do not belong in a reusable core. |
| Delivery | Independent semantic versions are possible if ever needed. | A repository-local package does not need independent versioning, while a remote package adds release coordination. |

## PhotoAIKit decision

PhotoAIKit should be a **dependency of the future package**, not source code copied,
moved, vendored, or merged into it.

Recommended ownership:

```text
RawCull app
  -> RawCullIntelligence public API
  -> RawCullIntelligencePhotoAIKit adapter
  -> PhotoAIContracts / PhotoAIWorkflows / PhotoAIStorage
  -> CoreAICLIPBackend / CoreAISAM3Backend /
     CoreAIEfficientSAMBackend / VisionFeaturePrintBackend
```

Reasons to depend on PhotoAIKit:

- It already owns provider-neutral artifacts, backend descriptors, workflows,
  storage primitives, model validation, CLIP, segmentation, and Vision fallback.
- RawCull-specific orchestration is a consumer of those facilities, not their new
  owner.
- Keeping the dependency explicit preserves independent PhotoAIKit evolution and
  prevents code forks.
- A focused adapter can translate PhotoAIKit values into package-owned public
  values, keeping PhotoAIKit out of the app-facing API.

Reasons not to absorb PhotoAIKit:

- It would duplicate or fork a reusable package that already has a clear purpose.
- It would make RawCull responsible for upstream provider and storage releases.
- It would blur the distinction between reusable AI infrastructure and RawCull
  product policy.
- It would expose far more implementation than RawCull callers require.

The final RawCull application target should ideally link the two local-package
products, not each concrete PhotoAIKit backend product. The package manifest would
declare the PhotoAIKit products it needs. Test targets may depend directly on
PhotoAIKit only when testing persistence compatibility or adapter behavior.

Do not use `@_exported import PhotoAIContracts`. Do not expose a public property,
associated value, parameter, or return type from PhotoAIKit. Translation belongs at
the adapter or repository edge.

## Proposed package shape

Create a repository-local package first:

```text
Packages/RawCullIntelligence/
  Package.swift
  Sources/
    RawCullIntelligence/
      Contracts/
      Similarity/
      SemanticSearch/
      BurstAnalysis/
      DeepReview/
      Persistence/
      Presentation/
      Runtime/
    RawCullIntelligencePhotoAIKit/
      Backends/
      Composition/
      Mapping/
  Tests/
    RawCullIntelligenceTests/
    RawCullIntelligencePhotoAIKitTests/
```

Use two library products:

1. `RawCullIntelligence` — the app-facing contracts, focused observable features,
   package-owned service protocols, orchestration, and repositories.
2. `RawCullIntelligencePhotoAIKit` — live implementations and factories backed by
   PhotoAIKit. Its public surface should be one configuration/factory boundary, not
   provider objects.

The core target should depend on `RawCullCore` and, only where implementation
requires it, `PhotoAnalysisKit`. The adapter target should own the PhotoAIKit
product dependencies. If removing `PhotoAIContracts` from the core implementation
would require wasteful artifact copying, it may remain an internal dependency, but
no PhotoAIKit type may appear in the public API.

Use Swift 6 and explicitly configure concurrency rather than relying on the app
target's settings. Match the verified application behavior:

- Swift language mode 6.
- Complete strict-concurrency checking in package tests and CI.
- `@MainActor` only on observable presentation/orchestration objects that are truly
  UI-owned.
- Immutable `Sendable` request/result values across worker boundaries.
- Actors for mutable persistence.
- No `@unchecked Sendable`, `@preconcurrency`, or `nonisolated(unsafe)` merely to
  make the extraction compile.

Do not publish this as a separate remote repository or assign an independent
version until another repository needs it. A local package gives the compiler
boundary without premature release management.

## Public API the package should expose

The following is the intended capability surface, not a requirement to preserve
every current type name. Only declarations needed by RawCull or a demonstrated
second client should be `public`; everything else should remain `internal` or
`package`.

### 1. Package-owned values

Expose immutable, `Equatable` and `Sendable` values where applicable:

- `RawCullCLIPModel` and `RawCullSegmentationModel`.
- `RawCullAICapabilityStatus`, `RawCullSemanticSearchCapabilityStatus`, and a
  package-owned backend presentation/identity that does not contain
  `SimilarityBackendDescriptor`.
- `RawCullAICapabilities`.
- `RawCullIntelligencePaths`, initialized with explicit application-support,
  cache, model, licence, and artifact roots. Do not expose a `.live()` lookup from
  the package API.
- `RawCullSimilarityCatalogIdentity`, `RawCullSimilarityCatalogSnapshot`,
  `RawCullSimilarityCatalogHydrationRequest`, `RawCullSimilarityIndexRequest`, and
  `RawCullSimilarityRankingRequest`, using `RawCullFileItem` explicitly.
- `RawCullSimilarityBackendPresentation`,
  `RawCullSimilarityIndexingPresentation`, and `RawCullSimilarityEvidence`.
- `RawCullSemanticSearchState`, `RawCullSemanticSearchProgress`,
  `RawCullSemanticSearchResultSummary`, `RawCullSemanticResultEvidence`, and
  `SemanticSearchUIPresentation` despite its current name; it is a Foundation value,
  not a SwiftUI type. Consider renaming only in a separate compatibility commit.
- Burst request/result, progress, diagnostic, group-signature, review-summary, and
  cache-outcome values required by application culling.
- Deep Review request, result, preset, confidence, reason, issue, capability, and
  presentation values.

Do not expose raw embedding payloads, PhotoAIKit artifacts, codecs, provider
instances, disk records, task handles, generation counters, or mutable dictionaries.

### 2. Application context protocols

Expose only the narrow main-actor protocols needed for application policy:

```swift
@MainActor
public protocol RawCullSimilarityApplicationContext: AnyObject { ... }

@MainActor
public protocol RawCullSemanticSearchApplicationContext: AnyObject { ... }

@MainActor
public protocol DeepAIReviewApplicationContext: AnyObject { ... }
```

Their requirements should use package/RawCullCore values. They must not mention
`RawCullViewModel`, SwiftUI, bindings, navigation types, settings models, or
PhotoAIKit. Implementations remain on `RawCullViewModel` in the app target and are
held weakly by feature objects.

### 3. Focused feature objects

Expose these `@MainActor` stable-reference objects with read-only state and commands:

- `RawCullSimilarityFeature`
  - backend and indexing presentation;
  - index completeness and per-file similarity evidence;
  - catalog hydration, explicit indexing, ranking, cancellation, and reset;
  - burst-facing hydration/indexing only if the burst coordinator cannot own those
    operations directly.
- `RawCullSemanticSearchFeature`
  - presentation, progress, result summary, ordered/selected IDs, and per-file
    evidence;
  - `search`, show-all/result-count adjustment, `clear`, and `cancel`;
  - no implicit indexing entry point.
- `BurstAnalysisCoordinator`
  - run/cancel/progress and explicit cache operations expressed through package
    requests and results;
  - no rating, navigation, selection, or comparison policy.
- `DeepAIReviewController`
  - capability/presentation, preset, result lookup, start/cancel/reset;
  - recommendation application remains an app action after signature validation.

The low-level `SimilarityScoringModel` should not be public. It is shared internally
by the similarity and semantic features and tested through package tests or
`@testable import`.

### 4. Dependency construction

Expose an initializer/factory boundary suitable for production and tests:

```swift
public struct RawCullIntelligenceDependencies: Sendable { ... }

@MainActor
public struct RawCullIntelligenceFactory {
    public static func make(
        configuration: RawCullIntelligenceConfiguration,
        dependencies: RawCullIntelligenceDependencies
    ) -> RawCullIntelligenceRuntime
}
```

The package-owned configuration should contain explicit paths, selected model
identities, model locations, artifact/cache repositories, and policy constants. A
test can provide in-memory services. The PhotoAIKit adapter product can expose a
`RawCullPhotoAIKitDependenciesFactory` that creates the live dependencies without
returning concrete providers.

`RawCullIntelligenceRuntime` should expose only the stable similarity, semantic,
burst, and Deep Review feature roots. It must not expose `RawCullAIIntegration`,
`SimilarityScoringModel`, provider objects, settings models, model-download
coordinators, or `RawCullViewModel`.

### 5. Persistence API

Expose repository protocols, not actors or codecs:

- similarity artifact load/upsert/remove operations expressed through package-
  owned source identity and compatibility summaries;
- burst cache load/save/delete/migration operations expressed through package
  snapshots and results;
- cache-usage and purge summaries for settings presentation.

Live actor implementations can be public only as factory-created opaque
dependencies. Their directory URLs must be required initializer arguments. Preserve
the existing bytes, schema numbers, file names, corrupt-record isolation, partial
writes, and legacy migrations.

### 6. API that must remain app-local

Do not expose or move:

- `RawCullApplicationState` or any factory that constructs `RawCullViewModel`;
- `RawCullAISettingsModel` and preference-key policy;
- model-download UI state and Background Assets coordination;
- production/staging manifest selection;
- app licence resource lookup and acceptance presentation;
- `Bundle.main`, `UserDefaults.standard`, or automatic RawCull directory discovery;
- SwiftUI views, bindings, sheets, toolbar state, navigation, ratings, or culling
  commands;
- security-scoped catalog lifetime and application termination behavior.

## Source-file disposition

The following table is specific to the current RawCull sources. “Move” means move
history into the local package only after the stated prerequisite; it does not
authorize a move now.

| Current source | Proposed disposition | Required preparation |
|---|---|---|
| `RawCull/Intelligence/Contracts/RawCullAIModels.swift` | **Split and move core contracts** | Replace PhotoAI descriptors in public values; move `.live()` filesystem lookup to app assembly; require explicit roots. |
| `RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift` | **Move to PhotoAIKit adapter target** | Keep providers/artifacts internal and map failures/progress to package values. |
| `RawCull/Intelligence/Similarity/SimilarityScoringModel.swift` | **Move to core as internal** | Replace `FileItem` with `RawCullFileItem`; hide PhotoAI artifact state and low-level model from public API. |
| `RawCull/Intelligence/Similarity/RawCullSimilarityFeature.swift` | **Move to core and expose narrowly** | Replace `FileItem`; use package backend identity; keep application context weak. |
| `RawCull/Intelligence/SemanticSearch/RawCullSemanticSearchService.swift` | **Move; implementation internal** | Map PhotoAI embeddings/descriptors at the adapter edge; expose only package result values. |
| `RawCull/Intelligence/SemanticSearch/RawCullSemanticSearchFeature.swift` | **Move to core and expose narrowly** | Replace `FileItem`; rename the application-target protocol consistently if desired in a separate commit. |
| `RawCull/Intelligence/Presentation/SemanticSearchUIPresentation.swift` | **Move to core** | Remove PhotoAI descriptor dependency from public cases; no SwiftUI dependency exists. |
| `RawCull/Intelligence/BurstAnalysis/BurstAnalysisModels.swift` | **Split and move reusable contracts** | Replace `FileItem`; keep app-only completed context, full-reindex UI request, progress copy, and undo entry app-local if only views/culling use them. |
| `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCacheRepository.swift` | **Move after Phase 9** | Remove `FileItem` from repository boundary and require an injected live repository. |
| `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator.swift` | **Move to core** | Replace `FileItem`; replace PhotoAI types in any public callback; keep callbacks package-owned and `Sendable` where they cross isolation. |
| `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator+Lifecycle.swift` | **Move with coordinator** | Keep lifecycle methods internal. |
| `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator+CacheCompatibility.swift` | **Move with coordinator** | Replace `FileItem`; preserve exact migration/remapping behavior. |
| `RawCull/Intelligence/BurstAnalysis/BurstReviewQueueModels.swift` | **Move only if reused by non-view orchestration** | It is product presentation policy. Otherwise keep in app presentation despite its current folder. |
| `RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift` | **Move; implementation mostly internal** | Keep PhotoAI workflows internal; expose package request/result/presentation values only. |
| `RawCull/Intelligence/DeepReview/SubjectMaskFocusScorer.swift` | **Move to core implementation** | Keep PhotoAnalysisKit behind package implementation; verify performance unchanged. |
| `RawCull/Intelligence/DeepReview/DeepAIReviewController.swift` | **Move to core and expose narrowly** | Replace `FileItem`; preserve weak application context and group-signature validation boundary. |
| `RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift` | **Move after Phase 9 as internal actor** | Require explicit directory; hide `PhotoAIStorage` records/codecs; preserve on-disk encoding. |
| `RawCull/Intelligence/Persistence/BurstAnalysisCache.swift` | **Move after Phase 9 as internal actor** | Require explicit directory; replace `FileItem`; hide PhotoAI artifact schema and preserve bytes/migrations. |
| `RawCull/Intelligence/Composition/RawCullAIIntegration.swift` | **Split** | Move provider/resource construction to `RawCullIntelligencePhotoAIKit`; keep app bundle/resource/path policy in RawCull assembly. |
| `RawCull/Intelligence/Composition/RawCullIntelligenceRuntime.swift` | **Split** | Move a provider-neutral runtime to core. Move `RawCullApplicationState`, `.live()`, and `RawCullViewModel` construction to a new app-local composition file. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelResourceManager.swift` | **Move to PhotoAIKit adapter only if useful independently** | Require candidate URLs and bundle/resource policy from the app; do not expose provider generic types. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift` | **Keep app-local initially** | It contains RawCull product catalogue, version, licence, and source policy. Pure checksum/value helpers may move later. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift` | **Keep app-local** | It owns Background Assets, production endpoints, installation, and host security policy. Extract only a tiny package-owned protocol if the core needs status. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelLicenceAcceptance.swift` | **Keep app-local** | Licence resources and acceptance storage are RawCull product concerns. Inject resulting authorization/model locations into the adapter. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelManagementModel.swift` | **Keep app-local** | It is settings/download presentation and uses app bundle/version behavior. |
| `RawCull/Intelligence/ModelManagement/RawCullAISettingsModel.swift` | **Keep app-local** | It owns preference keys, `UserDefaults`, settings presentation, and application configuration policy. |

The following non-intelligence files must remain in the RawCull application target
but will be changed to consume package API during an eventual extraction:

- `RawCull/Main/RawCullFileItem.swift` — retain aliases for the app, but never make
  package sources rely on them.
- `RawCull/Main/RawCullApp.swift` — retain stable SwiftUI ownership.
- `RawCull/Model/ViewModels/RawCullViewModel.swift` — implement only narrow package
  context protocols.
- `RawCull/Model/ViewModels/RawCullViewModel+Similarity.swift` — retain catalog,
  rating, selection, and navigation policy adapters.
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift` — retain rating,
  winner override, comparison, undo, recommendation application, and culling policy.
- `RawCull/Views/**` — consume public presentation values and actions only.
- `RawCullModelDownloader/RawCullModelDownloader.swift` — remain an app/extension
  integration target; it must not depend on the package core unless a small,
  extension-safe value contract is demonstrated.

## Mandatory prerequisites before creating `Package.swift`

All of these must be complete:

1. **Complete Phase 9.** No view, view model, or public repository protocol exposes
   `PhotoAIStorage`, codecs, persisted records, or `SimilarityArtifact` payloads.
2. **Remove app aliases from candidate sources.** Every package-facing file uses
   `RawCullCore.RawCullFileItem` or a genuinely package-owned value.
3. **Split runtime and application composition.** Package code cannot name or
   construct `RawCullViewModel`.
4. **Inject every path.** No package live repository uses
   `FileManager.default.urls(...)` to select a RawCull location.
5. **Inject every resource concern.** No package core reads `Bundle.main`, app
   version metadata, licence resources, or production manifest choice.
6. **Keep Background Assets in the app.** The core package must build and test
   without importing `BackgroundAssets`.
7. **Define package-owned backend identity.** Public API must not contain
   PhotoAIKit descriptors, artifacts, providers, stores, or workflow types.
8. **Record a consumer and metric.** Identify a second executable/tool or record a
   measurable build/test/enforcement improvement that justifies the boundary.
9. **Make manual qualification reproducible or explicitly accept the limitation.**
   Prefer obtaining the versioned catalog and licensed model resources before a
   broad target move.
10. **Freeze the persistence compatibility baseline.** Record fixture checksums,
    schema versions, selected package revisions, and pre-extraction test results.

## Detailed extraction plan

Each numbered step is a separate reviewable commit or small commit series. Do not
mix physical moves with behavior changes.

### Step 0 — create the decision baseline

- Record the exact commit, Xcode version, package resolution checksum, cache schema
  versions, model fingerprints, and test counts.
- Run import-boundary, smoke, full Thread Sanitizer, performance, Debug, and Release
  gates.
- Preserve representative persisted artifact and burst-cache fixtures and record
  checksums.
- Do not create a package yet if any prerequisite above is open.

### Step 1 — finish persistence encapsulation in the app target

- Complete Phase 9 without moving files.
- Introduce package-shaped repository protocols and package-owned summaries.
- Require explicit directories in production initializers; select live paths only
  in app assembly.
- Prove byte-for-byte compatibility, legacy migration, corrupt-record isolation,
  partial-write behavior, and cache purge scope.

### Step 2 — make contracts module-ready

- Replace `FileItem` in all candidate files with `RawCullFileItem`.
- Replace PhotoAIKit types in boundary values with package-owned identifiers,
  artifacts summaries, failures, and presentations.
- Audit every proposed public declaration for `Sendable`, `Equatable`, actor
  isolation, mutability, and documentation.
- Keep raw embeddings and stored payloads internal.

### Step 3 — split app composition from reusable runtime

- Move `RawCullApplicationState` and `.live()` construction into an app-local file.
- Make the reusable runtime accept already-created dependencies and expose only
  focused features.
- Keep settings-to-runtime configuration in an app-local adapter unless it can be
  expressed entirely with package-owned configuration values.
- Verify exact shared identity and weak-edge release behavior before moving files.

### Step 4 — create the empty local package

- Add `Packages/RawCullIntelligence/Package.swift` with macOS deployment matching
  RawCull, Swift 6, the two library products, and test targets.
- Add only a minimal marker or one pure contract; link the app to the local product.
- Keep all existing AI production files in the app target.
- Verify Xcode resolves one unified dependency graph and does not add duplicate
  PhotoAIKit versions.

### Step 5 — move pure values and policies

- Move contracts that depend only on Foundation/RawCullCore first.
- Move semantic presentation and burst review policy only when their ownership is
  genuinely reusable.
- Change access control deliberately; do not make all moved declarations public.
- Update imports and tests without changing symbols or behavior.

### Step 6 — move persistence actors

- Move repository protocols and explicit-path actor implementations.
- Keep codecs and PhotoAIStorage bridges internal.
- Run migration and performance gates immediately after each actor moves.
- Reopen pre-extraction fixtures and compare logical contents and file checksums
  where deterministic encoding permits.

### Step 7 — move similarity and semantic search

- Move service implementation, scoring model, and focused features.
- Keep `SimilarityScoringModel` internal.
- Move PhotoAI-backed indexing/ranking implementation to the adapter target where
  practical.
- Verify literal-query behavior, cached-only semantic search, model switching,
  fallback, cancellation, stale-generation rejection, partial failures, and
  non-finite CLIP recovery.

### Step 8 — move burst orchestration

- Move coordinator, lifecycle, compatibility mapping, and reusable pipeline values.
- Keep application rating/selection/navigation callbacks in RawCull.
- Preserve cache-first order: hydrate, migrate, compatible-cache load, score/index
  missing inputs, group, rank, apply, save.
- Run both performance tests because executable grouping and persistence code cross
  a module boundary.

### Step 9 — move Deep Review core

- Move feature, controller, scorer, and package values.
- Keep provider selection/resource construction in the PhotoAIKit adapter and
  recommendation application in RawCull.
- Verify SAM 3/EfficientSAM availability, cancellation, scoring policy, candidate
  limit, cache behavior, and group-signature validation.

### Step 10 — create the PhotoAIKit adapter product

- Move the provider-neutral portions of `RawCullAIIntegration` and live PhotoAIKit
  construction into `RawCullIntelligencePhotoAIKit`.
- Add mapping tests proving no PhotoAIKit type escapes its public API.
- Move the seven PhotoAIKit product dependencies from the RawCull app target to the
  adapter target when no app source imports them.
- Keep model paths, validated locations, bundle resources, and selected product
  policy passed in from app assembly.

### Step 11 — migrate application callers

- Make `RawCullViewModel` conform to package context protocols in app-local
  extensions.
- Construct settings/download state in the app, construct live AI dependencies via
  the adapter, then create the package runtime exactly once.
- Pass the runtime's focused feature objects to existing views.
- Remove temporary app copies only after `rg` proves there are no callers.

### Step 12 — migrate tests and tighten enforcement

- Move implementation tests with the implementation; keep app coordination and UI
  tests in `RawCullTests`.
- Replace path allowlisting for moved files with module dependency assertions and a
  smaller app import verifier.
- Reject direct imports of PhotoAIKit concrete products from the RawCull app target.
- Add an API leak check that fails if public symbol graphs mention PhotoAIKit,
  Background Assets, SwiftUI, `RawCullViewModel`, `UserDefaults`, or app bundle
  resources.

### Step 13 — remove target membership and finalize documentation

- Remove moved source files from the app target only after the local package builds.
- Confirm no file is compiled into both the package and app target.
- Update `README.md`, `Docs/ai-dependency-boundary.md`, test architecture,
  dependency inventory, release metadata expectations, and diagrams.
- Record the accepted public API and the reason every public declaration is needed.

## Test ownership after extraction

Move these suites, or their implementation-focused cases, to package tests:

- `RawCullSimilarityFeatureTests`
- `RawCullSemanticSearchTests`
- service-level cases from `RawCullSemanticSearchUITests`
- `BurstAnalysisCoordinatorTests`
- `BurstAnalysisPipelineValuesTests`
- `DeepAIReviewFeatureTests`
- `PerFileAnalysisArtifactStoreTests`
- `PhotoAIKitSimilarityMigrationTests`
- `TypedAIPersistenceMatrixTests`
- package-owned cases from `AICacheBoundaryTests`

Keep these app-facing responsibilities in `RawCullTests`:

- runtime/app composition identity and lifetime;
- settings, model download, licence, and Background Assets behavior;
- `RawCullViewModel` catalog/culling adapters;
- navigation, selection, ratings, toolbar, accessibility, and SwiftUI presentation;
- security-scoped access and termination behavior;
- extension embedding and release metadata.

## Validation gates for every move

At minimum:

```sh
swift test --package-path Packages/RawCullIntelligence
make verify-ai-import-boundary
make test-smoke
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -onlyUsePackageVersionsFromResolvedFile \
  build
```

Also run `make test-full` after moving executable logic, actor ownership,
cancellation entry points, or app composition. Run `make test-performance` after
moving indexing, ranking, grouping, artifact mapping, serialization, repositories,
or any package boundary that contains those operations.

Before accepting the extraction, all of the following must be green:

- local package build and tests;
- exact resolved-package Debug and Release app builds;
- smoke and full Thread Sanitizer plans;
- performance manifest;
- import/API leak checks;
- artifact and burst-cache compatibility fixtures;
- model-switch and fallback matrix;
- cancellation and stale-result tests;
- model downloader extension build and embedding verification;
- manual acceptance matrix, or an explicit recorded exception for unavailable
  licensed resources with no claim of manual completion.

## Risks and mitigations

- **Accidentally publishing implementation types:** generate and review a symbol
  graph after every public-surface commit.
- **Actor-isolation drift:** copy the app's verified Swift 6 concurrency assumptions
  explicitly into the package and test crossings with immutable values.
- **Duplicate model/runtime instances:** keep one factory and retain identity tests
  across app/package assembly.
- **Duplicate package resolution:** use the same PhotoAIKit identity and requirement;
  fail CI if `Package.resolved` contains an unexpected duplicate or revision.
- **Persistence incompatibility:** never combine schema changes with extraction;
  reopen pre-move fixtures after every repository move.
- **Resource lookup changes:** keep all app resources app-local and inject validated
  URLs/data rather than attempting implicit bundle lookup from package code.
- **Performance regression at module adapters:** avoid copying embedding payloads;
  profile indexing, ranking, grouping, and cache mapping before and after.
- **Circular app callbacks:** context protocols must contain only product snapshots
  and commands; package code must never import the app module.

## Rollback strategy

Every extraction commit must be reversible without data migration:

1. Restore the app target's prior source membership and imports.
2. Restore app assembly to the last package-free factory.
3. Remove the local package linkage only after the app sources compile again.
4. Keep all persisted schemas and paths unchanged, so caches, model licences, and
   downloaded model locations remain reusable.
5. Retain this decision record and any package-readiness refactors that were useful
   independently.

## Final recommendation

The current architecture is good enough to remain app-local and is mechanically
enforced. A complete package extraction is not yet justified because the remaining
work is not merely file movement: it requires finishing persistence encapsulation,
splitting app assembly, removing app aliases from contracts, injecting paths and
resources, and defining a PhotoAIKit-free public API.

If those prerequisites are completed and a measurable consumer or build/test value
exists, create the scoped local package described above. Include PhotoAIKit as an
implementation dependency through a dedicated adapter product; do not absorb it,
copy it, or expose its types. Keep RawCull settings, downloads, resources,
Background Assets, and application/culling policy in the app target.
