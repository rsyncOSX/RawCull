# Follow-up AI analysis over RawCull MCP

## Proposed workflow

The first prompt asks RawCull to load an authorized catalog and run burst analysis. RawCull uses sharpness and the configured similarity backend, Vision or CLIP, to group and rank frames. The client polls until the job reports `completed` and retains the catalog and job IDs.

The second prompt asks for a closer look at a burst or named photos. For example, “Compare the recommended frame and alternate in the lowest-confidence burst for expression, subject visibility, and obstructions.” RawCull would resolve the frames, run local visual assessment, and return findings the client can use to explain its choice. This concentrates model time on close calls and preserves the original ranking for reference.

## What works today

- Use `request_catalog_setup` with `jobType: "burstAnalysis"`, or `start_catalog_analysis` for an already authorized catalog. Poll `get_catalog_setup_status` when setup is needed, then `get_analysis_status` for progress and final coverage. The burst request uses the app’s configured backend. The MCP tool schemas do not accept a Vision or CLIP override.
- Use `list_bursts` with the completed job’s catalog and job IDs. Follow `nextCursor` to cover the entire list. Each entry includes a recommendation, alternate, confidence, reasons, cautions, and evidence for up to five frames. The result can be read after RawCull quits while it remains shared.
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
| Qwen assessment | The feature accepts a file batch and prompt criteria, loads previews, and returns structured assessments, freeform responses, or per-photo errors. Its current UI state filters out previously analyzed file IDs. | Pass criteria and return results per request. Make reuse depend on file identity, model, and criteria, or rerun inference. A second question about the same frame must receive results for the second question. |
| Other review modes | Object Analysis already accepts a file batch and criteria. Deep AI Review builds a preset-driven request with burst rank, sharpness, subject label, and AF point when available. | Add these modes once the Qwen flow passes release testing. Per-frame assessments can support a client comparison. A model that compares multiple frames directly would need a separate inference path and validation. |

Source entry points are [AnalysisTools](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift), [AnalysisJobStore](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift), [MCPAnalysisController](../RawCull/Main/MCPAnalysisController.swift), [Qwen Analysis](../RawCull/Intelligence/Qwen/RawCullQwenAnalysisFeature.swift), and [Object Analysis](../RawCull/Intelligence/ObjectAnalysis/RawCullObjectAnalysisFeature.swift).

## Implementation and release plan

Each step requires a passing release test **before work starts on the next step**. Use an installed, signed release candidate with its bundled helper, using TestFlight where applicable. Intermediate capabilities can be exercised on release candidates before broader distribution. Record the app build, helper version, model and backend, fixture, prompts or calls, relevant responses, and pass or fail verdict. Fix failures and rerun the affected gate. A deferred or unverified check leaves the gate open.

Use a repeatable fixture with a burst containing more than five frames, a close recommendation and alternate, and individual photos with visible differences. Keep a second catalog and a modified recurring-folder copy for authorization and stale-ID tests. Verify target filenames and photo identities against the app and use visibly distinct fixtures for assessment checks. Exact model wording and scores can vary.

### Step 1 — Establish the burst baseline

1. Confirm the bundled helper’s tool list and version from a fresh client session.
2. Run the existing setup and analysis workflow with Vision and CLIP, selecting the backend in RawCull before each run. Record the catalog and job IDs, coverage, backend counts, and expected recommendation and alternate identities for each run.
3. Save a repeatable follow-up prompt that interprets rankings using the completed job IDs.

**Release gate.** For each backend, run the workflow from a full quit, poll to completion, paginate `list_bursts`, and verify the job's returned backend and photo identities against the app. Quit and retrieve the shared result again. After clearing the result, verify that its rankings are unavailable. Run the follow-up prompt against an available result and verify that its output matches the recorded evidence. Use the [existing TestFlight checks](mcpserver.md#testflight-tests) for setup, cancellation, and revocation coverage.

### Step 2 — Preserve the source job and resolve targets

1. Keep one active MCP worker while allowing a completed burst result to remain addressable during a follow-up. Define how the app retains that source, how long it remains available, and how clearing or revoking access invalidates dependent results.
2. Resolve explicit photo IDs against the authorized source snapshot. Resolve burst IDs against the source job and retain full membership internally. Verify catalog identity and file identity after reopen. Reject stale, mismatched, and ambiguous targets before model work.
3. Define scope for follow-up authorization. Start with an eligible saved catalog grant and explicit authorization for follow-up assessment. A one-time burst approval should require a new authorization if extended to follow-up inference.

