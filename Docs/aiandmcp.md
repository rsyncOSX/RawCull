# Follow-up AI analysis over RawCull MCP

> **Note (version 3.5.0):** Deep AI Review, Qwen Vision and Object Analysis were removed from the app in favour of Review (see [ai-features-decision.md](ai-features-decision.md)). Steps below that route MCP to those features are superseded.

## Proposed workflow

The first prompt asks RawCull to load an authorized catalog and run burst analysis. RawCull uses sharpness and the configured similarity backend, Vision or CLIP, to group and rank frames. The client polls until the job reports `completed` and retains the catalog and job IDs.

The second prompt asks for a closer look at a burst or named photos. For example, “Compare the recommended frame and alternate in the lowest-confidence burst for composition, exposure, and subject visibility, including occlusion.” RawCull would resolve the frames, run local visual assessment, and return findings the client can use to explain its choice. This concentrates model time on close calls and preserves the original ranking for reference.

## What works today

- Use `request_catalog_setup` with `jobType: "burstAnalysis"`, or `start_catalog_analysis` for an already authorized catalog. Poll `get_catalog_setup_status` when setup is needed, then `get_analysis_status` for progress and final coverage. The burst request uses the app’s configured backend. The MCP tool schemas do not accept a Vision or CLIP override.
- Use `list_bursts` with the completed job’s catalog and job IDs. Follow `nextCursor` to cover the entire list. A page can contain up to 25 bursts. Each entry includes a recommendation, alternate, confidence, reasons, cautions, and evidence for up to five frames. The result can be read after RawCull quits while it remains shared.
- A client can explain close rankings and select frames for review using that evidence. The exposed tools return metadata and ranking evidence. New pixel-based analysis through MCP requires a new tool and app-side job support.
- In the app, AI Analysis can run Qwen assessment or Object Analysis on grid selections or tagged photos. Deep AI Review can review a burst using a preset and existing capture evidence. These app entry points are available independently of MCP.

> Using only the RawCull MCP server, read the completed burst job from this chat. Follow all burst pages and find three low-confidence bursts where the top two are close. Give the recommendation, alternate, and recorded reasons and cautions. Identify what I should check visually.

See [MCP tools and TestFlight checks](mcpserver.md), [AI Analysis input selection](../RawCull/Model/ViewModels/RawCullViewModel%2BAIAnalysis.swift), and [Deep AI Review controller](../RawCull/Intelligence/DeepReview/DeepAIReviewController.swift).

## Where the code is ready

| Area | Existing code | Follow-up work |
| --- | --- | --- |
| Tool transport | The signed stdio helper validates tool calls and uses shared storage to exchange requests and results with RawCull. | Define a typed follow-up request, status, and result. Advertise the capability when the installed app and helper support it. |
| Execution | The app-side controller handles workspace availability, catalog loading, authorization, progress, cancellation, and publication for burst jobs. | Reuse that lifecycle for a second job and keep the source burst result readable during the follow-up. The current store exposes one current job. Its shareable result is tied to burst coverage and rankings. |
| Photo identity | The burst controller maps catalog snapshot entries to internal file IDs. Recurring scans can issue new photo IDs. Burst IDs include the source job ID. | Resolve inputs against the exact source snapshot and verify files on reopen. Preserve full burst membership for server-side lookup. Public candidate summaries can omit frames. |
| Qwen assessment | The feature accepts a file batch and prompt criteria, loads previews, and returns structured assessments, freeform responses, or per-photo errors. Its current UI state owns the prompt, progress, and results, filters out previously analyzed IDs, and can return early when busy or unavailable. | Use a request-scoped runner with typed outcomes and shared access to the model runtime. |
| Other review modes | Object Analysis already accepts a file batch and criteria. Deep AI Review builds a preset-driven request with burst rank, sharpness, subject label, and AF point when available. | Add these modes once the Qwen flow passes release testing. Per-frame assessments can support a client comparison. A model that compares multiple frames directly would need a separate inference path and validation. |

