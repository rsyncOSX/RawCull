# RawCull test inventory

Updated 23 October 2026 after cleanup. The affected Swift suites and Python checks were run; this is not a claim that every test in the repository was executed. Counts are test function declarations; parameterized functions can execute multiple cases. Dependency-package tests are outside this repository inventory.

- Main target: **670 test functions in 99 files**.
- Release/probe target: **10 test functions in 3 files**.
- Python tooling: **17 test methods in 6 files**.

## What the tests cover

| Area | Coverage |
|---|---|
| AI and model infrastructure | Model downloads, licences, readiness, runtime configuration, similarity, CLIP semantic search, artifact compatibility and persistence. |
| AI reviews | Deep Review, object discovery and assessment, Combined Review, grounded evidence, malformed responses, retry budgets, cancellation, resume, masks and source coordinates. |
| Culling and bursts | Ratings, filtering, ranking, burst membership, review queues, manual winners, undo, cached analysis and session ownership. |
| Images and thumbnails | EXIF orientation, source selection, embedded JPEG versus sidecar/RAW, caches, decode admission, preload gates, bounded concurrency and stale-result rejection. |
| Presentation and interaction | Comparison grid, loupe, zoom, keyboard routing, viewport math, accessibility, histograms, saved-file rows and view observation boundaries. |
| Files and durability | Scanning/sorting, JPEG export, rsync copy, bookmarks, security-scoped access, settings, corrupt history and quit recovery. |
| Validation tools | Release metadata, model provenance, smoke selector integrity, real-model runners, frozen baselines and AF comparison evaluation. |

## How the test groups run

| Entry point | Selection and behavior |
|---|---|
| `make test-full` | Main RawCullTests target through RawCull plan, with Thread Sanitizer. Environment-gated probes remain opt-in. |
| `make test-smoke` | Smoke manifest selection, preceded by enumeration verification; Makefile expects 401 enumerated tests. |
| `make test-performance` | Two selectors: extreme concurrent-load stress test and Vision indexing/ranking benchmark. |
| `make releaseaiobjectstest` | Hostless Release AI Objects integration; enables real ARW/model run. |
| `make releasesharpnesstest` | Hostless Release sharpness suite; enables catalog analysis. |
| `make releaseafcomparison` | Enables AF comparison dataset export in the sharpness suite. |
| `make combinedinputstest` | Debug input-contract probe using installed preprocessors/models. Probe declarations are conditionally compiled. |
| `make combinedreviewtest` | Selects CombinedReviewRealModelTests; caller must supply opt-in environment and installed inputs. |
| `make combinedselectiontest` | Enables selected-catalog real-model Combined Review. |
| Python tooling | Separate unittest files under Scripts; not part of Xcode targets. |

Smoke and Performance plan files do not themselves filter individual tests: the Makefile supplies `-only-testing` manifests. Running those plans directly in Xcode may therefore select the whole main target. Likewise, both release plans point at the same release target; Makefile selectors distinguish their suites.

## Cleanup applied

- Split existing culling, sharpness and zoom suites into focused files, retaining suite identities and their test coverage. Shared culling fixtures now live in CullingTestSupport.swift.
- Consolidated the two public cache replacement tests into one parameterized test, and the two concurrent read/write tests into one parameterized test. Both memory and grid cases remain covered.
- Reworked the performance stress test to use 16 bounded workers that mutate/read/clear both caches, with final live-entry/count/cost checks. Its selector remains unchanged.
- Separated settings persistence, memory statistics and test tags from the old mixed concurrency file. Kept distinct settings failure, normalization, migration and snapshot coverage.
- Consolidated Python runner outcome tests into subtests without dropping success, failure or missing-evidence scenarios. Added malformed-progress, PNG-header and runner privacy regressions.
- Added `make test-scripts` and Scripts/README.md. Removed tracked Python bytecode and ignored generated Python files.

Smoke membership and the performance selectors are unchanged. Future smoke membership changes can require updating TestManifests/SmokeTests.txt, expected selectors/tagged suites in SmokeManifestIntegrityTests, and SMOKE_EXPECTED_TESTS in Makefile.

Installed-model probes remain opt-in; normal runs do not validate those workflows. RawCullSemanticSearchUITests tests presentation values in the main Swift Testing target rather than a separate UI automation target.

Validation: 182 affected Swift test-case records passed, including the cache stress test and smoke-manifest integrity tests. `make test-scripts` ran 17 Python tests: 16 passed and the OpenCV integration test skipped because OpenCV is unavailable. Xcode enumeration also confirmed 401 unique smoke tests and 2 unique performance tests. The Swift run did not enable Thread Sanitizer or execute installed-model/release probes.

## Main target — every test

### AIAnalysisInputSelectionTests (1)

[AIAnalysisInputSelectionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisInputSelectionTests.swift)

- [preserves grid selection only when leaving the grid](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisInputSelectionTests.swift:8)

### AIAnalysisRealModelTests (1)

[AIAnalysisRealModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisRealModelTests.swift)

- [selected ARWs run SAM CLIP then Qwen then Objects](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisRealModelTests.swift:16) — opt-in: RAWCULL_ANALYSIS_RUN

### AIAnalysisSelectionTests (5)

[AIAnalysisSelectionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift)

- [Grid source includes only selected files in catalog order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift:9)
- [Grid source falls back to the focused image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift:28)
- [Selected analysis images survive main view changes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift:42)
- [Browsing tagged images preserves the selected batch](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift:65) — parameterized
- [Analysis navigation walks ordered rows and stops at boundaries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AIAnalysisSelectionTests.swift:90)

### AICacheBoundaryTests (1)

[AICacheBoundaryTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AICacheBoundaryTests.swift)

- [independent cache clears preserve ratings settings decisions models and licences](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AICacheBoundaryTests.swift:9)

### AccessibilityPresentationTests (5)

[AccessibilityPresentationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift)

- [saved rows announce content and selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift:9)
- [image tiles announce rating selection and semantic rank](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift:23)
- [AI capability and downloads announce readiness licence progress and failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift:34)
- [semantic search announces CLIP backend coverage and result count](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift:60)
- [Deep Review announces SAM 3 progress and confidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/AccessibilityPresentationTests.swift:93)

### ApertureHintTests (6)

[ApertureHintTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift)

- [nil aperture maps to mid](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:15)
- [wide boundary is inclusive at 5 point 6](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:20)
- [landscape boundary is inclusive at f 8](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:28)
- [blur gate span is positive for every hint](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:36)
- [landscape has widest gate window and lowest threshold](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:44)
- [only landscape overrides salient weight and damps blur](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ApertureHintTests.swift:54)

### BurstAnalysisCoordinatorTests (8)

[BurstAnalysisCoordinatorTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift)

- [compatible cache hit returns remapped snapshot and review state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:10)
- [artifact digest mismatch rejects derived cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:42)
- [legacy candidate is remapped before import decision](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:67)
- [superseded cache preparation returns no result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:109)
- [review restoration follows membership rather than group id](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:133)
- [fresh orchestration preserves progress ranks and saves an immutable snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:189)
- [stale generation cannot apply or save a computed result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:249)
- [coordinator owns generation task and progress lifecycle](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTests.swift:280)

### BurstAnalysisPipelineValuesTests (3)

[BurstAnalysisPipelineValuesTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisPipelineValuesTests.swift)

- [pipeline request equals the legacy input snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisPipelineValuesTests.swift:9)
- [pipeline request remains an immutable configuration snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisPipelineValuesTests.swift:47)
- [pipeline result equality covers cache diagnostics and restored state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisPipelineValuesTests.swift:71)

### BurstCatalogPreparationPresentationTests (3)

[BurstCatalogPreparationPresentationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstCatalogPreparationPresentationTests.swift)

- [semantic indexing is the first visible stage](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstCatalogPreparationPresentationTests.swift:7)
- [sharpness calibration is visible even before scoring begins](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstCatalogPreparationPresentationTests.swift:32)
- [burst grouping follows completed indexing and sharpness stages](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstCatalogPreparationPresentationTests.swift:53)

### BurstWorkspaceSessionModelTests (2)

[BurstWorkspaceSessionModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstWorkspaceSessionModelTests.swift)

- [sliding window stays bounded around selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstWorkspaceSessionModelTests.swift:8)
- [group reset clears presentation and restores viewport](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstWorkspaceSessionModelTests.swift:16)

### CacheAccountingConcurrencyTests (3)

[CacheAccountingConcurrencyTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheAccountingConcurrencyTests.swift)

- [Concurrent replacements count one live entry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheAccountingConcurrencyTests.swift:7) — parameterized
- [Concurrent clear and insert leave consistent accounting](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheAccountingConcurrencyTests.swift:29) — parameterized
- [Evictions update the owning cache rather than the singleton](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheAccountingConcurrencyTests.swift:58) — parameterized

### CacheCounterTests (2)

[CacheCounterTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheCounterTests.swift)

- [replacing cache key updates manual counters](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheCounterTests.swift:9) — parameterized
- [clear caches resets live usage](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CacheCounterTests.swift:32)

### CatalogConcurrencyTests (3)

[CatalogConcurrencyTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogConcurrencyTests.swift)

- [Old sort cannot publish or finish a newer sort](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogConcurrencyTests.swift:8)
- [Cancelled or catalog-stale sort cannot publish](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogConcurrencyTests.swift:43) — parameterized
- [Abort invalidates a pending transition even when persistence fails](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogConcurrencyTests.swift:68) — parameterized

### CatalogLifecycleCoordinatorTests (4)

[CatalogLifecycleCoordinatorTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogLifecycleCoordinatorTests.swift)

- [Superseded persistence completion cannot act or clear the new transition](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogLifecycleCoordinatorTests.swift:7) — parameterized
- [Persistence failure restores selection only while still selected](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogLifecycleCoordinatorTests.swift:49) — parameterized
- [Cancelled load retains access until its worker returns](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogLifecycleCoordinatorTests.swift:67)
- [Coordinator destruction releases its active grant](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CatalogLifecycleCoordinatorTests.swift:94)

### CombinedReviewFeatureTests (28)

[CombinedReviewFeatureTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift)

- [malformed crop and report are repaired with charged attempts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:10)
- [prohibited crop criterion abstains while valid siblings survive without repair](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:23)
- [synthesis preserves crop and overview evidence without metric references or copied examples](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:41)
- [invalid exposure selection retains grounded coverage and restores its substitution](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:77)
- [degraded review keeps crops grounded and inspectable](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:98)
- [SAM and technical scorer supply separate measured evidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:121)
- [camera AF point reaches combined measurement and removes unavailable warning](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:144)
- [real scorer metadata survives restore and stale semantics cannot resume](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:161)
- [diagnostics and unsynthesized summaries survive export restore within per-run caps](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:225) — parameterized
- [malformed crop output is a failure and cannot become detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:276)
- [unknown report reference causes explicit partial report](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:287)
- [cancellation retains completed overview and resume spends no free retry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:296)
- [stored results restore without new inference and changed files refuse resume](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:323)
- [region settings are frozen and compact retention is explicit](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:340)
- [structured responses reject changed IDs and unsupported eye detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:353)
- [lease stays reserved until worker acknowledges invalidation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:361)
- [source refusal explains preview rerun and resume keeps saved source](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:372)
- [complete cleanup removes review storage and history and allows a fresh run](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:400)
- [cleanup refuses an active review reservation without deleting files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:423)
- [selection reviews every image before unrelated synthesis and restores without inference](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:436)
- [missing image stage cannot prevent other reports or force comparison](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:472)
- [comparison rejects subject image swaps and accepts supported ties](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:488)
- [eight image comparison preserves mandatory context coverage](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:519)
- [deep ties use capped matched pairs without overriding the selection tie](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:544) — parameterized
- [board records full frame transforms in stable image order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:573)
- [selection budget preserves mandatory synthesis and fair crop limits](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:582)
- [preflight replaces incompatible RAW setting before creating a run](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:612)
- [invalid criteria and selection are preparation status rather than review errors](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewFeatureTests.swift:629)

### CombinedReviewPresentationTests (6)

[CombinedReviewPresentationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift)

- [review layouts fit narrow and desktop widths](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:9) — parameterized
- [selected photo never inherits another photos review](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:45)
- [incomplete review keeps conflicts uncertainty and omitted coverage visible](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:53)
- [failed synthesis shows available observations without promoting measurements to findings](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:72)
- [finding links to its cited crop rather than the first region](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:83)
- [full record round trips exact measurements and all original limitations](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewPresentationTests.swift:97)

### CombinedReviewRealModelTests (3)

[CombinedReviewRealModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewRealModelTests.swift)

- [installed Qwen produces a bounded inspectable review](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewRealModelTests.swift:14) — opt-in: RAWCULL_COMBINED_REVIEW_RUN
- [selected ARWs complete full model review with criterion coverage](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewRealModelTests.swift:61) — opt-in: RAWCULL_COMBINED_SIX_RUN
- [six real Sony sources retain terminal reports and a bounded comparison](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CombinedReviewRealModelTests.swift:160) — opt-in: RAWCULL_COMBINED_SELECTION_RUN

### ComparisonGridDisplayStateTests (7)

[ComparisonGridDisplayStateTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift)

- [load key ignores selection changes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:49)
- [rapid selection changes update only the selected presentation value](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:60)
- [files resolve displayed comparison IDs in order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:72)
- [finalist focus uses recommended and second best IDs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:93)
- [finalist focus falls back to first four comparison IDs without burst result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:113)
- [selected comparison file is nil outside displayed files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:126)
- [missing comparison IDs leave an empty presentation and stable empty load key](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridDisplayStateTests.swift:135)

### ComparisonGridImageCoordinatorTests (4)

[ComparisonGridImageCoordinatorTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridImageCoordinatorTests.swift)

- [reload forwards the selected source for only the requested file](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridImageCoordinatorTests.swift:49)
- [cancelling a bulk load rejects the in flight result and stops later files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridImageCoordinatorTests.swift:70)
- [out of order reload completion accepts only the newest generation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridImageCoordinatorTests.swift:98)
- [bulk completion rejects work superseded by a reload](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridImageCoordinatorTests.swift:120)

### ComparisonGridNavigationTests (12)

[ComparisonGridNavigationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift)

- [left and right arrows move previous and next](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:6)
- [invalid current index returns nil](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:31)
- [four item navigation preserves linear boundaries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:50) — parameterized
- [single item comparison cannot navigate](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:75) — parameterized
- [printable shortcuts are resolved from characters before hardware key code](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:84)
- [non printable key codes resolve linear navigation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:90)
- [printable rating and toggle shortcuts resolve from characters](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:99)
- [Z resolves to actual-pixels inspection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:118) — parameterized
- [burst review shortcuts resolve navigation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:126)
- [window contains previous current and next frame](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:142)
- [window contracts at burst boundaries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:147)
- [window is always bounded and contains the selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonGridNavigationTests.swift:153)

### ComparisonImageAnalysisSourceTests (5)

[ComparisonImageAnalysisSourceTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift)

- [thumbnail sharpening changes display but not analysis pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift:8)
- [thumbnail source uses unsharpened pixels when sharpening is disabled](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift:23)
- [thumbnail source falls back when sharpening produces no image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift:38)
- [embedded JPG displays extracted pixels but analyzes thumbnail pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift:52)
- [embedded JPG falls back to extracted pixels when thumbnail is unavailable](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonImageAnalysisSourceTests.swift:66)

### ComparisonSessionModelTests (6)

[ComparisonSessionModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift)

- [lifecycle activates and cancels injected image services](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:152)
- [selection intents use the injected narrow selection boundary](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:167)
- [presentation reuses display mapping and owns finalist focus](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:184)
- [image intents route through the injected image service](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:224)
- [newer reload wins when an older request finishes last](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:244)
- [cancellation prevents an in flight reload from publishing](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ComparisonSessionModelTests.swift:280)

### CopyBookmarkStoreTests (5)

[CopyBookmarkStoreTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift)

- [missing and corrupt destination bookmarks fail without acquiring access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift:7)
- [failed replacement preserves the saved destination](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift:29)
- [saving a destination replaces its bookmark and releases access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift:57)
- [stale bookmark refreshes under access and releases once](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift:87)
- [destination access denial does not change its bookmark](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyBookmarkStoreTests.swift:127)

### CopyCompletionTests (3)

[CopyCompletionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyCompletionTests.swift)

- [runtime errors and cancellation survive process termination](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyCompletionTests.swift:9)
- [real rsync completion reports success or missing source failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyCompletionTests.swift:33) — parameterized
- [result title uses captured operation mode](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CopyCompletionTests.swift:95) — parameterized

