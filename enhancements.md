+++
author = "Thomas Evensen"
title = "Enhancements"
date = "2026-05-21"
weight = 90
tags = ["roadmap", "enhancements", "ideas"]
categories = ["technical details"]
+++

# Enhancements — Thoughts and Ideas

This page collects possible next steps for RawCull now that the source snapshot in `sourcecode/RawCull/` has been refreshed. It is intentionally written as a product and engineering roadmap rather than a finished specification: the goal is to identify useful directions, likely implementation areas, and risks worth resolving before the app grows further.

The current architecture already has strong foundations: Swift 6 concurrency, actor-protected caches, format-specific RAW extraction, burst grouping, sharpness and saliency scoring, saved-file persistence, rsync copy support, and detailed memory diagnostics. The ideas below build on those systems.

---

## 1. New Functions

### 1.1 Culling Session Summary

RawCull could create a final session summary after each culling run:

| Summary item | Value |
|---|---|
| Catalog path | Source folder reviewed |
| Total RAW files | Number of files discovered |
| Selected files | Rating / keeper count |
| Rejected files | Files intentionally left unselected |
| Burst groups | Number of analyzed groups |
| High-confidence recommendations | Burst groups safe for fast review |
| Copy status | Pending, copied, failed, or skipped |

This would make RawCull more useful after the work is done, not only during review. The summary could be stored next to `savedfiles.json` or exported as Markdown / JSON for later reference.

**Likely source areas:** `CullingModel`, `SavedFiles`, `RawCullViewModel+Catalog`, `RawCullViewModel+BurstGrouping`, `ExecuteCopyFiles`.

### 1.2 Review Queue

Add a dedicated review queue for files that need human attention:

| Queue source | Why it matters |
|---|---|
| Low-confidence burst winners | The algorithm cannot safely recommend a single keeper |
| Missing sharpness score | The frame was not fully analyzed |
| Metadata changes inside burst | Exposure, lens, or camera change may indicate a real scene change |
| Parser diagnostics warning | RAW metadata may be incomplete |
| Copy failure | User action may be needed before export is complete |

This queue would let the user focus on uncertain cases instead of manually scanning the entire catalog again.

**Likely source areas:** `BurstRankingEngine`, `BurstAnalysisModels`, `RawFileDiagnostics`, `CullingGridView`, `ComparisonGridView`.

### 1.3 Side-by-side Candidate Inspector

The comparison grid already supports candidate comparison. A next step could be a focused two-up or four-up inspector for burst finalists, showing:

- Full-size embedded JPEG previews.
- Sharpness score and rank.
- Saliency subject label.
- Focus points when available.
- Exposure, ISO, shutter speed, aperture, focal length, camera, and lens.
- Algorithm reasons and cautions.

This turns the current "recommended keeper" into an explainable recommendation.

**Likely source areas:** `ComparisonGridView`, `ZoomPreviewHandler`, `FocusPointsModel`, `SharpnessScoringModel`, `BurstRankingEngine`.

### 1.4 Catalog Health Report

RawCull could analyze a folder before or during scan and report catalog health:

| Check | Example warning |
|---|---|
| Mixed camera models | Burst grouping may need tighter boundaries |
| Unsupported RAW extension | File will not be processed |
| Missing embedded JPEG | Thumbnail or zoom path may fall back to slower decode |
| Duplicate file names | Saved-file matching may become ambiguous |
| Very large catalog | Memory and cache settings should be adjusted |

This is especially useful when the source folder comes from a card dump, a mixed import, or a partially copied shoot.

**Likely source areas:** `DiscoverFiles`, `ScanFiles`, `RawFormatRegistry`, `RawParserDiagnostics`, `MemoryViewModel`.

### 1.5 Export Presets

The rsync copy flow could be extended with named export presets:

| Preset | Behavior |
|---|---|
| Keepers only | Copy selected / rated files |
| Top burst candidates | Copy recommended files from each burst group |
| All reviewed files | Copy everything with a review state |
| Sidecar report | Include `savedfiles.json`, session summary, and diagnostics |

This keeps the copy workflow repeatable and reduces the chance of copying the wrong set after a long review session.