Source entry points are [AnalysisTools](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift), [AnalysisJobStore](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift), [MCPAnalysisController](../RawCull/Main/MCPAnalysisController.swift), [Qwen Analysis](../RawCull/Intelligence/Qwen/RawCullQwenAnalysisFeature.swift), and [Object Analysis](../RawCull/Intelligence/ObjectAnalysis/RawCullObjectAnalysisFeature.swift).

## Proposed first-release contract

### Assessment and results

- Accept a nonempty subset of `composition`, `exposure`, and `subjectVisibility`. Subject visibility includes occlusion. Generate instructions from a versioned server-side template keyed by those enum values. The client translates its user’s request into rubric choices.
- Decode and validate the full Qwen assessment, then project only the requested score and evidence pairs. Preserve null pairs when evidence is insufficient. Omit general problems, strengths, aggregate score, and self-reported confidence. Expression and eye state are outside this rubric. The current app path can return prose and requires `eyesOpen` to be null for a structured assessment. Return a typed per-photo failure if the follow-up runner cannot obtain a valid structured assessment after one retry.
- Return source and photo IDs, assessed and failed counts, model identifier and revision where available, prompt-template and result-schema versions, and an `assessedImage` descriptor with preview type and actual dimensions. The runner uses a preview with a maximum dimension of 2048 pixels. Scores are model judgments based on that preview. Compare per-frame results in the client.
- Pin the runtime’s model identity and generation before inference. If the model is changed or removed during the request, cancel and drain the run, discard staged assessments, and return `modelChanged` or `modelUnavailable`. Recheck at publication. An identical replay reuses the existing outcome. A new request runs independently.

### Source, permission, and workspace

- Persist a versioned app-side snapshot for the source job and saved grant. Map photo IDs to catalog-relative paths, sizes, and modification times. Map burst IDs to full ordered membership and original ranks, with the recommendation and alternate where available. Current catalog discovery is nonrecursive. Preserve the on-disk path for lookup and cover canonically equivalent Unicode names in tests. If name normalization is needed for a comparison, use canonical Unicode normalization and reject ambiguous matches. Later grouping settings and live group IDs do not determine identity or rank.
- Include follow-up assessments in burst analysis approval. **Approve This Job** keeps a read-only bookmark in RawCull for the current shared result. Clearing, revoking, or replacing that result ends its photo access. **Approve and Remember** uses the saved catalog grant for that job and later jobs. Existing analysis grants cover assessments after a burst job publishes an eligible source snapshot.
- The app worker resolves the saved bookmark, acquires scoped access before resolving targets, and retains it through preview loading and inference. Report a stale or denied bookmark as a typed error with reauthorization guidance. Reject absolute paths and parent traversal, resolve symlinks, and verify containment by path components under the resolved catalog root before opening a preview. Check size and modification time for changes. Retain access using the app’s catalog access layer independently of the visible selection.
- Run from the snapshot without switching catalogs, changing selected photos, or resetting burst UI. A different idle catalog on screen is valid. Return busy when the workspace or model lease conflicts with active UI work or a catalog transition.

### Storage, execution, and compatibility

