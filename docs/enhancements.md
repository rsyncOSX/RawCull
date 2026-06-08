+++
author = "Thomas Evensen"
title = "Enhancement Roadmap"
linkTitle = "Enhancements"
date = "2026-06-06"
weight = 90
tags = ["roadmap", "enhancements", "culling", "workflow"]
categories = ["planning"]
+++

# Enhancement Roadmap

RawCull is already a strong culling application: it scans Sony ARW and Nikon NEF catalogs, extracts previews, keeps thumbnail and full-size preview caches, persists ratings, scores focus and sharpness, reads Sony/Nikon focus points, groups bursts, ranks candidates, explains its ranking evidence, compares candidate frames, and copies selected RAW files through the rsync workflow.

The next phase should therefore avoid adding generic photo-browser features. The best value is to make RawCull faster at answering the culling question: which files are safe to reject, which files deserve careful review, and how do the keepers move cleanly into the photographer's editing workflow?

## Verified Current State

This roadmap was checked against the updated source snapshot on 6 June 2026.

| Area | Done now | Source evidence |
|---|---|---|
| RAW format coverage | Sony ARW and Nikon NEF are registered format families; JPEG/JPG files are also recognized by the app-side supported-file enum. | `RawParserKit/Sources/RawParserKit/RawFormatRegistry.swift`, `RawCull/Extensions/SupportedFileType.swift` |
| Catalog scan | Scan extracts file metadata, EXIF, dimensions, size class, and inline focus location in one task-group pass. | `RawCull/Actors/ScanFiles.swift` |
| Thumbnail and preview pipeline | Thumbnail extraction, disk cache, memory cache, full-size preview cache, sidecar-first zoom loading, and explicit embedded-JPEG export are implemented. | `RawCull/Actors/RequestThumbnail.swift`, `RawCull/Actors/DiskCacheManager.swift`, `RawCull/Actors/FullSizeJPGDiskCache.swift`, `RawCull/Model/Handlers/ZoomPreviewHandler.swift` |
| Sharpness and focus evidence | Sharpness scoring, saliency, AF-point weighting, focus-mask rendering, scoring quality/source options, and persisted scoring signatures are present. | `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`, `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift` |
| Burst intelligence | Burst grouping, ranking, confidence, reasons, cautions, manual winner overrides, one-click keep/reject actions, undo, and cache persistence are implemented. | `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `RawCullCore/Sources/RawCullCore/BurstGroupingEngine.swift`, `RawCullCore/Sources/RawCullCore/BurstRankingEngine.swift`, `RawCull/Actors/BurstAnalysisCache.swift` |
| Similarity review | Vision feature-print indexing, similar-image ranking, burst sensitivity, and similarity grid mode are implemented. | `RawCull/Model/ViewModels/SimilarityScoringModel.swift`, `RawCull/Views/SimilarityGridView/SimilarityGridView.swift` |
| Comparison workflow | Top candidates can be opened in comparison mode with a candidate inspector showing score components, focus evidence, camera settings, reasons, cautions, and rank rows. | `RawCull/Views/ComparisonGridView/ComparisonGridView.swift`, `RawCull/Views/ComparisonGridView/CandidateInspectorView.swift` |
| Persistence | `savedfiles.json` stores catalog records, ratings, scoring fields, and burst winner overrides. | `RawCull/Model/JSON/SavedFiles.swift`, `RawCull/Model/ViewModels/CullingModel.swift` |
| Copy/export | Rated file lists can be passed to the rsync copy workflow, and embedded JPEG previews can be extracted beside RAW files. | `RawCull/Views/CopyFiles/CopyFilesView.swift`, `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift`, `RawCull/Actors/ExtractAndSaveJPGs.swift` |
| Diagnostics | Memory diagnostics, raw-file parser diagnostics, scan stats, and histogram calculation exist. | `RawCull/Views/Diagnostics/MemoryDiagnosticsView.swift`, `RawCull/Model/Diagnostics/RawFileDiagnostics.swift`, `RawCull/Views/GridView/ScanStatsSheetView.swift`, `RawCull/Views/Histogram/HistogramView.swift` |
| Package split | Pure models, burst logic, focus parsing, histogram calculation, and raw parser code are extracted into `RawCullCore` and `RawParserKit` with tests. | `RawCullCore/Tests/RawCullCoreTests/`, `RawParserKit/Tests/RawParserKitTests/` |

## Product Direction

The strongest next direction is "decision trust plus workflow output."

RawCull already computes useful evidence. The next enhancements should make that evidence easier to act on, safer to automate, and more portable after culling. The app should become the place where a photographer can finish a first-pass cull, understand why the app recommends a frame, quickly review only uncertain cases, and hand off keepers to editing software without redoing work.

## Enhancement Priorities

### 1. Review Queue for Uncertain Decisions

Add a dedicated review queue that collects images and burst groups where RawCull is not confident enough for one-click culling.

Value for culling:

- Lets the photographer spend attention only where judgment is needed.
- Turns low-confidence burst groups, missing focus evidence, tight score gaps, metadata changes, and subject mismatch into a concrete review list.
- Preserves RawCull's conservative behavior: automate the easy rejects, slow down for ambiguous frames.

Suggested scope:

- Add a `Needs Review` mode beside loupe, grid, similarity, rated, and comparison modes.
- Include burst groups with `.low` or `.medium` confidence, candidate cautions, missing sharpness, missing AF evidence, unstable metadata, and manual override conflicts.
- Add quick actions: accept recommendation, keep top two, reject all but selected, defer, and mark reviewed.
- Persist review state by stable group signature rather than transient group id.

Source foundation:

- `BurstDecisionConfidence`, `BurstReviewState`, candidate cautions, and group cautions already exist in `RawCullCore`.
- `CandidateInspectorView` already exposes much of the evidence needed for the review queue.

### 2. Stable Decision Ledger and Audit Trail

Create a small per-catalog decision ledger that records what RawCull recommended, what the user accepted, and why.

Value for culling:

- Makes aggressive culling safer because every automated decision is inspectable.
- Allows "show me what changed since last session" and "undo this batch" workflows.
- Gives future scoring changes a way to compare old and new recommendations without silently changing user intent.

Suggested scope:

- Store accepted burst actions, manual winners, rejected files, deferred groups, and copy status.
- Key burst decisions by catalog-relative file names or a stable group signature, not by `Int` group id.
- Add a lightweight "Decision History" sheet for the current catalog.
- Keep the ledger compact and JSON-readable, similar to `savedfiles.json`.

Source foundation:

- `savedfiles.json` already stores ratings and manual burst winner overrides.
- `findings.md` already identifies transient group id and manual-override matching as hardening opportunities.

### 3. Editing Handoff: XMP Sidecars and Export Manifests

Add export options that hand RawCull's cull decisions to Lightroom Classic, Capture One, Photo Mechanic, darktable, or a simple file-based workflow.

Value for culling:

- The cull becomes useful outside RawCull.
- Star ratings, rejects, labels, and selected keepers can follow the RAW files into the next application.
- Photographers avoid repeating rating work after copy/export.

Suggested scope:

- Generate XMP sidecars for selected RAW files with rating and reject state.
- Generate CSV/JSON manifests with file name, rating, sharpness score, confidence, burst group, recommendation, camera, lens, ISO, shutter, aperture, and copied status.
- Add a dry-run preview for export count and destination paths.
- After rsync completes, update `dateCopied` or replace it with an explicit copy-state model.

Source foundation:

- Ratings are already stored in `FileRecord`.
- EXIF summary data is already available on `FileItem`.
- The rsync workflow already builds copy lists from rated filenames.

### 4. Exposure and Technical-Risk Warnings

Use histogram and EXIF evidence to flag frames with technical risks before final acceptance.

Value for culling:

- Sharp focus is not enough; a keeper can still be clipped, underexposed, motion-blurred, or too noisy.
- A risk badge prevents RawCull from recommending a technically sharp but unusable frame without warning.

Suggested scope:

- Add per-file warnings for highlight clipping, blocked shadows, very high ISO, slow shutter relative to focal length, and extreme exposure changes inside a burst.
- Add those warnings to candidate reasons/cautions and the review queue.
- Keep this as advisory evidence at first, not an automatic reject rule.

Source foundation:

- `HistogramCalculator` exists in `RawCullCore`.
- EXIF fields already include ISO, aperture, shutter speed, focal length, camera, and lens.
- `BurstRankingEngine` already has a metadata component and caution strings.

### 5. Active Learning From User Choices

Let RawCull learn local preferences from accepted and overridden culling decisions.

Value for culling:

- Wildlife, sports, events, and portraits have different keeper criteria.
- Manual winner overrides are valuable training signals: they show where the photographer disagreed with the ranking.
- This makes the app feel more personal without requiring cloud services or opaque AI.

Suggested scope:

- Start with local, transparent preference profiles rather than machine-learning complexity.
- Track which score components correlated with accepted manual winners.
- Offer profile presets such as Wildlife, Birds in Flight, Portraits, Sports, and General.
- Let the user compare the current recommendation with a profile-adjusted recommendation before applying it.

Source foundation:

- `SharpnessPhotoType`, `SharpnessScoringQuality`, focus settings, scoring signatures, and manual burst overrides already exist.
- `BurstRankingEngine` is pure code, so profile-weight changes can be tested without UI dependencies.

### 6. Broader RAW Format Path

Plan additional RAW formats only after the culling workflow above is stronger.

Value for culling:

- More format support increases RawCull's audience, but each format adds parser, preview, focus-point, and test-sample work.
- Format support should not outrun confidence in the core culling workflow.

Suggested scope:

- Add Canon CR3/CR2 or Fujifilm RAF as the next research track.
- Start with basic thumbnail/preview extraction and EXIF scan.
- Treat native AF-point parsing as a second phase per vendor.
- Require diagnostic pages and sample-file tests before calling a format supported.

Source foundation:

- `RawFormatRegistry` is designed for adding a new conformer.
- `RawParserKit` already isolates vendor-specific parser and extractor code.

## Six-Month Schedule

The schedule starts after the current 6 June 2026 source snapshot.

| Month | Theme | Deliverables | Why this first |
|---|---|---|---|
| June 2026 | Hardening before new behavior | Stable burst group signatures; stricter manual override matching; saved settings normalization; `FileRecord` equality/hash fix. | Removes known edge cases before more state is built on top. |
| July 2026 | Review queue MVP | `Needs Review` mode; queue rules from confidence/cautions/missing evidence; mark reviewed/deferred; quick accept actions; review counts in toolbar/sidebar. | Gives immediate culling value by directing attention to uncertain images. |
| August 2026 | Decision ledger | Persist accepted recommendations, deferred groups, manual overrides, batch actions, and copy status; add decision-history sheet; support batch undo for ledgered actions. | Makes automation auditable and safer across sessions. |
| September 2026 | Editing handoff | XMP sidecar export; CSV/JSON manifest export; rsync copy-status update; export preview and dry run. | Converts culling work into value in the editing pipeline. |
| October 2026 | Technical-risk scoring | Histogram clipping warnings; slow-shutter and high-ISO cautions; exposure-change warnings; integrate warnings into ranking cautions and review queue. | Improves recommendation quality beyond focus and similarity. |
| November 2026 | Preference profiles and format research | Local profile weights; profile comparison tests; collect parser diagnostics for the next RAW format; choose Canon or Fujifilm based on sample availability. | Adds personalization after the decision and export foundations are stable. |

## Suggested Milestones

### Milestone 1: Trustworthy Automation

Target: end of July 2026.

RawCull should be able to say: these groups are safe for one-click handling, these groups need review, and these decisions will remain attached to the correct images after reopening the catalog.

Acceptance criteria:

- Review states are keyed by stable group membership.
- Manual burst overrides require matching group membership.
- Low-confidence groups appear in `Needs Review`.
- One-click actions still require high confidence unless the user explicitly chooses otherwise.
- Tests cover regrouping, cache remapping, manual override matching, and review queue selection.

### Milestone 2: Workflow Handoff

Target: end of September 2026.

RawCull should be able to export its decisions in a way that survives outside the app.

Acceptance criteria:

- XMP sidecars correctly represent star ratings and rejects.
- CSV/JSON manifests include enough fields to audit recommendations.
- Copy status is updated after successful rsync completion.
- Empty copy sets are handled before launching rsync.
- Export preview shows counts by rating and destination.

### Milestone 3: Recommendation Quality

Target: end of November 2026.

RawCull should understand more than "sharpest in burst."

Acceptance criteria:

- Histogram clipping and EXIF risk warnings appear in candidate cautions.
- Risk warnings influence review queue selection.
- Profile weights can be applied and tested in `BurstRankingEngine`.
- Profile changes invalidate or version affected cached recommendations.
- The next RAW format has a documented parser plan and sample-file test requirements.

## Implementation Order

1. Build the review queue from existing confidence and caution data, using the completed stable-signature foundation.
2. Add decision ledger persistence after the queue rules settle.
3. Add XMP and manifest export using the ledger and current ratings.
4. Add rsync/copy hardening as part of the editing-handoff phase.
5. Add technical-risk warnings and feed them into review selection.
6. Add local preference profiles once the recommendation inputs are stable.
7. Research the next RAW format only after the workflow features are shippable.

## What Not To Prioritize Yet

Avoid these until the next phase is complete:

- A full editing/develop module. RawCull's value is fast selection, not replacing a RAW editor.
- Cloud sync or account features. The current local-first privacy model is a strength.
- Large UI redesign. The app already has specialized views; the next value is better workflow connection between them.
- New camera brands before the review/export flow is stronger. Format breadth is valuable, but workflow depth will help every current user immediately.

## Recommended Next Task

Start the July review queue MVP.

June hardening has established stable burst identity, conservative manual override matching, signature-keyed cache review state, saved-settings normalization, and safer `FileRecord` equality. The next task is to turn that stable foundation into a visible `Needs Review` workflow for low-confidence, caution-bearing, deferred, or manually conflicted burst decisions.

## June Hardening Completed

The June stabilization pass is complete and should no longer be treated as active roadmap work.

Completed outcomes:

- Burst-level review state is keyed by stable group membership instead of transient numeric group ids.
- Cached review state is restored only when the current group signature matches the saved signature.
- Manual winner overrides require exact canonical group membership; winner presence alone is not enough.
- Legacy manual overrides using `memberFileNames` remain readable under exact membership matching.
- Saved settings are normalized after decode and before save/snapshot use.
- `FileRecord` equality now accounts for persisted sharpness and saliency metadata instead of comparing only rating fields.
- The relevant Swift Testing coverage was added for override matching, cache remapping, settings normalization, and `FileRecord` equality.

Remaining work moved forward:

- Build the July `Needs Review` queue on top of the stable burst signature and review-state cache.
- Add the July-only review states and queue filters needed for `reviewed` and `deferred` workflows.
- Keep rsync/copy hardening separate for the later editing-handoff/copy-export phase.

## July Review Queue MVP Details

Prerequisite: June hardening is complete. The July queue should use the existing stable burst signature and signature-keyed review-state cache as its burst-item identity foundation.

The July milestone should turn RawCull's existing evidence into a focused review workflow. After the June hardening pass, the app should know which burst decisions are safely attached to stable member sets. The next step is to use that stability to create a separate `Needs Review` surface for images and burst groups that should not be handled by blind grid browsing or automatic one-click culling.

The core idea is simple: the grid is for browsing the catalog, similarity is for finding related frames, comparison is for inspecting candidates, and the review queue is for resolving uncertainty. The review queue should feel like a distinct workbench with its own entry point, counters, filters, empty state, actions, and completion model. A photographer should never wonder whether they are looking at the normal catalog grid or a curated list of unresolved decisions.

### Goal

Build a minimum viable `Needs Review` mode that gathers uncertain burst groups and individual files, explains why they are in the queue, and lets the user resolve each item with fast, conservative actions.

The main outcome is that RawCull guides the photographer toward the frames that need human judgment. It should reduce the cognitive load of culling by separating "browse everything" from "review only the unresolved cases." A secondary outcome is to create the state model that later decision-ledger and export features can depend on.

### Product Principle

The review queue should be a clear workflow boundary, not just another filter on the grid.

RawCull already has several specialized views. The risk of adding review as a subtle grid filter is that users may not know whether actions apply to the entire catalog, the current visual filter, a burst group, or a pending review task. The queue should therefore have a distinct title, count, visual treatment, toolbar actions, and navigation behavior.

Suggested UX boundaries:

- Name the mode `Needs Review` or `Review Queue` consistently in the sidebar/toolbar.
- Show a queue count, such as `12 Needs Review`, separate from total file count and rated-file count.
- Use a dedicated review layout instead of reusing the normal thumbnail grid unchanged.
- Present each queue item as a review task with a reason, suggested action, confidence, and status.
- Keep browse-only controls out of the primary review toolbar unless they directly help resolve the current task.
- Make completion explicit with states like `Reviewed`, `Deferred`, or `Applied`.
- Let users leave the queue and return without losing their place.

The visual and interaction language should communicate: "you are resolving uncertain decisions now." It should not communicate: "you are browsing a filtered subset of the catalog."

### Primary Problem

RawCull can already rank candidates, compare top frames, show focus evidence, and attach cautions. However, that evidence is distributed across several views and is easy to miss during a fast cull.

Concrete problems the queue should solve:

- Low-confidence burst groups require attention, but currently they can sit among high-confidence groups in the same browsing flow.
- Missing sharpness scores, missing AF evidence, or candidate cautions may not be obvious until the user opens an inspector.
- Similar frames outside a burst may be ambiguous, but the app does not yet turn that ambiguity into a task.
- Manual overrides and deferred choices need a visible place to come back to.
- A photographer may want to run automation on easy groups, then spend the rest of the session only on unresolved cases.

The review queue should collect those cases into a small, prioritized list and make the next action obvious.

### Required Scope

1. Add a dedicated review mode.

   Add a `Needs Review` mode alongside the existing app modes, but make it visually and behaviorally distinct. It can reuse existing candidate and comparison components internally, but the top-level view should clearly be a review queue. The entry point should show the number of unresolved review items.

2. Create queue item types.

   The MVP should support at least burst-group queue items. If individual file-level risk items are straightforward, include them as a second item type; otherwise design the model so file-level items can be added in October when technical-risk scoring lands.

   Suggested shape:

   ```swift
   enum ReviewQueueItemKind: Codable, Hashable, Sendable {
       case burstGroup(BurstGroupSignature)
       case file(String)
   }
   ```

   The stable key matters. A queue item should represent the actual files requiring review, not the current transient group id.

3. Define queue inclusion rules.

   The MVP should include burst groups when any of these are true:

   - Ranking confidence is `.low` or `.medium`.
   - The gap between the top two candidates is small.
   - The selected winner has candidate cautions.
   - The group has group-level cautions.
   - Sharpness score is missing or stale for one or more important candidates.
   - AF focus evidence is missing when the camera format normally supports it.
   - A manual winner override exists but the current recommendation disagrees.
   - The group was previously deferred.
   - A cached recommendation was invalidated because group membership or scoring signature changed.

   These rules should be conservative. It is better for the MVP queue to include a few extra ambiguous groups than to hide a decision that deserves attention.

4. Add review states and queue filters.

   The June work covers `.decisionApplied` and `.manualWinnerOverride`, but the queue still needs explicit states or an app-side review-state wrapper for:

   - `needsReview`: unresolved and visible in the queue.
   - `reviewed`: user inspected and intentionally closed the item without applying an automated decision.
   - `deferred`: user chose to leave the item for later.

   State should persist by stable group signature. Runtime lookup can still map back to `group.id` for view performance. Keep deferred visibility as a queue filter, not as a default low-priority unresolved item.

5. Add quick actions.

   The queue should help users finish work, not just list problems. For burst groups, include:

   - Accept RawCull recommendation.
   - Keep top two.
   - Reject all but selected.
   - Choose selected as winner.
   - Mark reviewed.
   - Defer.

   Actions that change ratings should show enough context to avoid surprises. For low-confidence groups, the primary action can still be available, but the UI should make it clear that the user is accepting a recommendation after review.

6. Explain why each item is queued.

   Every queue item should show concise reasons. Examples:

   - `Low confidence: top candidates are separated by 2.4 points`
   - `Missing sharpness score for DSC01234.ARW`
   - `Manual winner differs from current recommendation`
   - `AF point evidence unavailable`
   - `Candidate caution: subject may be off focus`

   This explanation is what makes the queue trustworthy. A queue with no reason text becomes another mysterious filter.

7. Preserve navigation context.

   Users should be able to open a queue item, compare candidates, inspect evidence, apply a decision, and return to the next unresolved item. The mode should remember the current queue position and should not bounce the user back to the full catalog after every action.

8. Add queue counts and empty states.

   The app should show unresolved count, deferred count, and reviewed/applied count for the current catalog. When the queue is empty, the empty state should be direct and useful: all uncertain groups are resolved, or no review items match the current queue filter.

### Review Queue Examples

#### Example 1: Low-Confidence Burst

RawCull scans a five-frame bird-in-flight burst:

```text
DSC04120.ARW
DSC04121.ARW
DSC04122.ARW
DSC04123.ARW
DSC04124.ARW
```

The ranking engine chooses `DSC04122.ARW`, but `DSC04123.ARW` has a very close score and the group confidence is `.medium`.

The queue item should appear as:

```text
Needs Review
Burst: DSC04120-DSC04124
Reason: Medium confidence. Top two candidates are close.
Recommendation: Keep DSC04122.ARW
Suggested action: Compare top two
```

Expected workflow:

1. User opens the item from `Needs Review`.
2. RawCull shows the top candidates in comparison mode with the candidate inspector visible.
3. User picks `DSC04123.ARW` after seeing better wing position.
4. RawCull saves a manual winner override for the exact burst signature.
5. The queue item moves out of unresolved review and is marked `manualWinnerOverride`.

The important behavior is that the user did not need to find this burst manually in the full grid. RawCull surfaced it because the decision was close.

#### Example 2: Missing Evidence

RawCull scans a three-frame burst where embedded preview extraction succeeded, but sharpness scoring failed for one candidate:

```text
DSC05010.ARW
DSC05011.ARW
DSC05012.ARW
```

The ranking engine recommends `DSC05011.ARW`, but `DSC05012.ARW` has no sharpness score.

The queue item should appear as:

```text
Needs Review
Burst: DSC05010-DSC05012
Reason: Missing sharpness score for DSC05012.ARW.
Recommendation: Review before applying one-click cull.
Suggested action: Inspect candidates
```

Expected workflow:

1. User opens the item.
2. RawCull displays the scored candidates and marks the missing-score frame clearly.
3. User manually inspects the previews.
4. User either keeps a selected frame, keeps top two, or marks the group reviewed.
5. RawCull persists the review state by burst signature.

The queue should not imply that the recommendation is bad. It should say that the evidence is incomplete.

#### Example 3: Manual Override Conflict

In a previous session, the user manually selected `DSC06105.ARW` as winner for:

```text
DSC06103.ARW
DSC06104.ARW
DSC06105.ARW
```

After scoring settings change, RawCull now recommends `DSC06104.ARW` for the same exact burst membership.

The queue item should appear as:

```text
Needs Review
Burst: DSC06103-DSC06105
Reason: Current recommendation differs from manual winner.
Manual winner: DSC06105.ARW
Current recommendation: DSC06104.ARW
Suggested action: Keep manual winner or accept new recommendation
```

Expected workflow:

1. User opens the item and sees both the previous manual choice and the new recommendation.
2. User confirms the manual winner, or accepts the new recommendation.
3. RawCull records the chosen outcome and removes the item from unresolved review.

The app should not silently replace the user's earlier manual judgment.

#### Example 4: Deferred Decision

The user reviews a difficult portrait burst and decides not to choose yet.

Expected workflow:

1. User opens the queue item.
2. User clicks `Defer`.
3. The item leaves the main unresolved queue but remains visible under a `Deferred` queue filter.
4. The toolbar count changes from `Needs Review: 8` to `Needs Review: 7`, and `Deferred: 1`.
5. Reopening the catalog restores the deferred item by stable signature.

Deferred should mean "come back later," not "hide forever."

#### Example 5: Accepting a Recommendation After Review

RawCull flags a group because confidence is `.medium`, but the photographer agrees with the suggested winner.

Expected workflow:

1. User opens the queue item.
2. User checks the top candidate and focus evidence.
3. User clicks `Accept Recommendation`.
4. RawCull applies the normal keep/reject or rating behavior for that action.
5. The item is marked `decisionApplied` and disappears from unresolved review.
6. Undo remains available for the immediate action.

The distinction is that medium-confidence automation becomes acceptable after explicit review.

### Suggested UI Shape

The MVP can be implemented without a large redesign, but it should still feel like its own workflow.

Recommended layout:

- Left or top queue summary: unresolved, deferred, reviewed, applied.
- Main list or vertical stack of review tasks, sorted by priority.
- Detail pane for the selected task, reusing candidate rows, focus evidence, and ranking reasons.
- Primary action area with review-specific actions.
- Optional "Open in Comparison" action when the dedicated comparison grid is better than an embedded detail view.

Recommended sorting:

1. Manual override conflicts.
2. Low-confidence groups.
3. Missing evidence.
4. Medium-confidence close calls.
5. Deferred items, when the deferred filter is active.

Recommended visual distinction:

- Use a clear `Needs Review` title in the mode header.
- Use status badges such as `Low confidence`, `Missing evidence`, `Manual conflict`, and `Deferred`.
- Avoid showing the full catalog thumbnail grid as the first thing in this mode.
- Keep queue items task-like, not photo-browser-like.

### Suggested Implementation Shape

The July work should build on the June stable-signature work:

- Add a `ReviewQueueBuilder` or small view-model helper that derives queue items from current burst groups, ranking results, review states, candidate cautions, and scoring state.
- Keep derivation deterministic and testable. Given the same groups and states, the queue should produce the same items in the same priority order.
- Store persisted review states by `BurstGroupSignature`, but expose UI state through current group ids after remapping.
- Treat queue items as derived from source-of-truth state rather than as a second permanent list whenever possible.
- Persist only user decisions and review states, not every computed queue row.
- Rebuild the queue after scoring completes, burst analysis changes, settings invalidate scores, or review actions are applied.

Suggested model sketch:

```swift
struct ReviewQueueItem: Identifiable, Hashable, Sendable {
    var id: ReviewQueueItemID
    var priority: ReviewQueuePriority
    var kind: ReviewQueueItemKind
    var status: BurstReviewState
    var title: String
    var reasons: [String]
    var recommendedAction: ReviewRecommendedAction?
    var candidateFileNames: [String]
}