**Likely source areas:** `SynchronizeConfiguration`, `ArgumentsSynchronize`, `ExecuteCopyFiles`, `PrepareOutputFromRsync`, `CullingModel`.

### 1.6 Parser Validation View

Because RawCull depends on camera-specific metadata, a small developer-facing parser validation view would be valuable. It could show extracted EXIF, MakerNote fields, focus points, preview offsets, thumbnail byte sizes, and parser warnings for the selected RAW file.

This would make support for new camera bodies easier to verify without stepping through the parser in Xcode.

**Likely source areas:** `SonyMakerNoteParser`, `NikonMakerNoteParser`, `RawFileDiagnostics`, `SonyThumbnailExtractor`, `NikonThumbnailExtractor`, `JPGSonyARWExtractor`, `JPGNikonNEFExtractor`.

---

## 2. Enhancements of Existing Functions

### 2.1 Burst Grouping and Ranking

The burst-group system is one of RawCull's strongest differentiators. Good next improvements:

| Enhancement | Why |
|---|---|
| Persist manual winner overrides | User decisions should survive regrouping and relaunch |
| Make ranking reasons more visible | Builds trust in recommendations |
| Add threshold preview | User sees how sensitivity changes groups before applying |
| Track changed inputs | Reuse cached analysis only when source files and settings still match |
| Add per-camera tuning | Different bodies and lenses may need slightly different thresholds |

Manual review state already exists in the analysis model, so the highest-value next step is probably stronger persistence and UI surfacing of why a frame won.

### 2.2 Sharpness and Focus Mask

Sharpness scoring could become more photographer-oriented:

| Enhancement | Why |
|---|---|
| Show score components | Separate global sharpness, subject sharpness, saliency confidence, and focus agreement |
| Normalize per burst | Ranking inside a burst matters more than absolute score |
| Flag motion blur vs missed focus | These are different reasons to reject a frame |
| Compare against selected winner | Show whether a rejected frame is meaningfully worse |

The current scoring engine already has saliency and focus-mask concepts. The next useful move is not only "better score", but better explanation of the score.

### 2.3 Thumbnail and Full-size JPEG Caching

The cache architecture is already layered and actor-protected. Improvements could focus on predictability:

| Enhancement | Why |
|---|---|
| Cache warming progress | User understands why the app is busy |
| Per-catalog cache stats | Easier to diagnose slow folders |
| Stale cache cleanup | Prevent disk cache from growing forever |
| Cache error display | Surface corrupt or unreadable cache entries |
| Priority loading | Visible thumbnails and active comparison candidates load first |

The `SharedMemoryCache`, `DiskCacheManager`, and `FullSizeJPGDiskCache` actors are good places to keep this logic centralized.

### 2.4 Memory Diagnostics

RawCull already tracks memory pressure and cache use. The next step is to convert diagnostics into guidance:

| Current signal | Possible user guidance |
|---|---|
| High memory use | Reduce thumbnail memory cache size |
| Frequent pressure warnings | Lower concurrent scan / decode work |
| Disk cache misses | Warm cache or increase cache retention |
| Very large embedded JPEGs | Prefer lower preview size in grid |

The app should not only show numbers; it should suggest the safest setting change.

### 2.5 Saved Files and Ratings

The saved-file system can become a stronger project record:

| Enhancement | Why |
|---|---|
| Version saved-file schema | Allows future migration without guessing |
| Store app/build version | Helps diagnose old culling sessions |
| Store review source | Distinguish manual rating, burst winner, and bulk action |
| Add audit timestamps | Make it easier to understand when decisions changed |
| Add recovery copy | Protect against interrupted writes or corrupt JSON |

The current debounced write model is a good base. The main improvement is making the saved state richer and easier to migrate.

### 2.6 Security-scoped Access

The security model should keep making sandbox behavior visible and understandable:

| Enhancement | Why |
|---|---|
| Show active source and destination scopes | User can see what RawCull currently has permission to access |
| Validate bookmarks at launch | Detect stale permissions early |
| Explain failed copy permission | Avoid confusing rsync errors |
| Add permission repair action | Let the user reselect a folder without resetting the session |

This is especially important because RawCull handles external drives, camera cards, and destination folders.

### 2.7 Documentation Site

The documentation is now broad enough that it can benefit from a few structural upgrades:

| Enhancement | Why |
|---|---|
| Add architecture map | Helps readers understand how pages connect |
| Add source coverage table | Shows which Swift files are documented |
| Add feature-to-source index | Makes maintenance easier after source updates |
| Add "last verified against source" notes | Reduces drift between docs and app |
| Add diagrams for cache and culling flows | Easier to understand than prose alone |

This page can become the starting point for tracking future documentation work.

---

## 3. Issues to Be Solved

### 3.1 Source and Documentation Drift

The documentation references a snapshot of source code, but the site does not compile the Swift app. That creates a natural risk: the app can change while the docs still describe older behavior.

Suggested fixes:

- Add a visible "source snapshot date" to major docs.
- Add a source coverage checklist for each documentation page.
- Run a simple CI check that verifies referenced source paths still exist.
- Prefer describing stable architecture over fragile line-by-line behavior.

### 3.2 Cache Invalidation

Any cache that outlives the current run needs a clear invalidation rule. If a RAW file changes, is renamed, or is replaced with another file of the same name, cached thumbnails and analysis data can become misleading.

Suggested fixes:

- Include file size and modification date in cache keys or cache metadata.
- Include parser version / algorithm version in analysis caches.
- Provide a per-catalog "rebuild analysis" action.
- Make cache hits and misses visible in diagnostics.

### 3.3 Error Surfacing

Several subsystems can fail in ways that are hard for users to interpret: RAW parsing, thumbnail extraction, security-scoped bookmarks, disk cache reads, and rsync copy. The app should keep converting low-level errors into user-facing recovery paths.

Suggested fixes:

- Standardize parser and cache diagnostic messages.
- Add a reviewable error list per catalog.
- Keep failed files visible with a clear state instead of silently skipping them.
- Add "retry failed items" actions for thumbnail generation and copy.

### 3.4 Cancellation and Partial Results

RawCull does a lot of work concurrently. Cancellation is essential, but partial results must remain coherent.

Suggested fixes:

- Define which partial results are allowed to persist after cancellation.
- Mark incomplete analysis results explicitly.
- Avoid saving uncertain intermediate state as if it were complete.
- Test cancellation during scan, thumbnail creation, burst analysis, and copy.

### 3.5 Scaling Very Large Catalogs

The architecture already considers memory pressure, but very large folders still deserve specific attention.

Suggested fixes:

- Measure scan and analysis behavior at 1,000 / 5,000 / 10,000 files.
- Keep visible-grid loading separate from background warming.
- Add configurable concurrency limits for slower machines.
- Consider paging or chunked analysis for burst detection.

### 3.6 Multi-format Growth

RawCull has format-specific parser and extractor layers. As more camera brands or RAW formats are added, the registry pattern needs to stay disciplined.

Suggested fixes:

- Keep all format dispatch inside `RawFormatRegistry` and format adapters.
- Add parser conformance tests using small sample metadata fixtures.
- Track unsupported-but-detected formats separately from unknown files.
- Document required steps for adding a new camera format.

### 3.7 Trust in Automatic Recommendations

Automatic culling is powerful, but users need to understand when the app is confident and when it is guessing.

Suggested fixes:

- Keep confidence labels conservative.
- Show ranking reasons near the recommendation.
- Make one-click actions available only for high-confidence groups.
- Preserve manual choices as stronger than algorithmic choices.

---

## 4. Suggested Priority Order

| Priority | Work | Reason |
|---|---|---|
| 1 | Persist manual burst winner overrides | Protects user decisions and improves trust |
| 2 | Add review queue | Turns diagnostics and low-confidence analysis into a clear workflow |
| 3 | Add session summary | Gives every culling run a useful end state |
| 4 | Improve cache invalidation metadata | Prevents stale thumbnails or analysis from misleading the user |
| 5 | Add parser validation view | Makes new camera support easier and safer |
| 6 | Add export presets | Makes the final copy workflow faster and less error-prone |

The best near-term direction is to make RawCull more explainable: preserve user intent, show why recommendations were made, and collect uncertain cases in one place. After that, export presets and parser tooling would make the app easier to use and easier to extend.

---

# Detailed plan

## (1) Persist manual burst winner overrides

