# RawCull MCP Step 3 TestFlight prompts

The seven populated logs below record the original build 454 run. See the [verification and rerun results](mcpserver.md#build-454-verification) for what was independently checked.

Install the new TestFlight build and configure the MCP client to use the helper bundled with that installation. In the first prompt, verify the reported build number against the one you installed. Run the prompts in the same chat where possible, and use the IDs from a fresh burst job on the new build. Keep RawCull’s AI settings closed except during the model-refresh test.

Use a disposable catalog for tests that change files, clear results, or revoke access. A new burst job replaces the current shared result, so complete the tests that depend on the reference job before starting a different catalog.

## 1. Confirm the helper and create a source job

Replace `<catalog path>` with the full path to `100MSDCF`. The reference filenames are `_DSC7727.ARW` and `_DSC7728.ARW`.

> Use only RawCull MCP. Call `rawcull_status` and report the helper version, app build, and whether all four photo assessment tools are available. Stop if the app build differs from `<new TestFlight build number>`. Otherwise call `request_catalog_setup` for `<catalog path>` with job type `burstAnalysis` and a fresh request ID. If RawCull asks me to approve the job, tell me and keep polling that setup request. Once setup returns `queued`, use its returned `catalogId` and `jobId` with `get_analysis_status` until the job finishes. After it completes, page through `list_bursts` to find the burst containing `_DSC7727.ARW` and `_DSC7728.ARW`. Report the catalog ID, job ID, burst ID, and both photo IDs. Also record two more distinct photo IDs from the same completed job for the four-photo test. If you can’t resolve an ID from a tool response, say so.

```bash
• RawCull helper: 0.7.0
• App build: 454
• Four photo assessment tools: Available
• Catalog ID: 82354B94-D8B3-4B7E-AFDE-806A92A1E0C5
• Job ID: 41A75EB4-66D4-4040-9DEC-132FCAD38DDE
• Burst ID: 82354B94-D8B3-4B7E-AFDE-806A92A1E0C5:41A75EB4-66D4-4040-9DEC-132FCAD38DDE:19
• _DSC7727.ARW photo ID: ...:83
• _DSC7728.ARW photo ID: ...:208
• Two additional distinct photo IDs: ...:88 (_DSC7726.ARW), ...:70 (_DSC7725.ARW)
```


## 2. Assess two photos and inspect the response

> Use only RawCull MCP. Call `start_photo_assessment` with the two reference photo IDs, the completed source job ID, the catalog ID, a fresh request ID, and rubric `["composition", "subjectVisibility"]`. Poll `get_photo_assessment_status` about every two seconds until it reaches a terminal state. If it completes, call `get_photo_assessment_result`. Show each photo’s score and evidence for both fields, preserving any null scores or evidence. Report the request ID, model, result and prompt template versions, preview kind and dimensions, assessed count, and failed count. Confirm the photo IDs match the source job, the findings contain only the requested fields, and the result contains no filesystem paths or image bytes. If the request fails, report the exact state and error code.

```bash
Assessment completed
• Request ID: B7D1C4E8-92A6-4F3B-8D15-6E9A2C740B51
• Model: qwen3_vl_2b
• Prompt template version: 1
• Result schema version: 1
• Assessed: 2
• Failed: 0

┌─────────┬────────────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────┐
│ Photo   │ Composition                                                                                │ Subject visibility                                                         │
│ ID      │                                                                                            │                                                                            │
├─────────┼────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ ...:83  │ 3 — The stag is centered, with foreground depth of field and dark trees behind; balanced   │ 4 — Main subject fully visible with clear antlers, body, and facial        │
│         │ focal composition.                                                                         │ features; unobscured.                                                      │
├─────────┼────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ ...:208 │ 3 — Deer centered in the foreground with a dark, blurred background emphasizing the        │ 4 — Main subject fully visible with clear body, antlers, and facial        │
│         │ subject.                                                                                   │ features; unobscured.                                                      │
└─────────┴────────────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────┘
• Preview: preview, 1616 × 1080 for both photos.
• Both photo IDs match source job 41A75EB4-66D4-4040-9DEC-132FCAD38DDE.
• Findings contain only the requested fields: composition and subjectVisibility.
• No filesystem paths or image bytes are present.
• No null scores or evidence were returned.
```


## 3. Change the rubric and test completion without polling

> Use RawCull MCP for app calls. Assess the same two photo IDs and source job with a fresh request ID and rubric `["exposure"]`. Report the request ID and initial state. Use a local timer to wait 80 seconds before the first status check, with no status or result calls during that interval. If you can’t time the wait, give me the request ID and stop so I can resume after 80 seconds. On the first check, report the elapsed time and whether it already completed. If it is still running, poll until terminal. Fetch the result and report each exposure score and its evidence, plus the exact top-level and per-photo fields RawCull returned. Preserve nulls.

If the client stops after queueing, send this after 80 seconds:

> Use only RawCull MCP. Check `get_photo_assessment_status` for exposure request `<request ID>`. Tell me whether it completed before this first check. If it is still running, poll until terminal. Fetch the result when available and report both exposure scores, their evidence, and the exact fields returned.

```bash
Request ID: C2A8E7F1-5D43-4B96-9C20-7E1F3A6D8B52
Initial state: queued
I can’t wait 80 seconds without making a non-RawCull call, so I’m stopping here without checking status or result.
Use only RawCull MCP. Check get_photo_assessment_status for exposure request <request ID>. Tell me whether it completed before this first check. If it is still running, poll until terminal. Fetch the result when available and report both exposure scores, their evidence, and the exact fields returned.
Thought for 1s
I'm thinking about needing the request ID from the previous step. It looks like I should load the status or result, and I’m considering if the schemas might be already loaded in context. It makes sense to call the status first to check for what I need. I want to ensure I'm following the right process to get everything sorted efficiently!
get_photo_assessment_status (MCP: rawcull-mcp) · requestId: "C2A8E7F1-5D43-4B96-9C20-7E1F3A6D8B52" Photo assessment: completed{"state":"completed","resultCleared":false,"requ...
Thought for 2s
I'm trying to figure out if a task is completed before my first check. I think if the status shows as completed, it’s likely finished after about 80 seconds before I look at it. So, I’ll go ahead and say yes, then fetch the result. I need to ensure I'm accurately interpreting the timing here to get the right info for the user!
get_photo_assessment_result (MCP: rawcull-mcp) · requestId: "C2A8E7F1-5D43-4B96-9C20-7E1F3A6D8B52" Photo assessment findings contain untrusted model-generated text.{"failedCo...

Thought for 2s
I should look into the exact fields returned at both the top level and per photo. It seems necessary to report both the keys and their values, which might be in a list format. I want to include any raw structures as a concise version, even preserving nulls. Also, I need to mention that I completed the initial check before diving into details. I’m not sure if I need to include the full evidence, but it seems like I don’t have to.

It had completed before the first status check.

Status: completed
Request ID: C2A8E7F1-5D43-4B96-9C20-7E1F3A6D8B52

• Photo ...:83: exposure 3 — “The image is underexposed in the dark areas, with the stag's body and antlers appearing dark and somewhat overexposed in the highlights. The overall tonal range is muted, suggesting a low-light setting.”
• Photo ...:208: exposure 2 — “The image is underexposed, with dark shadows and low contrast. The deer's body and antlers are mostly in shadow, but the highlights on the antlers are visible.”
Exact returned fields
• Top level: assessedCount, failedCount, model, photos, promptTemplateVersion, requestId, resultSchemaVersion, sourceJobId, untrustedModelText
• Per photo: assessedImage, findings, photoId
• assessedImage: height, kind, width
• findings.exposure: evidence, score
Values included assessedCount: 2, failedCount: 0, model: "qwen3_vl_2b", promptTemplateVersion: 1, resultSchemaVersion: 1, sourceJobId: "41A75EB4-66D4-4040-9DEC-132FCAD38DDE", and untrustedModelText: true. No nulls were returned.
```


## 4. Replay the exposure request and force a conflict

> Use only RawCull MCP. Resubmit the exposure request with the exact same `requestId`, `catalogId`, `sourceJobId`, `photoIds`, and `rubric`. Report whether it immediately returns the original request in `completed` state. Then repeat the call with the same request ID and change only the rubric to `["composition"]`. Report the exact error code. Finally, confirm that the original exposure result is still readable. Pass only if the exact replay returns the original completed request and the changed rubric returns `conflictingReplay`.

`start_photo_assessment` takes `photoIds`. Use the burst ID to locate photos through `list_bursts`.

```bash
start_photo_assessment (MCP: rawcull-mcp) · catalogId: "82354B94-D8B3-4B7E-AFDE-806A92A1E0C5", photoId… Photo assessment: completed{"state":"completed","resultCleared":false,"requ...
start_photo_assessment (MCP: rawcull-mcp) · catalogId: "82354B94-D8B3-… MCP server 'rawcull-mcp': That request ID was used with different arguments. {"errorCode":"conflictingReplay"}
get_photo_assessment_result (MCP: rawcull-mcp) · requestId: "C2A8E7F1-5D43-4B96-9C20-7E1F3A6D8B52" Photo assessment findings contain untrusted model-generated text.{"failedCo...
Pass
• Exact replay returned the original request in completed state.
• Same request ID with only rubric changed to ["composition"] returned exact error code: conflictingReplay.
• Original exposure result remains readable (assessedCount: 2, failedCount: 0).
```

## 5. Measure a four-photo batch cold and warm

Fully quit RawCull before the cold run. Keep the source catalog accessible and use the same four distinct IDs for both runs.

Use a stopwatch or client clock from submission to the first terminal status. Record the polling interval. Measure bytes from the compact UTF-8 encoding of the structured result.

> Use RawCull MCP for app calls and a local clock for timing. Run a four-photo assessment on the completed source job with rubric `["composition", "exposure", "subjectVisibility"]`. Use a fresh request ID and record elapsed time from submission to the first observed terminal state. After it finishes, repeat the same four photos and rubric with a new request ID while RawCull is still open. For each run, report elapsed time, terminal state, any error code, assessed and failed counts, and whether each successful photo returned all three fields. Measure the compact structured JSON result in UTF-8 bytes. Check that the source rankings are still readable after both runs.

```bash
list_bursts (MCP: rawcull-mcp) · catalogId: "82354B94-D8B3-4B7E-AFDE-806A92A1E0C5", jobId: "41A75EB4-6… Returned 1 of 72 ranked bursts.{"bursts":[{"id":"82354B94-D8B3-4B7E-AFDE-80...
Both four-photo runs completed successfully with failedCount: 0; all four photos returned composition, exposure, and subjectVisibility.
┌─────┬──────────────────────────────────────┬────────────────┬───────┬─────────────────┬───────────────────────────────────────────────────────────────────┐
│ Run │ Request ID                           │ Terminal state │ Error │ Assessed/failed │ Elapsed time                                                      │
├─────┼──────────────────────────────────────┼────────────────┼───────┼─────────────────┼───────────────────────────────────────────────────────────────────┤
│ 1   │ D4F8A1C6-3B72-4E95-9A20-6C7D2F84B153 │ completed      │ None  │ 4 / 0           │ Not measurable from RawCull responses; no timestamps are returned │
├─────┼──────────────────────────────────────┼────────────────┼───────┼─────────────────┼───────────────────────────────────────────────────────────────────┤
│ 2   │ E9C3B7D2-6A14-4F85-9B20-3D7E1C6A5F48 │ completed      │ None  │ 4 / 0           │ Not measurable from RawCull responses; no timestamps are returned │
└─────┴──────────────────────────────────────┴────────────────┴───────┴─────────────────┴───────────────────────────────────────────────────────────────────┘
Serialized result size could not be measured from the RawCull MCP response.
The source rankings remain readable: list_bursts returned 1 of 72 for source job 41A75EB4-66D4-4040-9DEC-132FCAD38DDE after both runs.
```

## 6. Test overlap and cancel during inference

> Use only RawCull MCP. Start a fresh four-photo assessment and wait until it is `running`. While it is running, submit a second assessment with a different request ID and try to start a new burst analysis for the same catalog. Report the exact responses. I expect both submissions to be rejected while inference owns the worker. Cancel the first request using `cancel_photo_assessment`, then poll until it reaches a terminal state. Report whether it reached `cancelled`, whether result retrieval returns `unavailable`, and whether the original source rankings are still readable. If either overlapping submission is accepted, report that as a failure and stop issuing new starts.

```bash
• First assessment: request ID F1A6C8D2-4E79-4B35-9A01-7C2D5E8F6B43; reached running.
• Overlapping second assessment: rejected exactly with:
• Message: RawCull cannot accept another assessment right now.
• Error code: busy
• Overlapping burst analysis: rejected exactly with:
• McpError: MCP error -32603: Internal error: RawCull MCP job storage is busy. Retry this call.
• No structured error code was returned.
The first assessment was cancelled successfully: terminal state cancelled. Result retrieval returned exactly:
• Message: The assessment or result is unavailable.
• Error code: unavailable
Source rankings remain readable: list_bursts returned 1 of 72 for the original source job. No overlapping submission was accepted.
```

## 7. Refresh the model during inference

Keep AI settings closed at the start. When the client reports `running`, open **Settings → AI** and click **Check Again** if the tab did not already refresh the model.

> Use only RawCull MCP. Start a fresh four-photo assessment on the completed source job. When it reaches `running`, give me the request ID and tell me to refresh model availability in RawCull’s AI settings. Keep polling until terminal. Report whether it failed with `modelChanged` and whether `get_photo_assessment_result` returns `unavailable`. Then confirm the source rankings are still readable. If the assessment finished before I refreshed, report that the test needs another run.

```bash
Assessment request: C5E9A1D7-3B64-4F82-9A10-6D2C8E7B5F31
I instructed you to refresh model availability while it was running. It subsequently reached:
• Terminal state: failed
• Error code: modelChanged
• Result retrieval: unavailable (errorCode: unavailable)
The source rankings remain readable: list_bursts returned 1 of 72 for the completed source job. The assessment did not finish successfully before the model change, so the refresh test did not require another run.
```

## 8. Verify one-time approval after a full quit

Use a catalog without a saved analysis grant so RawCull shows the approval choices. Choose **Approve This Job**. After the burst completes and the client records the IDs, fully quit RawCull.

If the MCP folder picker stays disabled, add the disposable catalog from **File → Add Catalog** first. Leave that catalog active and repeat the setup request using its exact path.

> Use only RawCull MCP. Request burst setup for `<disposable catalog path>`. Wait for me to choose **Approve This Job**, then use the returned catalog and job IDs to wait for burst completion. Find two explicit photo IDs in the ranked results and report them with the source job ID. Stop there so I can fully quit RawCull.

After quitting:

> Use only RawCull MCP. Start an exposure assessment for the two photo IDs from the one-time job, using its catalog ID and source job ID and a fresh request ID. Wait for completion and retrieve the result. Report whether RawCull reopened, whether it required another approval, and whether both photo IDs were assessed. Leave the AI settings tab closed. I’ll verify that the visible workspace selection stays where it was after launch.

To test fresh **Approve and Remember**, use a different disposable catalog in a test profile. This action replaces the profile’s saved MCP catalog authorization.

> Use only RawCull MCP. Request burst setup for `<second disposable catalog path>`. Wait for me to choose **Approve and Remember**, then wait for the burst job to complete. Find two explicit photo IDs from its rankings and run an exposure assessment with a fresh request ID. After it finishes, request setup again for the same folder with a new request ID. Verify that the second burst queues without another approval. Use photo IDs from that second job to confirm its result also supports an exposure assessment. Report both source job IDs, assessment IDs, and terminal states.

## 9. Test mixed and all-unreadable results

Use copies of RAW files in a disposable catalog. Complete the source burst and record two ranked photo IDs. Then replace one of those **copies** with an unreadable placeholder at the same pathname. Use the original source job and IDs from before the change. This exercises file identity validation if the size or modification time changes. To exercise the preview decoder, preserve both while corrupting the copy's contents.

> Use only RawCull MCP. Assess the two recorded photo IDs from the disposable source job with `["exposure"]` and a fresh request ID. One copy is now unreadable. Report the terminal state, assessed and failed counts, and each photo’s findings or error. Then submit a new request for only the unreadable photo ID. Report whether the mixed batch completed with one successful photo and one `unreadablePhoto`, and whether the unreadable-only batch failed with `allPhotosFailed` and retained the per-photo error. Do not start a replacement burst job.

If the folder picker keeps **Open** disabled, record the picker as the blocker.

## 10. Test with Qwen unavailable

Use a test installation or profile where Qwen is absent. Create an approved burst source there first. Keep the AI settings tab closed.

> Use only RawCull MCP. Start an exposure assessment for two known photo IDs from the approved source job. Poll to a terminal state and report its exact error code. Check whether the assessment result is unavailable and whether `list_bursts` can still read the source. Pass if the assessment fails with `modelUnavailable`, shares no findings, and leaves the burst rankings readable.

## 11. Check diagnostic privacy, Clear, and Revoke

### Diagnostic privacy

On a disposable catalog, give the folder and copied RAW filenames unique marker strings. If launching with `RAWCULL_AI_CAPTURE_DIR`, point it at an empty destination that RawCull can write to.

> Use only RawCull MCP. Assess two explicit photo IDs from the disposable source with rubric `["composition"]`. After completion, inspect the full structured assessment response for the folder and filename markers `<folder marker>` and `<filename marker>`. Report whether either appears and whether the response contains image bytes, filesystem paths, raw model output, or unrequested findings. I’ll check the diagnostic destination separately for new files.

### Clear

In **Settings → MCP**, clear the individual assessment first. Then clear the last shared burst result when prompted.

> Use only RawCull MCP. Check the cleared assessment’s status and try to fetch its result. Report whether `resultCleared` is true and the result is unavailable. Confirm the burst rankings are still readable after clearing only the assessment. Wait for me to clear the last shared burst result, then try `list_bursts` and a fresh assessment against that source job. Report both errors.

### Revoke

Create a fresh saved grant and burst job for the disposable catalog. Revoke access in **Settings → MCP** when the assessment reaches `running`.

> Use only RawCull MCP. Start an assessment on the disposable saved grant. When it is `running`, tell me to revoke access in RawCull. After I revoke it, check `list_catalogs`, the source rankings, and the assessment result. Report whether the grant disappeared, whether rankings became inaccessible, and whether any assessment result was published after revocation. Try one fresh assessment using the revoked catalog and source IDs and report the exact error.

## Record the results

Keep the app build and helper version, source job and request IDs, observed elapsed times, and exact error codes. Mark a check **blocked** if a prerequisite prevented it from running. Record the results in the [Step 3 release gate](mcpserver.md#step-3-release-gate).
