# RawCull 3.4.9 engineering review

Reviewed November 23, 2026, against app commit `0513a30e`, the revision recorded in the supplied graph. Source references below are relative to the RawCull repository. Links to sibling packages use the local multi-repository layout.

## Executive summary

1. Fix persistence of burst review decisions first. Reviewed and deferred states share a file with derived analysis. Valid catalog paths can prevent that file from being written, and the caller discards the failure.
2. Fix comparison-image publication next. Reloading one pane can discard valid work for other panes. A late focus result can also replace a newer group’s images. Both bugs survive main-actor isolation.
3. Preserve all rsync output in the details table. Short failed runs can currently display zero detail rows.
4. Reuse the burst workspace’s catalog lookup during selection changes. The repeated allocations are visible in source. Their effect on frame time remains unmeasured.
5. Resolve the configured thumbnail size before choosing the grid cache. Correct the similarity comparator’s result when comparing the anchor with itself.
6. Keep the existing package boundaries. The apparent package dependency on the app’s logger was a graph attribution error.
7. Preserve the narrow AI and MCP projections of the core file item. Its graph centrality reflects real domain use.
8. Prioritize state ownership over splitting large files. Burst review persistence and comparison-image publication have concrete failure modes that identify useful seams.
9. The app smoke suite passed after verification of 384 unique test identifiers. All 28 tests in the local RawCullCore checkout passed. The AI import-boundary check, model-provenance script test, and runner-privacy script test also passed.
10. This review combined source inspection, targeted tests, and a filesystem reproduction. The full Thread Sanitizer plan, interactive frame-time measurements, a VoiceOver walkthrough, and packaged-release entitlement or network-traffic audits were outside the verification performed.

### Health by dimension

