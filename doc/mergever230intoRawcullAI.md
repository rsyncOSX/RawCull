# Merge version-2.3.0 into RawCullAI

## Objective

Merge `version-2.3.0` into `RawCullAI` while preserving the macOS 27 AI architecture and adopting the PhotoAnalysisKit cleanup.

The two packages must remain unchanged:

- **PhotoAnalysisKit** owns sharpness scoring, focus masks, Vision saliency/classification, calibration, and its standalone Vision feature-print API.
- **PhotoAIKit** owns CLIP, SAM 3, descriptor-complete similarity artifacts, fallback workflows, storage, model identity, and model-resource handling.
- **RawCullAI** owns application composition, RAW decoding adapters, cache policy, UI state, and the wiring between the packages.

This merge must not replace PhotoAIKit with PhotoAnalysisKit. Both packages belong in the resulting RawCullAI dependency graph.

## Branch relationship

The branches diverge from commit `d74f8b8`:

- `RawCullAI` is seven commits ahead of the common base.
- `version-2.3.0` is ten commits ahead of the common base.
- A dry-run merge reports textual conflicts in three files:
  - `RawCull.xcodeproj/project.pbxproj`
  - `RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `RawCull/Model/ViewModels/SimilarityScoringModel.swift`

Other files may merge automatically but still require semantic review, especially the burst-analysis cache, tests, and Makefile.

## Resulting architecture

### PhotoAnalysisKit responsibilities

Adopt the `version-2.3.0` extraction of RawCull's internal analysis pipeline:

- Remove the application-owned focus engine implementation files.
- Remove the application-owned `Kernels.ci.metal` resource.
- Use PhotoAnalysisKit's packaged Metal pipeline and resource bundle.
- Keep `RawCullPhotoAnalysisAdapter` as the RawCull-specific boundary for RAW decoding and scoring-source selection.
- Keep the RawCull presentation wrapper around PhotoAnalysisKit's neutral sharpness result.
- Keep type aliases from RawCull names such as `FocusDetectorConfig` to the corresponding PhotoAnalysisKit types.

### PhotoAIKit responsibilities

Preserve the RawCullAI integration and all PhotoAIKit products:

- `PhotoAIContracts`
- `CoreAICLIPBackend`
- `CoreAISAM3Backend`
- `VisionFeaturePrintBackend`
- `PhotoAIWorkflows`
- `PhotoAIStorage`

PhotoAIKit remains the similarity architecture used by RawCullAI. It provides the descriptor-complete artifact model needed to support CLIP and whole-batch Vision fallback.

### RawCullAI responsibilities

RawCullAI should continue to:

- Locate and validate CLIP and SAM 3 model resources.
- Decode Sony RAW files into images accepted by the packages.
- Construct the AI composition root.
- Store and validate descriptor-complete similarity artifacts.
- Configure CLIP as the primary similarity provider.
- Configure Vision as the whole-batch fallback when CLIP indexing fails.
- Configure SAM 3 storage, segmentation, and application-facing workflows.
- Own settings, progress, cancellation, user-visible errors, and cache locations.

PhotoAIKit contains the fallback mechanism, but RawCullAI must explicitly compose it. The current RawCullAI implementation still uses Vision as its active primary similarity service; CLIP-to-Vision fallback wiring remains subsequent integration work.

## Conflict-resolution guide

### `RawCull.xcodeproj/project.pbxproj`

Do not select either side wholesale.

The resolved project must:

- Retain the PhotoAIKit package reference.
- Retain all PhotoAIKit products already linked by RawCullAI.
- Add the PhotoAnalysisKit `1.2.0` package reference and product.
- Keep `MACOSX_DEPLOYMENT_TARGET = 27.0` for RawCullAI.
- Preserve RawCullAI's Swift 6 and strict-concurrency build settings.

There is no linker or runtime conflict merely because both packages import Apple's Vision framework. Swift symbols are namespaced by their modules.

Both packages export a type named `VisionFeaturePrintBackend`. Avoid importing both backends into the same file and referring to that type without module qualification.

### `Package.resolved`

The final resolution must contain both:

- PhotoAnalysisKit `1.2.0`, revision `6e83ceebbca47a5dea0b1b2b4ee8b9132c281449`.
- PhotoAIKit at the revision selected by RawCullAI, currently `ef4ce1ab0d3f960c59e23cfbc8af2ea4e5716371`.

It must also retain PhotoAIKit's transitive dependencies.

After resolving `project.pbxproj`, regenerate `Package.resolved` with Xcode 27 instead of manually splicing the JSON:

```bash
xcodebuild -resolvePackageDependencies \
  -project RawCull.xcodeproj \
  -scheme RawCull