- Keep the existing burst format readable. Store mutable follow-up status separately from the immutable source snapshot and result. Each follow-up record includes its format and job kind, request ID and normalized arguments, source and grant IDs, snapshot version, state, progress, liveness diagnostics, and terminal outcome. On every read and before publication, verify follow-up consent, grant identity, current shared source job ID, and snapshot version. Older builds can clear or revoke the source without deleting follow-up files. Fail closed when those records disagree and remove orphan files on maintenance. Clear, revoke, and source or grant replacement in the updated build must remove the dependent path-bearing snapshots and results as appropriate.
- Use the same cross-process `analysis-worker.lock` for burst and follow-up execution. Coordinate both stores under the shared admission and publication lock. Retain a 120-second queued pickup deadline. For a running worker, the kernel lock is the liveness authority. A 45-second stale heartbeat is diagnostic while the lock remains held. Recover an interrupted request once the lock is available and the previous owner did not publish a terminal state. Graceful cancellation and quit drain work before releasing ownership. Hold an app activity during background analysis and update progress and heartbeat independently of client polling.
- Extend the app-side reservation currently used by Combined Review so MCP and the relevant UI workflows acquire it at admission. Replace the hand-listed running checks for work covered by the lease once those entry points acquire it. Retain checks for catalog transitions and other independent work. Connect the existing model and catalog invalidation hooks to the shared reservation and register cancellation with the owner. Hold the reservation until inference drains.
- The running app publishes its supported protocol range and a process identity with a freshness stamp in shared storage. Validate the running process and require a compatible handshake before creating a job. For cold launch, request app launch and wait for a bounded handshake. For version skew, including an old process still running after an in-place upgrade, fail with relaunch guidance. Keep tool discovery stable, report availability in status, and validate protocol for operations that require a running worker. Allow read-only calls after quit when the persisted record version is supported and authorization still holds. Include an app-controlled disable switch that suppresses follow-up admission and result access and cancels active work. Preserve baseline MCP tools.

### Proposed limits and sharing controls

Start with up to **four** distinct photo IDs per request, or **one** burst ID resolving to at most two photos. Allow one initial inference and at most one structured validation retry per photo. Benchmark cold load and warm inference on supported release hardware, including retries. Use those measurements to confirm or lower the cap and set the execution timeout before the Step 3 gate. A timeout requests cancellation and keeps the lease until work drains. Suggest polling every two seconds. A quiet client does not cause a running job to expire.

Use a proposed 16 KiB serialized result limit per request and 240 Unicode scalars per public evidence string. Keep at most 128 terminal follow-up records with a maximum age of 24 hours, subject to earlier invalidation. Keep compact replay receipts for up to seven days, with a cap of 128. During the first 24 hours, an identical replay returns the original request identity and available outcome. During receipt-only retention, return an expired result status and require a fresh UUID for new work. Preserve at most one eligible source snapshot, with a proposed cap of 16 MiB. If the snapshot exceeds the cap, keep the burst result usable and report follow-up as unavailable.

| Surface | Data and control |
| --- | --- |
| RawCull | The worker uses scoped file URLs and previews locally. Show an active follow-up indicator with Cancel. In MCP settings, show shared result summaries with photo count, rubric, time, and Clear. Clearing the source removes its dependent assessments. Clearing an individual assessment removes that result and retains only the replay receipt. |
| MCP client and its model provider | The client receives IDs, provenance, bounded structured findings, and typed errors. It may pass these to its model provider. Mark model-derived text as untrusted data in tool descriptions and results. Normalize control characters and apply field-specific limits before serialization. |
| Logs and diagnostic captures | Record lifecycle and error codes. Exclude photo paths, image bytes, prompt contents, and model findings. Disable the existing Qwen diagnostic capture for MCP requests, including when `RAWCULL_AI_CAPTURE_DIR` is set. |

Publish input and output schemas. Keep status and result tools observational and mark them read-only. Run maintenance in the worker or admission path. Mark start and cancel as mutating, and local-only execution with `openWorldHint: false`. Tool annotations describe behavior. Authorization and protocol checks enforce it.

See [worker recovery](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift), [catalog grants](../Tools/RawCullMCP/Sources/RawCullMCP/CatalogGrantStore.swift), [catalog access](../RawCull/Model/RawImageLoading.swift), [app reservation](../RawCull/Intelligence/CombinedReview/Storage/CombinedReviewLease.swift), [model runtime](../RawCull/Intelligence/Composition/RawCullAIModelRuntime.swift), [Qwen inference](../RawCull/Intelligence/Qwen/QwenInferenceRuntime.swift), and [assessment validation](../RawCull/Intelligence/Qwen/QwenPhotoAssessment.swift).

## Implementation and release plan

