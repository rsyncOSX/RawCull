# Follow-up AI analysis over RawCull MCP

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

- **Assessment.** Accept a nonempty subset of `composition`, `exposure`, and `subjectVisibility`. Subject visibility includes occlusion. The client translates the user’s prompt into those fields and compares the per-frame results. Expression and eye state are outside this rubric. The current app path can return prose, and its structured validator requires `eyesOpen` to be null. The MCP path should return validated rubric findings or a typed per-photo failure. An identical replay reuses the existing request. A new request for the same photo runs independently.
- **Source identity.** Persist a versioned app-side snapshot keyed by source job ID and catalog grant identity. Map each source photo ID to a catalog-relative path, size, and modification time. Use these attributes to detect file changes on reopen, and verify that the resolved path stays within the authorized catalog. Map each burst ID to the full ordered membership, original ranks where available, recommendation, and alternate. An ordinal photo ID has meaning within its source snapshot. Later grouping settings and live group IDs do not determine membership or rank.
- **Permission.** Add an explicit follow-up permission to an eligible saved catalog grant. Existing grants require an opt-in. A source created with **Approve This Job** remains readable as a burst result under its existing rules. For follow-up, tell the user how to authorize the catalog for follow-up assessment and create a new eligible source job. The one-time run lacks a persisted catalog bookmark for reopening its files.
- **Storage and lifetime.** Keep the existing burst record format readable. Store mutable follow-up status separately from the source snapshot and immutable result so progress updates stay small. The follow-up record needs its own format version, job kind, request ID and normalized arguments, source and grant IDs, state, progress, heartbeat, and terminal outcome. Bind availability to the current authorized source. Clear, revoke, grant replacement, or source replacement invalidates dependent results and prevents late publication. Keep terminal records and replay receipts within explicit retention and size bounds. Set and document those limits before exposing the tools.
- **Coordination.** Use one coordinated reservation across burst and follow-up records, plus a shared app-side execution lease for MCP and UI work that shares model or workspace resources. Run cleanup and revision checks across both stores. Use the existing burst job’s 120-second queue timeout and 45-second running heartbeat expiry as starting points for the follow-up. Update the heartbeat independently of inference progress. A stale or cancelled worker loses permission to publish. On graceful quit, terminate the active request and release its lease. After an unexpected exit, report interruption when the lease expires and let a fresh request start if the source is still eligible.
- **Compatibility.** Add an app/helper protocol version and verify it before enqueueing. Report follow-up availability only for a compatible pair. Preserve baseline tools across upgrades, and report a clear eligibility error for older source results that lack a follow-up snapshot.
- **Result boundary.** Keep image bytes and filesystem paths in RawCull. Structured text is visible to the MCP client and may reach its model provider. Bound individual fields and total serialized output. Normalize control characters, identify any returned model text as untrusted observations, and omit raw invalid responses and internal diagnostics. Structured fields can still contain text from the image, so the client must treat their contents as data.

See [Qwen inference instructions](../RawCull/Intelligence/Qwen/QwenInferenceRuntime.swift), [assessment validation](../RawCull/Intelligence/Qwen/QwenPhotoAssessment.swift), [catalog grants](../Tools/RawCullMCP/Sources/RawCullMCP/CatalogGrantStore.swift), and [capability reporting](../Tools/RawCullMCP/Sources/RawCullMCP/ToolHandlers.swift).

## Implementation and release plan

Each step requires a passing release test **before work starts on the next step**. Use an installed, signed release candidate with its bundled helper, using TestFlight where applicable. Intermediate capabilities can be exercised on release candidates before broader distribution. Record the app build, helper version, model and backend, fixture, prompts or calls, relevant responses, and pass or fail verdict. Fix failures and rerun the affected gate. A deferred or unverified check leaves the gate open. From Step 2 onward, run the relevant automated regression cases before the signed-candidate check. Extend MCP job lifecycle and helper tests for storage, replay, authorization, cancellation, and tool validation.

Use a repeatable fixture with a burst containing more than five frames, a close recommendation and alternate, and individual photos with visible differences. Keep a second catalog and a modified recurring-folder copy for authorization and stale-ID tests. Verify target filenames and photo identities against the app and use visibly distinct fixtures for assessment checks. Exact model wording and scores can vary.

### Step 1 — Establish the burst baseline

1. Confirm the bundled helper’s tool list and version from a fresh client session.
2. Run the existing setup and analysis workflow with Vision and CLIP, selecting the backend in RawCull before each run. Record the catalog and job IDs, coverage, backend counts, and expected recommendation and alternate identities for each run.
3. Save a repeatable follow-up prompt that interprets rankings using the completed job IDs.

