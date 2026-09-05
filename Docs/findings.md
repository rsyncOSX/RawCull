# RawCull 3.2.0 release review

Reviewed 2026-09-05 at commit `71346dd7555fd4912bec888678018304bf37af34` (version 3.2.0, build 351), using macOS 27.0 build `26A5425a` and Xcode 27.0 build `27A5252f`.

**Recommendation: hold the release pending the P1 findings below.** This is a source and release-configuration review, not certification of the packaged application. No production code, tags, model assets, or release artifacts were changed.

## Remediation update — 2026-09-05

Source fixes for findings 1 and 2 are implemented in the current worktree, together with the quit-save recovery and copy-bookmark issues from the Copilot review. See the [coordinated fix plan and validation record](fix-plan-2026-09-05.md). The original findings below remain as the review-time record; release-tag reconciliation, release-entry-point gating, and packaged-app validation are still separate work.

## Findings

### 1. [P1 — blocker] JPEG export silently overwrites existing photographs

**Locations:** `RawCull/Actors/SaveJPGImage.swift:22–52`; `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:43–47`; `RawCull/Views/RawCullSidebarMainView/ExtractJPGsSheetView.swift:74–82`.

Export constructs `<RAW basename>.jpg` and writes with `.atomic`, which replaces an existing file. There is no collision check, alternate filename, or overwrite confirmation in the export flow. The initial destination is the selected source folder, making a RAW+JPEG capture pair a direct trigger: exporting `DSC0001.ARW` replaces the camera's existing `DSC0001.JPG` on a normal case-insensitive volume. Demosaiced export can likewise replace an existing `_demosaic.jpg`. The write is counted as successful.

**Fix before release:** preserve existing files by default, using collision-safe unique names or an explicit overwrite decision. Enforce the policy at write time so concurrent outputs cannot race through an existence check.

**Verification:** export into a temporary folder containing a same-stem JPEG with known bytes; verify those bytes remain unchanged without explicit overwrite authorization. Cover both export modes and two inputs mapping to the same destination basename.

### 2. [P1 — blocker] SAM 3 is enabled despite an unresolved checked-in release block

**Locations:** `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift:30–32, 248–283`; `ModelAssets/Notices/SAM3/PROVENANCE.json:3–4`; `Makefile:22, 76–79`; `RawCullTests/ReleaseMetadataTests.swift:150–168`.

Production includes SAM 3 and its download, and its descriptor declares `.ready`. Its provenance record still declares `release_status: blocked`, with unresolved public-distribution approval and final archive evidence. The release test explicitly expects SAM 3 to remain blocked, while the preflight checks only DataComp. Consequently, both checks can accept this contradictory state once the unrelated tag mismatch is resolved. The catalog now supplies archive size/hash values, but the provenance record has not been reconciled with them.

**Fix before release:** reconcile the approval/evidence record with the actual distributed SAM 3 asset, or disable SAM 3 distribution until that is complete. Validate every production-enabled model against its provenance record, rather than maintaining a DataComp-only path and hard-coded expected blocked statuses. Missing or malformed provenance should fail validation.

This finding is about contradictory release evidence in the repository; it does not establish that the model licence prohibits distribution.

**Verification:** a production-enabled model with blocked, absent, or invalid provenance must fail release validation. Every enabled `.ready` descriptor must agree with its recorded asset evidence.

### 3. [P1 — release gate] The existing 3.2.0 tag identifies a different candidate

**Location:** `Makefile:71–75` and local Git release metadata.

With the initially clean worktree, `make release-preflight` failed with:

```text
Release blocked: existing 3.2.0 tag does not point to this release candidate
```

`v3.2.0^{commit}` resolves to `7123363c557961c72820ef22539ce79facafd81c`; reviewed HEAD is `71346dd7555fd4912bec888678018304bf37af34`. This is an observed release-state blocker, not an application runtime bug. An artifact built from HEAD would not match the source identified by the current tag.

**Before release:** resolve which commit/version is the intended release. If that tag has already been published as a release, use an appropriate new release identity; if it is only a provisional local tag, reconcile it under the project's release policy. Do not silently move a published tag. Commit the final candidate and rerun preflight. This review did not change tags or query remote publication state.

### 4. [P2] The default release build bypasses release preflight

**Locations:** `Makefile:25, 68–81`.

Neither `build` nor `archive` depends on `release-preflight`. `make -n build` goes directly through cleanup, archive, export, signing, and notarization without the checks. Thus the documented default release command can package a candidate even while an explicit preflight fails. It also omits the AI boundary check. This is separate from the current tag mismatch: future candidates can bypass the same protections.

