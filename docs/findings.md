+++
title = "Model Code Review Findings"
linkTitle = "Findings"
weight = 95
+++

# Model Code Review Findings

Review date: 3 June 2026. Package-boundary references updated after the `RawCullCore` and `RawParserKit` extraction.

Scope: `sourcecode/RawCull/Model/` and model-facing call sites needed to understand behavior. Concurrency and isolation correctness were intentionally not reviewed. The current focus masking and sharpness scoring pipeline looks stable overall; the findings below are mostly persistence, identity, and edge-case hardening opportunities.

## Summary

No blocker was found in the current model layer. The strongest follow-up candidates are:

- make burst review/cache identity more resilient after regrouping or cache remapping
- tighten saved-file record equality/hash behavior now that records carry scoring metadata
- make rsync copy argument/filter-file handling less brittle
- clamp or reject invalid persisted numeric settings and AF coordinates before they reach scoring/overlay math

## Findings

### Medium: cached burst review states are keyed only by transient group id

`RawCullViewModel+BurstGrouping.remapCachedSnapshot(_:to:)` remaps cached file IDs to the current scan's new `FileItem.id` values, but returns `reviewStates: snapshot.reviewStates` unchanged. Those review states are keyed by `Int` group id, while group ids are generated from the current grouping order. If regrouping changes because the threshold changes, files are added/removed, or a cache survives a subtle ordering change, a stale review state can be applied to the wrong group.

References:

- `sourcecode/RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `remapCachedSnapshot(_:to:)`
- `sourcecode/RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`, `markDecisionApplied(groupID:)`
- `sourcecode/RawCullCore/Sources/RawCullCore/BurstAnalysisModels.swift`, `BurstAnalysisResult.groupID`

Recommended action: key persisted burst review state by a stable group signature, such as sorted member file paths/names, or persist review state inside the remapped `BurstAnalysisResult` only after verifying the group's member set still matches.

### Medium: manual burst overrides match if the winner appears in the current group, not if the group membership matches

`CullingModel.overrideWinner(for:in:)` returns the last override whose `winnerFileName` is contained in the current group. It does not require the saved `memberFileNames` to match the current group. If regrouping later places that winner in a different group, the manual winner can be applied to the new group even though the override was created for a different burst.

References:

- `sourcecode/RawCull/Model/ViewModels/CullingModel.swift`, `overrideWinner(for:in:)`
- `sourcecode/RawCull/Model/ViewModels/CullingModel.swift`, `upsertBurstWinnerOverride(_:in:)`

Recommended action: require `Set(existing.memberFileNames) == Set(groupFiles.map(\.name))`, or at least require strong overlap plus the saved winner. This keeps manual choices attached to the burst they were made for.

### Medium: rsync argument construction depends on fragile placeholder trimming

`ArgumentsSynchronize.argumentsSynchronize(dryRun:)` removes the last two arguments only when both are empty strings, with an in-code comment noting it is a hack. `ExecuteCopyFiles.startcopyfiles(...)` then appends source and destination paths later. If the upstream `RsyncArguments` package changes placeholder behavior, or if one placeholder is non-empty, the final command can contain stale paths or fail silently.

References:

- `sourcecode/RawCull/Model/ParametersRsync/ArgumentsSynchronize.swift`, `argumentsSynchronize(dryRun:)`
- `sourcecode/RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift`, `startcopyfiles(fallbacksource:fallbackdest:)`

Recommended action: move path construction behind an explicit API or local helper that strips/replaces known source/destination positions deterministically. Also surface the failure to the UI instead of returning `nil` with no context.

### Low: `FileRecord` equality/hash omit sharpness and saliency fields

`FileRecord` stores sharpness score, saliency label, scoring signature, file size, and modification date, but its `Equatable`/`Hashable` conformance only considers file name, tag/copy dates, and rating. This is currently not a clear user-facing bug because records are mostly stored in arrays and located by file name. It is still a trap for future use in sets, diffable data, or tests that compare records after scoring changes.

References:

- `sourcecode/RawCull/Model/JSON/SavedFiles.swift`, `FileRecord`
- `sourcecode/RawCull/Model/ViewModels/CullingModel.swift`, `mergeScoringResults(_:in:)`

Recommended action: either remove `Hashable` if it is not needed, or include all persisted fields in equality/hash. If UI row identity needs to ignore scoring changes, model that separately instead of encoding it into the persistence type's equality.

### Low: focus-point parsing accepts invalid sensor dimensions and out-of-range coordinates

`FocusPoint.init(focusLocation:)` accepts four numeric values, but `normalizedX` and `normalizedY` divide by `sensorWidth` and `sensorHeight` without validating that dimensions are positive. The comment says valid data should be in `[0, 1]`, but malformed MakerNote/exiftool strings could produce `inf`, `nan`, or off-image markers.

References:

- `sourcecode/RawCullCore/Sources/RawCullCore/FocusPointParser.swift`, shared parser that already rejects non-positive dimensions
- `sourcecode/RawCull/Model/ViewModels/FocusandSharpness/FocusPointsModel.swift`, direct app-side parser still used by marker overlays

Recommended action: route `FocusPointsModel` through `FocusPointParser.normalizedPoint(from:)`, then clamp or reject coordinates outside the sensor bounds. This keeps scan-time and overlay-time parsing consistent.

### Low: saved settings decode restores numeric values without range validation

`SavedSettings.init(from:)` decodes cache sizes, thumbnail sizes, focus mask parameters, and scoring weights directly from JSON. The save path logs warnings for some cache sizes, but it does not clamp values. A corrupted or manually edited settings file could persist negative cache sizes, extreme blur/threshold values, or nonsensical scoring weights until the user resets settings.

References:

- `sourcecode/RawCull/Model/ViewModels/SettingsViewModel.swift`, `SavedSettings.init(from:)`
- `sourcecode/RawCull/Model/ViewModels/SettingsViewModel.swift`, `validateSettings()`
- `sourcecode/RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`, `effectiveThumbnailMaxPixelSize`

Recommended action: add a single normalization pass used by both decode and save. Clamp values to UI-supported ranges before assigning them to `SettingsViewModel`.

## Enhancement Ideas

### Persist copy status or remove the unused `dateCopied` field

`FileRecord.dateCopied` is decoded, encoded, and displayed, but the model code never updates it after a copy run. If copy status matters to users, `ExecuteCopyFiles` should update matching records after successful rsync completion. If not, removing it from the active UI/model surface would reduce confusion.

### Write rsync include files with explicit relative patterns

The copy model writes bare filenames into `copyfilelist.txt`. That works for flat catalogs, but it is ambiguous if RawCull later supports nested folders or duplicate names. Writing explicit relative paths, escaping/filtering rsync pattern metacharacters, and handling empty file lists before launching rsync would make the copy path more future-proof.

### Version sharpness signatures whenever scoring constants change

The sharpness signature already includes algorithm and policy versions, source, quality, pixel size, and major config fields. Keep bumping `currentAlgorithmVersion` whenever fixed constants in `FocusMaskEngine+Scoring.swift` change but are not represented directly in `SharpnessScoringSignature`, so persisted scores are invalidated predictably.