Each step requires a passing release test **before work starts on the next step**. Use an installed, signed release candidate with its bundled helper, using TestFlight where applicable. Intermediate capabilities can be exercised on release candidates before broader distribution. Record the app build, helper version, model and backend, fixture, prompts or calls, relevant responses, and pass or fail verdict. Fix failures and rerun the affected gate. A deferred or unverified check leaves the gate open. From Step 2 onward, run the relevant automated regression cases before the signed-candidate check. Run the helper suite with `swift test --package-path Tools/RawCullMCP` and add a repeatable build target for it. Build both app and helper because they compile the shared stores. Use a Release-configured integration test target and verify its imports before relying on the gate. Keep any testability setting scoped to testing. Record each gate’s verdict in the release log in [mcpserver.md](mcpserver.md).

Use a repeatable fixture with a burst containing more than five frames, a close recommendation and alternate, and individual photos with visible differences. Keep a second catalog and a modified recurring-folder copy for authorization and stale-ID tests. Verify target filenames and photo identities against the app and use visibly distinct fixtures for assessment checks. Measure repeated-run variation on clearly different fixtures. Gate on valid evidence and gross differences using tolerances agreed from those runs. Close scores can tie or change order. Check the pinned inference API for sampling controls during implementation and record the generation settings used for release testing.

### Step 1 — Establish the burst baseline

1. Confirm the bundled helper’s tool list and version from a fresh client session.
2. Run the existing setup and analysis workflow with Vision and CLIP, selecting the backend in RawCull before each run. Record the catalog and job IDs, coverage, backend counts, and expected recommendation and alternate identities for each run.
3. Save a repeatable follow-up prompt that interprets rankings using the completed job IDs.