enum ReviewQueuePriority: Int, Codable, Sendable {
    case manualConflict = 0
    case lowConfidence = 1
    case missingEvidence = 2
    case mediumConfidence = 3
}

enum ReviewQueueFilter: Codable, Sendable {
    case unresolved
    case deferred
    case reviewed
}
```

This can live in the app target at first. If the queue rules become pure and broadly testable, move the rule engine into `RawCullCore`.

### Main Code Surfaces

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`: current burst groups, review states, one-click actions, manual winner overrides, and cache interactions.
- `RawCullCore/Sources/RawCullCore/BurstRankingEngine.swift`: confidence, score gaps, reasons, cautions, and recommendation evidence.
- `RawCull/Model/ViewModels/BurstAnalysisModels.swift`: app-side stable burst signatures and review-state support models.
- `RawCull/Views/ComparisonGridView/ComparisonGridView.swift`: candidate comparison UI that can be reused or opened from a review item.
- `RawCull/Views/ComparisonGridView/CandidateInspectorView.swift`: evidence display for reasons, cautions, focus data, and score components.
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`: current burst group source and similarity analysis state.
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`: scoring freshness and missing-score evidence.
- A new `ReviewQueueView` or `NeedsReviewView`: the dedicated review surface.
- A new `ReviewQueueBuilder` or `RawCullViewModel+ReviewQueue.swift`: deterministic queue construction.