The goal is to make a user's manual burst decision stronger than the automatic recommendation. If the user explicitly chooses a winner in a burst group, RawCull should remember that choice after regrouping, re-analysis, catalog reload, and app relaunch. Automatic ranking can still run, but it should not silently replace the user's decision.

#### Current behavior

The current burst flow already has most of the surrounding machinery:

| Area | Current role |
|---|---|
| `RawCullViewModel+BurstGrouping.swift` | Runs burst analysis, keeps the best/top-two actions, applies ratings, marks `BurstReviewState.decisionApplied`, saves burst analysis cache |
| `BurstAnalysisModels.swift` | Defines `BurstAnalysisResult`, `BurstCandidateScore`, `BurstReviewState`, and cache-codable burst metadata |
| `BurstRankingEngine.swift` | Produces ranked candidates and `recommendedFileID` from sharpness, focus, saliency, metadata, and boundary evidence |
| `BurstAnalysisCache.swift` | Persists computed analysis artifacts for reuse when the same catalog and source files are still valid |
| `CullingModel.swift` | Persists user-facing per-file state in `savedfiles.json`, currently ratings plus sharpness and saliency metadata |
| `SavedFiles.swift` and `DecodeSavedFiles.swift` | Define the durable JSON schema used by `savedfiles.json` |
| `CullingGridView.swift` and `ComparisonGridView.swift` | Provide the current UI actions for `Keep Best`, `Keep Top 2`, compare, and undo |

The missing piece is that `decisionApplied` only says "a burst action happened." It does not record which file the user chose, why it was chosen, which burst membership it belonged to, or whether that decision should override a later automatic recommendation.

#### Desired result

After implementation:

- A manually selected burst winner is written to durable saved state, not only the burst analysis cache.
- Re-running burst analysis uses the manual winner as the displayed and actionable winner when the saved winner still belongs to the current group.
- Changing the burst threshold, regrouping, or relaunching RawCull preserves valid manual winners.
- If regrouping moves the saved winner into a different group, RawCull reattaches the override to the group containing that file.
- If the saved file no longer exists in the catalog, the override is ignored and clearly marked stale or removed during cleanup.
- UI badges distinguish automatic recommendations from manual overrides.
- `Keep Best` and keyboard-driven keep-best behavior operate on the manual override when one exists.
- Undo can restore ratings for the last action, but it should not accidentally delete unrelated persisted overrides.

#### Data model changes

Add an explicit burst override model in `BurstAnalysisModels.swift`:

| New type / field | Purpose |
|---|---|
| `BurstWinnerOverride` | Durable record of a user's chosen winner |
| `winnerFileName` | Stable match against `savedfiles.json` and current catalog file names |
| `winnerFileID` | Fast in-memory match for the current run; can be remapped like other cached UUIDs |
| `memberFileNames` | Snapshot of the burst membership when the override was created |
| `source` | Distinguishes `.manualWinner`, `.keepBestApplied`, or `.keepTopTwoApplied` if that distinction is useful |
| `dateApplied` | Audit trail for when the decision was made |
| `rankingAlgorithmVersion` | Helps explain whether the override predates a ranking change |

Extend `BurstReviewState` beyond `.none` and `.decisionApplied`:

| State | Meaning |
|---|---|
| `.none` | No user action yet |
| `.algorithmReviewed` | User inspected the group but did not override |
| `.manualWinnerOverride` | User explicitly chose a winner that should outrank algorithm output |
| `.decisionApplied` | Ratings were applied from the active winner recommendation |

Keep the enum decoder tolerant of unknown values, as it is today, so older or future saved JSON does not fail to load.

#### Persistence changes

Store manual burst overrides in `savedfiles.json`, because they represent user intent and should survive even when `BurstAnalysisCache` is invalidated.

Update these files:

| File | Change |
|---|---|
| `Model/JSON/SavedFiles.swift` | Add `burstWinnerOverrides: [BurstWinnerOverride]?` to `SavedFiles` |
| `Model/JSON/DecodeSavedFiles.swift` | Decode the optional override array with `decodeIfPresent` |
| `Model/ViewModels/CullingModel.swift` | Add methods to upsert, fetch, remove, and prune overrides for a catalog |
| `Model/JSON/WriteSavedFilesJSON.swift` | No format-specific change should be needed if the model remains `Codable`, but verify output includes the new optional field |
| `Model/JSON/ReadSavedFilesJSON.swift` | Verify older JSON without the new field still loads cleanly |