### CullingGridCoordinatorTests (25)

[CullingGridCoordinatorTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift)

- [session commands preserve manual override and independent restored states](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:78)
- [review session mutations reach facade observers and invalidate grid results](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:106)
- [burst undo restores ratings and consumes session entry without reverting review state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:150)
- [thumbnail workspace follows the current catalog across view switches](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:176)
- [normal command and shift selection preserve existing grid behavior](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:190)
- [hidden files are pruned from selection and action targets](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:250)
- [badge selection counts and matching ids come from burst and saliency labels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:273)
- [render cache filters visible burst files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:304)
- [burst view lists every file in ranked priority order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:322)
- [burst view appends every unranked file in original order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:337)
- [render cache key tracks complete membership and score availability](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:352)
- [sharpness score revision advances for replacement and incremental mutation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:371)
- [thumbnail source flags are pruned and initialized for comparison files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:386)
- [review queue policy includes every pending group and excludes completed states](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:400)
- [view model filters burst groups by review queue state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:451)
- [next burst navigation follows the review queue and skips single images](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:492)
- [next burst navigation defers an unrated current group before advancing](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:530)
- [next burst navigation does not defer a group with any rating](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:551) — parameterized
- [sharpness-only records do not prevent deferring an unrated group](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:579)
- [burst review summary is the source of truth for groups and live review states](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:609)
- [single image category excludes every multi-image burst](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:688)
- [combined single images preserve workflow states without choosing a winner](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:705)
- [review and defer actions toggle back to persisted neutral state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:735)
- [reviewed and deferred groups leave the needs review queue immediately](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:767)
- [singleton groups have a separate queue from all bursts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridCoordinatorTests.swift:801)

### CullingGridProjectionTests (2)

[CullingGridProjectionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridProjectionTests.swift)

- [selection and score-value changes reuse the projection while membership changes rebuild](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridProjectionTests.swift:13)
- [rating review-group and saliency mutations invalidate cached projections](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingGridProjectionTests.swift:35)

### CullingModelTests (21)

[CullingModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift)

- [scored photo stays unrated while explicit keeper is rated](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:12)
- [restoring unrated state preserves scoring metadata](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:30)
- [corrupt load blocks mutations and preserves in-memory state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:52)
- [hasExplicitRatings requires a non-nil rating in the requested catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:71)
- [explicit rating count excludes scoring-only records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:89)
- [cancelling similarity ranking stops its owned distance helper](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:103)
- [disarming similarity ranking preserves the last completed order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:138)
- [find similar indexes a fresh catalog before ranking](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:175)
- [similarity indexing cancellation stops structured embedding workers](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:198)
- [superseded similarity indexing cannot commit or clear newer run state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:223)
- [updateRating creates catalog record and debounced save snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:253)
- [failed persistence remains dirty and retry saves newest snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:271)
- [updateRatings and applyRatings upsert existing records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:297)
- [mergeScoringResults preserves ratings and writes scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:318)
- [resetSavedFiles clears records for catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:339)
- [manual winner override requires exact membership](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:355)
- [upsert preserves same winner for different member sets](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:382)
- [prune removes overrides with missing winner or member](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:407)
- [FileRecord equality includes persisted sharpness metadata](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:426)
- [SavedFiles equality includes records and burst overrides](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:454)
- [updateRating recreates records after reset leaves empty catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingModelTests.swift:471)

### DeepAIReviewFeatureTests (8)

[DeepAIReviewFeatureTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift)

- [Feature publishes a typed completed result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:13)
- [Cancelling Deep Review cancels the owned in-process task](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:34)
- [Cancelling Deep Review retains candidates that already completed](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:57)
- [Controller owns availability and request construction](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:76)
- [Controller represents checking unavailable and cancelled states](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:115)
- [Prompt policy and candidate limit match burst Deep Review](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:162)
- [Deep Review preview loads the selected prompt from disk only](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:180)
- [Subject-mask scorer measures detail only inside the mask](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewFeatureTests.swift:243)

### DeepAIReviewMaskOutlineRendererTests (2)

[DeepAIReviewMaskOutlineRendererTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift)

- [filled mask becomes a transparent contour](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift:6)
- [disconnected subjects each receive a contour](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift:21)

### DiskCacheAndScanAdmissionTests (20)

[DiskCacheAndScanAdmissionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift)

- [URL decode applies EXIF orientation to pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:179) — parameterized
- [URL decode applies right orientation to portrait dimensions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:204)
- [URL decode keeps up orientation dimensions unchanged](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:222)
- [data decode applies right orientation to portrait dimensions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:240)
- [bounded thumbnail decode applies right orientation to portrait dimensions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:250)
- [bounded thumbnail decode keeps up orientation dimensions unchanged](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:268)
- [source orientation can be baked into a decoded image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:286)
- [embedded preview uses its own orientation before source orientation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:305)
- [embedded preview falls back to source orientation when missing its own orientation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:327)
- [save and load thumbnail JPEG from isolated disk cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:351)
- [load thumbnail JPEG applies cached orientation metadata](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:371)
- [saving same source overwrites existing thumbnail cache entry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:387)
- [pruneCache removes old thumbnail files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:411)
- [missing full size JPEG entries are clean cache misses](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:435)
- [save contains and load full size JPEG from isolated disk cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:450)
- [load full size JPEG applies cached orientation metadata](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:469)
- [saving same source overwrites existing full size cache entry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:484)
- [embedded and developed JPEGs use separate cache entries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:503)
- [pruneCache removes old full size JPEG files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:526)
- [preload from disk cache admits only to grid cache not memory cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/DiskCacheAndScanAdmissionTests.swift:547)

### ExecuteCopyFilesStartupTests (8)

[ExecuteCopyFilesStartupTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift)

- [empty tagged list fails before copy starts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:8)
- [empty rated list fails before copy starts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:22)
- [missing view model fails before copy starts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:36)
- [include list paths are unique and outside Documents](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:53)
- [cleanup removes generated include list](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:78)
- [copy list is nul separated for literal rsync files-from matching](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:93)
- [selected catalog does not require a source bookmark](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:118) — parameterized
- [obsolete source bookmark cannot override the selected catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExecuteCopyFilesStartupTests.swift:157)

### ExtractJPGsSelectionTests (12)

[ExtractJPGsSelectionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift)

- [multi-selected thumbnails win over single selected image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:32)
- [single selected image is used when there is no thumbnail multi-selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:51)
- [no selected image blocks extraction](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:66)
- [denied destination access blocks extraction and presents error](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:83)
- [present extract jpgs defaults destination to selected source only when empty](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:103)
- [present extract jpgs preserves destination outside source catalogs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:127)
- [failed exports still advance completed count and report every failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:151)
- [embedded export writes natural jpg name in destination catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:182)
- [demosaiced export writes suffixed jpg name in destination catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:196)
- [concurrent exports preserve existing photographs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:210) — parameterized
- [uppercase camera JPEG is preserved](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:238)
- [save propagates destination write failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ExtractJPGsSelectionTests.swift:252)

### FocusImageResolutionPolicyTests (1)

[FocusImageResolutionPolicyTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusImageResolutionPolicyTests.swift)

- [analysis preserves decoded pixels for every orientation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusImageResolutionPolicyTests.swift:8) — parameterized

### FocusNumericHelperTests (13)

[FocusNumericHelperTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift)

- [robust tail score empty returns nil](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:17)
- [robust tail score uniform returns zero](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:22)
- [robust tail score dense edges full density factor](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:31)
- [robust tail score sparse edges scores low](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:44)
- [robust tail score dense edges scores higher than sparse](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:58)
- [micro contrast empty returns zero](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:75)
- [micro contrast uniform returns zero](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:80)
- [micro contrast alternating known variance](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:86)
- [micro contrast ignores non finite](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:94)
- [robust tail score is scale proportional](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:108)
- [focus failure classifier flags motion blur when all regions are weak](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:121)
- [focus failure classifier flags missed focus when subject trails frame](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:132)
- [focus failure classifier stays neutral for strong subject](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/FocusNumericHelperTests.swift:143)

### HistogramLoadingTests (6)

[HistogramLoadingTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift)

- [nil image clears published bins](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:9)
- [image conversion failure clears published bins](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:21)
- [successful calculation publishes normalized bins](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:33)
- [bounds histogram sample while preserving aspect ratio](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:43)
- [sampled histogram preserves dominant luminance values](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:53)
- [slow cancelled image cannot overwrite fast replacement](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/HistogramLoadingTests.swift:65)

