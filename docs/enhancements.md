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
| RAW format coverage | Sony ARW and Nikon NEF are registered format families; JPEG/JPG files are also recognized by the app-side supported-file enum. | `sourcecode/RawParserKit/Sources/RawParserKit/RawFormatRegistry.swift`, `sourcecode/RawCull/Extensions/SupportedFileType.swift` |
| Catalog scan | Scan extracts file metadata, EXIF, dimensions, size class, and inline focus location in one task-group pass. | `sourcecode/RawCull/Actors/ScanFiles.swift` |
| Thumbnail and preview pipeline | Thumbnail extraction, disk cache, memory cache, full-size preview cache, sidecar-first zoom loading, and explicit embedded-JPEG export are implemented. | `sourcecode/RawCull/Actors/RequestThumbnail.swift`, `sourcecode/RawCull/Actors/DiskCacheManager.swift`, `sourcecode/RawCull/Actors/FullSizeJPGDiskCache.swift`, `sourcecode/RawCull/Model/Handlers/ZoomPreviewHandler.swift` |
| Sharpness and focus evidence | Sharpness scoring, saliency, AF-point weighting, focus-mask rendering, scoring quality/source options, and persisted scoring signatures are present. | `sourcecode/RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`, `sourcecode/RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift` |
| Burst intelligence | Burst grouping, ranking, confidence, reasons, cautions, manual winner overrides, one-click keep/reject actions, undo, and cache persistence are implemented. | `sourcecode/RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `sourcecode/RawCullCore/Sources/RawCullCore/BurstGroupingEngine.swift`, `sourcecode/RawCullCore/Sources/RawCullCore/BurstRankingEngine.swift`, `sourcecode/RawCull/Actors/BurstAnalysisCache.swift` |
| Similarity review | Vision feature-print indexing, similar-image ranking, burst sensitivity, and similarity grid mode are implemented. | `sourcecode/RawCull/Model/ViewModels/SimilarityScoringModel.swift`, `sourcecode/RawCull/Views/SimilarityGridView/SimilarityGridView.swift` |
| Comparison workflow | Top candidates can be opened in comparison mode with a candidate inspector showing score components, focus evidence, camera settings, reasons, cautions, and rank rows. | `sourcecode/RawCull/Views/ComparisonGridView/ComparisonGridView.swift`, `sourcecode/RawCull/Views/ComparisonGridView/CandidateInspectorView.swift` |
| Persistence | `savedfiles.json` stores catalog records, ratings, scoring fields, and burst winner overrides. | `sourcecode/RawCull/Model/JSON/SavedFiles.swift`, `sourcecode/RawCull/Model/ViewModels/CullingModel.swift` |
| Copy/export | Rated file lists can be passed to the rsync copy workflow, and embedded JPEG previews can be extracted beside RAW files. | `sourcecode/RawCull/Views/CopyFiles/CopyFilesView.swift`, `sourcecode/RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift`, `sourcecode/RawCull/Actors/ExtractAndSaveJPGs.swift` |
| Diagnostics | Memory diagnostics, raw-file parser diagnostics, scan stats, and histogram calculation exist. | `sourcecode/RawCull/Views/Diagnostics/MemoryDiagnosticsView.swift`, `sourcecode/RawCull/Model/Diagnostics/RawFileDiagnostics.swift`, `sourcecode/RawCull/Views/GridView/ScanStatsSheetView.swift`, `sourcecode/RawCull/Views/Histogram/HistogramView.swift` |
| Package split | Pure models, burst logic, focus parsing, histogram calculation, and raw parser code are extracted into `RawCullCore` and `RawParserKit` with tests. | `sourcecode/RawCullCore/Tests/RawCullCoreTests/`, `sourcecode/RawParserKit/Tests/RawParserKitTests/` |

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
| June 2026 | Hardening before new behavior | Stable burst group signatures; stricter manual override matching; saved settings normalization; `FileRecord` equality/hash decision; rsync empty-list and relative-pattern handling. | Removes known edge cases before more state is built on top. |
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

1. Fix stable identity and persistence issues before adding a review queue.
2. Build the review queue from existing confidence and caution data.
3. Add decision ledger persistence after the queue rules settle.
4. Add XMP and manifest export using the ledger and current ratings.
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

Start with the June hardening work:

1. Introduce a stable burst group signature based on catalog-relative member names.
2. Store review state and manual winner overrides against that signature.
3. Add tests for cache remapping, regrouping, and manual override membership.
4. Then build the `Needs Review` queue using the existing confidence, reasons, and cautions.

This is the best first step because it strengthens RawCull's most valuable feature: confident, explainable burst culling.