```

### `SimilarityScoringModel.swift`

Use the RawCullAI implementation as the base resolution.

Preserve:

- `[UUID: SimilarityArtifact]` rather than `[UUID: Data]`.
- `RawCullSimilarityServicing` injection.
- Backend descriptors and source fingerprints.
- Artifact validation.
- Indexing failure reporting.
- PhotoAIKit-owned distance semantics.
- Structured cancellation and latest-generation state protection.
- Compatibility with future CLIP and Vision artifacts.

Do not replace this model with the `version-2.3.0` PhotoAnalysisKit feature-print implementation. That implementation is correct for the non-AI branch, but its raw `Data` storage would discard the metadata required for CLIP/Vision fallback and model-aware cache invalidation.

### `BurstAnalysisCache.swift`

The automatic merge should be reviewed to ensure it combines both branches correctly.

The final file should retain from RawCullAI:

- `import PhotoAIContracts`.
- `[UUID: SimilarityArtifact]` storage.
- `BurstSimilaritySignature.backendDescriptor`.
- `artifactSchemaVersion` validation.
- Complete source-fingerprint and backend validation.
- Cache schema version `5` or a newer version if the merged representation changes again.

It should accept from `version-2.3.0`:

- `import PhotoAnalysisKit` alongside `import PhotoAIContracts`.
- A `SharpnessAnalysisDescriptor` generated by
  `PhotoAnalyzer.sharpnessDescriptor(for:)`, rather than duplicating package
  algorithm constants in RawCull.
- Legacy signature decoding that leaves `analysisDescriptor` nil so old cache
  entries remain readable but always compare stale.

The merged descriptor representation uses cache schema version `6`. The sharpness signature change intentionally invalidates old sharpness results. Because sharpness and similarity are stored in the same burst snapshot, the first run after the merge may rebuild the complete snapshot, including similarity artifacts. This is expected cache invalidation, not data corruption.

### Focus and sharpness files

Accept the `version-2.3.0` cleanup:

- Delete the old application-owned `FocusMaskEngine` implementation files.
- Delete the old application-owned `FocusDetectorConfig` and calibration implementations.
- Delete the application-owned Metal kernel.
- Add and retain `RawCullPhotoAnalysisAdapter.swift`.
- Retain the PhotoAnalysisKit-backed type aliases and RawCull-specific presentation extensions.
- Retain the updated `FocusMaskModel` and `SharpnessScoringModel` integration.

PhotoAnalysisKit's bundled `default.metallib` becomes the source of the focus kernel.

### Tests

Preserve the RawCullAI PhotoAIKit tests and add the PhotoAnalysisKit focus/sharpness integration coverage.

The feature-print test added in `PhotoAnalysisKitIntegrationTests.swift` cannot be copied unchanged into the resolved RawCullAI model because it assumes:

- `SimilarityScoringModel.featurePrintRevision` exists.
- `SimilarityScoringModel.embeddings` contains `[UUID: Data]`.

RawCullAI instead stores `SimilarityArtifact`. Resolve this by either:

1. Limiting `PhotoAnalysisKitIntegrationTests` to focus, sharpness, breakdown mapping, and the packaged Metal resource; or
2. Rewriting the similarity test against RawCullAI's PhotoAIKit service and descriptor-complete artifacts.

The second option is preferable when completing CLIP integration. Add application-level coverage that proves:

- CLIP is used when the CLIP provider succeeds.
- A CLIP indexing failure triggers a whole-batch Vision rebuild.
- A fallback batch does not mix CLIP and Vision artifacts.
- Persisted artifacts contain complete backend and source descriptors.
- Cached artifacts are rejected when the backend, model fingerprint, source fingerprint, or artifact schema changes.
- Cancellation and superseded indexing runs cannot commit stale results.

Package-level fallback tests in PhotoAIKit remain valuable but do not prove that RawCullAI composed the providers correctly.

### Makefile and test plans

Retain the union of relevant smoke coverage:

- PhotoAnalysisKit focus/sharpness integration tests.
- RawCullAI PhotoAIKit similarity migration and artifact tests.
- Similarity cancellation and latest-run-wins tests.
- Existing critical burst, cache, and concurrency tests.

Keep `-enableCodeCoverage NO` for the fast smoke command if that is the desired `version-2.3.0` behavior. Do not accidentally remove RawCullAI-specific smoke selectors while resolving the automatically merged Makefile.

## Recommended merge sequence

Run the merge using Xcode 27 and a clean RawCullAI working tree:

```bash
git switch RawCullAI
git merge --no-commit --no-ff version-2.3.0
```

Resolve in this order:

1. Resolve `project.pbxproj` so both packages and all required products are present.
2. Regenerate `Package.resolved` under Xcode 27.
3. Resolve `SimilarityScoringModel.swift` using the RawCullAI artifact-based implementation.
4. Review the automatically merged `BurstAnalysisCache.swift` against the combined requirements above.
5. Accept the PhotoAnalysisKit focus/sharpness extraction and application adapter.
6. Update `PhotoAnalysisKitIntegrationTests.swift` for the RawCullAI architecture.
7. Reconcile the Makefile and test-plan coverage.
8. Search for unresolved or ambiguous package references.

Useful checks:

```bash
rg -n '<<<<<<<|=======|>>>>>>>' .
rg -n 'import Vision|VisionFeaturePrintBackend|PhotoAnalysisKit|PhotoAIKit' \
  RawCull RawCullTests RawCull.xcodeproj