### Concrete Code Change Plan

1. Define review state and queue item models.

   Add explicit state support for `needsReview`, `reviewed`, and `deferred`, then add lightweight models for queue item id, kind, priority, filter, reasons, and recommended action. Keep the models `Sendable` where practical. Use stable signatures for burst identity.

2. Add queue derivation.

   Build a pure or mostly pure helper that accepts current burst groups, file lookup, ranking results, review states, and scoring metadata. It should return unresolved queue items plus optional deferred/reviewed summaries.

3. Add inclusion rules one at a time.

   Start with low/medium confidence and candidate/group cautions. Then add missing sharpness/AF evidence if the needed state is readily available. Keep each rule named so the reason text can be tested.

4. Add `Needs Review` mode routing.

   Add the mode to the app's navigation or toolbar where the other major modes live. Do not bury it as a small grid filter. The mode should have its own title and count.

5. Build the queue view.

   The first version can use a split view: queue tasks on one side, selected task details on the other. It can reuse existing candidate rows and inspector components rather than duplicating scoring UI.

6. Connect quick actions.

   Wire `Accept Recommendation`, `Keep Top Two`, `Reject All But Selected`, `Choose Winner`, `Mark Reviewed`, and `Defer` to the existing burst action methods where possible. Make sure actions update review state and rebuild the queue.

