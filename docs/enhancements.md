+++
author = "Thomas Evensen"
title = "Enhancement Roadmap"
linkTitle = "Enhancements"
date = "2026-06-08"
weight = 90
tags = ["roadmap", "enhancements", "culling", "workflow"]
categories = ["planning"]
+++

# Enhancement Roadmap

RawCull is already a strong culling application: it scans Sony ARW and Nikon NEF catalogs, extracts previews, keeps thumbnail and full-size preview caches, persists ratings, scores focus and sharpness, reads Sony/Nikon focus points, groups bursts, ranks candidates, explains its ranking evidence, compares candidate frames, and copies selected RAW files through the rsync workflow.

The next phase should therefore avoid adding generic photo-browser features. The best value is to make RawCull faster at answering the culling question: which files are safe to reject, which files deserve careful review, and how do the keepers move cleanly into the photographer's editing workflow?

## Verified Current State

This roadmap was checked against the updated source snapshot on 8 June 2026.

| Area | Done now | Source evidence |
|---|---|---|
| RAW format coverage | Sony ARW and Nikon NEF are registered format families; JPEG/JPG files are also recognized by the app-side supported-file enum. | `RawParserKit/Sources/RawParserKit/RawFormatRegistry.swift`, `RawCull/Extensions/SupportedFileType.swift` |
| Catalog scan | Scan extracts file metadata, EXIF, dimensions, size class, and inline focus location in one task-group pass. | `RawCull/Actors/ScanFiles.swift` |
| Thumbnail and preview pipeline | Thumbnail extraction, disk cache, memory cache, full-size preview cache, sidecar-first zoom loading, and explicit embedded-JPEG export are implemented. | `RawCull/Actors/RequestThumbnail.swift`, `RawCull/Actors/DiskCacheManager.swift`, `RawCull/Actors/FullSizeJPGDiskCache.swift`, `RawCull/Model/Handlers/ZoomPreviewHandler.swift` |
| Sharpness and focus evidence | Sharpness scoring, saliency, AF-point weighting, focus-mask rendering, scoring quality/source options, and persisted scoring signatures are present. | `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`, `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift` |
| Burst intelligence | Burst grouping, ranking, confidence, reasons, cautions, manual winner overrides, one-click keep/reject actions, undo, and cache persistence are implemented. | `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `RawCullCore/Sources/RawCullCore/BurstGroupingEngine.swift`, `RawCullCore/Sources/RawCullCore/BurstRankingEngine.swift`, `RawCull/Actors/BurstAnalysisCache.swift` |
| Review queue MVP | Burst groups can be filtered by `All`, `Needs Review`, `Deferred`, and `Reviewed`; review counts are shown; groups can be marked reviewed, deferred, or returned to review; review state persists through the existing stable-signature cache. | `RawCull/Model/ViewModels/BurstReviewQueueModels.swift`, `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `RawCull/Views/SimilarityGridView/SimilarityGridSelectionView.swift`, `RawCull/Views/CullingGrid/CullingGridView.swift` |
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

The July MVP is in place for burst groups. It collects uncertain burst decisions through review filters and lets the user mark groups as reviewed, deferred, or needing review again.

Value for culling:

- Lets the photographer spend attention only where judgment is needed.
- Turns low-confidence burst groups, missing focus evidence, tight score gaps, metadata changes, and subject mismatch into a concrete review list.
- Preserves RawCull's conservative behavior: automate the easy rejects, slow down for ambiguous frames.

Completed MVP scope:

- Review filters: `All`, `Needs Review`, `Deferred`, and `Reviewed`.
- Queue rules from burst confidence, cautions, missing recommendations, and one-click safety.
- Quick review actions: mark reviewed, defer, return to needs review, keep best, keep top two, and compare.
- Review state persists by stable burst signature through `BurstReviewStateSnapshot`.
- Toolbar/header counts expose unresolved, deferred, and completed groups.

Remaining refinements:

- Add a more explicit empty state for each review filter.
- Add richer reason text for why each group entered the queue.
- Add individual file-level review items when technical-risk scoring lands.
- Consider a distinct task-list layout if the filtered burst grid is not clear enough in real use.