```

## Verification

At minimum, run:

```bash
make test-smoke
make test-full
```

Also verify:

- The application and test targets resolve both packages under Xcode 27.
- The PhotoAnalysisKit Metal resource is copied into the application and test bundles.
- Focus-mask generation returns a non-empty mask.
- Sharpness scoring returns a valid breakdown.
- Existing Vision similarity indexing and ranking still work before CLIP is enabled.
- Burst caches save, load, reject stale artifacts, and rebuild cleanly.
- RawCullAI capability reporting still distinguishes missing, invalid, and available CLIP/SAM resources.
- No file imports both `VisionFeaturePrintBackend` implementations ambiguously.

After CLIP fallback is wired, additionally verify a successful CLIP batch, a forced CLIP failure followed by a successful whole-batch Vision fallback, and persistence/reload for both backend types.

## Expected outcome

The completed merge should produce a macOS 27 RawCullAI branch with:

- The smaller, package-backed focus and sharpness implementation from `version-2.3.0`.
- PhotoAnalysisKit and PhotoAIKit present without changes to either package.
- RawCullAI's descriptor-complete similarity and cache architecture intact.
- A clean path to continue CLIP and SAM 3 integration through PhotoAIKit.
- No duplicate application-owned Vision focus pipeline or Metal kernel.

The merge is therefore primarily a cleanup of RawCull's focus/sharpness Vision implementation. It is not a replacement of PhotoAIKit's similarity, CLIP, SAM 3, or fallback responsibilities.