7. Preserve undo behavior.

   Existing immediate undo for burst actions should remain available. Because undo is in-session, it can restore prior ratings and prior review state from the undo entry without re-verifying group membership.

8. Persist review states.

   Save `reviewed`, `deferred`, `decisionApplied`, and `manualWinnerOverride` by stable signature. Do not persist transient queue ordering or computed reason strings.

9. Add counters.

   Add unresolved and deferred counts to the toolbar/sidebar. These counts should update after scoring, burst analysis, and review actions.

10. Add tests.

    Start with queue-builder tests before UI tests. The queue rules are the part most likely to regress quietly.

### What Can Go Wrong If This Is Not Implemented Clearly

The biggest risk is user confusion. A review queue that looks too much like the normal grid can make users uncertain about what they are acting on.

Concrete failure modes:

- The user thinks they are reviewing all files, but they are only seeing uncertain groups.
- The user thinks they are applying a decision to one image, but the action affects a whole burst group.
- Deferred items disappear because there is no visible deferred state or count.
- A queue item has no reason text, so the user cannot tell why RawCull is asking for attention.
- Review state is stored by runtime group id, so a resolved item can reappear incorrectly or an unresolved item can vanish after regrouping.
- The queue becomes a passive warning list instead of a workflow because it lacks quick actions.
- Medium-confidence recommendations feel automated rather than reviewed because `Accept Recommendation` does not clearly indicate user confirmation.