Source foundation:

- `BurstDecisionConfidence`, `BurstReviewState`, candidate cautions, and group cautions exist in `RawCullCore`.
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

The schedule reflects the 8 June 2026 source snapshot.

| Month | Theme | Deliverables | Why this first |
|---|---|---|---|
| June 2026 | Hardening before new behavior | Stable burst group signatures; stricter manual override matching; saved settings normalization; `FileRecord` equality/hash fix. | Completed. Removes known edge cases before more state is built on top. |
| July 2026 | Review queue MVP | Review filters from confidence/cautions/missing recommendation evidence; mark reviewed/deferred/needs-review; quick burst actions; review counts in toolbar/header. | Completed MVP. Directs attention to uncertain burst decisions. |
| August 2026 | Decision ledger | Persist accepted recommendations, deferred groups, manual overrides, batch actions, and copy status; add decision-history sheet; support batch undo for ledgered actions. | Makes automation auditable and safer across sessions. |
| September 2026 | Editing handoff | XMP sidecar export; CSV/JSON manifest export; rsync copy-status update; export preview and dry run. | Converts culling work into value in the editing pipeline. |
| October 2026 | Technical-risk scoring | Histogram clipping warnings; slow-shutter and high-ISO cautions; exposure-change warnings; integrate warnings into ranking cautions and review queue. | Improves recommendation quality beyond focus and similarity. |
| November 2026 | Preference profiles and format research | Local profile weights; profile comparison tests; collect parser diagnostics for the next RAW format; choose Canon or Fujifilm based on sample availability. | Adds personalization after the decision and export foundations are stable. |

## Suggested Milestones

### Milestone 1: Trustworthy Automation

Status: completed MVP on 8 June 2026; refinements remain.

RawCull should be able to say: these groups are safe for one-click handling, these groups need review, and these decisions will remain attached to the correct images after reopening the catalog.

Acceptance criteria:

- Review states are keyed by stable group membership.
- Manual burst overrides require matching group membership.
- Low-confidence and caution-bearing groups appear in `Needs Review`.
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

1. Add decision ledger persistence now that the review queue state model exists.
2. Add decision-history UI and batch undo on top of ledger entries.
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

Start the August decision ledger.

The review queue MVP now provides durable burst review state and a focused way to resolve uncertain groups. The next step is to record the decisions behind those state changes: accepted recommendations, deferred groups, manual winner overrides, batch actions, and copy/export outcomes. That ledger should become the audit trail used by decision history, batch undo, XMP/manifest export, and future scoring comparisons.

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

- Add a decision ledger and history sheet.
- Add richer review reasons and empty states after observing the MVP in use.
- Keep rsync/copy hardening separate for the later editing-handoff/copy-export phase.

## July Review Queue MVP Completed

The July review queue MVP is implemented in the app target and should no longer be treated as active planning work.

Completed outcomes:

- `BurstReviewState` supports `needsReview`, `reviewed`, and `deferred` through the imported `RawCullCore` package.
- App-side queue policy derives the effective review state from burst confidence, cautions, missing recommendation evidence, and one-click safety.
- Burst groups can be filtered by `All`, `Needs Review`, `Deferred`, and `Reviewed`.
- The similarity/burst grid exposes review counts and a direct `Needs Review` entry point when unresolved groups exist.
- The main toolbar exposes a review entry point when the current catalog has unresolved review groups.
- Burst headers expose `Reviewed`, `Defer`, and `Needs Review` actions.
- Review state changes are saved through the existing stable-signature burst analysis cache.
- Focused Swift Testing coverage was added for queue policy and view-model filtering.

Known MVP limits:

- The review surface currently reuses the burst-group grid instead of a dedicated task-list layout.
- Queue reasons come from existing confidence/caution presentation and are not yet a separate reviewed item model.
- Individual file-level review items are deferred until technical-risk scoring creates stronger file-level signals.
- Full `xcodebuild test` execution hung after launching the app-hosted macOS test runner in the local environment, but `make debug` and `xcodebuild build-for-testing` succeeded.