### ISOScalingTests (5)

[ISOScalingTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift)

- [below 800 is flat at 1 point 0](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift:15)
- [mid range ramps to 1 point 6 at 3200](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift:22)
- [high range caps at 2 point 2](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift:31)
- [monotonically non decreasing across range](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift:38)
- [high ISO is less aggressive than old sqrt formula](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ISOScalingTests.swift:47)

### ImageReviewFeatureDependenciesTests (2)

[ImageReviewFeatureDependenciesTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewFeatureDependenciesTests.swift)

- [selection policy uses only focused selection capability](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewFeatureDependenciesTests.swift:25)
- [rating presentation uses focused rating capability](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewFeatureDependenciesTests.swift:45)

### ImageReviewPoliciesTests (6)

[ImageReviewPoliciesTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift)

- [RAW failure restores the previous source and produces presentation inputs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:7)
- [viewport policies clamp each surface to its own limits](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:24)
- [keyboard input resolves to shared semantic actions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:37)
- [rating policy distinguishes unrated keeper reject and stars](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:51)
- [focus request identity rejects cancellation supersession and stale content](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:60)
- [subject outline context participates in request identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageReviewPoliciesTests.swift:82)

### ImageSourceSelectionStateTests (5)

[ImageSourceSelectionStateTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift)

- [selection can start with an extracted JPEG](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift:8)
- [extraction source toggles against thumbnail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift:15) — parameterized
- [disabled RAW source ignores toggle](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift:26)
- [RAW failure restores previous source and disables RAW](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift:39)
- [new image clears RAW disable while preserving selected source](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ImageSourceSelectionStateTests.swift:51)

### ItemizedOutputTests (4)

[ItemizedOutputTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ItemizedOutputTests.swift)

- [Classifies rsync itemized output](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ItemizedOutputTests.swift:11)
- [Supports openrsync itemized output](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ItemizedOutputTests.swift:27)
- [Ignores empty and summary lines](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ItemizedOutputTests.swift:36)
- [Failed stats parsing keeps safe defaults](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ItemizedOutputTests.swift:44)

### LoupeImageKeyActionTests (7)

[LoupeImageKeyActionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift)

- [J resolves to embedded JPG](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:8) — parameterized
- [R resolves to developed RAW](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:13) — parameterized
- [F resolves to focus mask](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:18) — parameterized
- [S resolves to Deep Review subject outline](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:23) — parameterized
- [A resolves to autofocus points](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:28) — parameterized
- [E resolves to metadata panel](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:33) — parameterized
- [Z resolves to actual-pixels inspection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeImageKeyActionTests.swift:38) — parameterized

### LoupeSessionModelTests (2)

[LoupeSessionModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeSessionModelTests.swift)

- [new source request rejects stale completion](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeSessionModelTests.swift:9)
- [reset cancels work and clears owned previews](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/LoupeSessionModelTests.swift:27)

### MemoryViewModelTests (1)

[MemoryViewModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/MemoryViewModelTests.swift)

- [memory stats update populates coherent values](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/MemoryViewModelTests.swift:9)

### ObjectAnalysisBoundaryTests (22)

[ObjectAnalysisBoundaryTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift)

- [Retry feedback names mismatched claim counts and missing focus evidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:8) — parameterized
- [Retry feedback explains invalid visibility and vague focus](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:26)
- [Undecodable feedback preserves typed errors and supplies a default](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:40)
- [Focus and claims require their own crop evidence and unverified expression abstains](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:47)
- [Sharp focus accepts equivalent resolved detail wording](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:69) — parameterized
- [Sharp focus still rejects unsupported or contradictory detail wording](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:81) — parameterized
- [Soft focus accepts negated sharpness without admitting positive sharpness](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:97) — parameterized
- [Retry feedback identifies focus contradictions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:107)
- [Final retry abstains from captured butterfly focus wording](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:119)
- [Final retry abstains when focus evidence is explicitly null](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:135) — parameterized
- [Final focus abstention preserves supported objects](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:152)
- [Focus abstention preserves paired evidence and unaffected object ownership](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:157)
- [Focus abstention still requires explicit nullable fields](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:194) — parameterized
- [Final focus abstention rejects unrelated invalid data](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:204) — parameterized
- [Automatic concepts normalize and deduplicate](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:218)
- [Invalid discovery is surfaced](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:224)
- [Manual concepts reject empty entries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:233)
- [Assessment accepts only rendered object IDs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:240)
- [Wrapped JSON remains strict](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:252)
- [Assessment rejects invalid confidence and duplicate object IDs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:266)
- [Captured assessment shape normalizes singular text lists](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:294)
- [Numeric board IDs normalize but still require an exact board match](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisBoundaryTests.swift:315)

### ObjectAnalysisFeatureTests (9)

[ObjectAnalysisFeatureTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift)

- [AF point and highlighted focus edges map to the matching object](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:13)
- [Near-identical cross-concept masks merge and retain alias](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:56)
- [Review board rejects an object whose numbered crop is unavailable](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:88)
- [Grayscale instance mask becomes a transparent contour](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:103)
- [Model removal cancels an in-flight object result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:122)
- [Manual analysis reports no matching objects without asking Qwen for a board](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:150)
- [Automatic analysis discovers, segments, and assesses one object](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:176)
- [Invalid assessment stays retryable and reuses cached segmentation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:209)
- [Schema retry repairs assessment without repeating segmentation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisFeatureTests.swift:237)

### ObjectAnalysisRealModelProbeTests (1)

[ObjectAnalysisRealModelProbeTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisRealModelProbeTests.swift)

- [probe one photo](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ObjectAnalysisRealModelProbeTests.swift:12) — opt-in: OBJECT_PROBE_IMAGE

### OverlayPresentationModelTests (3)

[OverlayPresentationModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/OverlayPresentationModelTests.swift)

- [cancelled focus request cannot replace the new source](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/OverlayPresentationModelTests.swift:8)
- [cancelling debounce prevents focus work](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/OverlayPresentationModelTests.swift:37)
- [obsolete outline completion cannot clear A newer image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/OverlayPresentationModelTests.swift:53)

### PerFileAnalysisArtifactStoreTests (6)

[PerFileAnalysisArtifactStoreTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift)

- [CLIP and Vision artifacts round-trip independently](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:8)
- [Source, backend, preview size, and pipeline changes are cache misses](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:51)
- [A corrupt record is isolated from valid records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:175)
- [Usage and clear operate on individual records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:227)
- [Replacement is atomic and cancellation preserves completed records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:253)
- [Cancellation during persistence retains only completed records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PerFileAnalysisArtifactStoreTests.swift:334)

### PhotoAIKitSimilarityMigrationTests (15)

[PhotoAIKitSimilarityMigrationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift)

- [CLIP retains successful artifacts and excludes failed images](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:407)
- [CLIP partial indexing captures image decoding failures](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:455)
- [CLIP reindexes only missing or stale artifacts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:489)
- [Durable indexing survives relaunch and reindexes only added or modified files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:541)
- [Vision and CLIP artifacts coexist without cross-loading](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:641)
- [Partial indexing persists successes and isolates invalid payloads](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:687)
- [Legacy burst artifacts migrate once into the per-file store](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:768)
- [Non-finite CLIP output retries once then reloads the provider](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:814)
- [Persistent non-finite CLIP output is excluded after provider reload](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:863)
- [Burst grouping excludes unindexed images and preserves hard boundaries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:914)
- [PhotoAIKit Vision indexing produces complete reusable artifacts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:939)
- [RawCull ranking policy is preserved behind the PhotoAIKit boundary](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:995)
- [Legacy burst artifacts are rejected and the current schema rebuild loads](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:1025)
- [Partial CLIP cache excludes files without validated artifacts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:1099)
- [PhotoAIKit Vision indexing and ranking benchmark](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAIKitSimilarityMigrationTests.swift:1181)

### PhotoAnalysisKitIntegrationTests (2)

[PhotoAnalysisKitIntegrationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAnalysisKitIntegrationTests.swift)

- [RawCull focus model analyzes through package Metal pipeline](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAnalysisKitIntegrationTests.swift:8)
- [RawCull breakdown preserves app scoring source](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/PhotoAnalysisKitIntegrationTests.swift:27)

### QuitRecoveryTests (1)

[QuitRecoveryTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QuitRecoveryTests.swift)