The MVP should optimize for clarity over density. RawCull can become more compact later, but the first version should teach the user what this new workflow means.

### Test Coverage

Use Swift Testing tests for queue derivation and state transitions. UI tests can be added later if the project does not already have a UI-testing harness, but the core queue rules should be covered immediately.

Required queue-builder tests:

- Low-confidence burst groups are included in unresolved review.
- Medium-confidence groups with close top candidates are included.
- High-confidence groups with no cautions are not included.
- Candidate cautions add a queue reason.
- Group cautions add a queue reason.
- Missing sharpness evidence adds a queue reason when the candidate is otherwise relevant.
- Manual winner conflicts are prioritized above ordinary low-confidence items.
- Deferred items are excluded from the default unresolved queue but included in the deferred filter.
- `decisionApplied` and `reviewed` items are excluded from unresolved review.
- Queue ordering is deterministic for equal-priority items.

Required state tests:

- Marking a queue item reviewed persists by stable signature.
- Deferring a queue item persists by stable signature.
- Accepting a recommendation updates review state to `decisionApplied`.
- Choosing a manual winner updates review state to `manualWinnerOverride`.
- A changed burst membership invalidates the previous review state and creates a fresh queue item if rules still match.
- Reopening or reloading a catalog restores deferred/reviewed state only for matching signatures.

