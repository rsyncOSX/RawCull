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

[AIAnalysisInputSelectionTests.swift](../RawCullTests/AIAnalysisInputSelectionTests.swift)

- [preserves grid selection only when leaving the grid](../RawCullTests/AIAnalysisInputSelectionTests.swift#L8)

### AIAnalysisRealModelTests (1)

[AIAnalysisRealModelTests.swift](../RawCullTests/AIAnalysisRealModelTests.swift)

- [selected ARWs run SAM CLIP then Qwen then Objects](../RawCullTests/AIAnalysisRealModelTests.swift#L16) — opt-in: RAWCULL_ANALYSIS_RUN

### AIAnalysisSelectionTests (5)

[AIAnalysisSelectionTests.swift](../RawCullTests/AIAnalysisSelectionTests.swift)

- [Grid source includes only selected files in catalog order](../RawCullTests/AIAnalysisSelectionTests.swift#L9)
- [Grid source falls back to the focused image](../RawCullTests/AIAnalysisSelectionTests.swift#L28)
- [Selected analysis images survive main view changes](../RawCullTests/AIAnalysisSelectionTests.swift#L42)
- [Browsing tagged images preserves the selected batch](../RawCullTests/AIAnalysisSelectionTests.swift#L65) — parameterized
- [Analysis navigation walks ordered rows and stops at boundaries](../RawCullTests/AIAnalysisSelectionTests.swift#L90)

### AICacheBoundaryTests (1)

[AICacheBoundaryTests.swift](../RawCullTests/AICacheBoundaryTests.swift)

- [independent cache clears preserve ratings settings decisions models and licences](../RawCullTests/AICacheBoundaryTests.swift#L9)

### AccessibilityPresentationTests (5)

[AccessibilityPresentationTests.swift](../RawCullTests/AccessibilityPresentationTests.swift)

- [saved rows announce content and selection](../RawCullTests/AccessibilityPresentationTests.swift#L9)
- [image tiles announce rating selection and semantic rank](../RawCullTests/AccessibilityPresentationTests.swift#L23)
- [AI capability and downloads announce readiness licence progress and failure](../RawCullTests/AccessibilityPresentationTests.swift#L34)
- [semantic search announces CLIP backend coverage and result count](../RawCullTests/AccessibilityPresentationTests.swift#L60)
- [Deep Review announces SAM 3 progress and confidence](../RawCullTests/AccessibilityPresentationTests.swift#L93)

### ApertureHintTests (6)

[ApertureHintTests.swift](../RawCullTests/ApertureHintTests.swift)

- [nil aperture maps to mid](../RawCullTests/ApertureHintTests.swift#L15)
- [wide boundary is inclusive at 5 point 6](../RawCullTests/ApertureHintTests.swift#L20)
- [landscape boundary is inclusive at f 8](../RawCullTests/ApertureHintTests.swift#L28)
- [blur gate span is positive for every hint](../RawCullTests/ApertureHintTests.swift#L36)
- [landscape has widest gate window and lowest threshold](../RawCullTests/ApertureHintTests.swift#L44)
- [only landscape overrides salient weight and damps blur](../RawCullTests/ApertureHintTests.swift#L54)

### BurstAnalysisCoordinatorTests (8)

[BurstAnalysisCoordinatorTests.swift](../RawCullTests/BurstAnalysisCoordinatorTests.swift)

- [compatible cache hit returns remapped snapshot and review state](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L10)
- [artifact digest mismatch rejects derived cache](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L42)
- [legacy candidate is remapped before import decision](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L67)
- [superseded cache preparation returns no result](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L109)
- [review restoration follows membership rather than group id](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L133)
- [fresh orchestration preserves progress ranks and saves an immutable snapshot](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L189)
- [stale generation cannot apply or save a computed result](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L249)
- [coordinator owns generation task and progress lifecycle](../RawCullTests/BurstAnalysisCoordinatorTests.swift#L280)

### BurstAnalysisPipelineValuesTests (3)

[BurstAnalysisPipelineValuesTests.swift](../RawCullTests/BurstAnalysisPipelineValuesTests.swift)

- [pipeline request equals the legacy input snapshot](../RawCullTests/BurstAnalysisPipelineValuesTests.swift#L9)
- [pipeline request remains an immutable configuration snapshot](../RawCullTests/BurstAnalysisPipelineValuesTests.swift#L47)
- [pipeline result equality covers cache diagnostics and restored state](../RawCullTests/BurstAnalysisPipelineValuesTests.swift#L71)

### BurstCatalogPreparationPresentationTests (3)

[BurstCatalogPreparationPresentationTests.swift](../RawCullTests/BurstCatalogPreparationPresentationTests.swift)

- [semantic indexing is the first visible stage](../RawCullTests/BurstCatalogPreparationPresentationTests.swift#L7)
- [sharpness calibration is visible even before scoring begins](../RawCullTests/BurstCatalogPreparationPresentationTests.swift#L32)
- [burst grouping follows completed indexing and sharpness stages](../RawCullTests/BurstCatalogPreparationPresentationTests.swift#L53)

### BurstWorkspaceSessionModelTests (2)

[BurstWorkspaceSessionModelTests.swift](../RawCullTests/BurstWorkspaceSessionModelTests.swift)

- [sliding window stays bounded around selection](../RawCullTests/BurstWorkspaceSessionModelTests.swift#L8)
- [group reset clears presentation and restores viewport](../RawCullTests/BurstWorkspaceSessionModelTests.swift#L16)

### CacheAccountingConcurrencyTests (3)

[CacheAccountingConcurrencyTests.swift](../RawCullTests/CacheAccountingConcurrencyTests.swift)

- [Concurrent replacements count one live entry](../RawCullTests/CacheAccountingConcurrencyTests.swift#L7) — parameterized
- [Concurrent clear and insert leave consistent accounting](../RawCullTests/CacheAccountingConcurrencyTests.swift#L29) — parameterized
- [Evictions update the owning cache rather than the singleton](../RawCullTests/CacheAccountingConcurrencyTests.swift#L58) — parameterized

### CacheCounterTests (2)

[CacheCounterTests.swift](../RawCullTests/CacheCounterTests.swift)

- [replacing cache key updates manual counters](../RawCullTests/CacheCounterTests.swift#L9) — parameterized
- [clear caches resets live usage](../RawCullTests/CacheCounterTests.swift#L32)

### CatalogConcurrencyTests (3)

[CatalogConcurrencyTests.swift](../RawCullTests/CatalogConcurrencyTests.swift)

- [Old sort cannot publish or finish a newer sort](../RawCullTests/CatalogConcurrencyTests.swift#L8)
- [Cancelled or catalog-stale sort cannot publish](../RawCullTests/CatalogConcurrencyTests.swift#L43) — parameterized
- [Abort invalidates a pending transition even when persistence fails](../RawCullTests/CatalogConcurrencyTests.swift#L68) — parameterized

### CatalogLifecycleCoordinatorTests (4)

[CatalogLifecycleCoordinatorTests.swift](../RawCullTests/CatalogLifecycleCoordinatorTests.swift)

- [Superseded persistence completion cannot act or clear the new transition](../RawCullTests/CatalogLifecycleCoordinatorTests.swift#L7) — parameterized
- [Persistence failure restores selection only while still selected](../RawCullTests/CatalogLifecycleCoordinatorTests.swift#L49) — parameterized
- [Cancelled load retains access until its worker returns](../RawCullTests/CatalogLifecycleCoordinatorTests.swift#L67)
- [Coordinator destruction releases its active grant](../RawCullTests/CatalogLifecycleCoordinatorTests.swift#L94)

### CombinedReviewFeatureTests (28)

[CombinedReviewFeatureTests.swift](../RawCullTests/CombinedReviewFeatureTests.swift)

- [malformed crop and report are repaired with charged attempts](../RawCullTests/CombinedReviewFeatureTests.swift#L10)
- [prohibited crop criterion abstains while valid siblings survive without repair](../RawCullTests/CombinedReviewFeatureTests.swift#L23)
- [synthesis preserves crop and overview evidence without metric references or copied examples](../RawCullTests/CombinedReviewFeatureTests.swift#L41)
- [invalid exposure selection retains grounded coverage and restores its substitution](../RawCullTests/CombinedReviewFeatureTests.swift#L77)
- [degraded review keeps crops grounded and inspectable](../RawCullTests/CombinedReviewFeatureTests.swift#L98)
- [SAM and technical scorer supply separate measured evidence](../RawCullTests/CombinedReviewFeatureTests.swift#L121)
- [camera AF point reaches combined measurement and removes unavailable warning](../RawCullTests/CombinedReviewFeatureTests.swift#L144)
- [real scorer metadata survives restore and stale semantics cannot resume](../RawCullTests/CombinedReviewFeatureTests.swift#L161)
- [diagnostics and unsynthesized summaries survive export restore within per-run caps](../RawCullTests/CombinedReviewFeatureTests.swift#L225) — parameterized
- [malformed crop output is a failure and cannot become detail](../RawCullTests/CombinedReviewFeatureTests.swift#L276)
- [unknown report reference causes explicit partial report](../RawCullTests/CombinedReviewFeatureTests.swift#L287)
- [cancellation retains completed overview and resume spends no free retry](../RawCullTests/CombinedReviewFeatureTests.swift#L296)
- [stored results restore without new inference and changed files refuse resume](../RawCullTests/CombinedReviewFeatureTests.swift#L323)
- [region settings are frozen and compact retention is explicit](../RawCullTests/CombinedReviewFeatureTests.swift#L340)
- [structured responses reject changed IDs and unsupported eye detail](../RawCullTests/CombinedReviewFeatureTests.swift#L353)
- [lease stays reserved until worker acknowledges invalidation](../RawCullTests/CombinedReviewFeatureTests.swift#L361)
- [source refusal explains preview rerun and resume keeps saved source](../RawCullTests/CombinedReviewFeatureTests.swift#L372)
- [complete cleanup removes review storage and history and allows a fresh run](../RawCullTests/CombinedReviewFeatureTests.swift#L400)
- [cleanup refuses an active review reservation without deleting files](../RawCullTests/CombinedReviewFeatureTests.swift#L423)
- [selection reviews every image before unrelated synthesis and restores without inference](../RawCullTests/CombinedReviewFeatureTests.swift#L436)
- [missing image stage cannot prevent other reports or force comparison](../RawCullTests/CombinedReviewFeatureTests.swift#L472)
- [comparison rejects subject image swaps and accepts supported ties](../RawCullTests/CombinedReviewFeatureTests.swift#L488)
- [eight image comparison preserves mandatory context coverage](../RawCullTests/CombinedReviewFeatureTests.swift#L519)
- [deep ties use capped matched pairs without overriding the selection tie](../RawCullTests/CombinedReviewFeatureTests.swift#L544) — parameterized
- [board records full frame transforms in stable image order](../RawCullTests/CombinedReviewFeatureTests.swift#L573)
- [selection budget preserves mandatory synthesis and fair crop limits](../RawCullTests/CombinedReviewFeatureTests.swift#L582)
- [preflight replaces incompatible RAW setting before creating a run](../RawCullTests/CombinedReviewFeatureTests.swift#L612)
- [invalid criteria and selection are preparation status rather than review errors](../RawCullTests/CombinedReviewFeatureTests.swift#L629)

### CombinedReviewPresentationTests (6)

[CombinedReviewPresentationTests.swift](../RawCullTests/CombinedReviewPresentationTests.swift)

- [review layouts fit narrow and desktop widths](../RawCullTests/CombinedReviewPresentationTests.swift#L9) — parameterized
- [selected photo never inherits another photos review](../RawCullTests/CombinedReviewPresentationTests.swift#L45)
- [incomplete review keeps conflicts uncertainty and omitted coverage visible](../RawCullTests/CombinedReviewPresentationTests.swift#L53)
- [failed synthesis shows available observations without promoting measurements to findings](../RawCullTests/CombinedReviewPresentationTests.swift#L72)
- [finding links to its cited crop rather than the first region](../RawCullTests/CombinedReviewPresentationTests.swift#L83)
- [full record round trips exact measurements and all original limitations](../RawCullTests/CombinedReviewPresentationTests.swift#L97)

### CombinedReviewRealModelTests (3)

[CombinedReviewRealModelTests.swift](../RawCullTests/CombinedReviewRealModelTests.swift)

- [installed Qwen produces a bounded inspectable review](../RawCullTests/CombinedReviewRealModelTests.swift#L14) — opt-in: RAWCULL_COMBINED_REVIEW_RUN
- [selected ARWs complete full model review with criterion coverage](../RawCullTests/CombinedReviewRealModelTests.swift#L61) — opt-in: RAWCULL_COMBINED_SIX_RUN
- [six real Sony sources retain terminal reports and a bounded comparison](../RawCullTests/CombinedReviewRealModelTests.swift#L160) — opt-in: RAWCULL_COMBINED_SELECTION_RUN

### ComparisonGridDisplayStateTests (7)

[ComparisonGridDisplayStateTests.swift](../RawCullTests/ComparisonGridDisplayStateTests.swift)

- [load key ignores selection changes](../RawCullTests/ComparisonGridDisplayStateTests.swift#L49)
- [rapid selection changes update only the selected presentation value](../RawCullTests/ComparisonGridDisplayStateTests.swift#L60)
- [files resolve displayed comparison IDs in order](../RawCullTests/ComparisonGridDisplayStateTests.swift#L72)
- [finalist focus uses recommended and second best IDs](../RawCullTests/ComparisonGridDisplayStateTests.swift#L93)
- [finalist focus falls back to first four comparison IDs without burst result](../RawCullTests/ComparisonGridDisplayStateTests.swift#L113)
- [selected comparison file is nil outside displayed files](../RawCullTests/ComparisonGridDisplayStateTests.swift#L126)
- [missing comparison IDs leave an empty presentation and stable empty load key](../RawCullTests/ComparisonGridDisplayStateTests.swift#L135)

### ComparisonGridImageCoordinatorTests (4)

[ComparisonGridImageCoordinatorTests.swift](../RawCullTests/ComparisonGridImageCoordinatorTests.swift)

- [reload forwards the selected source for only the requested file](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L49)
- [cancelling a bulk load rejects the in flight result and stops later files](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L70)
- [out of order reload completion accepts only the newest generation](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L98)
- [bulk completion rejects work superseded by a reload](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L120)

### ComparisonGridNavigationTests (12)

[ComparisonGridNavigationTests.swift](../RawCullTests/ComparisonGridNavigationTests.swift)

- [left and right arrows move previous and next](../RawCullTests/ComparisonGridNavigationTests.swift#L6)
- [invalid current index returns nil](../RawCullTests/ComparisonGridNavigationTests.swift#L31)
- [four item navigation preserves linear boundaries](../RawCullTests/ComparisonGridNavigationTests.swift#L50) — parameterized
- [single item comparison cannot navigate](../RawCullTests/ComparisonGridNavigationTests.swift#L75) — parameterized
- [printable shortcuts are resolved from characters before hardware key code](../RawCullTests/ComparisonGridNavigationTests.swift#L84)
- [non printable key codes resolve linear navigation](../RawCullTests/ComparisonGridNavigationTests.swift#L90)
- [printable rating and toggle shortcuts resolve from characters](../RawCullTests/ComparisonGridNavigationTests.swift#L99)
- [Z resolves to actual-pixels inspection](../RawCullTests/ComparisonGridNavigationTests.swift#L118) — parameterized
- [burst review shortcuts resolve navigation](../RawCullTests/ComparisonGridNavigationTests.swift#L126)
- [window contains previous current and next frame](../RawCullTests/ComparisonGridNavigationTests.swift#L142)
- [window contracts at burst boundaries](../RawCullTests/ComparisonGridNavigationTests.swift#L147)
- [window is always bounded and contains the selection](../RawCullTests/ComparisonGridNavigationTests.swift#L153)

### ComparisonImageAnalysisSourceTests (5)

[ComparisonImageAnalysisSourceTests.swift](../RawCullTests/ComparisonImageAnalysisSourceTests.swift)

- [thumbnail sharpening changes display but not analysis pixels](../RawCullTests/ComparisonImageAnalysisSourceTests.swift#L8)
- [thumbnail source uses unsharpened pixels when sharpening is disabled](../RawCullTests/ComparisonImageAnalysisSourceTests.swift#L23)
- [thumbnail source falls back when sharpening produces no image](../RawCullTests/ComparisonImageAnalysisSourceTests.swift#L38)
- [embedded JPG displays extracted pixels but analyzes thumbnail pixels](../RawCullTests/ComparisonImageAnalysisSourceTests.swift#L52)
- [embedded JPG falls back to extracted pixels when thumbnail is unavailable](../RawCullTests/ComparisonImageAnalysisSourceTests.swift#L66)

### ComparisonSessionModelTests (6)

[ComparisonSessionModelTests.swift](../RawCullTests/ComparisonSessionModelTests.swift)

- [lifecycle activates and cancels injected image services](../RawCullTests/ComparisonSessionModelTests.swift#L152)
- [selection intents use the injected narrow selection boundary](../RawCullTests/ComparisonSessionModelTests.swift#L167)
- [presentation reuses display mapping and owns finalist focus](../RawCullTests/ComparisonSessionModelTests.swift#L184)
- [image intents route through the injected image service](../RawCullTests/ComparisonSessionModelTests.swift#L224)
- [newer reload wins when an older request finishes last](../RawCullTests/ComparisonSessionModelTests.swift#L244)
- [cancellation prevents an in flight reload from publishing](../RawCullTests/ComparisonSessionModelTests.swift#L280)

### CopyBookmarkStoreTests (5)

[CopyBookmarkStoreTests.swift](../RawCullTests/CopyBookmarkStoreTests.swift)

- [missing and corrupt destination bookmarks fail without acquiring access](../RawCullTests/CopyBookmarkStoreTests.swift#L7)
- [failed replacement preserves the saved destination](../RawCullTests/CopyBookmarkStoreTests.swift#L29)
- [saving a destination replaces its bookmark and releases access](../RawCullTests/CopyBookmarkStoreTests.swift#L57)
- [stale bookmark refreshes under access and releases once](../RawCullTests/CopyBookmarkStoreTests.swift#L87)
- [destination access denial does not change its bookmark](../RawCullTests/CopyBookmarkStoreTests.swift#L127)

### CopyCompletionTests (3)

[CopyCompletionTests.swift](../RawCullTests/CopyCompletionTests.swift)

- [runtime errors and cancellation survive process termination](../RawCullTests/CopyCompletionTests.swift#L9)
- [real rsync completion reports success or missing source failure](../RawCullTests/CopyCompletionTests.swift#L33) — parameterized
- [result title uses captured operation mode](../RawCullTests/CopyCompletionTests.swift#L95) — parameterized

### CullingGridCoordinatorTests (25)

[CullingGridCoordinatorTests.swift](../RawCullTests/CullingGridCoordinatorTests.swift)

- [session commands preserve manual override and independent restored states](../RawCullTests/CullingGridCoordinatorTests.swift#L78)
- [review session mutations reach facade observers and invalidate grid results](../RawCullTests/CullingGridCoordinatorTests.swift#L106)
- [burst undo restores ratings and consumes session entry without reverting review state](../RawCullTests/CullingGridCoordinatorTests.swift#L150)
- [thumbnail workspace follows the current catalog across view switches](../RawCullTests/CullingGridCoordinatorTests.swift#L176)
- [normal command and shift selection preserve existing grid behavior](../RawCullTests/CullingGridCoordinatorTests.swift#L190)
- [hidden files are pruned from selection and action targets](../RawCullTests/CullingGridCoordinatorTests.swift#L250)
- [badge selection counts and matching ids come from burst and saliency labels](../RawCullTests/CullingGridCoordinatorTests.swift#L273)
- [render cache filters visible burst files](../RawCullTests/CullingGridCoordinatorTests.swift#L304)
- [burst view lists every file in ranked priority order](../RawCullTests/CullingGridCoordinatorTests.swift#L322)
- [burst view appends every unranked file in original order](../RawCullTests/CullingGridCoordinatorTests.swift#L337)
- [render cache key tracks complete membership and score availability](../RawCullTests/CullingGridCoordinatorTests.swift#L352)
- [sharpness score revision advances for replacement and incremental mutation](../RawCullTests/CullingGridCoordinatorTests.swift#L371)
- [thumbnail source flags are pruned and initialized for comparison files](../RawCullTests/CullingGridCoordinatorTests.swift#L386)
- [review queue policy includes every pending group and excludes completed states](../RawCullTests/CullingGridCoordinatorTests.swift#L400)
- [view model filters burst groups by review queue state](../RawCullTests/CullingGridCoordinatorTests.swift#L451)
- [next burst navigation follows the review queue and skips single images](../RawCullTests/CullingGridCoordinatorTests.swift#L492)
- [next burst navigation defers an unrated current group before advancing](../RawCullTests/CullingGridCoordinatorTests.swift#L530)
- [next burst navigation does not defer a group with any rating](../RawCullTests/CullingGridCoordinatorTests.swift#L551) — parameterized
- [sharpness-only records do not prevent deferring an unrated group](../RawCullTests/CullingGridCoordinatorTests.swift#L579)
- [burst review summary is the source of truth for groups and live review states](../RawCullTests/CullingGridCoordinatorTests.swift#L609)
- [single image category excludes every multi-image burst](../RawCullTests/CullingGridCoordinatorTests.swift#L688)
- [combined single images preserve workflow states without choosing a winner](../RawCullTests/CullingGridCoordinatorTests.swift#L705)
- [review and defer actions toggle back to persisted neutral state](../RawCullTests/CullingGridCoordinatorTests.swift#L735)
- [reviewed and deferred groups leave the needs review queue immediately](../RawCullTests/CullingGridCoordinatorTests.swift#L767)
- [singleton groups have a separate queue from all bursts](../RawCullTests/CullingGridCoordinatorTests.swift#L801)

### CullingGridProjectionTests (2)

[CullingGridProjectionTests.swift](../RawCullTests/CullingGridProjectionTests.swift)

- [selection and score-value changes reuse the projection while membership changes rebuild](../RawCullTests/CullingGridProjectionTests.swift#L13)
- [rating review-group and saliency mutations invalidate cached projections](../RawCullTests/CullingGridProjectionTests.swift#L35)

### CullingModelTests (21)

[CullingModelTests.swift](../RawCullTests/CullingModelTests.swift)

- [scored photo stays unrated while explicit keeper is rated](../RawCullTests/CullingModelTests.swift#L12)
- [restoring unrated state preserves scoring metadata](../RawCullTests/CullingModelTests.swift#L30)
- [corrupt load blocks mutations and preserves in-memory state](../RawCullTests/CullingModelTests.swift#L52)
- [hasExplicitRatings requires a non-nil rating in the requested catalog](../RawCullTests/CullingModelTests.swift#L71)
- [explicit rating count excludes scoring-only records](../RawCullTests/CullingModelTests.swift#L89)
- [cancelling similarity ranking stops its owned distance helper](../RawCullTests/CullingModelTests.swift#L103)
- [disarming similarity ranking preserves the last completed order](../RawCullTests/CullingModelTests.swift#L138)
- [find similar indexes a fresh catalog before ranking](../RawCullTests/CullingModelTests.swift#L175)
- [similarity indexing cancellation stops structured embedding workers](../RawCullTests/CullingModelTests.swift#L198)
- [superseded similarity indexing cannot commit or clear newer run state](../RawCullTests/CullingModelTests.swift#L223)
- [updateRating creates catalog record and debounced save snapshot](../RawCullTests/CullingModelTests.swift#L253)
- [failed persistence remains dirty and retry saves newest snapshot](../RawCullTests/CullingModelTests.swift#L271)
- [updateRatings and applyRatings upsert existing records](../RawCullTests/CullingModelTests.swift#L297)
- [mergeScoringResults preserves ratings and writes scores](../RawCullTests/CullingModelTests.swift#L318)
- [resetSavedFiles clears records for catalog](../RawCullTests/CullingModelTests.swift#L339)
- [manual winner override requires exact membership](../RawCullTests/CullingModelTests.swift#L355)
- [upsert preserves same winner for different member sets](../RawCullTests/CullingModelTests.swift#L382)
- [prune removes overrides with missing winner or member](../RawCullTests/CullingModelTests.swift#L407)
- [FileRecord equality includes persisted sharpness metadata](../RawCullTests/CullingModelTests.swift#L426)
- [SavedFiles equality includes records and burst overrides](../RawCullTests/CullingModelTests.swift#L454)
- [updateRating recreates records after reset leaves empty catalog](../RawCullTests/CullingModelTests.swift#L471)

### DeepAIReviewFeatureTests (8)

[DeepAIReviewFeatureTests.swift](../RawCullTests/DeepAIReviewFeatureTests.swift)

- [Feature publishes a typed completed result](../RawCullTests/DeepAIReviewFeatureTests.swift#L13)
- [Cancelling Deep Review cancels the owned in-process task](../RawCullTests/DeepAIReviewFeatureTests.swift#L34)
- [Cancelling Deep Review retains candidates that already completed](../RawCullTests/DeepAIReviewFeatureTests.swift#L57)
- [Controller owns availability and request construction](../RawCullTests/DeepAIReviewFeatureTests.swift#L76)
- [Controller represents checking unavailable and cancelled states](../RawCullTests/DeepAIReviewFeatureTests.swift#L115)
- [Prompt policy and candidate limit match burst Deep Review](../RawCullTests/DeepAIReviewFeatureTests.swift#L162)
- [Deep Review preview loads the selected prompt from disk only](../RawCullTests/DeepAIReviewFeatureTests.swift#L180)
- [Subject-mask scorer measures detail only inside the mask](../RawCullTests/DeepAIReviewFeatureTests.swift#L243)

### DeepAIReviewMaskOutlineRendererTests (2)

[DeepAIReviewMaskOutlineRendererTests.swift](../RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift)

- [filled mask becomes a transparent contour](../RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift#L6)
- [disconnected subjects each receive a contour](../RawCullTests/DeepAIReviewMaskOutlineRendererTests.swift#L21)

### DiskCacheAndScanAdmissionTests (20)

[DiskCacheAndScanAdmissionTests.swift](../RawCullTests/DiskCacheAndScanAdmissionTests.swift)

- [URL decode applies EXIF orientation to pixels](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L179) — parameterized
- [URL decode applies right orientation to portrait dimensions](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L204)
- [URL decode keeps up orientation dimensions unchanged](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L222)
- [data decode applies right orientation to portrait dimensions](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L240)
- [bounded thumbnail decode applies right orientation to portrait dimensions](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L250)
- [bounded thumbnail decode keeps up orientation dimensions unchanged](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L268)
- [source orientation can be baked into a decoded image](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L286)
- [embedded preview uses its own orientation before source orientation](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L305)
- [embedded preview falls back to source orientation when missing its own orientation](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L327)
- [save and load thumbnail JPEG from isolated disk cache](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L351)
- [load thumbnail JPEG applies cached orientation metadata](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L371)
- [saving same source overwrites existing thumbnail cache entry](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L387)
- [pruneCache removes old thumbnail files](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L411)
- [missing full size JPEG entries are clean cache misses](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L435)
- [save contains and load full size JPEG from isolated disk cache](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L450)
- [load full size JPEG applies cached orientation metadata](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L469)
- [saving same source overwrites existing full size cache entry](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L484)
- [embedded and developed JPEGs use separate cache entries](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L503)
- [pruneCache removes old full size JPEG files](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L526)
- [preload from disk cache admits only to grid cache not memory cache](../RawCullTests/DiskCacheAndScanAdmissionTests.swift#L547)

### ExecuteCopyFilesStartupTests (8)

[ExecuteCopyFilesStartupTests.swift](../RawCullTests/ExecuteCopyFilesStartupTests.swift)

- [empty tagged list fails before copy starts](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L8)
- [empty rated list fails before copy starts](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L22)
- [missing view model fails before copy starts](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L36)
- [include list paths are unique and outside Documents](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L53)
- [cleanup removes generated include list](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L78)
- [copy list is nul separated for literal rsync files-from matching](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L93)
- [selected catalog does not require a source bookmark](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L118) — parameterized
- [obsolete source bookmark cannot override the selected catalog](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L157)

### ExtractJPGsSelectionTests (12)

[ExtractJPGsSelectionTests.swift](../RawCullTests/ExtractJPGsSelectionTests.swift)

- [multi-selected thumbnails win over single selected image](../RawCullTests/ExtractJPGsSelectionTests.swift#L32)
- [single selected image is used when there is no thumbnail multi-selection](../RawCullTests/ExtractJPGsSelectionTests.swift#L51)
- [no selected image blocks extraction](../RawCullTests/ExtractJPGsSelectionTests.swift#L66)
- [denied destination access blocks extraction and presents error](../RawCullTests/ExtractJPGsSelectionTests.swift#L83)
- [present extract jpgs defaults destination to selected source only when empty](../RawCullTests/ExtractJPGsSelectionTests.swift#L103)
- [present extract jpgs preserves destination outside source catalogs](../RawCullTests/ExtractJPGsSelectionTests.swift#L127)
- [failed exports still advance completed count and report every failure](../RawCullTests/ExtractJPGsSelectionTests.swift#L151)
- [embedded export writes natural jpg name in destination catalog](../RawCullTests/ExtractJPGsSelectionTests.swift#L182)
- [demosaiced export writes suffixed jpg name in destination catalog](../RawCullTests/ExtractJPGsSelectionTests.swift#L196)
- [concurrent exports preserve existing photographs](../RawCullTests/ExtractJPGsSelectionTests.swift#L210) — parameterized
- [uppercase camera JPEG is preserved](../RawCullTests/ExtractJPGsSelectionTests.swift#L238)
- [save propagates destination write failure](../RawCullTests/ExtractJPGsSelectionTests.swift#L252)

### FocusImageResolutionPolicyTests (1)

[FocusImageResolutionPolicyTests.swift](../RawCullTests/FocusImageResolutionPolicyTests.swift)

- [analysis preserves decoded pixels for every orientation](../RawCullTests/FocusImageResolutionPolicyTests.swift#L8) — parameterized

### FocusNumericHelperTests (13)

[FocusNumericHelperTests.swift](../RawCullTests/FocusNumericHelperTests.swift)

- [robust tail score empty returns nil](../RawCullTests/FocusNumericHelperTests.swift#L17)
- [robust tail score uniform returns zero](../RawCullTests/FocusNumericHelperTests.swift#L22)
- [robust tail score dense edges full density factor](../RawCullTests/FocusNumericHelperTests.swift#L31)
- [robust tail score sparse edges scores low](../RawCullTests/FocusNumericHelperTests.swift#L44)
- [robust tail score dense edges scores higher than sparse](../RawCullTests/FocusNumericHelperTests.swift#L58)
- [micro contrast empty returns zero](../RawCullTests/FocusNumericHelperTests.swift#L75)
- [micro contrast uniform returns zero](../RawCullTests/FocusNumericHelperTests.swift#L80)
- [micro contrast alternating known variance](../RawCullTests/FocusNumericHelperTests.swift#L86)
- [micro contrast ignores non finite](../RawCullTests/FocusNumericHelperTests.swift#L94)
- [robust tail score is scale proportional](../RawCullTests/FocusNumericHelperTests.swift#L108)
- [focus failure classifier flags motion blur when all regions are weak](../RawCullTests/FocusNumericHelperTests.swift#L121)
- [focus failure classifier flags missed focus when subject trails frame](../RawCullTests/FocusNumericHelperTests.swift#L132)
- [focus failure classifier stays neutral for strong subject](../RawCullTests/FocusNumericHelperTests.swift#L143)

### HistogramLoadingTests (6)

[HistogramLoadingTests.swift](../RawCullTests/HistogramLoadingTests.swift)

- [nil image clears published bins](../RawCullTests/HistogramLoadingTests.swift#L9)
- [image conversion failure clears published bins](../RawCullTests/HistogramLoadingTests.swift#L21)
- [successful calculation publishes normalized bins](../RawCullTests/HistogramLoadingTests.swift#L33)
- [bounds histogram sample while preserving aspect ratio](../RawCullTests/HistogramLoadingTests.swift#L43)
- [sampled histogram preserves dominant luminance values](../RawCullTests/HistogramLoadingTests.swift#L53)
- [slow cancelled image cannot overwrite fast replacement](../RawCullTests/HistogramLoadingTests.swift#L65)

### ISOScalingTests (5)

[ISOScalingTests.swift](../RawCullTests/ISOScalingTests.swift)

- [below 800 is flat at 1 point 0](../RawCullTests/ISOScalingTests.swift#L15)
- [mid range ramps to 1 point 6 at 3200](../RawCullTests/ISOScalingTests.swift#L22)
- [high range caps at 2 point 2](../RawCullTests/ISOScalingTests.swift#L31)
- [monotonically non decreasing across range](../RawCullTests/ISOScalingTests.swift#L38)
- [high ISO is less aggressive than old sqrt formula](../RawCullTests/ISOScalingTests.swift#L47)

### ImageReviewFeatureDependenciesTests (2)

[ImageReviewFeatureDependenciesTests.swift](../RawCullTests/ImageReviewFeatureDependenciesTests.swift)

- [selection policy uses only focused selection capability](../RawCullTests/ImageReviewFeatureDependenciesTests.swift#L25)
- [rating presentation uses focused rating capability](../RawCullTests/ImageReviewFeatureDependenciesTests.swift#L45)

### ImageReviewPoliciesTests (6)

[ImageReviewPoliciesTests.swift](../RawCullTests/ImageReviewPoliciesTests.swift)

- [RAW failure restores the previous source and produces presentation inputs](../RawCullTests/ImageReviewPoliciesTests.swift#L7)
- [viewport policies clamp each surface to its own limits](../RawCullTests/ImageReviewPoliciesTests.swift#L24)
- [keyboard input resolves to shared semantic actions](../RawCullTests/ImageReviewPoliciesTests.swift#L37)
- [rating policy distinguishes unrated keeper reject and stars](../RawCullTests/ImageReviewPoliciesTests.swift#L51)
- [focus request identity rejects cancellation supersession and stale content](../RawCullTests/ImageReviewPoliciesTests.swift#L60)
- [subject outline context participates in request identity](../RawCullTests/ImageReviewPoliciesTests.swift#L82)

### ImageSourceSelectionStateTests (5)

[ImageSourceSelectionStateTests.swift](../RawCullTests/ImageSourceSelectionStateTests.swift)

- [selection can start with an extracted JPEG](../RawCullTests/ImageSourceSelectionStateTests.swift#L8)
- [extraction source toggles against thumbnail](../RawCullTests/ImageSourceSelectionStateTests.swift#L15) — parameterized
- [disabled RAW source ignores toggle](../RawCullTests/ImageSourceSelectionStateTests.swift#L26)
- [RAW failure restores previous source and disables RAW](../RawCullTests/ImageSourceSelectionStateTests.swift#L39)
- [new image clears RAW disable while preserving selected source](../RawCullTests/ImageSourceSelectionStateTests.swift#L51)

### ItemizedOutputTests (4)

[ItemizedOutputTests.swift](../RawCullTests/ItemizedOutputTests.swift)

- [Classifies rsync itemized output](../RawCullTests/ItemizedOutputTests.swift#L11)
- [Supports openrsync itemized output](../RawCullTests/ItemizedOutputTests.swift#L27)
- [Ignores empty and summary lines](../RawCullTests/ItemizedOutputTests.swift#L36)
- [Failed stats parsing keeps safe defaults](../RawCullTests/ItemizedOutputTests.swift#L44)

### LoupeImageKeyActionTests (7)

[LoupeImageKeyActionTests.swift](../RawCullTests/LoupeImageKeyActionTests.swift)

- [J resolves to embedded JPG](../RawCullTests/LoupeImageKeyActionTests.swift#L8) — parameterized
- [R resolves to developed RAW](../RawCullTests/LoupeImageKeyActionTests.swift#L13) — parameterized
- [F resolves to focus mask](../RawCullTests/LoupeImageKeyActionTests.swift#L18) — parameterized
- [S resolves to Deep Review subject outline](../RawCullTests/LoupeImageKeyActionTests.swift#L23) — parameterized
- [A resolves to autofocus points](../RawCullTests/LoupeImageKeyActionTests.swift#L28) — parameterized
- [E resolves to metadata panel](../RawCullTests/LoupeImageKeyActionTests.swift#L33) — parameterized
- [Z resolves to actual-pixels inspection](../RawCullTests/LoupeImageKeyActionTests.swift#L38) — parameterized

### LoupeSessionModelTests (2)

[LoupeSessionModelTests.swift](../RawCullTests/LoupeSessionModelTests.swift)

- [new source request rejects stale completion](../RawCullTests/LoupeSessionModelTests.swift#L9)
- [reset cancels work and clears owned previews](../RawCullTests/LoupeSessionModelTests.swift#L27)

### MemoryViewModelTests (1)

[MemoryViewModelTests.swift](../RawCullTests/MemoryViewModelTests.swift)

- [memory stats update populates coherent values](../RawCullTests/MemoryViewModelTests.swift#L9)

### ObjectAnalysisBoundaryTests (22)

[ObjectAnalysisBoundaryTests.swift](../RawCullTests/ObjectAnalysisBoundaryTests.swift)

- [Retry feedback names mismatched claim counts and missing focus evidence](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L8) — parameterized
- [Retry feedback explains invalid visibility and vague focus](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L26)
- [Undecodable feedback preserves typed errors and supplies a default](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L40)
- [Focus and claims require their own crop evidence and unverified expression abstains](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L47)
- [Sharp focus accepts equivalent resolved detail wording](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L69) — parameterized
- [Sharp focus still rejects unsupported or contradictory detail wording](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L81) — parameterized
- [Soft focus accepts negated sharpness without admitting positive sharpness](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L97) — parameterized
- [Retry feedback identifies focus contradictions](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L107)
- [Final retry abstains from captured butterfly focus wording](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L119)
- [Final retry abstains when focus evidence is explicitly null](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L135) — parameterized
- [Final focus abstention preserves supported objects](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L152)
- [Focus abstention preserves paired evidence and unaffected object ownership](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L157)
- [Focus abstention still requires explicit nullable fields](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L194) — parameterized
- [Final focus abstention rejects unrelated invalid data](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L204) — parameterized
- [Automatic concepts normalize and deduplicate](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L218)
- [Invalid discovery is surfaced](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L224)
- [Manual concepts reject empty entries](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L233)
- [Assessment accepts only rendered object IDs](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L240)
- [Wrapped JSON remains strict](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L252)
- [Assessment rejects invalid confidence and duplicate object IDs](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L266)
- [Captured assessment shape normalizes singular text lists](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L294)
- [Numeric board IDs normalize but still require an exact board match](../RawCullTests/ObjectAnalysisBoundaryTests.swift#L315)

### ObjectAnalysisFeatureTests (9)

[ObjectAnalysisFeatureTests.swift](../RawCullTests/ObjectAnalysisFeatureTests.swift)

- [AF point and highlighted focus edges map to the matching object](../RawCullTests/ObjectAnalysisFeatureTests.swift#L13)
- [Near-identical cross-concept masks merge and retain alias](../RawCullTests/ObjectAnalysisFeatureTests.swift#L56)
- [Review board rejects an object whose numbered crop is unavailable](../RawCullTests/ObjectAnalysisFeatureTests.swift#L88)
- [Grayscale instance mask becomes a transparent contour](../RawCullTests/ObjectAnalysisFeatureTests.swift#L103)
- [Model removal cancels an in-flight object result](../RawCullTests/ObjectAnalysisFeatureTests.swift#L122)
- [Manual analysis reports no matching objects without asking Qwen for a board](../RawCullTests/ObjectAnalysisFeatureTests.swift#L150)
- [Automatic analysis discovers, segments, and assesses one object](../RawCullTests/ObjectAnalysisFeatureTests.swift#L176)
- [Invalid assessment stays retryable and reuses cached segmentation](../RawCullTests/ObjectAnalysisFeatureTests.swift#L209)
- [Schema retry repairs assessment without repeating segmentation](../RawCullTests/ObjectAnalysisFeatureTests.swift#L237)

### ObjectAnalysisRealModelProbeTests (1)

[ObjectAnalysisRealModelProbeTests.swift](../RawCullTests/ObjectAnalysisRealModelProbeTests.swift)

- [probe one photo](../RawCullTests/ObjectAnalysisRealModelProbeTests.swift#L12) — opt-in: OBJECT_PROBE_IMAGE

### OverlayPresentationModelTests (3)

[OverlayPresentationModelTests.swift](../RawCullTests/OverlayPresentationModelTests.swift)

- [cancelled focus request cannot replace the new source](../RawCullTests/OverlayPresentationModelTests.swift#L8)
- [cancelling debounce prevents focus work](../RawCullTests/OverlayPresentationModelTests.swift#L37)
- [obsolete outline completion cannot clear A newer image](../RawCullTests/OverlayPresentationModelTests.swift#L53)

### PerFileAnalysisArtifactStoreTests (6)

[PerFileAnalysisArtifactStoreTests.swift](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift)

- [CLIP and Vision artifacts round-trip independently](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L8)
- [Source, backend, preview size, and pipeline changes are cache misses](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L51)
- [A corrupt record is isolated from valid records](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L175)
- [Usage and clear operate on individual records](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L227)
- [Replacement is atomic and cancellation preserves completed records](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L253)
- [Cancellation during persistence retains only completed records](../RawCullTests/PerFileAnalysisArtifactStoreTests.swift#L334)

### PhotoAIKitSimilarityMigrationTests (15)

[PhotoAIKitSimilarityMigrationTests.swift](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift)

- [CLIP retains successful artifacts and excludes failed images](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L407)
- [CLIP partial indexing captures image decoding failures](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L455)
- [CLIP reindexes only missing or stale artifacts](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L489)
- [Durable indexing survives relaunch and reindexes only added or modified files](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L541)
- [Vision and CLIP artifacts coexist without cross-loading](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L641)
- [Partial indexing persists successes and isolates invalid payloads](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L687)
- [Legacy burst artifacts migrate once into the per-file store](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L768)
- [Non-finite CLIP output retries once then reloads the provider](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L814)
- [Persistent non-finite CLIP output is excluded after provider reload](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L863)
- [Burst grouping excludes unindexed images and preserves hard boundaries](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L914)
- [PhotoAIKit Vision indexing produces complete reusable artifacts](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L939)
- [RawCull ranking policy is preserved behind the PhotoAIKit boundary](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L995)
- [Legacy burst artifacts are rejected and the current schema rebuild loads](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L1025)
- [Partial CLIP cache excludes files without validated artifacts](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L1099)
- [PhotoAIKit Vision indexing and ranking benchmark](../RawCullTests/PhotoAIKitSimilarityMigrationTests.swift#L1181)

### PhotoAnalysisKitIntegrationTests (2)

[PhotoAnalysisKitIntegrationTests.swift](../RawCullTests/PhotoAnalysisKitIntegrationTests.swift)

- [RawCull focus model analyzes through package Metal pipeline](../RawCullTests/PhotoAnalysisKitIntegrationTests.swift#L8)
- [RawCull breakdown preserves app scoring source](../RawCullTests/PhotoAnalysisKitIntegrationTests.swift#L27)

### QuitRecoveryTests (1)

[QuitRecoveryTests.swift](../RawCullTests/QuitRecoveryTests.swift)

- [failed save offers recovery and replies exactly once](../RawCullTests/QuitRecoveryTests.swift#L7) — parameterized

### QwenFeatureTests (20)

[QwenFeatureTests.swift](../RawCullTests/QwenFeatureTests.swift)

- [Local Qwen model answers a general vision request](../RawCullTests/QwenFeatureTests.swift#L11) — opt-in: QWEN_PHASE3_BUNDLE, QWEN_PHASE3_IMAGE
- [Input capabilities are absent before validation and after clear](../RawCullTests/QwenFeatureTests.swift#L41)
- [Qwen generation gate serializes and cancels queued work](../RawCullTests/QwenFeatureTests.swift#L76)
- [Assessment instruction requires evidence and permits abstention](../RawCullTests/QwenFeatureTests.swift#L101)
- [General Qwen request rejects an invalid token cap](../RawCullTests/QwenFeatureTests.swift#L111)
- [Structured assessment decodes JSON wrapped in model prose](../RawCullTests/QwenFeatureTests.swift#L126)
- [Structured assessment rejects scores outside the schema](../RawCullTests/QwenFeatureTests.swift#L155)
- [Free-form Qwen response counts as a successful result](../RawCullTests/QwenFeatureTests.swift#L164)
- [Response decoder preserves nonempty Qwen prose](../RawCullTests/QwenFeatureTests.swift#L177)
- [Response decoder uses structured assessment when valid](../RawCullTests/QwenFeatureTests.swift#L186)
- [Response decoder retains invalid structured output as rejected](../RawCullTests/QwenFeatureTests.swift#L200)
- [Response decoder rejects an empty Qwen response](../RawCullTests/QwenFeatureTests.swift#L209)
- [Unsupported criterion abstains without inventing an overall score](../RawCullTests/QwenFeatureTests.swift#L216)
- [Qwen inference runtime validates a compatible Core AI bundle](../RawCullTests/QwenFeatureTests.swift#L241)
- [Qwen inference runtime rejects a text-only Qwen model](../RawCullTests/QwenFeatureTests.swift#L268)
- [Analysis keeps prior results and only processes newly selected files](../RawCullTests/QwenFeatureTests.swift#L283)
- [Batch retains catalog access for later files after navigation](../RawCullTests/QwenFeatureTests.swift#L306)
- [Rejected oversized assessment retries once and reports field lengths](../RawCullTests/QwenFeatureTests.swift#L345)
- [Schema retry accepts repaired Qwen assessment](../RawCullTests/QwenFeatureTests.swift#L358)
- [arbitration waits for workers cancelled before the combined run](../RawCullTests/QwenFeatureTests.swift#L417)

### RawCullAIModelDownloadsTests (11)

[RawCullAIModelDownloadsTests.swift](../RawCullTests/RawCullAIModelDownloadsTests.swift)

- [Production catalog includes only configured models](../RawCullTests/RawCullAIModelDownloadsTests.swift#L8)
- [Coordinator blocks download before invoking its service](../RawCullTests/RawCullAIModelDownloadsTests.swift#L83)
- [Unconfigured managed service avoids Background Assets access](../RawCullTests/RawCullAIModelDownloadsTests.swift#L123)
- [affected macOS 27 Background Assets regressions are detected](../RawCullTests/RawCullAIModelDownloadsTests.swift#L138)
- [Affected runtime avoids Background Assets access](../RawCullTests/RawCullAIModelDownloadsTests.swift#L167)
- [Production models expose the Background Assets runtime failure](../RawCullTests/RawCullAIModelDownloadsTests.swift#L187)
- [Model management presents localized download failures](../RawCullTests/RawCullAIModelDownloadsTests.swift#L219)
- [Verified acceptance gates and unlocks a ready download](../RawCullTests/RawCullAIModelDownloadsTests.swift#L257)
- [Model management presents progress installation and removal](../RawCullTests/RawCullAIModelDownloadsTests.swift#L319)
- [Cancelling model management download restores coordinator state](../RawCullTests/RawCullAIModelDownloadsTests.swift#L385)
- [A changed licence checksum invalidates prior acceptance](../RawCullTests/RawCullAIModelDownloadsTests.swift#L428)

### RawCullAIModelRuntimeTests (9)

[RawCullAIModelRuntimeTests.swift](../RawCullTests/RawCullAIModelRuntimeTests.swift)

- [AI paths retain RawCull's canonical data namespaces](../RawCullTests/RawCullAIModelRuntimeTests.swift#L9)
- [Model runtime reports the complete Phase 1 capability surface](../RawCullTests/RawCullAIModelRuntimeTests.swift#L45)
- [Saved burst scan reads existing Vision cache evidence](../RawCullTests/RawCullAIModelRuntimeTests.swift#L152)
- [Model validation is reused until candidate metadata changes](../RawCullTests/RawCullAIModelRuntimeTests.swift#L225)
- [Missing and corrupt model resources recover after restoration](../RawCullTests/RawCullAIModelRuntimeTests.swift#L275)
- [Cancelling Settings refresh cancels its evidence scan](../RawCullTests/RawCullAIModelRuntimeTests.swift#L328)
- [CLIP enablement and exclusive model selection persist](../RawCullTests/RawCullAIModelRuntimeTests.swift#L355)
- [blocked segmenters are excluded and rejected](../RawCullTests/RawCullAIModelRuntimeTests.swift#L424)
- [Combined Review requires memory guidance before enabling](../RawCullTests/RawCullAIModelRuntimeTests.swift#L453) — parameterized

### RawCullIntelligenceRuntimeTests (8)

[RawCullIntelligenceRuntimeTests.swift](../RawCullTests/RawCullIntelligenceRuntimeTests.swift)

- [Application assembly shares one stable intelligence object graph](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L10)
- [Settings configuration updates the view model that shares runtime models](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L64)
- [Runtime shares one feature across similarity and semantic configuration](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L100)
- [Applying current services is a no-op for identity and hydration tasks](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L153)
- [Older configuration cannot replace a newer runtime identity](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L184)
- [Segmentation-only configuration preserves similarity work](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L228)
- [Configuration switch supersedes in-flight similarity hydration](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L268)
- [Weak typed configuration edges do not retain application state](../RawCullTests/RawCullIntelligenceRuntimeTests.swift#L330)

### RawCullSemanticSearchTests (13)

[RawCullSemanticSearchTests.swift](../RawCullTests/RawCullSemanticSearchTests.swift)

- [Semantic artifact handoffs preserve merge rules and observable facade revisions](../RawCullTests/RawCullSemanticSearchTests.swift#L296)
- [Semantic configuration replacement rejects an in-flight hydration completion](../RawCullTests/RawCullSemanticSearchTests.swift#L347)
- [Literal query encodes once, excludes Vision, isolates failures, and ranks deterministically](../RawCullTests/RawCullSemanticSearchTests.swift#L373)
- [Empty query and Vision-only snapshots are distinct typed failures](../RawCullTests/RawCullSemanticSearchTests.swift#L413)
- [Large searches show the top twenty and can expand all results](../RawCullTests/RawCullSemanticSearchTests.swift#L441)
- [Show all updates the admitted RawCull grid without rerunning CLIP](../RawCullTests/RawCullSemanticSearchTests.swift#L503)
- [Clear restores the catalog without discarding the scoped burst index](../RawCullTests/RawCullSemanticSearchTests.swift#L547)
- [Semantic selection scopes existing burst groups](../RawCullTests/RawCullSemanticSearchTests.swift#L643)
- [Preparing a reindex resets selection and restores the full catalog](../RawCullTests/RawCullSemanticSearchTests.swift#L708)
- [A superseded query cannot overwrite the newer result](../RawCullTests/RawCullSemanticSearchTests.swift#L747)
- [Cancellation returns to idle and ignores a late provider response](../RawCullTests/RawCullSemanticSearchTests.swift#L790)
- [Cached-only ranking composes with rating filters and clear restores catalog order](../RawCullTests/RawCullSemanticSearchTests.swift#L829)
- [Partial index, empty index, provider failure, and model switch remain distinct](../RawCullTests/RawCullSemanticSearchTests.swift#L879)

### RawCullSemanticSearchUITests (4)

[RawCullSemanticSearchUITests.swift](../RawCullTests/RawCullSemanticSearchUITests.swift)

- [capability controls](../RawCullTests/RawCullSemanticSearchUITests.swift#L44)
- [indexing state](../RawCullTests/RawCullSemanticSearchUITests.swift#L74)
- [result states](../RawCullTests/RawCullSemanticSearchUITests.swift#L106)
- [cancellation and clear state](../RawCullTests/RawCullSemanticSearchUITests.swift#L162)

### RawCullSimilarityFeatureTests (4)

[RawCullSimilarityFeatureTests.swift](../RawCullTests/RawCullSimilarityFeatureTests.swift)

- [Feature and semantic search share the exact model and feature](../RawCullTests/RawCullSimilarityFeatureTests.swift#L18)
- [Presentation hides backend descriptors and model progress](../RawCullTests/RawCullSimilarityFeatureTests.swift#L32)
- [Backend replacement resets burst state before replacing the model service](../RawCullTests/RawCullSimilarityFeatureTests.swift#L57)
- [Catalog hydration rejects a stale catalog identity](../RawCullTests/RawCullSimilarityFeatureTests.swift#L76)

### RawCullVerifyTestsDataRaceDetectionTests (2)

[RawCullVerifyTestsDataRaceDetectionTests.swift](../RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift)

- [cache supports concurrent nonisolated reads and writes](../RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift#L16) — parameterized
- [Extreme concurrent load reveals no data races](../RawCullTests/RawCullVerifyTestsDataRaceDetectionTests.swift#L52)

### RawCullVerifyViewModelSecurityScopeTests (7)

[RawCullVerifyViewModelSecurityScopeTests.swift](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift)

- [Worker grant survives switching roots and releases exactly once](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L8)
- [starting same active catalog does not duplicate security scoped access](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L32)
- [starting another catalog stops previous security scoped access](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L54)
- [stopping active catalog is idempotent](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L78)
- [failed start leaves no active security scoped access](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L97)
- [catalog cancellation stops active security scoped access](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L115)
- [empty catalog scan clears active load state and security scope](../RawCullTests/RawCullVerifyViewModelSecurityScopeTests.swift#L133)

### RawCullViewModelCullingTests (41)

[RawCullViewModelCullingTests.swift](../RawCullTests/RawCullViewModelCullingTests.swift)

- [AF scores persist separately and legacy records remain unmeasured](../RawCullTests/RawCullViewModelCullingTests.swift#L12)
- [rebuildRatingCache populates ratings and tagged filenames for selected catalog](../RawCullTests/RawCullViewModelCullingTests.swift#L35)
- [passesRatingFilter distinguishes rejected keepers and star ratings](../RawCullTests/RawCullViewModelCullingTests.swift#L53)
- [preselectFirstVisibleFileByName selects alphabetically first visible file](../RawCullTests/RawCullViewModelCullingTests.swift#L80)
- [preselectFirstVisibleFileByName replaces previous selection](../RawCullTests/RawCullViewModelCullingTests.swift#L94)
- [preselectFirstVisibleFileByName clears selection when no files are visible](../RawCullTests/RawCullViewModelCullingTests.swift#L110)
- [enabling AF sharpness sorting selects strongest AF detail despite combined scores](../RawCullTests/RawCullViewModelCullingTests.swift#L123)
- [disabling sharpness sorting preserves current selection](../RawCullTests/RawCullViewModelCullingTests.swift#L142)
- [burst analysis targets selected thumbnails before rating filter](../RawCullTests/RawCullViewModelCullingTests.swift#L156)
- [burst analysis targets exact active star rating](../RawCullTests/RawCullViewModelCullingTests.swift#L170)
- [burst analysis keeps full catalog for unscoped filters](../RawCullTests/RawCullViewModelCullingTests.swift#L186)
- [burst analysis orders shots by capture date with file-date fallback](../RawCullTests/RawCullViewModelCullingTests.swift#L210)
- [sharpness scoring targets selected thumbnails before rating filter](../RawCullTests/RawCullViewModelCullingTests.swift#L225)
- [sharpness scoring targets active star rating in visible order](../RawCullTests/RawCullViewModelCullingTests.swift#L240)
- [sharpness scoring falls back to filename sorted catalog for non-star filters](../RawCullTests/RawCullViewModelCullingTests.swift#L258)
- [sharpness scoring appends hidden selected files after visible selected files](../RawCullTests/RawCullViewModelCullingTests.swift#L283)
- [calibrateAndScoreCurrentCatalog scores and persists only target files](../RawCullTests/RawCullViewModelCullingTests.swift#L299)
- [extractRatedfilenames returns files at or above requested rating](../RawCullTests/RawCullViewModelCullingTests.swift#L340)
- [bulk updateRating updates culling model and cache](../RawCullTests/RawCullViewModelCullingTests.swift#L357)
- [rating mutations refresh the active rating-filter count](../RawCullTests/RawCullViewModelCullingTests.swift#L370)
- [clear all culling state synchronizes caches filters and persisted data](../RawCullTests/RawCullViewModelCullingTests.swift#L396)
- [applying Deep Review winner rates it three stars and marks group reviewed](../RawCullTests/RawCullViewModelCullingTests.swift#L428)
- [updateRatingAndAdvance rates current file and selects next visible file](../RawCullTests/RawCullViewModelCullingTests.swift#L468)
- [updateRatingAndAdvance marks active burst reviewed](../RawCullTests/RawCullViewModelCullingTests.swift#L486) — parameterized
- [updateRatingAndAdvance leaves last visible file selected](../RawCullTests/RawCullViewModelCullingTests.swift#L506)
- [updateRatingAndAdvance without catalog leaves rating and selection unchanged](../RawCullTests/RawCullViewModelCullingTests.swift#L522)
- [updateRatingAndAdvance with file outside visible order does not change selection](../RawCullTests/RawCullViewModelCullingTests.swift#L537)
- [clearCurrentCatalogCullingState allows rating same catalog again](../RawCullTests/RawCullViewModelCullingTests.swift#L554)
- [burst signatures are order independent and catalog relative](../RawCullTests/RawCullViewModelCullingTests.swift#L575)
- [cached review state restores by signature after file id remap](../RawCullTests/RawCullViewModelCullingTests.swift#L602)
- [cached review state ignores matching group id with changed membership](../RawCullTests/RawCullViewModelCullingTests.swift#L629)
- [cancelled burst analysis cannot apply a late cache result](../RawCullTests/RawCullViewModelCullingTests.swift#L656)
- [catalog cancellation resets all burst analysis state](../RawCullTests/RawCullViewModelCullingTests.swift#L702)
- [burst cache rejects a different similarity signature](../RawCullTests/RawCullViewModelCullingTests.swift#L727)
- [restoring an existing full burst index never starts scoring or indexing](../RawCullTests/RawCullViewModelCullingTests.swift#L767)
- [burst cache rejects groups produced by the previous timestamp algorithm](../RawCullTests/RawCullViewModelCullingTests.swift#L809)
- [burst cache reports usage and clears every catalog snapshot](../RawCullTests/RawCullViewModelCullingTests.swift#L840)
- [burst cache round trips a large snapshot off the main actor](../RawCullTests/RawCullViewModelCullingTests.swift#L871)
- [review state persistence keeps completed analysis scope](../RawCullTests/RawCullViewModelCullingTests.swift#L929)
- [live regroup review state follows membership instead of group id](../RawCullTests/RawCullViewModelCullingTests.swift#L980)
- [live regroup drops state when reused group id has changed membership](../RawCullTests/RawCullViewModelCullingTests.swift#L1007)

### RawImageLoadingIntegrationTests (10)

[RawImageLoadingIntegrationTests.swift](../RawCullTests/RawImageLoadingIntegrationTests.swift)

- [thumbnail request promotes source decode to memory for later hits](../RawCullTests/RawImageLoadingIntegrationTests.swift#L106)
- [thumbnail request decodes a replacement written at the same path](../RawCullTests/RawImageLoadingIntegrationTests.swift#L129)
- [full size preview loader saves extracted preview and reuses disk cache](../RawCullTests/RawImageLoadingIntegrationTests.swift#L163)
- [full size preview loader caches original embedded JPEG without recoding](../RawCullTests/RawImageLoadingIntegrationTests.swift#L182)
- [full size preview loader prefers sidecar jpg before raw extraction](../RawCullTests/RawImageLoadingIntegrationTests.swift#L209)
- [cancelled full size preview load does not save extracted image](../RawCullTests/RawImageLoadingIntegrationTests.swift#L230)
- [scan files uses loader metadata for exif and focus point](../RawCullTests/RawImageLoadingIntegrationTests.swift#L258)
- [embedded export ignores sidecars and preserves standalone JPEG bytes](../RawCullTests/RawImageLoadingIntegrationTests.swift#L331)
- [missing embedded pixels do not fall back to a sidecar](../RawCullTests/RawImageLoadingIntegrationTests.swift#L350)
- [helper providers read only their own temporary disk cache](../RawCullTests/RawImageLoadingIntegrationTests.swift#L361)

### ReleaseMetadataTests (5)

[ReleaseMetadataTests.swift](../RawCullTests/ReleaseMetadataTests.swift)

- [app and extension metadata are aligned](../RawCullTests/ReleaseMetadataTests.swift#L8)
- [README documents every exact resolved package pin](../RawCullTests/ReleaseMetadataTests.swift#L103)
- [model manifest catalog and destinations agree](../RawCullTests/ReleaseMetadataTests.swift#L132)
- [background assets metadata is complete](../RawCullTests/ReleaseMetadataTests.swift#L179)
- [model provenance status and notice hashes are complete](../RawCullTests/ReleaseMetadataTests.swift#L207)

### ReviewDiagnosticsTests (21)

[ReviewDiagnosticsTests.swift](../RawCullTests/ReviewDiagnosticsTests.swift)

- [optional shapes are isolated independently while malformed core still fails](../RawCullTests/ReviewDiagnosticsTests.swift#L8)
- [ambiguous aliases and invalid optional points abstain while oversized core text still fails](../RawCullTests/ReviewDiagnosticsTests.swift#L33)
- [scene conflicts span registered subjects but subject detail conflicts remain local](../RawCullTests/ReviewDiagnosticsTests.swift#L48)
- [fallback target flag alone cannot establish subject detail](../RawCullTests/ReviewDiagnosticsTests.swift#L69)
- [overview rejects copied instructions and discards undiscovered optional context](../RawCullTests/ReviewDiagnosticsTests.swift#L79)
- [partial synthesis retains valid observations and reports rejected claims](../RawCullTests/ReviewDiagnosticsTests.swift#L90)
- [rejections preserve the failing decoder or guard without copying untrusted text](../RawCullTests/ReviewDiagnosticsTests.swift#L108)
- [grounding ownership runtime mask geometry budget and timeout remain distinct](../RawCullTests/ReviewDiagnosticsTests.swift#L137)
- [raw text retention is UTF8 bounded separate from findings reloadable and cleanable](../RawCullTests/ReviewDiagnosticsTests.swift#L161)
- [synthesis resolves one subject and rejects swapped or unrelated support](../RawCullTests/ReviewDiagnosticsTests.swift#L181)
- [absent unknown and unregistered crop targets cannot establish detail](../RawCullTests/ReviewDiagnosticsTests.swift#L204)
- [numeric summaries preserve distinct subject values and stale evidence abstains](../RawCullTests/ReviewDiagnosticsTests.swift#L234)
- [texture alias still requires one qualified subject crop](../RawCullTests/ReviewDiagnosticsTests.swift#L254)
- [prompt eligibility excludes unidentified crops and measurements from detail](../RawCullTests/ReviewDiagnosticsTests.swift#L294)
- [v14 technical claims cannot exceed their cited observation](../RawCullTests/ReviewDiagnosticsTests.swift#L308)
- [technical excerpts preserve support and missing texture abstains](../RawCullTests/ReviewDiagnosticsTests.swift#L328)
- [criterion crops require nullable strings and keep anatomy outside observations](../RawCullTests/ReviewDiagnosticsTests.swift#L346)
- [criterion grounding prevents repeated prose and uncertainty becoming evidence](../RawCullTests/ReviewDiagnosticsTests.swift#L366)
- [criterion background blur uses its exact registered criterion boundary](../RawCullTests/ReviewDiagnosticsTests.swift#L386)
- [invalid selections recover validated priority rows without overriding null abstention](../RawCullTests/ReviewDiagnosticsTests.swift#L406)
- [null criteria preserve explicit abstention without contradictory flags](../RawCullTests/ReviewDiagnosticsTests.swift#L429)

### ReviewImageSourceTests (14)

[ReviewImageSourceTests.swift](../RawCullTests/ReviewImageSourceTests.swift)

- [source availability uses the same admission boundary as execution](../RawCullTests/ReviewImageSourceTests.swift#L12) — parameterized
- [orientation and source crops](../RawCullTests/ReviewImageSourceTests.swift#L21) — parameterized
- [coordinate and encoder round trips](../RawCullTests/ReviewImageSourceTests.swift#L61) — parameterized
- [clipping stable IDs and invalid bounds](../RawCullTests/ReviewImageSourceTests.swift#L87)
- [render isolation and lossless retention](../RawCullTests/ReviewImageSourceTests.swift#L108)
- [unsupported RAW fallback is explicit](../RawCullTests/ReviewImageSourceTests.swift#L132)
- [embedded loader never substitutes sidecar](../RawCullTests/ReviewImageSourceTests.swift#L151)
- [cancellation does not return source](../RawCullTests/ReviewImageSourceTests.swift#L166)
- [wide gamut ICC conversion](../RawCullTests/ReviewImageSourceTests.swift#L177)
- [HDR render is finite SDR](../RawCullTests/ReviewImageSourceTests.swift#L198)
- [bounded preview fallback preserves orientation](../RawCullTests/ReviewImageSourceTests.swift#L230) — parameterized
- [large Sony source receives a bounded preview](../RawCullTests/ReviewImageSourceTests.swift#L246)
- [memory admission rejects before decode](../RawCullTests/ReviewImageSourceTests.swift#L253)
- [full source working set](../RawCullTests/ReviewImageSourceTests.swift#L261)

### ReviewKeyboardScopeTests (5)

[ReviewKeyboardScopeTests.swift](../RawCullTests/ReviewKeyboardScopeTests.swift)

- [only anchored key window receives shortcuts](../RawCullTests/ReviewKeyboardScopeTests.swift#L23)
- [command modifiers are left to app kit](../RawCullTests/ReviewKeyboardScopeTests.swift#L39) — parameterized
- [native controls and text own their input](../RawCullTests/ReviewKeyboardScopeTests.swift#L49)
- [anchor tracks window and detaches](../RawCullTests/ReviewKeyboardScopeTests.swift#L70)
- [attached sheet keeps keys](../RawCullTests/ReviewKeyboardScopeTests.swift#L85)

### ReviewMaskProcessingTests (4)

[ReviewMaskProcessingTests.swift](../RawCullTests/ReviewMaskProcessingTests.swift)

- [background registration preserves producer diagnostics and deduplicated geometry](../RawCullTests/ReviewMaskProcessingTests.swift#L8)
- [crop support matches original scans and invalidates cache when mask changes](../RawCullTests/ReviewMaskProcessingTests.swift#L26)
- [retained inputs preserve grayscale foreground when eagerly decoded](../RawCullTests/ReviewMaskProcessingTests.swift#L43)
- [cancelled worker operation refuses a raster scan](../RawCullTests/ReviewMaskProcessingTests.swift#L58)

### ReviewMaskRegistrationTests (2)

[ReviewMaskRegistrationTests.swift](../RawCullTests/ReviewMaskRegistrationTests.swift)

- [asymmetric edge foreground stays registered after EXIF normalization](../RawCullTests/ReviewMaskRegistrationTests.swift#L10) — parameterized
- [foreground retention separates avoidable truncation from source edge contact](../RawCullTests/ReviewMaskRegistrationTests.swift#L45)

### ReviewPersistenceTests (8)

[ReviewPersistenceTests.swift](../RawCullTests/ReviewPersistenceTests.swift)

- [rating a scored record sets its date and later scoring preserves it](../RawCullTests/ReviewPersistenceTests.swift#L8)
- [rerating an existing record replaces its tagging date](../RawCullTests/ReviewPersistenceTests.swift#L24)
- [unread store rejects edits and a flush loads rather than overwrites history](../RawCullTests/ReviewPersistenceTests.swift#L39)
- [concurrent initialization shares one read and blocks edits while loading](../RawCullTests/ReviewPersistenceTests.swift#L61)
- [corrupt initialization preserves the file and remains blocked until explicit retry](../RawCullTests/ReviewPersistenceTests.swift#L87)
- [repaired history refreshes ratings filters selection and copy admission](../RawCullTests/ReviewPersistenceTests.swift#L122)
- [archiving damaged history clears stale presentation even if saving the reset fails](../RawCullTests/ReviewPersistenceTests.swift#L153)
- [restoration publishes scores once and preserves first duplicate and metadata validation](../RawCullTests/ReviewPersistenceTests.swift#L185)

### ReviewRunContractTests (12)

[ReviewRunContractTests.swift](../RawCullTests/ReviewRunContractTests.swift)

- [budgets reserve coverage and count every attempt](../RawCullTests/ReviewRunContractTests.swift#L7)
- [repairs have a separate finite allowance per image](../RawCullTests/ReviewRunContractTests.swift#L31)
- [compatibility changes only consuming stages](../RawCullTests/ReviewRunContractTests.swift#L44)
- [cancellation preserves independent observations and spent budget](../RawCullTests/ReviewRunContractTests.swift#L55)
- [invalidation propagates through completed descendants](../RawCullTests/ReviewRunContractTests.swift#L70)
- [manifests require every accepted image and acyclic dependencies](../RawCullTests/ReviewRunContractTests.swift#L84)
- [atomic artifacts restore partial work and reject future schemas](../RawCullTests/ReviewRunContractTests.swift#L97)
- [derived cache eviction preserves evidence and rejects traversal](../RawCullTests/ReviewRunContractTests.swift#L132)
- [evidence claims cannot invent IDs](../RawCullTests/ReviewRunContractTests.swift#L144)
- [resume rebuilds compatibility instead of trusting saved fields](../RawCullTests/ReviewRunContractTests.swift#L155)
- [latest run ignores filesystem modification dates and breaks creation ties](../RawCullTests/ReviewRunContractTests.swift#L165)
- [word boundaries permit ordinary observations and uncertainty limitations](../RawCullTests/ReviewRunContractTests.swift#L186)

### ReviewSubjectPriorityTests (5)

[ReviewSubjectPriorityTests.swift](../RawCullTests/ReviewSubjectPriorityTests.swift)

- [main rabbit precedes contextual flowers without using SAM confidence](../RawCullTests/ReviewSubjectPriorityTests.swift#L12)
- [primary mallard point must belong to registered foreground and ambiguity remains visible](../RawCullTests/ReviewSubjectPriorityTests.swift#L21)
- [overview priority cues require discovered concepts and normalized locations](../RawCullTests/ReviewSubjectPriorityTests.swift#L36)
- [overlay leaves background transparent and maps all source coordinates at different sizes](../RawCullTests/ReviewSubjectPriorityTests.swift#L49)
- [inspection canvas renders aligned transparent foreground at two sizes](../RawCullTests/ReviewSubjectPriorityTests.swift#L62)

### ReviewViewBoundaryTests (4)

[ReviewViewBoundaryTests.swift](../RawCullTests/ReviewViewBoundaryTests.swift)

- [zoom controls observe session viewport instead of unrelated loupe zoom](../RawCullTests/ReviewViewBoundaryTests.swift#L12)
- [burst header observes catalog changes independently of viewport changes](../RawCullTests/ReviewViewBoundaryTests.swift#L31)
- [loupe image content observes source changes independently of inactive preview images](../RawCullTests/ReviewViewBoundaryTests.swift#L46)
- [extracted review sections render at narrow and desktop widths](../RawCullTests/ReviewViewBoundaryTests.swift#L63) — parameterized

### SavedFilesJSONTests (6)

[SavedFilesJSONTests.swift](../RawCullTests/SavedFilesJSONTests.swift)

- [reader distinguishes missing and corrupt stores](../RawCullTests/SavedFilesJSONTests.swift#L12)
- [second write preserves previous store as backup](../RawCullTests/SavedFilesJSONTests.swift#L38)
- [write creates Application Support directory and saved files JSON](../RawCullTests/SavedFilesJSONTests.swift#L59)
- [older saved files JSON decodes](../RawCullTests/SavedFilesJSONTests.swift#L83)
- [read loads saved files from Application Support URL](../RawCullTests/SavedFilesJSONTests.swift#L102)
- [read ignores old Documents file when Application Support file exists](../RawCullTests/SavedFilesJSONTests.swift#L129)

### SavedFilesPresentationTests (4)

[SavedFilesPresentationTests.swift](../RawCullTests/SavedFilesPresentationTests.swift)

- [Legacy missing fields have display fallbacks without inventing ratings](../RawCullTests/SavedFilesPresentationTests.swift#L8)
- [Stored dates and rejected ratings survive presentation while sharpness is formatted](../RawCullTests/SavedFilesPresentationTests.swift#L35)
- [Source mutations invalidate presentation reads and preserve selection identity](../RawCullTests/SavedFilesPresentationTests.swift#L55)
- [Absent selections and missing record arrays have no rows or detail](../RawCullTests/SavedFilesPresentationTests.swift#L81)

### ScanAdmissionTests (2)

[ScanAdmissionTests.swift](../RawCullTests/ScanAdmissionTests.swift)

- [scan bounds metadata reads and coalesces monotonic progress](../RawCullTests/ScanAdmissionTests.swift#L60)
- [cancelling a scan stops admission and drains admitted workers](../RawCullTests/ScanAdmissionTests.swift#L77)

### ScanAndExtractJPGsTests (1)

[ScanAndExtractJPGsTests.swift](../RawCullTests/ScanAndExtractJPGsTests.swift)

- [unsupported files are counted as processed](../RawCullTests/ScanAndExtractJPGsTests.swift#L18)

### ScanFilesSortAndFormatTests (9)

[ScanFilesSortAndFormatTests.swift](../RawCullTests/ScanFilesSortAndFormatTests.swift)

- [sortFiles sorts by name ascending](../RawCullTests/ScanFilesSortAndFormatTests.swift#L32)
- [sortFiles sorts by date descending](../RawCullTests/ScanFilesSortAndFormatTests.swift#L49)
- [sortFiles sorts by date ascending](../RawCullTests/ScanFilesSortAndFormatTests.swift#L66)
- [sortFiles sorts by size ascending](../RawCullTests/ScanFilesSortAndFormatTests.swift#L83)
- [sortFiles filters search text case insensitively after sorting](../RawCullTests/ScanFilesSortAndFormatTests.swift#L100)
- [sortFiles can search by stem fragment](../RawCullTests/ScanFilesSortAndFormatTests.swift#L117)
- [sortFiles supports descending order for every field](../RawCullTests/ScanFilesSortAndFormatTests.swift#L134) — parameterized
- [sortFiles preserves input order when field values tie](../RawCullTests/ScanFilesSortAndFormatTests.swift#L155)
- [sortFiles handles empty and single-item input](../RawCullTests/ScanFilesSortAndFormatTests.swift#L172)

### SettingsPersistenceTests (3)

[SettingsPersistenceTests.swift](../RawCullTests/SettingsPersistenceTests.swift)

- [save failure preserves edits and retry persists them](../RawCullTests/SettingsPersistenceTests.swift#L7)
- [malformed load is observable and repaired settings can be retried](../RawCullTests/SettingsPersistenceTests.swift#L27)
- [absent settings use defaults without presenting an error](../RawCullTests/SettingsPersistenceTests.swift#L47)

### SettingsViewModelPersistenceTests (8)

[SettingsViewModelPersistenceTests.swift](../RawCullTests/SettingsViewModelPersistenceTests.swift)

- [settings save and load round trips through isolated file](../RawCullTests/SettingsViewModelPersistenceTests.swift#L9)
- [save during initial load preserves persisted cache maximums](../RawCullTests/SettingsViewModelPersistenceTests.swift#L44)
- [legacy settings JSON defaults scoring photo type to auto and ignores badge toggles](../RawCullTests/SettingsViewModelPersistenceTests.swift#L74)
- [new settings use package focus mask morphology defaults](../RawCullTests/SettingsViewModelPersistenceTests.swift#L100)
- [extreme settings JSON decodes inside supported ranges](../RawCullTests/SettingsViewModelPersistenceTests.swift#L111)
- [save writes normalized settings](../RawCullTests/SettingsViewModelPersistenceTests.swift#L155)
- [asyncgetsettings returns value snapshot](../RawCullTests/SettingsViewModelPersistenceTests.swift#L190)
- [asyncgetsettings returns normalized value snapshot](../RawCullTests/SettingsViewModelPersistenceTests.swift#L207)

### SharpnessScoringTests (16)

[SharpnessScoringTests.swift](../RawCullTests/SharpnessScoringTests.swift)

- [max score small set uses maximum not minimum](../RawCullTests/SharpnessScoringTests.swift#L17)
- [max score large set uses P 90](../RawCullTests/SharpnessScoringTests.swift#L35)
- [sharpness label maps threshold boundaries](../RawCullTests/SharpnessScoringTests.swift#L48)
- [sharpness label clamps and handles invalid denominator](../RawCullTests/SharpnessScoringTests.swift#L57)
- [auto photo type preserves current focus config](../RawCullTests/SharpnessScoringTests.swift#L65)
- [photo type presets map to expected scoring emphasis](../RawCullTests/SharpnessScoringTests.swift#L75)
- [scoring quality maps to compute cost and precision config](../RawCullTests/SharpnessScoringTests.swift#L105)
- [scoring signature uses package analysis descriptor](../RawCullTests/SharpnessScoringTests.swift#L132)
- [legacy scoring signature decodes as stale](../RawCullTests/SharpnessScoringTests.swift#L154)
- [AF ranking uses center detail without background or saliency fallback](../RawCullTests/SharpnessScoringTests.swift#L189)
- [AF ranking treats absent detail and invalid measurements as unknown](../RawCullTests/SharpnessScoringTests.swift#L206) — parameterized
- [AF sorting preserves ties and places unknown measurements last](../RawCullTests/SharpnessScoringTests.swift#L219)
- [legacy scores cannot enable AF sorting and AF measurements survive hydration](../RawCullTests/SharpnessScoringTests.swift#L231)
- [batch AF scoring rejects sharp background around a textureless focus point](../RawCullTests/SharpnessScoringTests.swift#L250)
- [loading cached burst AF evidence preserves best frame scores](../RawCullTests/SharpnessScoringTests.swift#L273)
- [concurrent scoreFiles call awaits in flight scoring](../RawCullTests/SharpnessScoringTests.swift#L295)

### SmokeManifestIntegrityTests (2)

[SmokeManifestIntegrityTests.swift](../RawCullTests/SmokeManifestIntegrityTests.swift)

- [manifest is ordered unique and unchanged](../RawCullTests/SmokeManifestIntegrityTests.swift#L6)
- [every source smoke declaration has a suite selector](../RawCullTests/SmokeManifestIntegrityTests.swift#L14)

### SubjectMaskFocusRegressionTests (4)

[SubjectMaskFocusRegressionTests.swift](../RawCullTests/SubjectMaskFocusRegressionTests.swift)

- [disjoint grayscale masks select different textures through PNG retention](../RawCullTests/SubjectMaskFocusRegressionTests.swift#L10)
- [grayscale and alpha have equivalent support bounds and scores](../RawCullTests/SubjectMaskFocusRegressionTests.swift#L35)
- [empty sparse and mismatched masks abstain explicitly while full masks are suspect](../RawCullTests/SubjectMaskFocusRegressionTests.swift#L60)
- [padded grayscale rows preserve raw threshold and contract registration](../RawCullTests/SubjectMaskFocusRegressionTests.swift#L82)

### ThumbnailCacheIdentityTests (7)

[ThumbnailCacheIdentityTests.swift](../RawCullTests/ThumbnailCacheIdentityTests.swift)

- [replacing source bytes at the same path changes thumbnail identity](../RawCullTests/ThumbnailCacheIdentityTests.swift#L9)
- [purpose and requested size identify separate representations](../RawCullTests/ThumbnailCacheIdentityTests.swift#L34)
- [missing source metadata bypasses thumbnail reuse](../RawCullTests/ThumbnailCacheIdentityTests.swift#L58)
- [atomic writers and cancelled save never leave a partial JPEG](../RawCullTests/ThumbnailCacheIdentityTests.swift#L76)
- [corrupt JPEG becomes a miss and is removed](../RawCullTests/ThumbnailCacheIdentityTests.swift#L116)
- [migration removes only legacy thumbnail JPEGs](../RawCullTests/ThumbnailCacheIdentityTests.swift#L133)
- [thumbnail representation changes preserve Vision CLIP and SAM identities](../RawCullTests/ThumbnailCacheIdentityTests.swift#L162)

### ThumbnailKeyActionTests (2)

[ThumbnailKeyActionTests.swift](../RawCullTests/ThumbnailKeyActionTests.swift)

- [Z resolves to actual-pixels inspection](../RawCullTests/ThumbnailKeyActionTests.swift#L8) — parameterized
- [unmapped thumbnail key is ignored](../RawCullTests/ThumbnailKeyActionTests.swift#L13)

### ThumbnailKeyboardRoutingTests (4)

[ThumbnailKeyboardRoutingTests.swift](../RawCullTests/ThumbnailKeyboardRoutingTests.swift)

- [burst commands have one owner](../RawCullTests/ThumbnailKeyboardRoutingTests.swift#L8) — parameterized
- [unavailable burst command cannot become rating two](../RawCullTests/ThumbnailKeyboardRoutingTests.swift#L19)
- [ordinary grid preserves existing shortcuts](../RawCullTests/ThumbnailKeyboardRoutingTests.swift#L31) — parameterized
- [unrelated keys continue to existing handlers](../RawCullTests/ThumbnailKeyboardRoutingTests.swift#L41) — parameterized

### ThumbnailLoaderConcurrencyTests (5)

[ThumbnailLoaderConcurrencyTests.swift](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift)

- [saturated loader queues waiter until slot is released](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L11)
- [cancelled queued waiter does not consume slot](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L39)
- [max concurrency bound holds while queued waiters cancel and resume](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L62)
- [cancelAll drains waiters without granting slots](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L97)
- [FIFO grant skips cancelled waiter](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L123)

### ThumbnailPreloadGateTests (3)

[ThumbnailPreloadGateTests.swift](../RawCullTests/ThumbnailPreloadGateTests.swift)

- [completed visible file is released while the catalog is still preloading](../RawCullTests/ThumbnailPreloadGateTests.swift#L8)
- [completion belongs to its own active session](../RawCullTests/ThumbnailPreloadGateTests.swift#L25)
- [other catalogs and failed-file completion never wait for the catalog end](../RawCullTests/ThumbnailPreloadGateTests.swift#L42)

### ThumbnailPreloadSaveOwnershipTests (1)

[ThumbnailPreloadSaveOwnershipTests.swift](../RawCullTests/ThumbnailPreloadSaveOwnershipTests.swift)

- [preload owns bounded saves and releases gates before disk completion](../RawCullTests/ThumbnailPreloadSaveOwnershipTests.swift#L96) — parameterized

### ThumbnailPresentationModelTests (3)

[ThumbnailPresentationModelTests.swift](../RawCullTests/ThumbnailPresentationModelTests.swift)

- [request identity includes representation and source revision](../RawCullTests/ThumbnailPresentationModelTests.swift#L11)
- [late old load cannot overwrite a newer image or its binding](../RawCullTests/ThumbnailPresentationModelTests.swift#L24)
- [cancelled load does not publish its result](../RawCullTests/ThumbnailPresentationModelTests.swift#L50)

### ThumbnailProviderTests (13)

[ThumbnailProviderTests.swift](../RawCullTests/ThumbnailProviderTests.swift)

- [new isolated cache starts empty](../RawCullTests/ThumbnailProviderTests.swift#L22)
- [thumbnail request for missing file returns nil](../RawCullTests/ThumbnailProviderTests.swift#L30)
- [cancelled thumbnail request returns nil without surfacing failure](../RawCullTests/ThumbnailProviderTests.swift#L43)
- [clear caches removes cached items](../RawCullTests/ThumbnailProviderTests.swift#L69)
- [preload nonexistent catalog reports no processed files](../RawCullTests/ThumbnailProviderTests.swift#L87)
- [production config uses larger limits than testing config](../RawCullTests/ThumbnailProviderTests.swift#L101)
- [custom config preserves explicit limits](../RawCullTests/ThumbnailProviderTests.swift#L110)
- [sixteen GB low free memory keeps adaptive baseline](../RawCullTests/ThumbnailProviderTests.swift#L123)
- [sixteen GB with five point six GB free prioritizes grid cache](../RawCullTests/ThumbnailProviderTests.swift#L140)
- [sixteen GB high free memory caps at safe tier](../RawCullTests/ThumbnailProviderTests.swift#L157)
- [adaptive cache respects user maximums](../RawCullTests/ThumbnailProviderTests.swift#L174)
- [warning pressure shrinks adaptive baseline](../RawCullTests/ThumbnailProviderTests.swift#L191)
- [thumbnail cost is based on pixel footprint](../RawCullTests/ThumbnailProviderTests.swift#L210)

### TypedAIPersistenceMatrixTests (4)

[TypedAIPersistenceMatrixTests.swift](../RawCullTests/TypedAIPersistenceMatrixTests.swift)

- [dataComp and OpenAI artifacts relaunch without cross-loading](../RawCullTests/TypedAIPersistenceMatrixTests.swift#L39)
- [source add replace rename and removal preserve only compatible active records](../RawCullTests/TypedAIPersistenceMatrixTests.swift#L83)
- [superseded semantic hydration cannot publish an older backend](../RawCullTests/TypedAIPersistenceMatrixTests.swift#L148)
- [a per-record write failure retains usable session artifacts and returns idle](../RawCullTests/TypedAIPersistenceMatrixTests.swift#L181)

### ZoomCullingMetadataTests (3)

[ZoomCullingMetadataTests.swift](../RawCullTests/ZoomCullingMetadataTests.swift)

- [rows are omitted when decision evidence is absent](../RawCullTests/ZoomCullingMetadataTests.swift#L9)
- [only present decision evidence creates rows](../RawCullTests/ZoomCullingMetadataTests.swift#L22)
- [vital culling and completed CLIP evidence create concise rows](../RawCullTests/ZoomCullingMetadataTests.swift#L35)

### ZoomKeyboardControllerTests (2)

[ZoomKeyboardControllerTests.swift](../RawCullTests/ZoomKeyboardControllerTests.swift)

- [exposure inspection keeps navigation and rating disabled](../RawCullTests/ZoomKeyboardControllerTests.swift#L8)
- [subject outline shortcut requires an available outline](../RawCullTests/ZoomKeyboardControllerTests.swift#L38)

### ZoomOverlayImagePolicyTests (2)

[ZoomOverlayImagePolicyTests.swift](../RawCullTests/ZoomOverlayImagePolicyTests.swift)

- [dedicated thumbnail analysis pixels are preferred over display pixels](../RawCullTests/ZoomOverlayImagePolicyTests.swift#L8)
- [CG display image remains the analysis fallback](../RawCullTests/ZoomOverlayImagePolicyTests.swift#L21)

### ZoomOverlayKeyActionTests (6)

[ZoomOverlayKeyActionTests.swift](../RawCullTests/ZoomOverlayKeyActionTests.swift)

- [horizontal arrows resolve to previous and next](../RawCullTests/ZoomOverlayKeyActionTests.swift#L8)
- [vertical arrows resolve to previous and next](../RawCullTests/ZoomOverlayKeyActionTests.swift#L22)
- [unrelated arrows are ignored for the active axis](../RawCullTests/ZoomOverlayKeyActionTests.swift#L36)
- [escape zoom and source shortcuts resolve](../RawCullTests/ZoomOverlayKeyActionTests.swift#L50)
- [rating shortcuts resolve from characters](../RawCullTests/ZoomOverlayKeyActionTests.swift#L104)
- [unmapped keys are ignored](../RawCullTests/ZoomOverlayKeyActionTests.swift#L153)

### ZoomOverlayLaunchContextTests (2)

[ZoomOverlayLaunchContextTests.swift](../RawCullTests/ZoomOverlayLaunchContextTests.swift)

- [default zoom overlay launch context preserves existing behavior](../RawCullTests/ZoomOverlayLaunchContextTests.swift#L9)
- [actual-pixels launch context requests embedded JPG and focus points](../RawCullTests/ZoomOverlayLaunchContextTests.swift#L21)

### ZoomOverlayNavigationContextTests (1)

[ZoomOverlayNavigationContextTests.swift](../RawCullTests/ZoomOverlayNavigationContextTests.swift)

- [context keeps first occurrence when duplicate IDs are supplied](../RawCullTests/ZoomOverlayNavigationContextTests.swift#L8)

### ZoomSessionModelTests (3)

[ZoomSessionModelTests.swift](../RawCullTests/ZoomSessionModelTests.swift)

- [preview clipping warning distinguishes white black and ordinary colors](../RawCullTests/ZoomSessionModelTests.swift#L9)
- [launch context initializes source zoom and focus presentation](../RawCullTests/ZoomSessionModelTests.swift#L37)
- [keyboard actions use shared zoom policy adapter](../RawCullTests/ZoomSessionModelTests.swift#L54)

### ZoomViewportMathTests (10)

[ZoomViewportMathTests.swift](../RawCullTests/ZoomViewportMathTests.swift)

- [landscape inspection maps one image pixel to one display point](../RawCullTests/ZoomViewportMathTests.swift#L8)
- [portrait inspection maps one image pixel to one display point](../RawCullTests/ZoomViewportMathTests.swift#L18)
- [inspection scale reduces a fit-upscaled preview to actual pixels](../RawCullTests/ZoomViewportMathTests.swift#L28)
- [aspect mismatch still maps the fitted image to actual pixels](../RawCullTests/ZoomViewportMathTests.swift#L38)
- [focus point pan centers a normalized point when there is room](../RawCullTests/ZoomViewportMathTests.swift#L55)
- [focus point pan clamps at all four image edges](../RawCullTests/ZoomViewportMathTests.swift#L68)
- [out of range focus point clamps to an image edge](../RawCullTests/ZoomViewportMathTests.swift#L100)
- [missing focus point keeps actual-pixels view centered](../RawCullTests/ZoomViewportMathTests.swift#L111)
- [invalid sizes use a finite centered fallback](../RawCullTests/ZoomViewportMathTests.swift#L123)
- [non finite focus point uses a centered fallback](../RawCullTests/ZoomViewportMathTests.swift#L145)

## Release/probe target — every test

### CombinedReviewInputProbe (2)

[CombinedReviewInputProbe.swift](../RawCullReleaseTests/CombinedReviewInputProbe.swift)

- [orientation fixtures preserve corner identity](../RawCullReleaseTests/CombinedReviewInputProbe.swift#L20)
- [verify installed inputs](../RawCullReleaseTests/CombinedReviewInputProbe.swift#L44) — opt-in: RAWCULL_INPUT_PROBE_RUN

### ReleaseAIObjectsTest (3)

[ReleaseAIObjectsTest.swift](../RawCullReleaseTests/ReleaseAIObjectsTest.swift)

- [discovers only top level regular ARW files](../RawCullReleaseTests/ReleaseAIObjectsTest.swift#L9)
- [report preserves failures and unprocessed files](../RawCullReleaseTests/ReleaseAIObjectsTest.swift#L25)
- [analyze downloads](../RawCullReleaseTests/ReleaseAIObjectsTest.swift#L46) — opt-in: RAWCULL_RELEASE_RUN

### ReleaseSharpnessTest (5)

[ReleaseSharpnessTest.swift](../RawCullReleaseTests/ReleaseSharpnessTest.swift)

- [analyze catalog](../RawCullReleaseTests/ReleaseSharpnessTest.swift#L10) — opt-in: RAWCULL_RELEASE_SHARPNESS_RUN
- [report preserves failures missing evidence and pending comparisons](../RawCullReleaseTests/ReleaseSharpnessTest.swift#L81)
- [summary distinguishes ranking changes from larger scores](../RawCullReleaseTests/ReleaseSharpnessTest.swift#L107)
- [rejects invalid scores](../RawCullReleaseTests/ReleaseSharpnessTest.swift#L150) — parameterized
- [export AF comparison dataset](../RawCullReleaseTests/ReleaseSharpnessTest.swift#L195) — opt-in: RAWCULL_AF_COMPARISON_RUN

## Python tooling — every test

### TestCompareAFSharpness (4)

- [test_exported_crop_workflow_prefers_sharp_edges](../Scripts/TestCompareAFSharpness.py#L13)
- [test_direction_ties_missing_and_exclusions](../Scripts/TestCompareAFSharpness.py#L34)
- [test_reversed_duplicates_rejected](../Scripts/TestCompareAFSharpness.py#L47)
- [test_burst_membership_required](../Scripts/TestCompareAFSharpness.py#L52)

### TestFreezeCombinedReviewBaseline (4)

- [test_inventory_keeps_identity_payload_and_hash_without_mutating_export](../Scripts/TestFreezeCombinedReviewBaseline.py#L10)
- [test_missing_export_is_explicit](../Scripts/TestFreezeCombinedReviewBaseline.py#L25)
- [test_truncated_or_invalid_png_header_is_rejected](../Scripts/TestFreezeCombinedReviewBaseline.py#L31)
- [test_png_dimensions_and_format_are_preserved](../Scripts/TestFreezeCombinedReviewBaseline.py#L41)

### TestModelProvenance (1)

- [test_invalid_enabled_evidence_is_rejected](../Scripts/TestModelProvenance.py#L10)

### TestRunAIAnalysis (3)

- [test_selection_is_sorted_unbounded_and_nonrecursive](../Scripts/TestRunAIAnalysis.py#L17)
- [test_runner_exit_and_evidence_outcomes](../Scripts/TestRunAIAnalysis.py#L48)
- [test_progress_ignores_incomplete_or_malformed_diagnostics](../Scripts/TestRunAIAnalysis.py#L53)

### TestRunCombinedReviewSix (4)

- [test_progress_tracks_execution_order_and_terminal_reports](../Scripts/TestRunCombinedReviewSix.py#L18)
- [test_all_files_are_sorted_and_ignore_non_raw_and_subdirectories](../Scripts/TestRunCombinedReviewSix.py#L70)
- [test_empty_directory_fails_before_xcode](../Scripts/TestRunCombinedReviewSix.py#L79)
- [test_runner_exit_and_evidence_outcomes](../Scripts/TestRunCombinedReviewSix.py#L88)

### TestRunnerPrivacy (1)

- [test_private_outputs_restore_callers_umask_on_success_and_failure](../Scripts/TestRunnerPrivacy.py#L14)

The exported-crop integration test in TestCompareAFSharpness requires OpenCV and skips when it is unavailable.

## Supporting files without test declarations

- [BurstAnalysisCoordinatorTestSupport.swift](../RawCullTests/BurstAnalysisCoordinatorTestSupport.swift)
- [CullingTestSupport.swift](../RawCullTests/CullingTestSupport.swift)
- [TestIsolationHelpers.swift](../RawCullTests/TestIsolationHelpers.swift)
- [TestTags.swift](../RawCullTests/TestTags.swift)
- [CombinedReviewInputFixtures.swift](../RawCullReleaseTests/CombinedReviewInputFixtures.swift)
- [ReleaseAnalysisReport.swift](../RawCullReleaseTests/ReleaseAnalysisReport.swift)
- [ReleaseRunConfiguration.swift](../RawCullReleaseTests/ReleaseRunConfiguration.swift)
- [ReleaseSharpnessReport.swift](../RawCullReleaseTests/ReleaseSharpnessReport.swift)

TestManifests lists selected tests; Scripts/VerifyTestEnumeration.swift validates Xcode enumeration; Scripts/VerifyAIImportBoundary.sh and Scripts/VerifyModelProvenance.py provide additional validation outside the Swift test suites.