Recommended `CullingModel` API:

| Method | Behavior |
|---|---|
| `upsertBurstWinnerOverride(_:in:)` | Inserts or replaces an override for the matching burst membership |
| `burstWinnerOverrides(in:)` | Returns all persisted overrides for the selected catalog |
| `overrideWinner(for:groupFiles:in:)` | Finds the best matching override for the current group |
| `removeBurstWinnerOverride(id:in:)` | Clears a manual override when the user explicitly asks |
| `pruneStaleBurstOverrides(validFileNames:in:)` | Removes overrides whose winner and members are no longer in the catalog |

Use file names as the durable identity because `FileItem.id` is generated for the current run, while the existing saved-file system is already keyed by `fileName`.

#### View model changes

Update `RawCullViewModel+BurstGrouping.swift` so manual overrides become part of the ranking flow:

1. Load catalog overrides after `cullingModel.loadSavedFiles()` and after the current catalog files are known.
2. After `similarityModel.groupBursts(files:)`, match overrides to current groups by winner file name and member overlap.
3. Apply overrides after `BurstRankingEngine.rank(...)` returns:
   - If an override winner is present in a current group, set `recommendedFileID` to that file's current UUID.
   - Set `reviewState` to `.manualWinnerOverride`.
   - Add a reason such as `Manual winner override`.
   - Keep the algorithmic winner in the candidate list for comparison.
4. Make `keepBestInGroup(from:)` use the effective winner: manual override first, algorithm recommendation second, sharpest fallback last.
5. Add a new explicit action such as `setManualBurstWinner(_ file: FileItem, in groupFiles: [FileItem])`.
6. When a manual winner is set, persist the override through `CullingModel`, update `burstAnalysisResults`, and save the burst analysis cache.
7. When `reGroupBursts()` runs, reapply saved overrides after recomputing rankings.
8. During cache load in `applyCachedBurstAnalysis(_:)`, still reapply durable saved overrides, because the cache may not know about newer user decisions.

Do not rely on `BurstAnalysisCache` as the source of truth for manual overrides. The cache can include applied override state as a convenience, but `savedfiles.json` should win whenever there is a disagreement.

#### Ranking engine changes

Keep `BurstRankingEngine.swift` mostly pure. The preferred design is:

- Let `BurstRankingEngine.rank(...)` continue producing the algorithmic result.
- Add a small post-processing helper in `RawCullViewModel+BurstGrouping.swift`, or a pure helper such as `BurstOverrideResolver`, that overlays persisted manual decisions on top of the ranked result.
- Preserve all algorithm candidate scores so the UI can still explain what the model would have chosen.

This avoids mixing durable user preference storage with the scoring algorithm.

#### UI changes

Update the burst UI so users can see and control overrides:

| File | Change |
|---|---|
| `Views/CullingGrid/CullingGridView.swift` | Show a `Manual winner` badge in `BurstGroupHeaderView` when `reviewState == .manualWinnerOverride` |
| `Views/ThumbnailComponents/ImageItemView.swift` | Add or adapt the burst badge so the overridden winner is visually distinct from the algorithmic recommendation |
| `Views/ComparisonGridView/ComparisonGridView.swift` | Add a `Set as Burst Winner` action for the selected comparison candidate |
| `Views/CullingGrid/CullingGridView.swift` | Consider a context menu action on burst thumbnails for `Set as Burst Winner` and `Clear Manual Winner` |

The UI should avoid making overrides feel like hidden state. A user should be able to tell whether a winner is automatic or manual before applying a one-click cull action.

#### Validation and tests

Add focused tests around the risky parts:

| Test area | Expected behavior |
|---|---|
| JSON backward compatibility | Existing `savedfiles.json` files without overrides decode successfully |
| JSON round trip | A saved override encodes and decodes with winner file name, members, date, and source intact |
| Override matching | A saved winner is reapplied when the same files are regrouped |
| Regrouping | If sensitivity changes but the winner remains in a burst group, the override follows the winner |
| Missing file | Overrides pointing to deleted files are ignored or pruned |
| Keep Best | `keepBestInGroup(from:)` rates the manual winner when present |
| Cache disagreement | Durable saved override wins over a stale cached algorithm recommendation |

