# macOS 26 Tahoe Vision-only conversion plan

## Goal

Convert the current RawCull application into one product whose supported baseline is macOS 26 Tahoe and whose only image-similarity implementation is Apple's Vision feature-print API. Remove the macOS 27 model-AI product surface completely rather than hiding it behind availability checks.

This is an implementation plan only. No source-code changes are part of this document change.

## Final product definition

The converted product must:

- set macOS 26 as the deployment target for the app and test targets;
- build with the macOS 26/Xcode 26 toolchain, not merely run on macOS 26 after being built with Xcode 27;
- use `PhotoAnalysisKit.VisionFeaturePrintBackend` for image-to-image similarity and burst grouping;
- retain existing non-model photo analysis supplied by Apple frameworks and `PhotoAnalysisKit`, including focus, sharpness, saliency, and metadata work;
- contain no CLIP, text-to-image semantic search, SAM 3, EfficientSAM, subject segmentation, Deep Review, model download, model licensing, or Managed Background Assets code;
- contain no `PhotoAIKit`, `coreai-models`, or `BackgroundAssets.framework` dependency in the resolved build graph or shipped app;
- preserve catalog, rating, thumbnail, comparison, export, ordinary similarity, burst grouping, and manual review workflows;
- treat old model-derived caches as incompatible without damaging catalogs, ratings, or original image files; and
- have no macOS 27-only code path, extension, entitlement, package product, UI, test expectation, or release claim.

“Vision-only” describes the backend boundary, not an assertion that Vision performs no machine learning. Vision feature prints and Vision saliency are Apple framework features and remain in scope. Third-party or separately distributed model runtimes are out of scope.

Setting a deployment target of macOS 26 establishes the minimum supported system; it does not prevent the app from launching on later macOS releases. “macOS 26 only” in this plan means one Tahoe-baseline implementation with no macOS 27-specific feature variant.

## Verified current blockers

The current repository cannot become a macOS 26 product by changing only `MACOSX_DEPLOYMENT_TARGET`:

- `RawCull.xcodeproj/project.pbxproj` sets the project, app, tests, and model-downloader extension to macOS 27.
- The app target links `CoreAICLIPBackend`, `CoreAIEfficientSAMBackend`, `CoreAISAM3Backend`, `PhotoAIContracts`, `PhotoAIStorage`, `PhotoAIWorkflows`, and `VisionFeaturePrintBackend` from `PhotoAIKit`.
- The pinned `PhotoAIKit` manifest declares `.macOS("27.0")` for every product. Even its Vision product is therefore unavailable to a macOS 26 target.
- The app embeds `RawCullModelDownloader.appex`; that target links `BackgroundAssets.framework` and also requires macOS 27.
- `RawCullAIIntegration` constructs Vision, CLIP, segmentation, mask storage, and Deep Review as one composition root.
- `RawCullIntelligenceRuntime`, `SimilarityScoringModel`, `RawCullViewModel`, and many views carry semantic-search and Deep Review state even when Vision is selected.
- The burst and per-file caches encode `PhotoAIKit` contract types, so simply removing the package would break their compilation and decoding.
- Tests explicitly require a macOS 27 deployment target and cover the model-only product surface.
- The existing `PhotoAnalysisKit` dependency is version 1.2.2, declares `.macOS(.v26)`, and already supplies `VisionFeaturePrintBackend`, `VisionFeaturePrint`, secure payload persistence, revision compatibility, cancellation, and native Vision distance calculation. It is the migration destination.

## Architecture after conversion

Keep one simple dependency direction:

```text
RawCull app and views
    -> RawCull similarity and burst orchestration
        -> RawCull-owned source/cache records
            -> PhotoAnalysisKit.VisionFeaturePrintBackend
                -> Apple Vision
```

There must be no model selector and no fallback policy. Vision is the single configured backend. The application root should create one Vision similarity service, one similarity feature, and one view model. Runtime reconfiguration machinery should be removed unless it still serves a real non-model setting.

Use RawCull-owned adapter types at the application boundary instead of recreating the generic `PhotoAIKit` type system. The smallest useful boundary is:

- a source value containing stable file ID, URL, display name, size, and modification date;
- a persisted Vision artifact containing source identity plus `PhotoAnalysisKit.VisionFeaturePrint`;
- a Vision service that decodes source images, requests feature prints, reports progress, and compares compatible prints;
- an actor-isolated store for those artifacts; and
- the existing similarity/burst feature APIs after all backend switching and semantic-search members are removed.