**Fix:** make the release entry point enforce preflight and the AI boundary check before cleanup/archive. Express ordering through dependencies so parallel make cannot start packaging before verification finishes.

**Verification:** deliberately fail preflight in an isolated checkout and verify the release entry point exits before deleting artifacts or invoking archive/export/notarization.

### 5. [P2] Refresh replaces active download state and hides cancellation

**Locations:** `RawCull/Intelligence/ModelManagement/RawCullAIModelManagementModel.swift:90–100, 119–135, 184–189`; `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift:185–206`; `RawCull/Views/Settings/AIModelDownloadsView.swift:54–56, 150–174`.

`refresh()` replaces the entire state dictionary with a coordinator snapshot, even when `downloadTasks[id]` owns an active transfer. For a pack not yet installed, the live service reports `.ready` once it finds the manifest entry; it does not report the ongoing transfer. Start a download, close the sheet, and reopen it while the transfer is pending: the sheet's refresh can change Downloading to Ready. Cancel disappears, and Download does nothing because `downloadTasks[id]` is still non-nil. A later progress update can restore the display, but a stalled transfer leaves no cancellation control. Another model completing or accepting its licence also triggers this refresh path.

**Fix:** merge snapshots with per-model operation state, preserving locally owned download/removal state until its operation completes. Ensure stale refreshes cannot replace a newer operation's state.

**Verification:** inject a service that suspends download and reports `.ready` from its state query. Start downloading, refresh, and assert the row still offers cancellation; repeat while the other model finishes downloading.

### 6. [P1 — release gate] Automated tests fail against the selected release configuration

**Locations:** `RawCullTests/ReleaseMetadataTests.swift:23`; `RawCullTests/RawCullAIIntegrationTests.swift:407–442`; `RawCullTests/RawCullIntelligenceRuntimeTests.swift:74–84`.

The executed Smoke test plan finished with **375 passed, 3 failed, 378 total tests** in the Xcode result summary (parameterized executions are counted separately in its device totals). These are assertion failures, not a package-resolution failure:

- Release metadata expects build `350`; all app/extension configurations now contain `351`.
- The segmentation-default test expects `[.efficientSAM]` and an EfficientSAM preference; production now enables SAM 3.
- The runtime-settings test selects `.openAI` and expects the semantic capability to change. OpenAI CLIP is excluded from production, and `RawCullAISettingsModel.setSelectedCLIPModel` correctly rejects an excluded selection, so the capability remains unchanged.

**Fix before release:** update the assertions/fixtures to test the intended 3.2.0 configuration after resolving SAM 3 readiness. Keep app/extension alignment coverage without pinning an obsolete build number. Test supported configuration changes and explicitly test rejection of excluded models. These failures do not by themselves demonstrate broken inference, but the candidate currently has no passing test gate.

**Verification:** rerun the Smoke plan and full test plan after correcting these cases; retain a passing result for the final candidate.

## Validation and remaining release evidence

- AI import-boundary verifier: passed.
- Release preflight: failed on the tag mismatch before this report was created; the worktree was clean at that point.
- Release command dry run: confirmed preflight is absent from the default build path.
- App and downloader target metadata: both use version 3.2.0/build 351 and the same model-assets App Group.
- Reviewed source paths include model download/licence state, AI resource loading, semantic-search actions, Deep Review task lifecycle, artifact persistence, culling persistence, JPEG extraction, copy startup, and release packaging. This was not a line-by-line audit of every dependency or view.
- Automated validation: the app compiled and the Smoke plan ran, with 375 passed / 3 failed. Command: `xcodebuild test -project RawCull.xcodeproj -scheme RawCull -destination 'platform=macOS' -testPlan Smoke -onlyUsePackageVersionsFromResolvedFile -derivedDataPath /tmp/rawcull-release-review -quiet`. This ran the plan directly, without the narrower Makefile manifest filter. The initial sandboxed attempt could not resolve GitHub dependencies; the retry with required access completed with exit 65 due to the assertions above. Local evidence: `/tmp/rawcull-release-review.log` and `/tmp/rawcull-release-review/Logs/Test/Test-RawCull-2026.09.05_18-39-03-+0200.xcresult`.
- No signed archive was produced or installed, and no live model download or real-image inference was exercised. Before shipping, test the Developer ID-signed packaged app on the supported macOS 27 build: fresh installation, DataComp/SAM 3 download, cancellation, removal/reinstall, offline reuse, semantic search, and Deep Review. Run the full test plan with Thread Sanitizer and retain the results. Source inspection and a Debug test host cannot establish that Background Assets validates the distributed app/extension.

The P1 source findings are supported by the implementation and checked-in metadata; the proposed regression scenarios have not been executed in the GUI during this review.