- [failed save offers recovery and replies exactly once](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QuitRecoveryTests.swift:7) — parameterized

### QwenFeatureTests (20)

[QwenFeatureTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift)

- [Local Qwen model answers a general vision request](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:11) — opt-in: QWEN_PHASE3_BUNDLE, QWEN_PHASE3_IMAGE
- [Input capabilities are absent before validation and after clear](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:41)
- [Qwen generation gate serializes and cancels queued work](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:76)
- [Assessment instruction requires evidence and permits abstention](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:101)
- [General Qwen request rejects an invalid token cap](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:111)
- [Structured assessment decodes JSON wrapped in model prose](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:126)
- [Structured assessment rejects scores outside the schema](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:155)
- [Free-form Qwen response counts as a successful result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:164)
- [Response decoder preserves nonempty Qwen prose](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:177)
- [Response decoder uses structured assessment when valid](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:186)
- [Response decoder retains invalid structured output as rejected](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:200)
- [Response decoder rejects an empty Qwen response](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:209)
- [Unsupported criterion abstains without inventing an overall score](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:216)
- [Qwen inference runtime validates a compatible Core AI bundle](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:241)
- [Qwen inference runtime rejects a text-only Qwen model](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:268)
- [Analysis keeps prior results and only processes newly selected files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:283)
- [Batch retains catalog access for later files after navigation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:306)
- [Rejected oversized assessment retries once and reports field lengths](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:345)
- [Schema retry accepts repaired Qwen assessment](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:358)
- [arbitration waits for workers cancelled before the combined run](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/QwenFeatureTests.swift:417)

### RawCullAIModelDownloadsTests (11)

[RawCullAIModelDownloadsTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift)

- [Production catalog includes only configured models](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:8)
- [Coordinator blocks download before invoking its service](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:83)
- [Unconfigured managed service avoids Background Assets access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:123)
- [affected macOS 27 Background Assets regressions are detected](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:138)
- [Affected runtime avoids Background Assets access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:167)
- [Production models expose the Background Assets runtime failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:187)
- [Model management presents localized download failures](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:219)
- [Verified acceptance gates and unlocks a ready download](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:257)
- [Model management presents progress installation and removal](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:319)
- [Cancelling model management download restores coordinator state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:385)
- [A changed licence checksum invalidates prior acceptance](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelDownloadsTests.swift:428)

### RawCullAIModelRuntimeTests (9)

[RawCullAIModelRuntimeTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift)