| Dimension | Grade | Basis |
|---|---|---|
| Concurrency correctness | B | Catalog sorting revalidates generation, source, order, and search text after suspension. Comparison image operations lack a common publication rule across operation types. [Catalog guard](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L368) |
| Architecture and design | B | Contracts and injected services establish real boundaries. The burst-cache contract permits manual decisions to fail silently. [Cache repository](../RawCull/Intelligence/BurstAnalysis/BurstAnalysisCacheRepository.swift#L8) |
| Idiomatic Swift | B | The one-child task group documents the invariant behind its forced unwrap. The similarity comparator violates strict ordering. [Task helper](../RawCull/Extensions/extension+Task+Detached.swift#L20) |
| SwiftUI | B | Keyed tasks, focused keyboard handling, accessibility labels, Settings, commands, and split navigation are present. State publication and burst presentation need attention. [Comparison lifecycle](../RawCull/Views/ComparisonGridView/ComparisonGridView.swift#L65) · [App scenes](../RawCull/Main/RawCullApp.swift#L195) |
| Performance and memory | B | Scanning bounds concurrent metadata reads and thumbnail admission has an explicit limit. Presenting one burst still performs catalog-sized work. [Scan admission](../RawCull/Actors/ScanFiles.swift#L133) · [Thumbnail admission](../RawCull/Actors/ThumbnailLoader.swift#L34) |
| Tests | B | The smoke suite and controlled concurrency tests provide useful coverage. The bulk-reload test accepts discarding a batch without checking unaffected panes. [Policy test](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L121) |
| Security and privacy | B | Reviewed paths use scoped bookmarks, read-only MCP catalog access, job and grant checks, local stdio, and recorded model-licence acceptance. The privacy manifest declares tracking disabled and lists timestamp and defaults access. [MCP bookmark](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L58) · [Transport](../Tools/RawCullMCP/Sources/RawCullMCP/RawCullMCPMain.swift#L39) · [Licence gate](../RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift#L397) · [Manifest](../RawCull/PrivacyInfo.xcprivacy#L5) |

## Findings in priority order

The first five rows are the top five risks. Medium severity reflects loss of review progress, incorrect comparison state, or missing operational diagnostics. The review found no evidence that these defects modify original photographs.

| ID | Severity | Category | Location | Finding | Verification |
|---|---|---|---|---|---|
| RC-02 | Medium | Persistence | [BurstAnalysisCache](../RawCull/Intelligence/Persistence/BurstAnalysisCache.swift#L388) | Long catalog paths produce unwritable cache filenames. Failures saving user decisions are discarded. | Filesystem failure reproduced and save path traced |
| RC-03 | Medium | Concurrency | [ComparisonSessionModel](../RawCull/Model/ViewModels/ComparisonSessionModel.swift#L234) | Reloading one pane can leave unrelated panes waiting for images. | Confirmed in source |
| RC-04 | Medium | Concurrency and SwiftUI | [ComparisonSessionModel](../RawCull/Model/ViewModels/ComparisonSessionModel.swift#L288) | A late focus result can restore an older group’s image dictionary. | Confirmed publication ordering in source |
| RC-05 | Medium | Error presentation | [DetailsView](../RawCull/Views/OutputViews/DetailsView.swift#L89) | The rsync details table drops its last 11 lines, including failure diagnostics. | Confirmed in source |
| RC-06 | Low | SwiftUI performance | [BurstCullingWorkspaceView](../RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift#L419) | Displaying one burst repeatedly builds a catalog-wide lookup. | Work confirmed, latency unmeasured |
| RC-01 | Low | Thumbnail correctness | [ThumbnailLoader](../RawCull/Actors/ThumbnailLoader.swift#L80) | A warm 200-pixel image can satisfy a request for the configured preview size. | Loader behavior confirmed, screen impact unverified |
| RC-07 | Low | Swift correctness | [CatalogController sorting](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L459) | The similarity comparator orders the anchor before itself. | Predicate violation confirmed, visible misordering unverified |

### RC-02 · Manual burst decisions can silently fail to persist

The cache key uses `Data(catalog.path.utf8).base64EncodedString()`, strips padding, and adds `.json`. The entire path becomes one filename component. On a filesystem with a 255-byte component limit, 188 path bytes yield a 256-byte filename including the suffix. A valid nested catalog with a 270-byte path produced a 365-byte cache filename in the filesystem check. Writing it failed with macOS error 63, “File name too long.” [Key construction](../RawCull/Intelligence/Persistence/BurstAnalysisCache.swift#L388)

Marking a group reviewed or deferred updates the session and calls the snapshot persistence path. The snapshot includes `reviewStateSnapshots`. The writer returns false on failure and the coordinator executes `_ = await cacheRepository.save(snapshot, catalog: catalog)`. A photographer can mark groups, close the catalog, and reopen it without those decisions. The discarded error also applies when a volume is full. Original image files and separately stored ratings follow different paths. [Review actions](../RawCull/Model/ViewModels/BurstWorkflowController+Grouping.swift#L449) · [Snapshot construction](../RawCull/Model/ViewModels/BurstWorkflowController+Grouping.swift#L712) · [Save result](../RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator.swift#L319)

**Fix.** Use a fixed-length SHA-256 digest of the catalog identity for the filename. On a digest-key miss, attempt the legacy filename when its component length is valid. Migrate only after decoding and validating the legacy snapshot, and retain it until the new write succeeds. Return the save outcome to the review-state owner. Keep manual decisions visibly pending after failure and allow a retry. [Existing digest implementation](../RawCull/Intelligence/Persistence/FaceEvidenceCache.swift#L94)

**Regression tests.** Round-trip reviewed and deferred flags for a deeply nested catalog. Restore a valid short-path legacy snapshot and reopen using the new key. Inject a failing writer after marking a group deferred, verify the UI retains the pending decision, then verify retry persists it.

### RC-03 · A one-pane reload can strand other comparison panes

The bulk loader fills a local dictionary and returns it as a unit. Changing the source in pane A starts a reload and increments the session-wide `imageMutationRevision`. The bulk completion requires `currentMutationRevision == mutationRevision`, so it discards its whole result. The reload then publishes only A. If B and C did not already have images, their views continue to display a progress indicator. The policy test expressly expects the batch rejection but never checks B or C. [Bulk loading](../RawCull/Views/ComparisonGridView/ComparisonGridImageCoordinator.swift#L29) · [Session publication](../RawCull/Model/ViewModels/ComparisonSessionModel.swift#L234) · [Source change](../RawCull/Views/ComparisonGridView/ComparisonPane.swift#L39) · [Pane fallback](../RawCull/Views/ComparisonGridView/ComparisonImagePaneView.swift#L34) · [Policy test](../RawCullTests/ComparisonGridImageCoordinatorTests.swift#L121)

**Fix.** Retain the session generation for navigation. Capture a source revision for each file in the bulk request. For a still-current group, merge images and source flags only for files whose revisions still match. A’s newer source and image survive, and B and C can complete normally.

**Regression test.** Suspend a three-file bulk load through the injected image service, reload A, and release the two operations in each order. Assert all three final images and source flags. The existing controlled reload test provides the fixture pattern. [Comparison session tests](../RawCullTests/ComparisonSessionModelTests.swift#L245)

### RC-04 · A late focus result can replace the newly displayed group

Focus regeneration captures `let states = imageStates`. Its worker starts from `var updatedStates = states` and returns that dictionary. The session publishes it with `imageStates = updatedStates`. A bulk load can replace the displayed group without advancing the revision checked by the focus request. If focus analysis for group A starts, group B loads, and A finishes last, the session can hold A’s image states while displaying B. The view starts bulk loading and focus regeneration independently. [View triggers](../RawCull/Views/ComparisonGridView/ComparisonGridView.swift#L78) · [Focus publication](../RawCull/Model/ViewModels/ComparisonSessionModel.swift#L288) · [Worker](../RawCull/Views/ComparisonGridView/ComparisonGridImageCoordinator.swift#L118)

**Fix.** Invalidate pending focus work when the displayed file set changes. Return focus results keyed by file and merge only focus fields when the session and image revisions still match. Preserve the current image dictionary and source selection.

**Regression test.** Hold A’s focus result, publish B, then release A. Verify B’s keys, pixels, and image sources survive. Also exercise a same-group focus setting change during bulk loading so the latest legitimate focus configuration is applied.

### RC-05 · Copy details remove the diagnostics users are asked to inspect

The termination handler appends the failure text to the end of the output and the row builder preserves each line. The details table then executes `originalRecords.dropLast(min(11, originalRecords.count))`. An eight-line failed run displays zero detail rows. Longer failures lose their trailing diagnostics. A summary remains visible, but its instruction to review the output leads to an incomplete table. [Termination handler](../RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift#L270) · [Row builder](../RawCull/Actors/CreateOutputforView.swift#L12) · [Summary](../RawCull/Views/CopyFiles/CopyFilesView.swift#L104) · [Table](../RawCull/Views/OutputViews/DetailsView.swift#L89)

**Fix and test.** Pass `originalRecords` directly to the table. The existing row renderer already handles unparsed diagnostic lines. If a transfer-only summary is desired, filter recognized statistics separately and keep the raw output accessible. Extend the real-rsync completion test with a short failure and assert that its final diagnostic reaches the detail rows. [Fallback renderer](../RawCull/Views/OutputViews/ItemizedOutputRow.swift#L26) · [Real-rsync test](../RawCullTests/CopyCompletionTests.swift#L34)

### RC-06 · A small burst repeatedly indexes the active catalog

For a normal burst group, `bestFrameFiles` builds `Dictionary(uniqueKeysWithValues: catalogController.activeCatalogFiles.map { ($0.id, $0) })`. The view computes `displayedFiles = files`, then accesses selected-file and candidate properties that evaluate the lookup again. Selection or progress updates can repeat catalog-sized allocations even when the displayed burst contains only a few frames. Source inspection establishes the repeated work. No interactive slowdown was measured. [View body](../RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift#L122) · [Group lookup](../RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift#L419)

**Fix and test.** Derive the selected file, candidate, and index from the already computed displayed files. If navigation still needs a catalog-wide index, retain it at the active-scope boundary and invalidate it when the catalog or semantic selection changes. Count builds while navigating a small burst in a large catalog. The performance suite already checks an analogous invariant for zoom ordering. [Zoom performance assertion](../RawCullPerformanceTests/CatalogPerformanceTests.swift#L299)

### RC-01 · A warm grid cache overrides a default preview request

Zero requests the configured preview size. The loader checks `if targetSize <= 200` before it calls `resolvedTargetSize(targetSize)`. With a warm grid cache a zero request immediately returns 200 pixels. On a miss it can wait for grid preloading and then return the same undersized image. The existing test verifies resolution to 1,024 and 2,048 through the helper. It does not exercise the cache branch. The current screen impact of passing zero was not established. [Loader](../RawCull/Actors/ThumbnailLoader.swift#L80) · [Size-resolution test](../RawCullTests/ThumbnailLoaderConcurrencyTests.swift#L18)

**Fix and test.** Compute `let requestedSize = await resolvedTargetSize(targetSize)` before the grid branches. Use that same value for cache admission and decoding. Request zero with a warm 200-pixel cache and a 1,024-pixel preview setting. Assert that the preview path requests 1,024. Use an explicit 200-pixel request as the cache-hit control.

### RC-07 · The anchor sort predicate violates strict ordering

The similarity comparator begins with `if lhs.id == anchorID { return true }`. Comparing the anchor with itself therefore returns true. This violates the ordering contract even if a particular catalog happens to appear in the expected order. [Sort predicate](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L459)

**Fix and test.** Compute both operands’ anchor status. When the statuses differ, return whether the left operand is the anchor. Otherwise apply the existing distance and name comparison. Test the anchor against itself, the anchor on each side of a different file, and two files with tied distances.

## Graph-informed architecture map

The report describes 7,174 nodes, 18,431 edges, and 292 communities. Nine percent of edges were inferred. The local graph records the same app revision as the checkout. The app pins package releases independently of the local sibling checkouts. In particular, RawCullCore 1.1.5 in the app and the local core checkout implement the same file-item equality. The explanatory identity comment is newer in the local checkout.

PhotoAIKit exposes contracts, workflows, storage, and backend targets. The workflows and storage targets depend on PhotoAIContracts. App composition supplies implementations, including the Vision serializer. PhotoEvidenceEngine depends on PhotoEvidenceContracts, and PhotoEvidenceUI depends on both. At the app boundary, similarity maps FileItem to AIImageSource and the MCP catalog summary maps it to CatalogPhoto. These projections already limit what crosses package and process boundaries. [PhotoAIKit manifest](../../PhotoAIKit/Package.swift#L30) · [PhotoEvidenceKit manifest](../../PhotoEvidenceKit/Package.swift#L14) · [AI projection](../RawCull/Intelligence/Similarity/SimilarityScoringModel.swift#L1002) · [MCP projection](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L27)

| Graph hub | Edges | Source-based assessment |
|---|---:|---|
| RawCullFileItem | 343 | Earned. An immutable, sendable identity and metadata value is used throughout catalog workflows. Keep analysis and UI state in their existing owners. [Core type](../../RawCullCore/Sources/RawCullCore/RawCullFileItem.swift#L4) |
| BurstWorkflowController | 111 | Broad. Analysis generation, regrouping, navigation, decisions, undo, and persistence have different failure boundaries. Extract decision persistence first. [Grouping and review actions](../RawCull/Model/ViewModels/BurstWorkflowController+Grouping.swift#L213) |
| SimilarityScoringModel | 106 | Broad. Artifact hydration, admission, indexing, ranking, and grouping share an owner. Index supersession, waiters, and completion form a credible extraction. [Index coordination](../RawCull/Intelligence/Similarity/SimilarityScoringModel.swift#L901) |
| CombinedReviewFeature | 103 | Mostly earned. Prepare, analyze, resume, and cancel share a run and lease. Execution already distinguishes prepare, plan, inspect, and finish. [Feature](../RawCull/Intelligence/CombinedReview/CombinedReviewFeature.swift#L200) · [Stages](../RawCull/Intelligence/CombinedReview/Execution/CombinedReviewExecution.swift#L27) |
| CatalogController | 101 | Mixed. Switching sources and cancelling work belong together. Filtering and ranking can move independently while generation and source validation remain with the owner. [Sort publication](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L354) |
| CGRect | 97 | Earned. Requested, padded, source, and retained rectangles are explicit evidence fields. Preserve coordinate-space names. [Region record](../RawCull/Intelligence/CombinedReview/Evidence/ReviewEvidence.swift#L161) |
| AnalysisJobStore | 88 | Earned. Cross-process locking, worker leases, recovery, and transition writes benefit from one transaction boundary. [Locks and leases](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L141) |
| MCPAnalysisController | 83 | Broad but defensible. It coordinates persistent jobs with the live workspace. Grant and job-currentness validation could be extracted if reused. Preserve the final publication check. [Authorization](../RawCull/Main/MCPAnalysisController.swift#L504) |
| RawCullSimilarityFeature | 82 | Mostly earned. It adapts app context, tracks catalog identity, and coordinates hydration and ranking. Preserve this boundary while simplifying the scoring model. [Feature](../RawCull/Intelligence/Similarity/RawCullSimilarityFeature.swift#L276) |
| RawCullViewModel | 80 | Earned as a composition root. Selection, rating, catalog, and workflow already have distinct owners. [Composition](../RawCull/Model/ViewModels/RawCullViewModel.swift#L101) |

### Low-cohesion communities

- **Comparison Session Model.** Keep one session owner. Give loading, reloads, and mask updates a shared publication policy with per-file revisions. RC-03 and RC-04 identify the boundary that needs work. [Session state](../RawCull/Model/ViewModels/ComparisonSessionModel.swift#L113)
- **Review Evidence and Review Evidence Types.** Persisted records and claim validation are useful file-level seams. The graph scores alone do not justify a package split and its migration cost. [Evidence records and validation](../RawCull/Intelligence/CombinedReview/Evidence/ReviewEvidence.swift#L95)
- **Combined Review UI.** The inspector file already contains separate view types and route state. File length overstates the amount of code in any single view body. [Inspector views](../RawCull/Views/AIAnalysis/CombinedReviewInspectorPane.swift#L117)
- **Burst Workflow Controller Grouping.** Manual decisions have different durability requirements from derived scores. This is the strongest candidate for a split. [State persistence](../RawCull/Model/ViewModels/BurstWorkflowController+Grouping.swift#L608)

### Five inferred connections checked against source

| Graph connection | Result |
|---|---|
| SubjectMaskDiskStore → app Logger extension | False attribution. The package imports OSLog and constructs its own logger. The app defines a separate Logger.process. [Package logger](../../PhotoAIKit/Sources/PhotoAIStorage/SubjectMaskDiskStore.swift#L12) · [App extension](../RawCull/Extensions/extension+Thread+Logger.swift#L25) |
| CombinedReviewTechnicalDetails → TextEmbedding.values | False attribution. The receiver is ReviewMeasurement and its values property is a dictionary of measurements. [View](../RawCull/Views/AIAnalysis/CombinedReviewTechnicalDetails.swift#L65) · [Property](../RawCull/Intelligence/CombinedReview/Evidence/ReviewEvidence.swift#L70) |
| selectedCandidate → BurstAnalysisResult | Confirmed indirectly. The view obtains a candidate score through analysis.candidates. [Selection](../RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift#L447) |
| canIndexSemanticSearchArtifacts → SimilarityBackendDescriptor | Confirmed. The capability check tests membership of the semantic backend in the configured artifact descriptors. [Capability check](../RawCull/Intelligence/Similarity/SimilarityScoringModel.swift#L215) |
| BurstDetectedFaceLoader → FaceEvidenceAnalyzer | Confirmed. The loader directly constructs the package analyzer. [Loader](../RawCull/Views/ComparisonGridView/BurstDetectedFacesView.swift#L125) |

None of these five edges establishes a package dependency back into the app. A sample of the 1,409 weakly connected symbols also showed why low graph degree is weak evidence of dead code. Source callers exist for recordHeartbeat(), resetForCatalogChange(), and clearBurstGrouping(). AppKit invokes the viewDidMoveToWindow() override through its lifecycle. Retain all four. [Heartbeat caller](../RawCull/Main/MCPAnalysisController+Analysis.swift#L63) · [Ratings reset](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L201) · [Grouping reset](../RawCull/Model/ViewModels/BurstWorkflowController+Grouping.swift#L664) · [AppKit override](../RawCull/Views/Modifiers/ReviewKeyboardScope.swift#L68)

## Strengths to preserve

- **Cancellation and bounded thumbnail admission.** The structured detachedCancellable helper runs decoding as a child task, propagating cancellation. The thumbnail loader transfers an occupied slot directly to the next waiter and installs its release defer before checking cancellation. Preserve the distinction between cancellable request work and independent cache writes. [Helper](../RawCull/Extensions/extension+Task+Detached.swift#L20) · [Slot handoff](../RawCull/Actors/ThumbnailLoader.swift#L67)
- **Vision serialization.** RawCull injects a serializer that routes PhotoAIKit requests through PhotoAnalysisKit’s shared VisionRequestGate. Inspecting the package defaults alone would miss the live wiring. [Composition](../RawCull/Intelligence/Composition/RawCullAIModelRuntime.swift#L74) · [Adapter](../RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift#L16)
- **Cache accounting.** TrackedThumbnailCache justifies unchecked sendability through private lock-protected mutable state, a recursive lock for delegate callbacks, and entry IDs for replacements. CachedThumbnail relies on a separate invariant: its NSImage is fully constructed and treated as immutable after publication. The inspected paths supplied no demonstrated violation. [Tracked cache](../RawCull/Model/Cache/TrackedThumbnailCache.swift#L4) · [Image wrapper](../RawCull/Model/Cache/CachedThumbnail.swift#L15)
- **Catalog transitions and ratings recovery.** Catalog loading drains the thumbnail actor, publishes final counts, and rejects callbacks for an old progress object. The culling store preserves damaged ratings data and blocks automatic mutation after a failed read. Both patterns apply to review-state durability. [Progress completion](../RawCull/Model/ViewModels/CatalogController+Loading.swift#L309) · [Ratings recovery](../RawCull/Model/ViewModels/CullingModel.swift#L91)
- **Copy safety.** Per-operation include lists, NUL-delimited literal filenames, structured process arguments, and separate scoped access for source and destination all reduce ambiguity. Keep these while fixing the details table. [Copy arguments](../RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift#L155) · [Filename test](../RawCullTests/ExecuteCopyFilesStartupTests.swift#L94)
- **MCP and model management.** The inspected MCP path checks job identity and catalog authorization before publication and uses a local stdio transport. Model download checks recorded licence acceptance. The import-boundary and script tests passed, but the runner-privacy test concerns the test runner’s output permissions and does not establish app-wide privacy compliance. [Current-job check](../RawCull/Main/MCPAnalysisController.swift#L520) · [Licence gate](../RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift#L397) · [Runner test](../Scripts/TestRunnerPrivacy.py#L12)

## Prioritized roadmap

| Order | Work | Dependency and acceptance criterion |
|---|---|---|
| Quick wins, roughly under one hour each | Preserve all detail rows (RC-05), resolve preview size first (RC-01), and correct the comparator (RC-07). | Independent changes. Verify short copy failures, warm-cache preview requests, and strict anchor ordering respectively. |
| First medium change | Bound the burst-cache filename, migrate legacy entries, and surface decision-save failures (RC-02). | Verify long-path reopening, migration, and retry before changing where manual state lives. |
| Second medium change | Unify comparison publication rules (RC-03 and RC-04). | One session generation, per-file source revisions, and field-level focus updates. Verify both completion orders through the injected service. |
| Performance follow-up | Reuse resolved files and count burst index builds (RC-06). | Verify selection-only navigation and semantic-scope invalidation before introducing a long-lived index. Measure representative catalog navigation before claiming a latency improvement. |
| Strategic change | Decide the durability of reviewed and deferred states, then extract their persistence from BurstWorkflowController if durable. | Decide purge and reindex behavior before moving storage. A broader SimilarityScoringModel refactor can follow independently. |

## Open product question

Should **Clear caches** or a model-driven reindex erase reviewed and deferred decisions? Today these decisions occupy the same snapshot as derived scores, and the purge path clears that cache. If photographers expect review progress to survive either operation, a bounded filename and visible save failures address only part of RC-02. [Snapshot fields](../RawCull/Intelligence/Persistence/BurstAnalysisCache.swift#L22) · [Purge action](../RawCull/Views/Settings/CacheSettingsTab.swift#L214)

## Reviewer comments (Claude, November 23, 2026)

Each finding below was checked against the current source. All seven point at real code. Some severities and fixes are adjusted.

### Per-finding comments

**RC-02 · Burst decisions may not be saved. Agree, Medium.**
- Confirmed: `cacheFileName(for:)` base64-encodes the whole catalog path. Paths of roughly 188 bytes or more exceed the 255-byte filename limit. Uncommon, but plausible for deeply nested folders on external volumes.
- Only the manual-decision save discards the result. The post-analysis save (`BurstAnalysisCoordinator.swift:149`) already checks it. The one that drops it is `save(_:catalog:)` at line 321.
- The SHA-256 fix fits. `FaceEvidenceCache.recordURL` already does this, using `standardizedFileURL.absoluteString`. Use the same normalization here.
- Keep migration small: on a miss, read the legacy filename only when it is 255 bytes or fewer. Delete it only after the new write succeeds.
- The "visibly pending decisions" UI is more than needed. A non-blocking "Couldn't save review state" notice plus a log entry covers most of the value.
- The open product question matters more than the filename bug. If **Clear caches** or a reindex erases reviewed/deferred states, users lose work through a normal action. Store manual decisions apart from derived scores, as ratings already are in `CullingModel`. That removes this class of bug.

**RC-03 · A one-pane reload can strand other panes. Agree, narrow trigger.**
- Confirmed: `reload` bumps the session-wide `imageMutationRevision`, so any in-flight bulk load is discarded entirely.
- Trigger: switching the image source on one pane while the group's first bulk load is still running. The other panes keep stale state or keep spinning until the group is re-entered.
- Per-file revisions are correct but heavier than needed. Smaller fix: keep a `Set<FileItem.ID>` of files reloaded since the bulk load started. If the generation still matches, publish the bulk result for every file not in that set.
- Minor: a rejected bulk load returns without clearing `bulkLoadTask` and `bulkLoadGeneration`.

**RC-04 · A late focus result can overwrite a newer group. Agree.**
- Confirmed: `loadImages` never bumps `imageMutationRevision`, so a late focus result still passes the revision check.
- Trigger: the only call site is `.onChange(of: sharpnessModel.effectiveFocusConfig)`. It takes a focus-setting change, then switching groups before regeneration finishes. Uncommon, but the panes then show wrong images.
- Minimal fix: at the top of `loadImages`, call `focusRegenerationTask?.cancel()` and bump the revision. The field-level merge proposed above is the better long-term shape; do it together with RC-03.
- Minor: that `onChange` starts an unstructured `Task {}` not tied to the view's lifetime.

**RC-05 · The rsync details table drops diagnostics. Agree with the bug, not the fix.**
- Confirmed: `handleProcessTermination` appends the failure message to the output, and `RsyncOutputRowView` then removes it with `dropLast(11)`.
- Passing `originalRecords` directly would be a regression. `dropLast(11)` hides the `--stats` summary on successful runs.
- Better fix: keep failure diagnostics separate from the rsync output (or append them after the stats are removed), and show them in their own section.
- The fixed count of 11 is fragile. macOS openrsync and GNU rsync 3.x print different numbers of stats lines. Detect the start of the stats block (for example "Number of files:") instead of counting from the end.
- This is the most user-visible of the seven. Do it first.

**RC-06 · Repeated catalog-wide lookup. Agree, Low.**
- Confirmed: `bestFrameFiles` builds a dictionary over the whole active catalog each time, and `files`, `selectedFile` and `closeUpFiles` each evaluate it again.
- Cheap fix: `let ids = Set(rankedIDs)`, filter the catalog once, then order by rank. Or reuse an existing ID lookup on the catalog controller.
- With a few thousand files this is likely under a millisecond per evaluation. Measure before prioritizing it.

**RC-01 · Cached 200-pixel image can satisfy a preview-size request. Downgrade to Nit.**
- No caller passes `targetSize: 0` today. Grid callers pass 220, 180, `thumbnailSize` and `gridCacheTargetSize`. The loupe uses the `.list` path, which bypasses the loader.
- This is an API hazard, not a current bug. The two-line reorder is still worth doing: resolve the size before the `<= 200` check.

**RC-07 · The sort comparator isn't a strict ordering. Agree, Nit/Low.**
- Confirmed: comparing the anchor with itself returns `true`, which `sort(by:)` does not allow.
- Swift's sort rarely compares an element with itself, so this is unlikely to show, but the fix is one line: `if lhs.id == anchorID { return rhs.id != anchorID }`.

### On the report overall

- Good calibration. It separates "confirmed in source" from "impact unmeasured" and does not inflate severity.
- The graph triage held up. The strongest refutation, the `SubjectMaskDiskStore` to app `Logger` edge, was spot-checked and is a false link.
- Keep its conclusions to retain the low-degree symbols; that code is not dead.
- It is thinner than the prompt asked for on actor reentrancy (`ScanAndCreateThumbnails`, `SharedMemoryCache`, `DiskCacheManager`), the 16 `Task.detached` uses, MCP job lifecycle and grant scope, and the large SwiftUI views. Seven findings for a 50k-line app means it went deep on a few areas rather than across all dimensions. Treat it as a partial pass, not a clean bill of health.
- Not verified here: the filesystem reproduction for RC-02, and the exact stats line counts for each rsync variant.

### Suggested order

| Order | Work | Notes |
|---|---|---|
| 1 | RC-05 | Keep diagnostics separate from the stats trailer; detect the stats block instead of dropping 11 lines. |
| 2 | RC-07 | One-line comparator fix. |
| 3 | RC-01 | Resolve the size before the grid-cache branch. |
| 4 | RC-04 minimal fix | Cancel pending focus work and bump the revision at the start of `loadImages`. |
| 5 | RC-02 | SHA-256 filename, small legacy fallback, surface save failures. Decide at the same time where manual review state lives and whether **Clear caches** may erase it. |
| 6 | RC-03 + RC-04 full fix | One publication rule for bulk loads, reloads and focus results (reloaded-file set or per-file revisions). |
| 7 | RC-06 | Measure first, then filter by group IDs instead of building a catalog-wide dictionary. |