Do not copy `PhotoAIKit` contracts, codecs, or workflow implementations into RawCull under new names. Port only behavior required by the Vision pipeline and express it in terms of `PhotoAnalysisKit.VisionFeaturePrint`.

## Removal inventory

> Applied 31 August 2026. The feature areas, model resources, model-only tests,
> downloader target, Managed Background Assets metadata, and PhotoAIKit build
> graph described below have been removed. Retained Vision behavior now has
> replacement persistence, integration, similarity, and cache-boundary coverage.

### Delete complete feature areas

Remove these production directories/files after their callers have been detached:

- `RawCull/Intelligence/DeepReview/`
  - `DeepAIReviewController.swift`
  - `DeepAIReviewFeature.swift`
  - `SubjectMaskFocusScorer.swift`
- `RawCull/Intelligence/ModelManagement/`
  - model catalog, resource manager, download service, license acceptance, management model, and settings model;
- `RawCull/Intelligence/SemanticSearch/`
  - semantic-search service and feature;
- `RawCull/Intelligence/Presentation/SemanticSearchUIPresentation.swift`;
- `RawCull/Views/CullingGrid/DeepAIReviewSheetView.swift`;
- `RawCull/Views/SimilarityGridView/SemanticSearchStateViews.swift`;
- `RawCull/Views/SimilarityGridView/SemanticSearchViews.swift`;
- `RawCull/Views/Settings/AISettingsTab.swift`;
- `RawCull/Views/Settings/AIModelDownloadsView.swift`;
- `RawCull/Views/Settings/ModelLocationButton.swift` if it has no non-model caller; and
- the complete `RawCullModelDownloader/` directory.

Remove these resources after verifying they are referenced only by deleted model features:

- `ModelAssets/manifest.template.json`;
- `ModelAssets/README.md`;
- all `ModelAssets/Notices/CLIP-DataComp/` files;
- all `ModelAssets/Notices/CLIP-OpenAI/` files;
- all `ModelAssets/Notices/SAM3/` files; and
- model-specific entries in `Licence.MD`, About text, acknowledgements, generated notices, and release documentation.

If `ModelAssets` becomes empty, remove the directory. Do not remove general application licenses.

### Delete model-only tests

Delete tests whose subject no longer exists:

- `RawCullTests/DeepAIReviewFeatureTests.swift`;
- `RawCullTests/RawCullAIIntegrationTests.swift` after its Vision assembly coverage is replaced;
- `RawCullTests/RawCullAIModelDownloadsTests.swift`;
- `RawCullTests/RawCullIntelligenceRuntimeTests.swift` after retained lifetime tests are moved;
- `RawCullTests/RawCullSemanticSearchTests.swift`;
- `RawCullTests/RawCullSemanticSearchUITests.swift`;
- `RawCullTests/PhotoAIKitSimilarityMigrationTests.swift` once the chosen cache policy is covered by new tests;
- `RawCullTests/TypedAIPersistenceMatrixTests.swift` after Vision persistence cases are moved; and
- model-only portions of `AICacheBoundaryTests`, `AccessibilityPresentationTests`, `SmokeManifestIntegrityTests`, and `TestIsolationHelpers`.

Tests are removed because the features are removed, not to make the suite pass. Every retained behavior must keep or gain equivalent coverage.

### Remove build-system objects

From `RawCull.xcodeproj/project.pbxproj`, remove every object belonging to:

- the `RawCullModelDownloader` native target;
- its product reference and file-system-synchronized group;
- its target dependency from `RawCull`;
- the `Embed ExtensionKit Extensions` copy phase and embedded `.appex` build file;
- `BackgroundAssets.framework` file and framework build entries;
- all seven `PhotoAIKit` product dependencies;
- the `PhotoAIKit` remote package reference; and
- the extension's Debug/Release build configurations and configuration list.

After package resolution, confirm that neither `PhotoAIKit` nor `coreai-models` remains in `Package.resolved`. Retain `PhotoAnalysisKit` as the one package used for both the existing analysis functionality and Vision feature prints.

## Rework inventory

### Composition and application lifetime

