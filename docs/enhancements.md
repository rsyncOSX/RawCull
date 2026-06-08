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

## June Hardening Work Details

This task is the stabilization pass that should happen before adding the `Needs Review` queue or a decision ledger. The current burst workflow already ranks candidates and tracks manual choices, but some of that state is still attached to transient runtime identities. The June work makes those decisions survive cache reloads, regrouping, and settings reloads without being applied to the wrong files.

### Goal

Make RawCull's existing culling state stable enough that future review and ledger features can rely on it.

The main outcome is that a burst decision is attached to the burst's actual member files, not to whatever numeric group id happened to be assigned in the latest analysis pass. A secondary outcome is to clean up nearby persistence assumptions that could otherwise become harder to fix once more state is built on top.

### Primary Problem

Burst groups currently have two identities:

- A transient `Int` group id produced by the grouping pass.
- The actual set of member files that the photographer sees and acts on.

The transient id is useful for in-memory lookup, but it is not safe as a persistence key. If a cache is loaded, file IDs are remapped, grouping sensitivity changes, files are added or removed, or group ordering changes, the same `Int` can refer to a different member set. That can make cached review state or "decision applied" state drift onto the wrong group.

Manual winner overrides have a related problem. `BurstWinnerOverride` stores `winnerFileName` and `memberFileNames`, but lookup currently accepts the last override whose winner appears in the current group. It does not require the saved member set to match the current group. If the winning file later belongs to a different group, RawCull can treat an old manual winner as valid for a different burst.

### Required Scope

1. Add a stable burst group signature.

   The signature should be derived from catalog-relative member names or paths, sorted into a deterministic order. It should not use `FileItem.id`, scan order, or `BurstGroup.id`. Prefer catalog-relative paths if nested catalogs or duplicate file names are possible; otherwise document why file names are sufficient for the current catalog model. This signature is the persistence identity for burst-level state; the transient `Int` group id remains session/UI-only.

2. Use the signature for persisted/reused burst state.

   Review state such as `.decisionApplied` and `.manualWinnerOverride` should be stored and restored by stable signature. Runtime dictionaries may still use `Int` group id for view performance, but cache load/remap should only transfer persisted review state after the current group's signature matches the saved signature.

3. Tighten manual winner override matching.

   `CullingModel.overrideWinner(for:in:)` should require the saved member set to match the current group member set before returning an override. The winner must still be present, but winner presence alone is not enough. If a relaxed overlap rule is ever needed, it should be explicit and tested; the default June hardening behavior should be exact membership.

4. Preserve backward compatibility.

   Existing `savedfiles.json` files may contain `BurstWinnerOverride` values without a new signature field. Those records can still be interpreted through their saved `memberFileNames`, but they should be upgraded or matched using the same canonical membership logic. Existing burst analysis cache files should either be invalidated by schema version or decoded with a clear migration path.

5. Keep one-click culling conservative.

   `keepBestInGroup(from:)` and `keepTopTwoInGroup(from:)` should continue to require `canApplyOneClickCulling`. This task should not broaden automation rules; it only makes the state identity safer.

### Secondary Hardening In Same June Batch

These items are smaller than burst identity, but they are part of the same "hardening before new behavior" milestone:

- Add a single saved-settings normalization path used after decode and before save. Clamp cache sizes, thumbnail sizes, scoring weights, focus-mask parameters, and sharpening values to the app's supported ranges before assigning them to `SettingsViewModel`.
- Fix the latent `FileRecord` equality/hash risk. Either include all persisted fields, including sharpness and saliency metadata, in `==`/`hash(into:)`, or remove `Hashable` if records should never be used as set/diff identity. The current behavior must not allow two records with different persisted sharpness metadata to compare equal silently.
- Defer rsync/copy hardening to a later copy/export pass. Do not include empty-list handling, include-pattern rewriting, or argument placeholder trimming in this June-focused batch.

### Main Code Surfaces