**Release gate.** For each backend, run the workflow from a full quit, poll to completion, paginate `list_bursts`, and verify the returned backend identifier (`vision-feature-print` or `clip`) and photo identities against the app. Check pagination with a small page size and verify the 25-item page limit. Quit and retrieve the shared result again. After clearing the result, verify that its rankings are unavailable. Run the follow-up prompt against an available result and verify that its output matches the recorded evidence. Use the [existing TestFlight checks](mcpserver.md#testflight-tests) for setup, cancellation, and revocation coverage.

### Step 2 — Preserve the source job and resolve targets

1. Save the app-side source snapshot and full membership when publishing burst results. Resolve explicit IDs and bursts through this snapshot. Reject wrong-job IDs or changed files before preview loading.
2. Implement the follow-up grant, separate request and result storage, and coordinated reservation and invalidation. Cover cleanup, replay, heartbeat expiry, and older records. Test cancellation or revocation racing publication.
3. Add a test-target integration harness around the production resolver, grants, and stores. Seed a completed source with fixture photos, then invoke the same resolution and admission paths the app worker will use. Use the harness to exercise this step before exposing public follow-up tools.

**Release gate.** Run the harness in Release configuration. Verify exact resolution after reopen, including duplicate basenames and a member beyond the first five. Regroup the same catalog and verify the original membership and rank. Exercise replaced files, a newer recurring scan, wrong catalog or job IDs, clear, and revoke. Confirm invalid requests fail before preview loading. Test burst and follow-up reservation concurrently and verify the source stays readable during the follow-up. On the signed candidate, confirm existing grants and legacy rankings still load and run the baseline workflow.

### Step 3 — Expose local Qwen assessment for explicit photos

1. Add start, status, result, and cancel tools. The start request carries a client-generated UUID, catalog ID, source job ID, distinct photo IDs, and rubric fields. Use bounded batches and a single bounded result per request. Document the concrete limits, retention, and stable errors before opening the gate. Error cases include incompatible app, missing permission, stale source, invalid target, conflicting replay, busy, and unavailable model.
2. Extract a request-scoped runner using the existing preview loader and Qwen inference service. Reuse structured validation and retry, and read model availability from the runtime. Return outcomes such as unreadable photo and invalid assessment per file. Publish successful assessments alongside per-photo failures and report a failed job when every file fails.
3. Acquire the shared lease at the MCP and UI entry points. Publish only while the worker still owns its reservation and the source grant is valid. Enforce the text and response boundaries before returning results.

An example start payload for the proposed tool is:

```json
{
  "requestId": "<new UUID>",
  "catalogId": "<catalog ID>",
  "sourceJobId": "<completed burst job ID>",
  "photoIds": ["<recommended photo ID>", "<alternate photo ID>"],
  "rubric": ["composition", "subjectVisibility"]
}
```

**Release gate.** Automate input validation, structured response handling, replay and conflicting replay, lease exclusion in both directions, heartbeat expiry, cancellation, and partial failure. With the signed candidate, assess two explicit IDs through MCP and confirm the results map to the expected frames and requested fields. Assess the same IDs with a different rubric and a new request ID, then replay the identical request and verify that it does not trigger duplicate inference. Exercise a missing model and an unreadable photo. Verify response bounds, absence of image bytes and paths, and continued access to the source rankings.

### Step 4 — Target a burst directly

1. Add a burst selector scoped to the completed source job. In the first release, select the saved recommendation and alternate. If the alternate is absent, return one assessment and report that coverage explicitly. Defer all-frame assessment until the caller can see the resolved count and the batch limit behavior is defined.
2. Return the assessed photo IDs, their source ranks, per-frame findings, and coverage. Let the client synthesize the comparison from those findings and identify which frames were assessed.
3. Support a shortlist of bursts by letting the client page the rankings and submit selected bursts through the primary job flow. Verify the one-worker constraint when requests arrive together.

**Release gate.** Run the two-prompt flow in one chat without manually copying IDs. Ask for the lowest-confidence burst, then compare its recommended frame and alternate. Verify the client uses the completed job and that both assessed IDs match the ranking. Exercise a missing alternate and a burst over five frames. Verify a wrong-job burst ID fails and concurrent submissions produce the documented busy or replay response.

### Step 5 — Validate the release workflow

1. Document the user prompts, model prerequisites, authorization behavior, and result lifetime. Document what the client can see and how to revisit or remove a result.
2. Validate an upgrade from an installation with existing catalog grants and burst results. Check both version-skew directions. Unsupported pairs must fail before creating a follow-up job while preserving baseline tool behavior.
3. Check that cancelling, quitting during inference, clearing, or revoking leaves recoverable job state. Results must follow the published access and retention rules.

**Release gate.** Install the signed candidate over the previous supported release and use its bundled helper in a fresh chat. Run the baseline with both similarity backends and complete the second prompt for both a burst and specific photos. Quit and reopen at the documented points. During an active follow-up, exercise cancellation and revocation separately and verify no result is subsequently published under that request. Verify clear behavior, expired lease recovery, the one-time approval message, missing models, and continued access to existing tools. Record the release verdict before enabling further review modes.

### Step 6 — Add Deep AI Review and Object Analysis as separate increments

1. Route a burst and explicit preset to the existing Deep AI Review pipeline. Build candidates from the persisted membership and ranks. Verify the resolved files match the source snapshot before adding available sharpness, subject label, and AF-point evidence. Return job-scoped results and coverage. Key any reused results to source identity, model, and preset.
2. In a later increment, route bounded photo selections and criteria to Object Analysis. Report model availability, per-photo failures, and the supported evidence fields. Use request-scoped results and include criteria and model identity in any reuse decision.

**Release gate for Deep AI Review.** With the installed candidate, compare an MCP preset run against the app’s review of the same burst and preset. Check candidate identities, evidence fields, progress, cancellation, and unavailable segmentation behavior. Regroup the app after the source job and verify original membership and ranks. Repeat with a changed preset and verify the request uses it. Run the Qwen smoke test. Pass this gate before starting Object Analysis.

**Release gate for Object Analysis.** With the installed candidate, assess a fixed photo set with observable objects. Confirm results map to the correct photos and criteria, and verify repeat requests with changed criteria, partial failures, and unavailable models. Run the baseline burst, Qwen, and Deep AI Review smoke tests before release.

All follow-up steps are proposed. The existing burst validation is recorded in [mcpserver.md](mcpserver.md).