Replace `RawCullAIIntegration.swift` with a narrowly named Vision composition object, or eliminate the object and assemble `RawCullVisionSimilarityService` directly in `RawCullApplicationState.live()`.

Rework `RawCullIntelligenceRuntime.swift` as follows:

- remove `RawCullIntelligenceConfigurationIdentity`, semantic configuration, segmentation selection, revision-based model switching, capabilities, model-management state, and settings binding;
- keep only a stable owner if it is still needed to guarantee that one `RawCullSimilarityFeature` instance is shared by the app and view model;
- rename remaining “Intelligence” or “AI” types to “Similarity” only when the old name would misrepresent their responsibility; and
- make `RawCullApplicationState.make` accept a Vision service and artifact store for tests, with live defaults for production.

Update `RawCull/Main/RawCullApp.swift` to:

- retain only the simplified similarity lifetime;
- stop refreshing model settings at launch;
- stop injecting semantic-search and Deep Review objects into the main scene; and
- construct `SettingsView` without an AI settings model.

Update `RawCull/Main/RawCullMainView.swift` and all descendant initializers to remove semantic-search and Deep Review parameters. Prefer removing the parameters through the full view tree in one pass so there are no placeholder services or permanently unavailable states.

### Similarity contracts and Vision service

`RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift` currently contains both the Vision and CLIP implementations and imports `PhotoAIContracts`, `PhotoAIStorage`, `PhotoAIWorkflows`, and `VisionFeaturePrintBackend`. Split and reduce it:

- import `PhotoAnalysisKit` and use its `VisionFeaturePrintBackend` actor;
- remove `RawCullCLIPSimilarityService`, fallback providers, CLIP diagnostics, model fingerprints, normalization versions, text compatibility, and whole-batch fallback fields;
- replace `AIImageSource` with the RawCull-owned source value;
- replace `SimilarityArtifact` with the RawCull-owned Vision artifact;
- keep bounded parallel decoding/generation, cancellation checks, partial per-file failures, progress callbacks, and finite-distance validation;
- keep feature-print revision and representation version as compatibility keys; and
- make incompatible revisions return a cache miss or non-comparable result rather than crash.

The adapter must not archive `VNFeaturePrintObservation` itself. Persist the `VisionFeaturePrint` returned by `PhotoAnalysisKit`; the package owns secure Vision encoding and decoding.

### Similarity state and orchestration

Reduce `SimilarityScoringModel.swift` to image similarity and burst grouping:

- remove semantic capability, service, task, generation, artifacts, scores, result ordering, progress, result limits, search methods, and semantic hydration;
- remove CLIP retry/fallback fields and messages;
- hold exactly one Vision backend identity;
- preserve generation tokens for image indexing and ranking;
- preserve cancellation, partial indexing failure reporting, anchor selection, distance sorting, and stale-result rejection;
- preserve cache-first hydration and only index missing or explicitly refreshed files; and
- keep existing threshold semantics only after a regression test proves they produce the intended groups with Vision distances.

Reduce `RawCullSimilarityFeature.swift`:

- remove the `.clip`/`.other` backend cases and present Vision directly;
- remove backend replacement, semantic hydration, semantic task generations, and CLIP-only evidence;
- keep catalog hydration, explicit refresh, ranking, cancellation, progress projection, and burst accessors; and
- remove application callbacks that exist only to react to backend changes.

Audit `RawCullViewModel+Similarity.swift` and `RawCullViewModel+BurstGrouping.swift` for assumptions about a selectable backend. The view model should request Vision indexing directly and must not cancel work in response to model-setting changes that no longer exist.

### Persistence and migration

Rewrite `PerFileAnalysisArtifactStore.swift` around a RawCull-owned Codable Vision record. Preserve:

- source fingerprinting by standardized path, file size, and modification date;
- one-record-per-source behavior;
- atomic writes;
- actor isolation;
- cancellation between commits;
- last-access metadata and usage reporting; and
- corruption handling as a cache miss.

Use a new schema version and a Vision-specific storage namespace. Do not try to decode old `PhotoAIKit.SimilarityArtifact` values after removing its codec. This intentionally makes CLIP and old generic artifacts cold-cache data.

Rework `BurstAnalysisCache.swift`:

- replace `SimilarityArtifact`, `SimilarityArtifactDescriptor`, and backend arrays with the new Vision artifact and a compact Vision signature;
- include Vision request revision, representation version, source fingerprint rules, thumbnail size, and RawCull pipeline version in compatibility checks;
- increment the burst-cache schema version;
- reject old schemas before attempting to decode removed model-specific payloads;
- preserve compatible sharpness scores and manual review state only if they can be decoded independently and mapped safely; otherwise reject the complete old burst snapshot and recompute;
- retain digest validation for the exact set of Vision artifacts; and
- never reinterpret a CLIP payload as a Vision feature print.

The preferred cleanup policy is lazy and safe: leave old cache files untouched during migration, write new Vision files into the new namespace, and let the existing cache-clear UI remove both namespaces. An optional one-time cleanup may delete only the known obsolete RawCull model-cache subdirectories after their paths are resolved explicitly. Never delete catalogs, ratings, exported files, or source photographs.

Update `BurstAnalysisCoordinator+CacheCompatibility.swift` and related coordinator files so cache reuse has one Vision signature rather than primary/fallback backend sets. Remove `semanticReview` from `BurstFullReindexRequest` and any branch that exists only to prepare a CLIP semantic index.

### View model and UI

Remove semantic-search state from:

- `RawCullViewModel.swift`;
- `RawCullViewModel+Catalog.swift` filtering, result ordering, and empty-index handling;
- `FileDetailView.swift` and `RawCullDetailContainerView.swift`;
- `SharedMainToolbarContent.swift`;
- `GridThumbnailSelectionView.swift` and `GridThumbnailView.swift`;
- `SimilarityGridSelectionView.swift` and `SimilarityGridView.swift`;
- `BurstGroupsHomeView.swift` semantic-index counts;
- `MainThumbnailImageView.swift`; and
- `ZoomCullingMetadata.swift` CLIP match rank/score presentation.

Remove Deep Review state, controls, sheets, result badges, reset calls, and injected controllers from:

- `RawCullViewModel.swift` and `RawCullViewModel+BurstGrouping.swift`;
- `RawCullMainView.swift`;
- `CullingGridView.swift`;
- grid and similarity view initializers; and
- any accessibility presentation that announces Deep Review, segmentation, model availability, or model download status.

Keep ordinary burst ranking, recommendation badges, manual winner overrides, undo, and culling progress. Where Deep Review currently augments an existing screen, remove only its controls and branches; do not remove the base culling screen.

Rework `SettingsView.swift` to remove the injected `RawCullAISettingsModel` and the AI tab. Keep Cache, Thumbnails, Focus, and Memory. If users need Vision index usage or clearing controls, put them in Cache under neutral “Similarity index” wording.

Search the string catalog and source for `AI`, `CLIP`, `SAM`, `Deep Review`, `semantic`, `model download`, and `macOS 27`. Remove strings that no remaining UI references, then regenerate localization symbols. Preserve unrelated uses of words such as “model” in ordinary view-model architecture.

### Documentation and release metadata

As the final implementation phase, update:

- `README.md` to describe the Tahoe Vision-only product and remove branch guidance that calls the current app macOS 27 AI-based;
- `Licence.MD` and About/acknowledgement UI to remove only licenses for unshipped model assets/dependencies;
- build/version documentation that mentions the model downloader or Managed Background Assets;
- test architecture documentation and smoke manifests; and
- release notes to disclose that semantic search and Deep Review are intentionally removed and old similarity caches will be rebuilt.

## Ordered implementation phases

### Phase 1 — Establish a protected baseline

1. Record a clean Debug build, Release build, unit-test result, and a small manual catalog run before removal.
2. Capture expected behavior for catalog loading, focus/sharpness, similarity sorting, burst grouping, manual winner selection, ratings, compare, and export.
3. Add or retain fixtures that contain at least two obvious visual bursts and unrelated images. These become the before/after regression set.
4. Record current application-data locations and classify each as user data, regenerable cache, or model asset before writing migration cleanup.

Exit condition: retained behavior has reproducible baseline evidence and user-owned data is clearly separated from removable cache data.

### Phase 2 — Prove the Tahoe dependency floor