- `RawCull/Model/ViewModels/BurstAnalysisModels.swift`: shared burst support models such as `BurstGroupSignature`, plus any signature fields added to persisted burst-related records.
- `RawCull/Model/ViewModels/CullingModel.swift`: `BurstWinnerOverride` persistence, lookup, pruning, and membership matching.
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`: in-memory review state, manual override application, cached snapshot remapping, one-click actions, undo state, and cache save/load handoff.
- `RawCull/Actors/BurstAnalysisCache.swift`: cached snapshot schema, review-state persistence, and schema-version invalidation or migration.
- `RawCull/Model/JSON/SavedFiles.swift`: persisted override and `FileRecord` equality/hash decisions.
- `RawCull/Model/ViewModels/SettingsViewModel.swift`: saved settings decode/save normalization.

### Suggested Implementation Shape

- Introduce a small shared `Codable`, `Hashable`, `Sendable` value type for canonical burst membership, for example `BurstGroupSignature`.
- Build signatures from current `groupFiles` at action time and from cached snapshot file metadata at cache load time.
- Store signatures in cache snapshots beside review states, or key review states by signature directly.
- Keep the UI-facing `burstReviewStates` dictionary keyed by `groupID` only as a derived runtime map.
- On cache remap, rebuild runtime review states by matching saved signatures to the current groups. Persisted review states must never be restored by numeric `groupID` alone.
- On manual override lookup, compare canonical member sets before accepting a saved override. Winner presence alone is invalid.
- Prune stale overrides only when the winner or member files no longer exist in the catalog; do not silently reattach them to a new group.
- Bump `BurstAnalysisCache.schemaVersion` if the serialized cache shape changes.

### Concrete Code Change Plan

The burst-identity part can be implemented as a contained model-layer change. The important distinction is:

- `groupID`: current-session lookup key for views, ranking results, and in-memory dictionaries.
- `BurstGroupSignature`: stable persisted key for decisions that should survive regrouping, cache reload, and app restart.

Suggested code plan:

1. Add a canonical signature helper.

   Add a small `Codable`, `Hashable`, `Sendable` value in `RawCull/Model/ViewModels/BurstAnalysisModels.swift` near the burst-analysis presentation/support models:

   ```swift
   struct BurstGroupSignature: Codable, Hashable, Sendable {
       var memberKeys: [String]
   }
   ```

   The initializer should sort canonical member keys so `A, B, C` and `C, A, B` produce the same signature. The preferred key is a catalog-relative path, because it can distinguish duplicate names in nested folders. If RawCull only supports flat catalogs today, a filename-based signature is acceptable for the first implementation, but the code should be easy to switch to relative paths later.

2. Add signature builders in `RawCullViewModel+BurstGrouping.swift`.

   Add helpers along these lines:

   ```swift
   private func burstSignature(for groupFiles: [FileItem]) -> BurstGroupSignature
   private func burstSignature(for group: BurstGroup, filesByID: [UUID: FileItem]) -> BurstGroupSignature?
   ```

   These helpers should be the only place that decides how a group becomes a stable identity. That keeps later duplicate-name or nested-folder changes local.

3. Keep runtime review state by `groupID`, but persist by signature.

   `RawCullViewModel.burstReviewStates` can stay as `[Int: BurstReviewState]` for current UI/ranking use. The cache should gain a signature-keyed representation, for example:

   ```swift
   var reviewStatesBySignature: [BurstGroupSignature: BurstReviewState]
   ```

   Then `saveBurstAnalysisCache(catalog:files:)` should derive `reviewStatesBySignature` from the current `similarityModel.burstGroups`, not simply encode `[Int: BurstReviewState]`.

4. Rebuild runtime review state after cache load/remap.

   `applyCachedBurstAnalysis(_:)` should not do this anymore:

   ```swift
   burstReviewStates = snapshot.reviewStates
   ```

   Instead, after cached groups are remapped to the current `FileItem.id` values, build each current group's signature and look it up in `snapshot.reviewStatesBySignature`. Only matching signatures should become entries in `burstReviewStates[group.id]`.

5. Make `remapCachedSnapshot(_:to:)` stop trusting review-state group ids.

   This method already remaps file IDs for groups, boundary evidence, candidates, and results. The hardening change is that it should either:

   - drop old `reviewStates` entirely and let `applyCachedBurstAnalysis(_:)` rebuild them by signature, or
   - return remapped runtime review states only after verifying each group's signature.

   The first option is cleaner because it keeps persistence identity and runtime identity separate.

6. Add the signature to manual winner overrides or derive it from `memberFileNames`.

   `BurstWinnerOverride` already stores:

   ```swift
   winnerFileName
   memberFileNames
   ```

   The minimum hardening change is to update `CullingModel.overrideWinner(for:in:)` so it compares the full canonical member set:

   ```swift
   let groupNames = Set(groupFiles.map(\.name))
   return burstWinnerOverrides(in: catalog).last {
       Set($0.memberFileNames) == groupNames &&
       groupNames.contains($0.winnerFileName)
   }
   ```

   A stronger version adds `groupSignature` to `BurstWinnerOverride` and populates it when saving new overrides. Existing saved overrides can still be matched from `memberFileNames` by applying the same canonical membership logic.

7. Update `setManualBurstWinner(_:in:)`.

   When saving a manual winner, continue saving the winner and member names, and also save the stable signature if the model gains a signature field. The saved override should represent "this winner for exactly this burst membership", not "this winner wherever it appears later."

8. Update `applyManualWinnerOverrides(files:)`.

   This method loops through current burst groups and applies overrides. After hardening, it should only mark `.manualWinnerOverride` when the override signature or canonical member set matches the current group. It should not set:

   ```swift
   burstReviewStates[group.id] = .manualWinnerOverride
   ```

   unless that exact membership check succeeds.

9. Update undo only if needed.

   `BurstUndoEntry` currently stores `groupID` and previous ratings. That is acceptable for an immediate in-session undo, because it is not persisted. If undo state ever becomes persisted or survives regrouping, it should also carry a `BurstGroupSignature`.

10. Bump or migrate the burst cache schema.

    `BurstAnalysisCache.schemaVersion` should increase if the JSON shape changes. Existing caches that only contain `[Int: BurstReviewState]` should either be ignored or decoded as legacy data without applying review state. Recomputing burst analysis is safer than restoring stale decisions.

11. Add focused Swift Testing coverage.

    Put pure persistence and override tests near `CullingModelTests`. Put cache/remap tests near view-model or burst-analysis tests, using isolated temporary catalogs and synthetic `FileItem` values. The tests should prove that changing group membership invalidates burst-level state while exact membership preserves it.

### What Can Go Wrong If This Is Not Implemented

The failure mode is usually not a crash. The risk is worse for a culling app: RawCull may look confident while using stale burst identity.

Concrete scenarios:

- The identity/similarity slider is changed.

  Before the slider change, RawCull may have:

  ```text
  Group 1: A.ARW, B.ARW, C.ARW
  Group 2: D.ARW, E.ARW
  ```

  After the slider change, RawCull may regroup the same files:

  ```text
  Group 1: A.ARW, B.ARW
  Group 2: C.ARW, D.ARW, E.ARW
  ```

  If review state is tied only to `Group 1`, RawCull can treat the new `A, B` group as if the old `A, B, C` decision still applies. With stable signatures, the old signature `A+B+C` does not match the new signature `A+B`, so the group is treated as needing fresh evaluation.

- A manual winner follows the file instead of the burst.

  A photographer manually chooses `A.ARW` as winner for:

  ```text
  A.ARW, B.ARW, C.ARW
  ```

  Later, after regrouping, `A.ARW` appears in:

  ```text
  A.ARW, X.ARW, Y.ARW
  ```

  Without exact membership matching, RawCull can say "A.ARW was manually chosen before" and apply that choice to the new group. That is wrong because the user never chose `A.ARW` against `X.ARW` and `Y.ARW`.

- A cached "decision applied" state can be restored to the wrong group.

  If cached group ids are reused after file IDs are remapped, RawCull can show a group as already handled even though the current member files are different. A future review queue might then skip that group entirely.

- One-click culling can act on stale confidence.

  The ranking engine may have marked one old group as safe for one-click culling. If the group membership changes but the old state is reused, RawCull may allow keep/reject actions based on evidence from a different set of frames.

- The future decision ledger can record the wrong history.

  Once a ledger is added, a stale group identity problem becomes harder to unwind. The app could record that RawCull recommended, accepted, or rejected a group, while the persisted identity points to files that were not actually part of the user's original decision.

- The future `Needs Review` queue can miss important work.

  If `.decisionApplied`, `.manualWinnerOverride`, `.reviewed`, or `.deferred` states are restored by numeric id, the review queue may hide a newly formed group because an unrelated old group had already been handled.

- User trust can be damaged without an obvious error message.

  The dangerous part is that the UI can still look normal. The wrong badge, wrong manual winner, or wrong "already applied" state may appear plausible unless the photographer notices the specific membership change.

Stable signatures make RawCull conservative: when a group changes, the old burst-level decision does not automatically follow it. File-level ratings can remain, but group-level decisions must match the actual member files.

### Test Coverage

Use Swift Testing tests with isolated temporary paths and no production settings/cache state.

Required burst tests:

- Cached review state is restored to the matching member set after file IDs are remapped.
- Cached review state is not restored when the same numeric group id now has different members.
- Regrouping with changed membership does not apply `.decisionApplied` to the wrong group.
- Manual winner override returns only when `memberFileNames` match the current group membership.
- Manual winner override is ignored when the winner appears in a different current group.
- Legacy overrides using only `memberFileNames` still match exact membership.

Required secondary tests:

- Decoding malformed or extreme settings produces normalized values inside supported ranges.
- Saving settings writes normalized values, not out-of-range values.
- `FileRecord` equality/hash behavior reflects the documented decision.

### Acceptance Criteria

- Burst review state cannot be transferred solely by numeric group id.
- Manual winner overrides require matching group membership.
- Cache reload and cache remapping preserve decisions only for the same burst members.
- Existing saved manual overrides remain readable.
- One-click culling behavior remains conservative and confidence-gated.
- Settings loaded from disk cannot put scoring, focus-mask, thumbnail, or cache fields outside supported ranges.
- Tests cover the identity, migration, settings, and `FileRecord` edge cases above.

### Out Of Scope For This Task

- Building the `Needs Review` queue UI.
- Adding the decision ledger.
- Changing burst ranking weights or confidence thresholds.
- Adding XMP sidecars or export manifests.
- Changing rsync copy setup, include-list generation, or argument construction.
- Adding new RAW format support.

Those features should follow after this hardening pass, because they will depend on stable group identity and trustworthy persisted decisions.

## July Review Queue MVP Details

Prerequisite: do not begin July review queue implementation until the June acceptance criteria pass and the stable burst signature type is available to the review queue model. The queue's burst-item identity depends directly on the June hardening work.

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

4. Add review states.

   Use `BurstReviewState` if it already covers the needed states. If it does not, extend carefully rather than adding a parallel state model. The MVP needs at least:

   - `needsReview`: unresolved and visible in the queue.
   - `reviewed`: user inspected and intentionally closed the item without applying an automated decision.
   - `deferred`: user chose to leave the item for later.
   - `decisionApplied`: user accepted or applied an action.
   - `manualWinnerOverride`: user manually selected a winner.

   State should persist by stable group signature. Runtime lookup can still map back to `group.id` for view performance.

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
    case deferred = 4
}
```