**Release gate.** For each backend, run the workflow from a full quit, poll to completion, paginate `list_bursts`, and verify the returned backend identifier (`vision-feature-print` or `clip`) and photo identities against the app. Check pagination with a small page size and verify the 25-item page limit. Quit and retrieve the shared result again. After clearing the result, verify that its rankings are unavailable. Run the follow-up prompt against an available result and verify that its output matches the recorded evidence. Use the [existing TestFlight checks](mcpserver.md#testflight-tests) for setup, cancellation, and revocation coverage.

### Step 2 — Preserve the source job and resolve targets

1. Save the app-side source snapshot and full membership when publishing burst results. Resolve explicit IDs and bursts through this snapshot. Reject wrong-job IDs or changed files before preview loading.
2. Implement the follow-up grant, separate request and result storage, and coordinated reservation and invalidation. Cover cleanup, replay, dead-worker recovery, and older records. Inject process death during publication and verify recovery. Exercise clear, cancellation, or revocation racing publication and permission preservation through a recurring grant rewrite.
3. Add a test-target integration harness around the production resolver, grants, and stores. Seed a completed source with fixture photos, then invoke the same resolution and admission paths the app worker will use. Use the harness to exercise this step before exposing public follow-up tools.

**Release gate.** Run the harness in Release configuration. Verify exact resolution after reopen, including same-name files across two catalogs, Unicode path handling, symlink containment, and a member beyond the first five. Regroup the same catalog and verify the original membership and rank. Exercise replaced files, a newer recurring scan, wrong catalog or job IDs, clear, and revoke. Confirm invalid requests fail before preview loading. Test burst and follow-up reservation concurrently. Verify a live worker with a stale heartbeat retains ownership and that process death releases the kernel lock. Verify old-format clear or revoke makes retained follow-up files inaccessible. Verify that a recurring grant refresh preserves consent and that the source stays readable during the follow-up. On the signed candidate, confirm existing grants and legacy rankings still load and run the baseline workflow.

### Step 3 — Expose local Qwen assessment for explicit photos

1. Add start, status, result, and cancel tools. Put the running-app handshake in admission. Status and result reads validate the persisted records and current consent, including after the app quits. The start request carries a client-generated UUID, catalog ID, source job ID, distinct photo IDs, and rubric fields. Use bounded batches and a single bounded result per request. Confirm the proposed limits with latency measurements and document the final values and stable errors before passing the gate. Error cases include incompatible app, missing permission, stale source, invalid target, conflicting replay, busy, and unavailable model.
2. Extract a request-scoped runner using the existing preview loader and Qwen inference service. Reuse structured validation and retry, and read model availability from the runtime. Return outcomes such as unreadable photo and invalid assessment per file. Publish successful assessments alongside per-photo failures and report a failed job when every file fails.
3. Acquire the shared lease at the MCP and UI entry points. Publish only while the worker still owns its reservation, the source grant is valid, and the model identity is unchanged. Add the app indicator, Cancel, and result summaries with Clear. Enforce sharing and diagnostic boundaries before returning results.

Both burst approval choices cover assessments from the completed job. The saved grant from **Approve and Remember** also covers later burst jobs. **Approve This Job** keeps read-only access for its result until the result is cleared, revoked, or replaced. The worker refreshes model availability if needed when it picks up an assessment.

An example start payload is:

```json
{
  "requestId": "<new UUID>",
  "catalogId": "<catalog ID>",
  "sourceJobId": "<completed burst job ID>",
  "photoIds": ["<recommended photo ID>", "<alternate photo ID>"],
  "rubric": ["composition", "subjectVisibility"]
}
```

The development candidate exposes the following tools through its bundled helper.

| Tool | Arguments and result |
| --- | --- |
| `start_photo_assessment` | The payload above. Returns request identity and state. A repeat of the same normalized request returns its existing state. A different payload using the same ID returns `conflictingReplay`. |
| `get_photo_assessment_status` | Takes `requestId`. Returns state, cancellation and Clear flags, and a failure code when applicable. |
| `get_photo_assessment_result` | Takes `requestId`. Returns bounded preview findings, per-photo failures, and provenance. An all-photos failure can include per-photo errors. |
| `cancel_photo_assessment` | Takes `requestId`. Cancels queued work or asks the running worker to stop. |

The candidate accepts four photos, one retry per photo, and up to 16 KiB of serialized results. The provisional execution timeout is 180 seconds. The helper waits up to six seconds for the bundled app to publish its protocol compatibility and suggests polling every two seconds. Common admission errors are `incompatibleApp`, `permissionRequired`, `staleSource`, `invalidRequest`, `invalidTarget`, `conflictingReplay`, and `busy`. The app can report `modelUnavailable`, `modelChanged`, `reauthorizationRequired`, `executionTimeout`, or `allPhotosFailed` after queueing. Returned evidence is model-generated text.

**Release gate.** Automate input validation, structured response handling, replay and conflicting replay, lease exclusion in both directions, dead-worker recovery, model change during a batch, cancellation, and partial failure. With the signed candidate, assess two explicit IDs through MCP and confirm the results map to the expected frames and requested fields. Assess the same IDs with a different rubric and a new request ID, then replay the identical request and verify that it does not trigger duplicate inference. Exercise a missing model and an unreadable photo. Verify result provenance, projection, size bounds, and continued access to source rankings. Check app controls and diagnostic capture with private fixture markers. Run without client polling and verify the app activity and lease stay effective. Confirm the visible workspace selection is preserved.

**Gate status — open.** All 37 helper and Release lifecycle tests passed on the current checkout. Installed TestFlight build 454 completed the timed four-photo batches, one-time approval after a verified quit and relaunch, a timed no-polling request, exact and conflicting replay, and mixed and all-unreadable photo checks. The live missing-model check and retry-heavy timing remain open. See the [build 454 verification](mcpserver.md#build-454-verification) for the audit of the original logs and the remaining release checks.

### Step 4 — Target a burst directly

1. Add `burstId` as an alternative to `photoIds` on the same request. Require exactly one selector. Select the saved recommendation and alternate, deduplicated. If one exists, assess it and report coverage. If neither exists, return a typed target error. Defer all-frame assessment until the caller can see the resolved count and the batch limit behavior is defined.
2. Return the assessed photo IDs, their source ranks, per-frame findings, and coverage. Let the client synthesize the comparison from those findings and identify which frames were assessed.
3. Support a shortlist of bursts by letting the client page the rankings and submit one request per selected burst through the follow-up start tool. Sort known burst decision confidence from `low` to `medium` to `high`. Treat unknown values as unclassified and retain source order for ties. Verify the one-worker constraint when requests arrive together.

The candidate accepts exactly one of `photoIds` and `burstId`. Use the burst ID from `list_bursts` with the same catalog and source job IDs. Burst results add `burstId`, `burstFrameCount`, and each selected frame's one-based `sourceRank`, including failed frames. The existing assessed and failed counts describe the selected frames. A burst with neither saved pick, or an ID from a different job, returns `invalidTarget`. Supplying both selectors or omitting both returns `invalidRequest`. A running app must advertise burst assessment support before the helper can queue a new burst request.

**Release gate.** Run the two-prompt flow in one chat without manually copying IDs. Ask for the lowest-confidence burst, then compare its recommended frame and alternate. Verify the client uses the completed job and that both assessed IDs match the ranking. Exercise a missing recommendation, a missing alternate, both missing, a request with both selectors, and a burst over five frames. Verify a wrong-job burst ID fails and concurrent submissions produce the documented busy or replay response.

Use the [same-chat comparison prompt](prompts.md#compare-the-recommendation-and-alternate) and record the outcome in the [Step 4 release gate](mcpserver.md#step-4-release-gate).

### Step 5 — Validate the release workflow

1. Document the user prompts, model prerequisites, authorization behavior, and result lifetime. Document what the client can see and how to revisit or remove a result.
2. Validate an upgrade from an installation with existing catalog grants and burst results. Check both version-skew directions. Unsupported pairs must fail before creating a follow-up job while preserving baseline tool behavior. Test an in-place upgrade with the previous app process still running. Test cold launch and the follow-up disable switch.
3. Check that cancelling, quitting during inference, clearing, or revoking leaves recoverable job state. Results must follow the published access and retention rules.

**Release gate.** Install the signed candidate over the previous supported release and use its bundled helper in a fresh chat. Run the baseline with both similarity backends and complete the second prompt for both a burst and specific photos. Quit and reopen at the documented points. During an active follow-up, exercise cancellation and revocation separately and verify no result is subsequently published under that request. Verify clear behavior, dead-worker recovery, the one-time approval message, missing models, and continued access to existing tools. Record the release verdict before enabling further review modes.

See [photo assessment controls and lifetime](mcpserver.md#follow-up-photo-assessments) and the [Step 5 TestFlight checklist](mcpserver.md#step-5-release-gate).

### Step 6 — Add Deep AI Review and Object Analysis as separate increments

1. Route a burst and explicit preset to the existing Deep AI Review pipeline. Build candidates from the persisted membership and ranks. Verify the resolved files match the source snapshot before adding available sharpness, subject label, and AF-point evidence. Return job-scoped results and coverage. Key any reused results to source identity, model, and preset.
2. In a later increment, route bounded photo selections and criteria to Object Analysis. Report model availability, per-photo failures, and the supported evidence fields. Use request-scoped results and include criteria and model identity in any reuse decision.

**Release gate for Deep AI Review.** With the installed candidate, compare an MCP preset run against the app’s review of the same burst and preset. Check candidate identities, evidence fields, progress, cancellation, and unavailable segmentation behavior. Regroup the app after the source job and verify original membership and ranks. Repeat with a changed preset and verify the request uses it. Run the Qwen smoke test. Pass this gate before starting Object Analysis.

**Release gate for Object Analysis.** With the installed candidate, assess a fixed photo set with observable objects. Confirm results map to the correct photos and criteria, and verify repeat requests with changed criteria, partial failures, and unavailable models. Run the baseline burst, Qwen, and Deep AI Review smoke tests before release.

The burst baseline and follow-up release evidence are recorded in [mcpserver.md](mcpserver.md).
