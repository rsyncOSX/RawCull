# Test architecture

RawCull uses Swift Testing for unit, integration, cache, and workflow coverage. Tests are grouped around retained product behavior:

- catalog scanning, ratings, selection, comparison, export, and culling state;
- thumbnail loading, cache identity, cancellation, and concurrency;
- focus, sharpness, saliency, histogram, and RAW image integration;
- Apple Vision feature-print indexing, compatibility, persistence, ranking, and burst grouping;
- application accessibility and release metadata; and
- concurrency and data-race checks.

`TestManifests/SmokeTests.txt` selects the fast release gate. It includes all suites tagged `.smoke` plus individually selected cancellation and stale-result regression tests. `SmokeManifestIntegrityTests` keeps the manifest ordered, unique, and synchronized with source declarations.

`TestManifests/PerformanceTests.txt` contains the longer concurrency stress selection. Vision behavior is covered through `PhotoAnalysisKitIntegrationTests`, `PerFileAnalysisArtifactStoreTests`, `RawCullSimilarityFeatureTests`, `BurstAnalysisCoordinatorTests`, and the similarity cases in `CullingModelTests`.

All test stores and cache roots must use isolated temporary directories. Tests must not read or mutate a person's live RawCull application data.