This can live in the app target at first. If the queue rules become pure and broadly testable, move the rule engine into `RawCullCore`.

### Main Code Surfaces

- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`: current burst groups, review states, one-click actions, manual winner overrides, and cache interactions.
- `RawCullCore/Sources/RawCullCore/BurstRankingEngine.swift`: confidence, score gaps, reasons, cautions, and recommendation evidence.
- `RawCullCore/Sources/RawCullCore/BurstGroupingEngine.swift`: group membership and stable group signatures after the June work.
- `RawCull/Views/ComparisonGridView/ComparisonGridView.swift`: candidate comparison UI that can be reused or opened from a review item.
- `RawCull/Views/ComparisonGridView/CandidateInspectorView.swift`: evidence display for reasons, cautions, focus data, and score components.
- `RawCull/Model/ViewModels/SimilarityScoringModel.swift`: current burst group source and similarity analysis state.
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`: scoring freshness and missing-score evidence.
- A new `ReviewQueueView` or `NeedsReviewView`: the dedicated review surface.
- A new `ReviewQueueBuilder` or `RawCullViewModel+ReviewQueue.swift`: deterministic queue construction.

### Concrete Code Change Plan

1. Define queue item models.

   Add lightweight models for queue item id, kind, priority, reasons, and recommended action. Keep the models `Sendable` where practical. Use stable signatures for burst identity.

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

   Existing immediate undo for burst actions should remain available. If an action changes ratings and review state, undo should restore both enough to avoid a stale queue item.

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