1. Confirm all retained Swift packages declare macOS 26 or lower and are consumable by Xcode 26. `PhotoAnalysisKit 1.2.2` already meets the manifest platform requirement; verify its pinned source and resolved checksum in a clean build.
2. Remove `PhotoAIKit` products and package reference from a working branch before lowering the deployment target. This forces all leaked contract usages to become compiler-visible migration work.
3. Remove the downloader target and `BackgroundAssets.framework` graph.
4. Set project, app, and tests to `MACOSX_DEPLOYMENT_TARGET = 26.0`. If a retained dependency genuinely requires 26.1 or 26.2, document the evidence and use that exact minimum consistently instead of scattering overrides.
5. Audit `MTL_LANGUAGE_REVISION = Metal40`, Swift language/upcoming-feature settings, generated string-symbol settings, and any Xcode 27-created project fields. Use an Xcode 26-compatible Metal revision or the SDK default where no Metal 4 feature is required.
6. Resolve packages and build with Xcode 26 so a newer SDK cannot hide unavailable API use.

Exit condition: the target graph contains no macOS 27-only product and Xcode 26 reaches RawCull source compilation with only expected migration errors.

### Phase 3 — Introduce the Vision-only data boundary

1. Add RawCull-owned Vision source, artifact, descriptor/signature, and persistence record types.
2. Implement the adapter over `PhotoAnalysisKit.VisionFeaturePrintBackend`.
3. Port bounded indexing, progress, cancellation, partial failure, and distance behavior.
4. Implement the new per-file store and its compatibility validation.
5. Add focused tests before connecting UI or burst grouping.

Exit condition: a fixture image set can be indexed, persisted, reloaded, compared, partially failed, and cancelled without importing any `PhotoAIKit` module.

### Phase 4 — Simplify similarity and burst orchestration

1. Convert `SimilarityScoringModel` to the new Vision types.
2. Remove semantic and backend-switching state from the model and feature.
3. Convert burst signatures, caches, coordinators, and digest checks.
4. Increment cache schemas and verify old model artifacts are rejected safely.
5. Verify cancellation and catalog-generation checks still prevent stale results from replacing a newer catalog.

Exit condition: similarity sorting and burst grouping work end to end through Vision with cache hits on the second run.

### Phase 5 — Remove model features from application state and UI

1. Simplify application composition and view-model initializers.
2. Remove semantic-search filtering and presentation from the view hierarchy.
3. Remove Deep Review from culling and burst screens.
4. Remove AI/model settings and download presentation.
5. Remove model-only accessibility and localization content.
6. Compile frequently and remove obsolete parameters/types rather than inserting stubs.

Exit condition: no live source file references a removed feature and every retained screen is reachable without dummy model state.

### Phase 6 — Delete dead code, resources, and tests

1. Delete the complete feature areas in the removal inventory.
2. Delete model assets and unneeded notices.
3. Delete model-only tests and replace retained coverage in the same change set.
4. Run repository-wide import and terminology audits.
5. Inspect the built product and package graph for accidental leftovers.

Exit condition: searches for removed module imports and product identifiers return no production matches, and no model assets or downloader extension are shipped.

### Phase 7 — Tahoe compatibility pass

1. Build Debug and Release with Xcode 26 using the macOS 26 SDK.
2. Treat availability warnings as errors during the audit.
3. Replace genuinely newer APIs with macOS 26 equivalents. Use `if #available` only when a retained framework API has an optional newer enhancement; the base path must be complete on Tahoe.
4. Do not use `#if canImport` to conceal a macOS 27 package, `#if compiler` as an OS check, or runtime availability to retain removed model features.
5. Run on the oldest supported macOS 26 point release and on the latest macOS 26 update.

Exit condition: the exact release configuration builds and runs on the declared Tahoe minimum without weak-link crashes or unavailable-API warnings.

### Phase 8 — Release validation and documentation

1. Run the full unit, smoke, and performance plans.
2. Perform manual workflows on a real ARW catalog.
3. Archive the app and inspect its bundle and linked libraries.
4. Update release metadata, licenses, README, and migration notes.
5. Repeat the Release build from a clean checkout using only the resolved package file.

Exit condition: the archive is demonstrably Vision-only, all retained workflows pass, and public documentation matches the shipped product.

## Required test coverage

### Vision service tests

- feature prints are generated for valid images;
- corrupt or undecodable images produce per-file failures without losing successful artifacts;
- progress is monotonic and finishes at the expected total;
- cancellation stops later generation and persistence;
- compatible prints yield finite distances;
- different Vision revisions or representation versions are rejected;
- concurrency never exceeds the configured limit; and
- no model download, network, or external asset is required.