If this documentation snapshot remains non-compiling, these tests belong in the app repository rather than this Hugo site. The documentation site can still reference the expected test cases.

#### Rollout steps

1. Add the new override data model and make JSON decoding backward compatible.
2. Add `CullingModel` APIs for override persistence and pruning.
3. Implement override matching and post-ranking application in `RawCullViewModel+BurstGrouping.swift`.
4. Update keep-best and compare flows to use the effective winner.
5. Add UI affordances for setting, displaying, and clearing manual winners.
6. Save burst cache after override changes, but treat `savedfiles.json` as authoritative.
7. Add unit tests in the app project for JSON migration, override matching, regrouping, and keep-best behavior.
8. Manually verify with a catalog by selecting a manual winner, changing burst sensitivity, quitting/relaunching, and confirming the same winner remains active.

## (2) Add review queue

The goal is to turn scattered uncertainty signals into a single workflow. Instead of making the user hunt through the whole catalog for low-confidence burst groups, missing analysis, parser failures, copy problems, or metadata warnings, RawCull should collect those items into a review queue that can be opened, filtered, resolved, and revisited.

#### Current behavior

RawCull already produces several signals that are useful for review, but they live in different places:

| Area | Current role |
|---|---|
| `BurstAnalysisModels.swift` | Stores `BurstDecisionConfidence`, `BurstAnalysisResult.reasons`, `cautions`, and `reviewState` |
| `BurstRankingEngine.swift` | Marks recommendations as high, medium, or low confidence |
| `RawCullViewModel+BurstGrouping.swift` | Holds `burstAnalysisResults` and knows which files belong to each burst group |
| `RawCullViewModel+Sharpness.swift` | Persists sharpness scores and saliency labels when scoring completes |
| `RawFileDiagnostics.swift` | Produces detailed diagnostics text for unsupported files, unreadable files, ImageIO failures, and MakerNote parser failures |
| `RawParserDiagnostics.swift` | Carries parser `value`, `trace`, and `failure` data from Sony and Nikon parser paths |
| `ExecuteCopyFiles.swift` and `CopyFilesView.swift` | Run rsync copy operations and expose raw copy output, but do not classify failed files into catalog review work |
| `CullingGridView.swift`, `ComparisonGridView.swift`, and `ImageItemView.swift` | Surface burst confidence, candidate badges, and comparison actions inside the normal browsing views |

The missing piece is a durable, user-facing list of "things that need attention." Today, the user can see some of these states while browsing, but RawCull does not collect them into a queue, track whether they were resolved, or provide next-step actions.

#### Desired result

After implementation:

- RawCull exposes a Review Queue view for the active catalog.
- Queue items are generated from burst analysis, sharpness/scoring state, parser diagnostics, copy results, and catalog health checks.
- Each item has a severity, reason, file or burst reference, recommended action, and resolution state.
- The queue can be filtered by category: burst confidence, missing sharpness, parser issue, metadata change, copy issue, and catalog issue.
- Selecting a queue item navigates to the relevant file, burst group, comparison view, diagnostics output, or copy result.
- Resolved items stay hidden by default but can be shown for audit.
- Queue generation is repeatable and should not duplicate the same issue every time analysis runs.
- Manual user decisions and successful re-analysis can clear or resolve queue items.

#### Data model changes

Add a small review-queue model, preferably in a new file such as `Model/ViewModels/ReviewQueueModels.swift`:

| New type / field | Purpose |
|---|---|
| `ReviewQueueItem` | One actionable issue for a file, burst group, copy result, or catalog |
| `ReviewQueueCategory` | Categorizes items as `.burst`, `.sharpness`, `.parser`, `.metadata`, `.copy`, `.catalog`, or `.cache` |
| `ReviewQueueSeverity` | Sorts attention level as `.info`, `.warning`, or `.blocking` |
| `ReviewQueueResolutionState` | Tracks `.open`, `.resolved`, `.ignored`, or `.stale` |
| `fileName` | Durable file identity for single-file issues |
| `fileID` | Current-run UUID for fast navigation |
| `groupID` | Current burst group when the item applies to a burst |
| `relatedFileNames` | Burst members or copy-output files involved in the same issue |
| `title` | Short UI label |
| `detail` | User-facing reason and recovery hint |
| `source` | Identifies the subsystem that created the item |
| `createdAt` and `resolvedAt` | Audit timestamps |
| `fingerprint` | Stable de-duplication key derived from catalog, category, file names, and reason |