Required action tests:

- `Accept Recommendation` applies the expected ratings or keep/reject behavior.
- `Keep Top Two` keeps exactly the selected recommendation set.
- `Reject All But Selected` does not run unless the selected file belongs to the current group.
- Undo restores ratings and review visibility for the affected group.

### Acceptance Criteria

- `Needs Review` is a distinct mode, not only a hidden grid filter.
- The mode shows unresolved and deferred counts for the current catalog.
- Queue items explain why they require review.
- Low/medium-confidence burst groups and caution-bearing groups appear in the queue.
- High-confidence groups without cautions stay out of the queue.
- Users can accept a recommendation, keep top two, reject all but selected, choose a manual winner, mark reviewed, or defer.
- Review states persist by stable group signature.
- Deferred items can be found again through an explicit deferred view/filter.
- Queue order is deterministic and prioritizes manual conflicts and low-confidence work.
- Tests cover queue inclusion, state transitions, persistence by signature, and quick-action behavior.

### Out Of Scope For This Task

- A full decision ledger or historical audit sheet.
- XMP sidecar export or external editing handoff.
- New technical-risk scoring rules that require histogram work not already exposed to the ranking engine.
- New RAW format support.
- A broad redesign of RawCull's main navigation.
- Training or preference-profile learning from accepted review decisions.