**Release gate.** Exercise target resolution using a release-candidate test entry point. Resolve the recommendation, alternate, and a frame beyond the first five to the expected files after quitting and reopening. Confirm that a follow-up can reserve the worker while the source result remains readable. Try the same inputs after a changed recurring scan, another catalog selection, clear, and revoke. Each invalid request must fail before loading a preview. Confirm the installed build still reads existing burst results and runs the baseline workflow.

### Step 3 — Expose local Qwen assessment for explicit photos

1. Add a start tool with a client-generated request UUID, catalog ID, source job ID, explicit photo IDs, and criteria. Add status and result retrieval, and route cancellation through the job lifecycle. Bound the batch and criteria size. Define validation errors, partial success behavior, and replay semantics. Use the source job’s photo IDs in results.
2. Reuse the app’s Qwen inference and preview loader. Give each request its own criteria, progress, and result. Report model unavailable or workspace busy through the tool. Serialize shared model access with the app’s AI features.
3. Return structured per-photo findings and explicit failures. Keep image bytes and local paths in RawCull. Text results returned over MCP are visible to the client and may reach the model serving that client.

**Release gate.** In a fresh session, run a burst job and then assess two explicit photo IDs using only MCP. Check that both results map to the expected frames and reflect the requested criteria. Ask a different question about the same frames with a new request ID and verify a new assessment. Replay an identical request and verify the same job without duplicate work. Try a conflicting replay, cancellation, unavailable model, and a valid batch with one unreadable photo. Verify the terminal status, partial failures where applicable, and absence of image bytes and paths in tool responses. Recheck that the source rankings remain readable.

### Step 4 — Target a burst directly

1. Add a burst selector scoped to the completed source job. Start with the recommended frame and alternate. Offer a bounded all-frame option only if the caller can see the resolved frame count and coverage. Define behavior for a missing alternate and for bursts exceeding the batch limit.
2. Return the assessed photo IDs, their source ranks, per-frame findings, and coverage. Let the client synthesize the comparison from those findings and identify which frames were assessed.
3. Support a shortlist of bursts by letting the client page the rankings and submit selected bursts through the primary job flow. Verify the one-worker constraint when requests arrive together.

**Release gate.** Run the two-prompt flow in one chat without manually copying IDs. Ask for the lowest-confidence burst, then compare its recommended frame and alternate. Verify the client uses the completed job and that both assessed IDs match the ranking. Exercise a missing alternate and a burst over five frames. If all-frame selection ships, verify membership beyond the public top five and the behavior at the batch limit. Verify a wrong-job burst ID fails and concurrent submissions produce the documented busy or replay response.

### Step 5 — Validate the release workflow

1. Document the user prompts, model prerequisites, authorization behavior, and result lifetime. Document what the client can see and how to revisit or remove a result.
2. Validate an upgrade from an installation with existing catalog grants and burst results. Check compatibility and capability reporting when the app and helper differ in version.
3. Check that cancelling, quitting during inference, clearing, or revoking leaves recoverable job state. Results must follow the published access and retention rules.

**Release gate.** Install the signed candidate over the previous supported release and use its bundled helper in a fresh chat. Run the baseline with both similarity backends and complete the second prompt for both a burst and specific photos. Quit and reopen at the documented points. During an active follow-up, exercise cancellation and revocation separately and verify no result is subsequently published under that request. Verify clear behavior, handling of missing models, and continued access to existing tools. Record the release verdict before enabling further review modes.

### Step 6 — Add Deep AI Review and Object Analysis as separate increments

1. Route a burst and explicit preset to the existing Deep AI Review pipeline. Carry source rank, sharpness, subject label, and AF-point evidence into the request. Return the selected candidates and the evidence actually available for each.
2. In a later increment, route bounded photo selections and criteria to Object Analysis. Report model availability, per-photo failures, and the supported evidence fields.

**Release gate for Deep AI Review.** With the installed candidate, compare an MCP preset run against the app’s review of the same burst and preset. Check candidate identities, evidence fields, progress, cancellation, and unavailable segmentation behavior. Run the Qwen smoke test. Pass this gate before starting Object Analysis.

**Release gate for Object Analysis.** With the installed candidate, assess a fixed photo set with observable objects. Confirm results map to the correct photos and criteria, and verify partial failures and unavailable models. Run the baseline burst, Qwen, and Deep AI Review smoke tests before release.

All follow-up steps are proposed. The existing burst validation is recorded in [mcpserver.md](mcpserver.md).