- [AI paths retain RawCull's canonical data namespaces](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:9)
- [Model runtime reports the complete Phase 1 capability surface](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:45)
- [Saved burst scan reads existing Vision cache evidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:152)
- [Model validation is reused until candidate metadata changes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:225)
- [Missing and corrupt model resources recover after restoration](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:275)
- [Cancelling Settings refresh cancels its evidence scan](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:328)
- [CLIP enablement and exclusive model selection persist](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:355)
- [blocked segmenters are excluded and rejected](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:424)
- [Combined Review requires memory guidance before enabling](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullAIModelRuntimeTests.swift:453) — parameterized

### RawCullIntelligenceRuntimeTests (8)

[RawCullIntelligenceRuntimeTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift)

- [Application assembly shares one stable intelligence object graph](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:10)
- [Settings configuration updates the view model that shares runtime models](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:64)
- [Runtime shares one feature across similarity and semantic configuration](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:100)
- [Applying current services is a no-op for identity and hydration tasks](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:153)
- [Older configuration cannot replace a newer runtime identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:184)
- [Segmentation-only configuration preserves similarity work](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:228)
- [Configuration switch supersedes in-flight similarity hydration](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:268)
- [Weak typed configuration edges do not retain application state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullIntelligenceRuntimeTests.swift:330)

### RawCullSemanticSearchTests (13)

[RawCullSemanticSearchTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift)

- [Semantic artifact handoffs preserve merge rules and observable facade revisions](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:296)
- [Semantic configuration replacement rejects an in-flight hydration completion](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:347)
- [Literal query encodes once, excludes Vision, isolates failures, and ranks deterministically](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:373)
- [Empty query and Vision-only snapshots are distinct typed failures](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:413)
- [Large searches show the top twenty and can expand all results](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:441)
- [Show all updates the admitted RawCull grid without rerunning CLIP](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:503)
- [Clear restores the catalog without discarding the scoped burst index](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:547)
- [Semantic selection scopes existing burst groups](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:643)
- [Preparing a reindex resets selection and restores the full catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:708)
- [A superseded query cannot overwrite the newer result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:747)
- [Cancellation returns to idle and ignores a late provider response](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:790)
- [Cached-only ranking composes with rating filters and clear restores catalog order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:829)
- [Partial index, empty index, provider failure, and model switch remain distinct](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchTests.swift:879)

### RawCullSemanticSearchUITests (4)

[RawCullSemanticSearchUITests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchUITests.swift)

- [capability controls](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchUITests.swift:44)
- [indexing state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchUITests.swift:74)
- [result states](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchUITests.swift:106)
- [cancellation and clear state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSemanticSearchUITests.swift:162)

### RawCullSimilarityFeatureTests (4)

[RawCullSimilarityFeatureTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSimilarityFeatureTests.swift)

- [Feature and semantic search share the exact model and feature](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSimilarityFeatureTests.swift:18)
- [Presentation hides backend descriptors and model progress](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSimilarityFeatureTests.swift:32)
- [Backend replacement resets burst state before replacing the model service](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSimilarityFeatureTests.swift:57)
- [Catalog hydration rejects a stale catalog identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullSimilarityFeatureTests.swift:76)

### RawCullVerifyTestsDataRaceDetectionTests (2)

[RawCullVerifyTestsDataRaceDetectionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift)

- [cache supports concurrent nonisolated reads and writes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift:16) — parameterized
- [Extreme concurrent load reveals no data races](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift:52)

### RawCullVerifyViewModelSecurityScopeTests (7)

[RawCullVerifyViewModelSecurityScopeTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift)

- [Worker grant survives switching roots and releases exactly once](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:8)
- [starting same active catalog does not duplicate security scoped access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:32)
- [starting another catalog stops previous security scoped access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:54)
- [stopping active catalog is idempotent](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:78)
- [failed start leaves no active security scoped access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:97)
- [catalog cancellation stops active security scoped access](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:115)
- [empty catalog scan clears active load state and security scope](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift:133)

### RawCullViewModelCullingTests (41)

[RawCullViewModelCullingTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift)

- [AF scores persist separately and legacy records remain unmeasured](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:12)
- [rebuildRatingCache populates ratings and tagged filenames for selected catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:35)
- [passesRatingFilter distinguishes rejected keepers and star ratings](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:53)
- [preselectFirstVisibleFileByName selects alphabetically first visible file](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:80)
- [preselectFirstVisibleFileByName replaces previous selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:94)
- [preselectFirstVisibleFileByName clears selection when no files are visible](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:110)
- [enabling AF sharpness sorting selects strongest AF detail despite combined scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:123)
- [disabling sharpness sorting preserves current selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:142)
- [burst analysis targets selected thumbnails before rating filter](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:156)
- [burst analysis targets exact active star rating](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:170)
- [burst analysis keeps full catalog for unscoped filters](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:186)
- [burst analysis orders shots by capture date with file-date fallback](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:210)
- [sharpness scoring targets selected thumbnails before rating filter](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:225)
- [sharpness scoring targets active star rating in visible order](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:240)
- [sharpness scoring falls back to filename sorted catalog for non-star filters](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:258)
- [sharpness scoring appends hidden selected files after visible selected files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:283)
- [calibrateAndScoreCurrentCatalog scores and persists only target files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:299)
- [extractRatedfilenames returns files at or above requested rating](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:340)
- [bulk updateRating updates culling model and cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:357)
- [rating mutations refresh the active rating-filter count](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:370)
- [clear all culling state synchronizes caches filters and persisted data](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:396)
- [applying Deep Review winner rates it three stars and marks group reviewed](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:428)
- [updateRatingAndAdvance rates current file and selects next visible file](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:468)
- [updateRatingAndAdvance marks active burst reviewed](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:486) — parameterized
- [updateRatingAndAdvance leaves last visible file selected](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:506)
- [updateRatingAndAdvance without catalog leaves rating and selection unchanged](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:522)
- [updateRatingAndAdvance with file outside visible order does not change selection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:537)
- [clearCurrentCatalogCullingState allows rating same catalog again](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:554)
- [burst signatures are order independent and catalog relative](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:575)
- [cached review state restores by signature after file id remap](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:602)
- [cached review state ignores matching group id with changed membership](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:629)
- [cancelled burst analysis cannot apply a late cache result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:656)
- [catalog cancellation resets all burst analysis state](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:702)
- [burst cache rejects a different similarity signature](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:727)
- [restoring an existing full burst index never starts scoring or indexing](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:767)
- [burst cache rejects groups produced by the previous timestamp algorithm](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:809)
- [burst cache reports usage and clears every catalog snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:840)
- [burst cache round trips a large snapshot off the main actor](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:871)
- [review state persistence keeps completed analysis scope](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:929)
- [live regroup review state follows membership instead of group id](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:980)
- [live regroup drops state when reused group id has changed membership](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawCullViewModelCullingTests.swift:1007)

### RawImageLoadingIntegrationTests (10)

[RawImageLoadingIntegrationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift)

- [thumbnail request promotes source decode to memory for later hits](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:106)
- [thumbnail request decodes a replacement written at the same path](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:129)
- [full size preview loader saves extracted preview and reuses disk cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:163)
- [full size preview loader caches original embedded JPEG without recoding](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:182)
- [full size preview loader prefers sidecar jpg before raw extraction](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:209)
- [cancelled full size preview load does not save extracted image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:230)
- [scan files uses loader metadata for exif and focus point](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:258)
- [embedded export ignores sidecars and preserves standalone JPEG bytes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:331)
- [missing embedded pixels do not fall back to a sidecar](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:350)
- [helper providers read only their own temporary disk cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/RawImageLoadingIntegrationTests.swift:361)

### ReleaseMetadataTests (5)

[ReleaseMetadataTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift)

- [app and extension metadata are aligned](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift:8)
- [README documents every exact resolved package pin](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift:103)
- [model manifest catalog and destinations agree](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift:132)
- [background assets metadata is complete](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift:179)
- [model provenance status and notice hashes are complete](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReleaseMetadataTests.swift:207)

### ReviewDiagnosticsTests (21)

[ReviewDiagnosticsTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift)

- [optional shapes are isolated independently while malformed core still fails](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:8)
- [ambiguous aliases and invalid optional points abstain while oversized core text still fails](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:33)
- [scene conflicts span registered subjects but subject detail conflicts remain local](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:48)
- [fallback target flag alone cannot establish subject detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:69)
- [overview rejects copied instructions and discards undiscovered optional context](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:79)
- [partial synthesis retains valid observations and reports rejected claims](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:90)
- [rejections preserve the failing decoder or guard without copying untrusted text](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:108)
- [grounding ownership runtime mask geometry budget and timeout remain distinct](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:137)
- [raw text retention is UTF8 bounded separate from findings reloadable and cleanable](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:161)
- [synthesis resolves one subject and rejects swapped or unrelated support](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:181)
- [absent unknown and unregistered crop targets cannot establish detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:204)
- [numeric summaries preserve distinct subject values and stale evidence abstains](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:234)
- [texture alias still requires one qualified subject crop](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:254)
- [prompt eligibility excludes unidentified crops and measurements from detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:294)
- [v14 technical claims cannot exceed their cited observation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:308)
- [technical excerpts preserve support and missing texture abstains](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:328)
- [criterion crops require nullable strings and keep anatomy outside observations](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:346)
- [criterion grounding prevents repeated prose and uncertainty becoming evidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:366)
- [criterion background blur uses its exact registered criterion boundary](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:386)
- [invalid selections recover validated priority rows without overriding null abstention](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:406)
- [null criteria preserve explicit abstention without contradictory flags](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewDiagnosticsTests.swift:429)

### ReviewImageSourceTests (14)

[ReviewImageSourceTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift)

- [source availability uses the same admission boundary as execution](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:12) — parameterized
- [orientation and source crops](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:21) — parameterized
- [coordinate and encoder round trips](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:61) — parameterized
- [clipping stable IDs and invalid bounds](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:87)
- [render isolation and lossless retention](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:108)
- [unsupported RAW fallback is explicit](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:132)
- [embedded loader never substitutes sidecar](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:151)
- [cancellation does not return source](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:166)
- [wide gamut ICC conversion](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:177)
- [HDR render is finite SDR](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:198)
- [bounded preview fallback preserves orientation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:230) — parameterized
- [large Sony source receives a bounded preview](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:246)
- [memory admission rejects before decode](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:253)
- [full source working set](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewImageSourceTests.swift:261)

### ReviewKeyboardScopeTests (5)

[ReviewKeyboardScopeTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift)

- [only anchored key window receives shortcuts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift:23)
- [command modifiers are left to app kit](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift:39) — parameterized
- [native controls and text own their input](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift:49)
- [anchor tracks window and detaches](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift:70)
- [attached sheet keeps keys](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewKeyboardScopeTests.swift:85)

### ReviewMaskProcessingTests (4)

[ReviewMaskProcessingTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskProcessingTests.swift)

- [background registration preserves producer diagnostics and deduplicated geometry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskProcessingTests.swift:8)
- [crop support matches original scans and invalidates cache when mask changes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskProcessingTests.swift:26)
- [retained inputs preserve grayscale foreground when eagerly decoded](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskProcessingTests.swift:43)
- [cancelled worker operation refuses a raster scan](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskProcessingTests.swift:58)

### ReviewMaskRegistrationTests (2)

[ReviewMaskRegistrationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskRegistrationTests.swift)

- [asymmetric edge foreground stays registered after EXIF normalization](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskRegistrationTests.swift:10) — parameterized
- [foreground retention separates avoidable truncation from source edge contact](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewMaskRegistrationTests.swift:45)

### ReviewPersistenceTests (8)

[ReviewPersistenceTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift)

- [rating a scored record sets its date and later scoring preserves it](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:8)
- [rerating an existing record replaces its tagging date](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:24)
- [unread store rejects edits and a flush loads rather than overwrites history](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:39)
- [concurrent initialization shares one read and blocks edits while loading](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:61)
- [corrupt initialization preserves the file and remains blocked until explicit retry](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:87)
- [repaired history refreshes ratings filters selection and copy admission](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:122)
- [archiving damaged history clears stale presentation even if saving the reset fails](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:153)
- [restoration publishes scores once and preserves first duplicate and metadata validation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewPersistenceTests.swift:185)

### ReviewRunContractTests (12)

[ReviewRunContractTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift)

- [budgets reserve coverage and count every attempt](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:7)
- [repairs have a separate finite allowance per image](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:31)
- [compatibility changes only consuming stages](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:44)
- [cancellation preserves independent observations and spent budget](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:55)
- [invalidation propagates through completed descendants](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:70)
- [manifests require every accepted image and acyclic dependencies](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:84)
- [atomic artifacts restore partial work and reject future schemas](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:97)
- [derived cache eviction preserves evidence and rejects traversal](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:132)
- [evidence claims cannot invent IDs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:144)
- [resume rebuilds compatibility instead of trusting saved fields](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:155)
- [latest run ignores filesystem modification dates and breaks creation ties](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:165)
- [word boundaries permit ordinary observations and uncertainty limitations](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewRunContractTests.swift:186)

### ReviewSubjectPriorityTests (5)

[ReviewSubjectPriorityTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift)

- [main rabbit precedes contextual flowers without using SAM confidence](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift:12)
- [primary mallard point must belong to registered foreground and ambiguity remains visible](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift:21)
- [overview priority cues require discovered concepts and normalized locations](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift:36)
- [overlay leaves background transparent and maps all source coordinates at different sizes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift:49)
- [inspection canvas renders aligned transparent foreground at two sizes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewSubjectPriorityTests.swift:62)

### ReviewViewBoundaryTests (4)

[ReviewViewBoundaryTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewViewBoundaryTests.swift)

- [zoom controls observe session viewport instead of unrelated loupe zoom](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewViewBoundaryTests.swift:12)
- [burst header observes catalog changes independently of viewport changes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewViewBoundaryTests.swift:31)
- [loupe image content observes source changes independently of inactive preview images](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewViewBoundaryTests.swift:46)
- [extracted review sections render at narrow and desktop widths](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ReviewViewBoundaryTests.swift:63) — parameterized

### SavedFilesJSONTests (6)

[SavedFilesJSONTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift)

- [reader distinguishes missing and corrupt stores](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:12)
- [second write preserves previous store as backup](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:38)
- [write creates Application Support directory and saved files JSON](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:59)
- [older saved files JSON decodes](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:83)
- [read loads saved files from Application Support URL](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:102)
- [read ignores old Documents file when Application Support file exists](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesJSONTests.swift:129)

### SavedFilesPresentationTests (4)

[SavedFilesPresentationTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesPresentationTests.swift)

- [Legacy missing fields have display fallbacks without inventing ratings](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesPresentationTests.swift:8)
- [Stored dates and rejected ratings survive presentation while sharpness is formatted](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesPresentationTests.swift:35)
- [Source mutations invalidate presentation reads and preserve selection identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesPresentationTests.swift:55)
- [Absent selections and missing record arrays have no rows or detail](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SavedFilesPresentationTests.swift:81)

### ScanAdmissionTests (2)

[ScanAdmissionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanAdmissionTests.swift)

- [scan bounds metadata reads and coalesces monotonic progress](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanAdmissionTests.swift:60)
- [cancelling a scan stops admission and drains admitted workers](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanAdmissionTests.swift:77)

### ScanAndExtractJPGsTests (1)

[ScanAndExtractJPGsTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanAndExtractJPGsTests.swift)

- [unsupported files are counted as processed](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanAndExtractJPGsTests.swift:18)

### ScanFilesSortAndFormatTests (9)

[ScanFilesSortAndFormatTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift)

- [sortFiles sorts by name ascending](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:32)
- [sortFiles sorts by date descending](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:49)
- [sortFiles sorts by date ascending](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:66)
- [sortFiles sorts by size ascending](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:83)
- [sortFiles filters search text case insensitively after sorting](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:100)
- [sortFiles can search by stem fragment](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:117)
- [sortFiles supports descending order for every field](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:134) — parameterized
- [sortFiles preserves input order when field values tie](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:155)
- [sortFiles handles empty and single-item input](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ScanFilesSortAndFormatTests.swift:172)

### SettingsPersistenceTests (3)

[SettingsPersistenceTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsPersistenceTests.swift)

- [save failure preserves edits and retry persists them](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsPersistenceTests.swift:7)
- [malformed load is observable and repaired settings can be retried](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsPersistenceTests.swift:27)
- [absent settings use defaults without presenting an error](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsPersistenceTests.swift:47)

### SettingsViewModelPersistenceTests (8)

[SettingsViewModelPersistenceTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift)

- [settings save and load round trips through isolated file](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:9)
- [save during initial load preserves persisted cache maximums](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:44)
- [legacy settings JSON defaults scoring photo type to auto and ignores badge toggles](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:74)
- [new settings use package focus mask morphology defaults](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:100)
- [extreme settings JSON decodes inside supported ranges](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:111)
- [save writes normalized settings](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:155)
- [asyncgetsettings returns value snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:190)
- [asyncgetsettings returns normalized value snapshot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SettingsViewModelPersistenceTests.swift:207)

### SharpnessScoringTests (16)

[SharpnessScoringTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift)

- [max score small set uses maximum not minimum](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:17)
- [max score large set uses P 90](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:35)
- [sharpness label maps threshold boundaries](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:48)
- [sharpness label clamps and handles invalid denominator](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:57)
- [auto photo type preserves current focus config](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:65)
- [photo type presets map to expected scoring emphasis](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:75)
- [scoring quality maps to compute cost and precision config](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:105)
- [scoring signature uses package analysis descriptor](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:132)
- [legacy scoring signature decodes as stale](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:154)
- [AF ranking uses center detail without background or saliency fallback](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:189)
- [AF ranking treats absent detail and invalid measurements as unknown](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:206) — parameterized
- [AF sorting preserves ties and places unknown measurements last](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:219)
- [legacy scores cannot enable AF sorting and AF measurements survive hydration](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:231)
- [batch AF scoring rejects sharp background around a textureless focus point](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:250)
- [loading cached burst AF evidence preserves best frame scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:273)
- [concurrent scoreFiles call awaits in flight scoring](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SharpnessScoringTests.swift:295)

### SmokeManifestIntegrityTests (2)

[SmokeManifestIntegrityTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SmokeManifestIntegrityTests.swift)

- [manifest is ordered unique and unchanged](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SmokeManifestIntegrityTests.swift:6)
- [every source smoke declaration has a suite selector](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SmokeManifestIntegrityTests.swift:14)

### SubjectMaskFocusRegressionTests (4)

[SubjectMaskFocusRegressionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SubjectMaskFocusRegressionTests.swift)

- [disjoint grayscale masks select different textures through PNG retention](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SubjectMaskFocusRegressionTests.swift:10)
- [grayscale and alpha have equivalent support bounds and scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SubjectMaskFocusRegressionTests.swift:35)
- [empty sparse and mismatched masks abstain explicitly while full masks are suspect](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SubjectMaskFocusRegressionTests.swift:60)
- [padded grayscale rows preserve raw threshold and contract registration](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/SubjectMaskFocusRegressionTests.swift:82)

### ThumbnailCacheIdentityTests (7)

[ThumbnailCacheIdentityTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift)

- [replacing source bytes at the same path changes thumbnail identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:9)
- [purpose and requested size identify separate representations](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:34)
- [missing source metadata bypasses thumbnail reuse](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:58)
- [atomic writers and cancelled save never leave a partial JPEG](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:76)
- [corrupt JPEG becomes a miss and is removed](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:116)
- [migration removes only legacy thumbnail JPEGs](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:133)
- [thumbnail representation changes preserve Vision CLIP and SAM identities](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailCacheIdentityTests.swift:162)

### ThumbnailKeyActionTests (2)

[ThumbnailKeyActionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyActionTests.swift)

- [Z resolves to actual-pixels inspection](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyActionTests.swift:8) — parameterized
- [unmapped thumbnail key is ignored](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyActionTests.swift:13)

### ThumbnailKeyboardRoutingTests (4)

[ThumbnailKeyboardRoutingTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyboardRoutingTests.swift)

- [burst commands have one owner](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyboardRoutingTests.swift:8) — parameterized
- [unavailable burst command cannot become rating two](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyboardRoutingTests.swift:19)
- [ordinary grid preserves existing shortcuts](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyboardRoutingTests.swift:31) — parameterized
- [unrelated keys continue to existing handlers](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailKeyboardRoutingTests.swift:41) — parameterized

### ThumbnailLoaderConcurrencyTests (5)

[ThumbnailLoaderConcurrencyTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift)

- [saturated loader queues waiter until slot is released](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift:11)
- [cancelled queued waiter does not consume slot](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift:39)
- [max concurrency bound holds while queued waiters cancel and resume](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift:62)
- [cancelAll drains waiters without granting slots](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift:97)
- [FIFO grant skips cancelled waiter](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailLoaderConcurrencyTests.swift:123)

### ThumbnailPreloadGateTests (3)

[ThumbnailPreloadGateTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadGateTests.swift)

- [completed visible file is released while the catalog is still preloading](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadGateTests.swift:8)
- [completion belongs to its own active session](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadGateTests.swift:25)
- [other catalogs and failed-file completion never wait for the catalog end](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadGateTests.swift:42)

### ThumbnailPreloadSaveOwnershipTests (1)

[ThumbnailPreloadSaveOwnershipTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadSaveOwnershipTests.swift)

- [preload owns bounded saves and releases gates before disk completion](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPreloadSaveOwnershipTests.swift:96) — parameterized

### ThumbnailPresentationModelTests (3)

[ThumbnailPresentationModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPresentationModelTests.swift)

- [request identity includes representation and source revision](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPresentationModelTests.swift:11)
- [late old load cannot overwrite a newer image or its binding](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPresentationModelTests.swift:24)
- [cancelled load does not publish its result](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailPresentationModelTests.swift:50)

### ThumbnailProviderTests (13)

[ThumbnailProviderTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift)

- [new isolated cache starts empty](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:22)
- [thumbnail request for missing file returns nil](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:30)
- [cancelled thumbnail request returns nil without surfacing failure](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:43)
- [clear caches removes cached items](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:69)
- [preload nonexistent catalog reports no processed files](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:87)
- [production config uses larger limits than testing config](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:101)
- [custom config preserves explicit limits](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:110)
- [sixteen GB low free memory keeps adaptive baseline](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:123)
- [sixteen GB with five point six GB free prioritizes grid cache](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:140)
- [sixteen GB high free memory caps at safe tier](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:157)
- [adaptive cache respects user maximums](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:174)
- [warning pressure shrinks adaptive baseline](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:191)
- [thumbnail cost is based on pixel footprint](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ThumbnailProviderTests.swift:210)

### TypedAIPersistenceMatrixTests (4)

[TypedAIPersistenceMatrixTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TypedAIPersistenceMatrixTests.swift)

- [dataComp and OpenAI artifacts relaunch without cross-loading](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TypedAIPersistenceMatrixTests.swift:39)
- [source add replace rename and removal preserve only compatible active records](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TypedAIPersistenceMatrixTests.swift:83)
- [superseded semantic hydration cannot publish an older backend](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TypedAIPersistenceMatrixTests.swift:148)
- [a per-record write failure retains usable session artifacts and returns idle](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TypedAIPersistenceMatrixTests.swift:181)

### ZoomCullingMetadataTests (3)

[ZoomCullingMetadataTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomCullingMetadataTests.swift)

- [rows are omitted when decision evidence is absent](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomCullingMetadataTests.swift:9)
- [only present decision evidence creates rows](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomCullingMetadataTests.swift:22)
- [vital culling and completed CLIP evidence create concise rows](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomCullingMetadataTests.swift:35)

### ZoomKeyboardControllerTests (2)

[ZoomKeyboardControllerTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomKeyboardControllerTests.swift)

- [exposure inspection keeps navigation and rating disabled](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomKeyboardControllerTests.swift:8)
- [subject outline shortcut requires an available outline](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomKeyboardControllerTests.swift:38)

### ZoomOverlayImagePolicyTests (2)

[ZoomOverlayImagePolicyTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayImagePolicyTests.swift)

- [dedicated thumbnail analysis pixels are preferred over display pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayImagePolicyTests.swift:8)
- [CG display image remains the analysis fallback](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayImagePolicyTests.swift:21)

### ZoomOverlayKeyActionTests (6)

[ZoomOverlayKeyActionTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift)

- [horizontal arrows resolve to previous and next](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:8)
- [vertical arrows resolve to previous and next](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:22)
- [unrelated arrows are ignored for the active axis](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:36)
- [escape zoom and source shortcuts resolve](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:50)
- [rating shortcuts resolve from characters](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:104)
- [unmapped keys are ignored](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayKeyActionTests.swift:153)

### ZoomOverlayLaunchContextTests (2)

[ZoomOverlayLaunchContextTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayLaunchContextTests.swift)

- [default zoom overlay launch context preserves existing behavior](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayLaunchContextTests.swift:9)
- [actual-pixels launch context requests embedded JPG and focus points](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayLaunchContextTests.swift:21)

### ZoomOverlayNavigationContextTests (1)

[ZoomOverlayNavigationContextTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayNavigationContextTests.swift)

- [context keeps first occurrence when duplicate IDs are supplied](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomOverlayNavigationContextTests.swift:8)

### ZoomSessionModelTests (3)

[ZoomSessionModelTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomSessionModelTests.swift)

- [preview clipping warning distinguishes white black and ordinary colors](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomSessionModelTests.swift:9)
- [launch context initializes source zoom and focus presentation](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomSessionModelTests.swift:37)
- [keyboard actions use shared zoom policy adapter](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomSessionModelTests.swift:54)

### ZoomViewportMathTests (10)

[ZoomViewportMathTests.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift)

- [landscape inspection maps one image pixel to one display point](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:8)
- [portrait inspection maps one image pixel to one display point](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:18)
- [inspection scale reduces a fit-upscaled preview to actual pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:28)
- [aspect mismatch still maps the fitted image to actual pixels](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:38)
- [focus point pan centers a normalized point when there is room](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:55)
- [focus point pan clamps at all four image edges](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:68)
- [out of range focus point clamps to an image edge](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:100)
- [missing focus point keeps actual-pixels view centered](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:111)
- [invalid sizes use a finite centered fallback](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:123)
- [non finite focus point uses a centered fallback](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/ZoomViewportMathTests.swift:145)

## Release/probe target — every test

### CombinedReviewInputProbe (2)

[CombinedReviewInputProbe.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/CombinedReviewInputProbe.swift)

- [orientation fixtures preserve corner identity](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/CombinedReviewInputProbe.swift:20)
- [verify installed inputs](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/CombinedReviewInputProbe.swift:44) — opt-in: RAWCULL_INPUT_PROBE_RUN

### ReleaseAIObjectsTest (3)

[ReleaseAIObjectsTest.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseAIObjectsTest.swift)

- [discovers only top level regular ARW files](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseAIObjectsTest.swift:9)
- [report preserves failures and unprocessed files](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseAIObjectsTest.swift:25)
- [analyze downloads](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseAIObjectsTest.swift:46) — opt-in: RAWCULL_RELEASE_RUN

### ReleaseSharpnessTest (5)

[ReleaseSharpnessTest.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift)

- [analyze catalog](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift:10) — opt-in: RAWCULL_RELEASE_SHARPNESS_RUN
- [report preserves failures missing evidence and pending comparisons](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift:81)
- [summary distinguishes ranking changes from larger scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift:107)
- [rejects invalid scores](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift:150) — parameterized
- [export AF comparison dataset](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessTest.swift:195) — opt-in: RAWCULL_AF_COMPARISON_RUN

## Python tooling — every test

### TestCompareAFSharpness (4)

- [test_exported_crop_workflow_prefers_sharp_edges](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestCompareAFSharpness.py:13)
- [test_direction_ties_missing_and_exclusions](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestCompareAFSharpness.py:34)
- [test_reversed_duplicates_rejected](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestCompareAFSharpness.py:47)
- [test_burst_membership_required](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestCompareAFSharpness.py:52)

### TestFreezeCombinedReviewBaseline (4)

- [test_inventory_keeps_identity_payload_and_hash_without_mutating_export](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestFreezeCombinedReviewBaseline.py:10)
- [test_missing_export_is_explicit](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestFreezeCombinedReviewBaseline.py:25)
- [test_truncated_or_invalid_png_header_is_rejected](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestFreezeCombinedReviewBaseline.py:31)
- [test_png_dimensions_and_format_are_preserved](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestFreezeCombinedReviewBaseline.py:41)

### TestModelProvenance (1)

- [test_invalid_enabled_evidence_is_rejected](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestModelProvenance.py:10)

### TestRunAIAnalysis (3)

- [test_selection_is_sorted_unbounded_and_nonrecursive](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunAIAnalysis.py:17)
- [test_runner_exit_and_evidence_outcomes](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunAIAnalysis.py:48)
- [test_progress_ignores_incomplete_or_malformed_diagnostics](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunAIAnalysis.py:53)

### TestRunCombinedReviewSix (4)

- [test_progress_tracks_execution_order_and_terminal_reports](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunCombinedReviewSix.py:18)
- [test_all_files_are_sorted_and_ignore_non_raw_and_subdirectories](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunCombinedReviewSix.py:70)
- [test_empty_directory_fails_before_xcode](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunCombinedReviewSix.py:79)
- [test_runner_exit_and_evidence_outcomes](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunCombinedReviewSix.py:88)

### TestRunnerPrivacy (1)

- [test_private_outputs_restore_callers_umask_on_success_and_failure](/Users/thomas/GitHub/RawCull/RawCull/Scripts/TestRunnerPrivacy.py:14)

The exported-crop integration test in TestCompareAFSharpness requires OpenCV and skips when it is unavailable.

## Supporting files without test declarations

- [BurstAnalysisCoordinatorTestSupport.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/BurstAnalysisCoordinatorTestSupport.swift)
- [CullingTestSupport.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/CullingTestSupport.swift)
- [TestIsolationHelpers.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TestIsolationHelpers.swift)
- [TestTags.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullTests/TestTags.swift)
- [CombinedReviewInputFixtures.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/CombinedReviewInputFixtures.swift)
- [ReleaseAnalysisReport.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseAnalysisReport.swift)
- [ReleaseRunConfiguration.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseRunConfiguration.swift)
- [ReleaseSharpnessReport.swift](/Users/thomas/GitHub/RawCull/RawCull/RawCullReleaseTests/ReleaseSharpnessReport.swift)

TestManifests lists selected tests; Scripts/VerifyTestEnumeration.swift validates Xcode enumeration; Scripts/VerifyAIImportBoundary.sh and Scripts/VerifyModelProvenance.py provide additional validation outside the Swift test suites.