The queue should use file names for durable matching, matching the existing `savedfiles.json` approach. In-memory `fileID` and `groupID` values can be rebuilt after each catalog scan.

#### Persistence changes

Persist user resolution state, not necessarily every generated queue item. Most queue items can be regenerated from current analysis state, while ignored/resolved decisions should survive relaunch.

Update these files:

| File | Change |
|---|---|
| `Model/JSON/SavedFiles.swift` | Add optional `reviewQueueStates: [ReviewQueueItemState]?` to `SavedFiles` |
| `Model/JSON/DecodeSavedFiles.swift` | Decode optional queue state for backward compatibility |
| `Model/ViewModels/CullingModel.swift` | Add APIs to save, resolve, ignore, and clear queue item states by fingerprint |
| `Model/JSON/WriteSavedFilesJSON.swift` | Verify the optional queue state is encoded by the existing `Codable` path |
| `Model/JSON/ReadSavedFilesJSON.swift` | Verify older saved files without queue state still load |

Recommended `CullingModel` API:

| Method | Behavior |
|---|---|
| `reviewQueueStates(in:)` | Returns persisted resolution state for the active catalog |
| `updateReviewQueueState(_:in:)` | Saves resolved, ignored, or reopened state by item fingerprint |
| `clearReviewQueueStates(in:)` | Clears queue state for a catalog when the user resets saved files |
| `pruneReviewQueueStates(validFingerprints:in:)` | Removes persisted state for issues that can no longer be regenerated |

This keeps `savedfiles.json` as the record of user review decisions without bloating it with transient diagnostics.

#### Queue generation changes

Add a queue builder that derives queue items from existing model state. A good starting point is a pure helper such as `ReviewQueueBuilder` plus a small view-model wrapper in `RawCullViewModel`.

Update or add these areas:

| File | Change |
|---|---|
| `Model/ViewModels/ReviewQueueBuilder.swift` | New pure builder that accepts files, ratings, burst results, sharpness scores, diagnostics summaries, copy output, and persisted queue states |
| `Model/ViewModels/RawCullViewModel.swift` | Add `reviewQueueItems`, active filters, selected queue item, and queue summary counts |
| `Model/ViewModels/RawCullViewModel+BurstGrouping.swift` | Rebuild queue after `analyzeBursts()`, `reGroupBursts()`, manual winner changes, and burst actions |
| `Model/ViewModels/RawCullViewModel+Sharpness.swift` | Rebuild queue after scoring completes and after persisted scores are loaded |
| `Model/Diagnostics/RawFileDiagnostics.swift` | Add structured diagnostics in addition to the current text log, or provide a parser that extracts error lines into review issues |
| `Model/ParametersRsync/ExecuteCopyFiles.swift` | Return enough structured copy status to identify failed or skipped files |
| `Views/CopyFiles/CopyFilesView.swift` | Feed copy completion results back into the queue builder through `RawCullViewModel` |

Recommended generated item rules:

| Queue source | Trigger | Action |
|---|---|---|
| Low-confidence burst | `BurstAnalysisResult.confidence == .low` | Open comparison for the burst group |
| Medium-confidence burst | `confidence == .medium` and no user decision | Review top candidates |
| Missing sharpness | File has no `sharpnessModel.scores[file.id]` after scoring should have completed | Re-run sharpness scoring for catalog or file |
| Parser failure | `RawParserDiagnostics.failure != nil` or `RawFileDiagnostics` contains parser/ImageIO errors | Open diagnostics for the file |
| Metadata boundary | Burst boundary evidence has exposure, camera, or lens changes inside a close sequence | Review group boundary |
| Copy issue | rsync output indicates failed, skipped, permission-denied, or missing files | Open copy output and show affected file |
| Catalog issue | Unsupported extension, unreadable file, missing source file, or duplicate durable file name | Open catalog health details |