### Persistence tests

- unchanged files produce cache hits;
- path, size, modification date, pipeline version, Vision revision, or representation changes produce cache misses;
- corrupt records are isolated and do not invalidate valid siblings;
- atomic writes preserve previously committed records when cancellation occurs;
- old generic/CLIP records and old burst schemas are rejected without a decoding crash;
- clearing caches removes both the new Vision namespace and known obsolete RawCull analysis caches; and
- user catalogs, ratings, sources, and exports are never cleanup targets.

### Similarity and burst tests

- anchor sorting is deterministic for equal distances;
- missing artifacts do not crash ranking or silently become zero-distance matches;
- a repeated catalog uses persisted Vision artifacts;
- force refresh regenerates the intended records;
- a catalog switch or newer generation prevents stale task completion from publishing;
- grouping thresholds are calibrated against Vision distances;
- manual winner overrides, undo, review queue state, and recommendation badges remain correct; and
- partial indexing failures are visible and exclude only affected files.

### UI tests

- Settings contains Cache, Thumbnails, Focus, and Memory, with no AI tab;
- no semantic-search field, state, badge, rank, or toolbar control appears;
- no Deep Review control, sheet, progress, or failure state appears;
- ordinary similarity sorting and burst navigation remain accessible by mouse and keyboard;
- accessibility labels describe Vision similarity without CLIP/model terminology; and
- empty, loading, error, and partial-result states remain usable.

### Build and archive tests

- all project/app/test deployment settings resolve to the chosen macOS 26 minimum;
- Release metadata tests reject any return to macOS 27;
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug -destination 'platform=macOS,arch=arm64' build` passes with Xcode 26;
- the equivalent Release build and archive pass;
- package resolution contains `PhotoAnalysisKit` and contains neither `PhotoAIKit` nor `coreai-models`;
- `otool -L` on the app executable shows no `BackgroundAssets.framework` or model-only framework;
- the archive contains no `.appex`, model manifest, CLIP/SAM notice bundle, or model payload; and
- the app launches and completes core workflows with network access disabled.

## Repository-wide completion audit

Run targeted searches after implementation. Classify every match rather than blindly deleting generic words:

```sh
rg -n 'PhotoAIKit|CoreAICLIPBackend|CoreAISAM3Backend|CoreAIEfficientSAMBackend|PhotoAIContracts|PhotoAIStorage|PhotoAIWorkflows|VisionFeaturePrintBackend' .
rg -n 'RawCullModelDownloader|BackgroundAssets|AssetPackManager' .
rg -n 'CLIP|SAM 3|EfficientSAM|SemanticSearch|DeepAIReview|SubjectMask' RawCull RawCullTests ModelAssets README.md Licence.MD
rg -n 'MACOSX_DEPLOYMENT_TARGET = 27|macOS 27' RawCull.xcodeproj RawCull RawCullTests README.md Docs
```

The first two searches must have no shipped-code or project matches. `VisionFeaturePrintBackend` may remain only as the `PhotoAnalysisKit` type/import, not the removed `PhotoAIKit` product. The terminology searches may retain historical release notes only when clearly labeled and intentionally shipped; current UI and current release documentation must have no model-feature claims.

## Definition of done

The conversion is complete only when all of the following are true:

- Xcode 26 builds and tests the app with the declared macOS 26 Tahoe deployment target.
- The project and resolved dependency graph contain no `PhotoAIKit`, `coreai-models`, downloader extension, or Background Assets linkage.
- Vision feature prints from `PhotoAnalysisKit` are the only similarity artifacts generated or compared.
- Semantic search, CLIP, SAM/EfficientSAM, Deep Review, model management, model assets, and their UI are removed rather than disabled.
- Existing user-owned catalogs, ratings, and photographs survive migration unchanged.
- Old model-derived caches are rejected safely and rebuilt as Vision caches.
- Similarity sorting, burst grouping/ranking, focus/sharpness, manual review, compare, and export pass regression testing.
- A clean Release archive contains no model assets, model notices, or embedded extension.
- README, licenses, About text, release metadata, and tests describe the same Vision-only Tahoe product that is actually shipped.