### June Hardening — Confirmed Bugs

**1. `overrideWinner` only checks winner presence, not full member set (confirmed)**

`CullingModel.overrideWinner(for:in:)` uses `.last { groupNames.contains($0.winnerFileName) }`.
This is confirmed in source. The fix described in step 6 of the June code plan is correct.

**2. Direct `burstReviewStates = snapshot.reviewStates` assignment (confirmed)**

`RawCullViewModel+BurstGrouping.swift` line 328 directly assigns `snapshot.reviewStates` without
signature verification. This matches the bug described in the June section exactly.

### June Hardening — Document Gaps

**3. Burst winner and signature model surface is not only `CullingModel`**

The "Main Code Surfaces" list originally omitted `RawCull/Model/ViewModels/BurstAnalysisModels.swift`.
Adding `BurstGroupSignature` or any signature-bearing burst support model requires changes near the
existing burst-analysis models, not only in `CullingModel`. The June code surfaces list now includes
that file.

**4. `FileRecord` equality/hash is a latent data-loss bug, not just an open decision**

`FileRecord.==` compares only `fileName`, `dateTagged`, `dateCopied`, and `rating`. The five
sharpness and saliency fields (`sharpnessScore`, `saliencySubject`, `sharpnessScoringSignature`,
`sharpnessFileSize`, `sharpnessModificationDate`) are excluded. Two records with the same name and
rating but different sharpness data are considered equal. If `FileRecord` is placed in a `Set` or
used as a `Dictionary` key, the second record is silently discarded.