The first version can generate items on demand for the active catalog. A later version can cache structured diagnostics if full parser checks become expensive.

#### View model behavior

Add queue operations to `RawCullViewModel`:

| Method | Behavior |
|---|---|
| `rebuildReviewQueue()` | Regenerates queue items and overlays persisted resolution state |
| `openReviewQueueItem(_:)` | Navigates to the correct view for the item category |
| `resolveReviewQueueItem(_:)` | Marks the item resolved and persists that state |
| `ignoreReviewQueueItem(_:)` | Hides an item without changing ratings or analysis |
| `reopenReviewQueueItem(_:)` | Restores a resolved or ignored item |
| `reviewQueueSummary` | Returns counts for toolbar badges and sidebar labels |

Navigation should use existing views where possible:

- Burst items should open `ComparisonGridView` through `compareBurstGroup(_:)`.
- File-specific items should select the file and open loupe/grid context.
- Parser items should open or reuse the diagnostics view/log for the selected file.
- Copy items should open `DetailsView` with the rsync output already available.

#### UI changes

Add a dedicated queue surface without replacing the current culling flow.

Update these files:

| File | Change |
|---|---|
| `Views/RawCullSidebarMainView/SharedMainToolbarContent.swift` | Add a Review Queue button with a count badge |
| `Views/RawCullSidebarMainView/RawCullMainView.swift` | Present the queue as a sheet or side panel |
| `Views/ReviewQueue/ReviewQueueView.swift` | New list view grouped by category and severity |
| `Views/ReviewQueue/ReviewQueueRowView.swift` | New row component with title, detail, severity, action, resolve, and ignore controls |
| `Views/CullingGrid/CullingGridView.swift` | Optionally show a small attention marker on burst headers with open queue items |
| `Views/ThumbnailComponents/ImageItemView.swift` | Optionally show an attention badge for file-specific queue items |

The queue view should be task-oriented:

| UI action | Behavior |
|---|---|
| `Open` | Navigate to the file, burst comparison, diagnostics, or copy output |
| `Resolve` | Mark the item done without changing files |
| `Ignore` | Hide a known non-issue |
| `Show Resolved` | Toggle audit view |
| Category filter | Narrow to burst, parser, copy, sharpness, metadata, or catalog items |

The toolbar badge should count only open warning/blocking items, so it remains useful instead of becoming visual noise.

#### Validation and tests

Add focused tests around generation, de-duplication, and state overlay:

| Test area | Expected behavior |
|---|---|
| Low-confidence burst | A low-confidence `BurstAnalysisResult` creates one burst queue item |
| Missing sharpness | A file missing a score creates a sharpness queue item only after scoring was expected |
| Parser failure | A structured parser failure creates a parser queue item with the file name and reason |
| Copy failure | Failed rsync output creates a copy queue item tied to affected output |
| De-duplication | Rebuilding the queue does not duplicate existing items with the same fingerprint |
| Resolution overlay | A persisted resolved state hides the generated item by default |
| Reopen | Reopening an item makes it visible again |
| Navigation | Opening each category selects the expected file, group, diagnostics, or copy output view |
| Backward compatibility | Existing `savedfiles.json` files without queue state decode successfully |

If the app repository owns the Swift build and test target, add these there. The documentation site should describe the test cases and expected behavior, but it does not need to compile the Swift source snapshot.

#### Rollout steps

1. Add `ReviewQueueItem`, category, severity, resolution, and persisted state models.
2. Add `CullingModel` APIs for queue state persistence and backward-compatible JSON decoding.
3. Implement `ReviewQueueBuilder` for burst confidence, missing sharpness, and parser failures first.
4. Add `RawCullViewModel` queue state, summary counts, rebuild hooks, and navigation methods.
5. Add `ReviewQueueView` and toolbar access with open-item count.
6. Wire queue rebuilds after burst analysis, regrouping, scoring, catalog load, and copy completion.
7. Add rsync/copy issue classification once copy output has enough structured information.
8. Add tests for queue generation, de-duplication, persisted resolution, and navigation.
9. Manually verify with a catalog containing one low-confidence burst, one missing score, one parser warning, and one copy failure; confirm each appears once, opens the right context, and stays resolved or ignored after relaunch.