Those features should follow after the queue proves that RawCull can separate normal browsing from uncertainty resolution in a way that feels clear and trustworthy.

## Document Review Notes — June 2026

The following issues and enhancements were identified by cross-checking this document against the actual source snapshot on 7 June 2026. Items are grouped by section.

### June Hardening — Resolved

The June hardening review items have been incorporated and implemented. The original confirmed bugs around manual winner matching and numeric review-state cache restoration are no longer active roadmap items.

Resolved outcomes:

- Manual winner overrides now require exact canonical burst membership instead of winner-file presence alone.
- Cached burst review state is restored by stable burst signature, not by transient numeric group id.
- `BurstGroupSignature` lives with the app-side burst analysis support models.
- `FileRecord` equality no longer ignores persisted sharpness and saliency metadata.
- Saved settings are normalized on decode and before save/snapshot use.
- Rsync/copy hardening remains intentionally deferred to the later copy/export work and is not part of the completed June batch.

### July Review Queue — Folded Into Plan

The remaining review notes are now part of the July review queue plan itself:

- July starts from the completed June stable-signature foundation.
- The queue must add explicit state support for `needsReview`, `reviewed`, and `deferred`.
- Deferred items are handled through an explicit queue filter, not as a default unresolved sort priority.
- Immediate undo restores prior ratings and prior review state in memory; it does not need signature rematching during the same session.