The document says "decide the intended equality/hash behavior." The phrasing understates the risk.
The secondary hardening item should be prescriptive: either include all persisted fields in `==`, or
remove `Hashable` to prevent accidental Set/Dict misuse.

**5. `BurstGroupSignature` target file is now specified**

The June plan previously said the type should live "near the burst-analysis models" without
specifying a concrete file. This matters:

- Cache snapshots, manual winner overrides, and the July review queue will all need the same
  signature type.
- Keeping the type near the existing burst-analysis support models avoids duplicate app-local
  signature logic.

The June plan now specifies `RawCull/Model/ViewModels/BurstAnalysisModels.swift` as the target file
for `BurstGroupSignature`.

**6. Rsync hardening is deferred out of the June batch**

The secondary hardening item previously mentioned replacing fragile source/destination placeholder
trimming in `ArgumentsSynchronize.argumentsSynchronize(dryRun:)`. That work is now intentionally
deferred to a later copy/export hardening pass, along with rsync empty-list handling and include-list
rewriting. The June batch should not touch `ArgumentsSynchronize.swift` or `ExecuteCopyFiles.swift`.

### July Review Queue — Blocking Dependency

**7. `BurstReviewState` is missing three required cases — this is a `RawCullCore` change**

`BurstReviewState` (in `RawCullCore/Sources/RawCullCore/BurstAnalysisModels.swift`) currently has
only three cases: `.none`, `.manualWinnerOverride`, `.decisionApplied`. The July queue requires
`.needsReview`, `.reviewed`, and `.deferred`.

The July section says "Use `BurstReviewState` if it already covers the needed states." It does not.
Adding three cases to a `RawCullCore` enum is a package API change and must be done before the
review queue state model can be wired. This should appear as step 1 in the July concrete plan, and
`RawCullCore/Sources/RawCullCore/BurstAnalysisModels.swift` should be added to the July "Main Code
Surfaces" list.

### July Review Queue — Document Gaps

**8. No explicit gate requiring June completion before July begins**

The July section says "the July work should build on the June stable-signature work." However,
`ReviewQueueItemKind.burstGroup(BurstGroupSignature)` directly depends on `BurstGroupSignature`
existing, which is a June deliverable. Add a clear prerequisite note at the start of the July
section: do not begin July work until June acceptance criteria pass and the stable signature type is
available in `RawCullCore`.

**9. `ReviewQueuePriority.deferred` conflicts with the described queue filter model**

`ReviewQueuePriority` has `case deferred = 4`. However, the document states that deferred items are
excluded from the default unresolved queue and only visible through a separate deferred filter
(Example 4, toolbar count split). Having `deferred` as a raw-value priority case implies the queue
builder can produce it as a low-priority unresolved item, which conflicts with the "excluded unless
deferred filter active" behavior.

Consider either renaming the concept (e.g., a separate `ReviewQueueFilter` that includes `.deferred`
as a filter mode, not a sort priority), or adding a clear doc comment that `deferred` is only used
when the deferred filter is explicitly active and is never returned as part of the default unresolved
priority ordering.

**10. Undo step is underspecified**

Step 7 in the July concrete plan says "undo should restore both enough to avoid a stale queue item."
The word "enough" is vague. Since undo is always in-session (no catalog reload between the action
and undo), undo can safely restore the prior `BurstReviewState` from `BurstUndoEntry` without
needing signature matching. The step should specify this: undo restores the prior review state and
prior ratings in memory; it does not need to re-verify group membership because regrouping cannot
happen mid-session while undo is active.

### Rest of Document

**11. `sourcecode/` prefix in "Verified Current State" table**

The source paths in the table (e.g., `sourcecode/RawCull/Actors/ScanFiles.swift`) use a
`sourcecode/` prefix that matches the TechDocRawcull website mirror
(`TechDocRawcull/sourcecode/...`), not the Xcode project layout (`RawCull/Actors/ScanFiles.swift`).
A reader trying to open the cited files directly from the Xcode project will not find them at the
listed paths. Consider adding a footnote: "Source paths are relative to the TechDocRawcull content
mirror; in the Xcode project, omit the `sourcecode/` prefix."
