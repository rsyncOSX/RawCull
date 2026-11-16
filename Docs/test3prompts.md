# RawCull MCP Step 3 TestFlight prompts

Install the new TestFlight build and configure the MCP client to use the helper bundled with that installation. In the first prompt, verify the reported build number against the one you installed. Run the prompts in the same chat where possible, and use the IDs from a fresh burst job on the new build. Keep RawCull’s AI settings closed except during the model-refresh test.

Use a disposable catalog for tests that change files, clear results, or revoke access. A new burst job replaces the current shared result, so complete the tests that depend on the reference job before starting a different catalog.

## 1. Confirm the helper and create a source job

Replace `<catalog path>` with the full path to `100MSDCF`. The reference filenames are `_DSC7727.ARW` and `_DSC7728.ARW`.

> Use only RawCull MCP. Call `rawcull_status` and report the helper version, app build, and whether all four photo assessment tools are available. Stop if the app build differs from `<new TestFlight build number>`. Otherwise call `request_catalog_setup` for `<catalog path>` with job type `burstAnalysis` and a fresh request ID. If RawCull asks me to approve the job, tell me and keep polling that setup request. Once setup returns `queued`, use its returned `catalogId` and `jobId` with `get_analysis_status` until the job finishes. After it completes, page through `list_bursts` to find the burst containing `_DSC7727.ARW` and `_DSC7728.ARW`. Report the catalog ID, job ID, burst ID, and both photo IDs. Also record two more distinct photo IDs from the same completed job for the four-photo test. If you can’t resolve an ID from a tool response, say so.

## 2. Assess two photos and inspect the response

> Use only RawCull MCP. Call `start_photo_assessment` with the two reference photo IDs, the completed source job ID, the catalog ID, a fresh request ID, and rubric `["composition", "subjectVisibility"]`. Poll `get_photo_assessment_status` about every two seconds until it reaches a terminal state. If it completes, call `get_photo_assessment_result`. Show each photo’s score and evidence for both fields, preserving any null scores or evidence. Report the request ID, model, result and prompt template versions, preview kind and dimensions, assessed count, and failed count. Confirm the photo IDs match the source job, the findings contain only the requested fields, and the result contains no filesystem paths or image bytes. If the request fails, report the exact state and error code.

## 3. Change the rubric and test completion without polling

> Use only RawCull MCP. Assess the same two photo IDs and source job with a fresh request ID and rubric `["exposure"]`. Report the request ID and initial state. Wait 80 seconds before the first status check, with no status or result calls during that interval. If you can’t wait without polling, give me the request ID and stop so I can resume after 80 seconds. On the first check, report whether it already completed. If it is still running, poll until terminal. Fetch the result and report each exposure score and its evidence, plus the exact top-level and per-photo fields RawCull returned. Preserve nulls.

If the client stops after queueing, send this after 80 seconds:

> Use only RawCull MCP. Check `get_photo_assessment_status` for exposure request `<request ID>`. Tell me whether it completed before this first check. If it is still running, poll until terminal. Fetch the result when available and report both exposure scores, their evidence, and the exact fields returned.

## 4. Replay the exposure request and force a conflict

> Use only RawCull MCP. Resubmit the exposure request with the exact same `requestId`, `catalogId`, `sourceJobId`, `photoIds`, and `rubric`. Report whether it immediately returns the original request in `completed` state. Then repeat the call with the same request ID and change only the rubric to `["composition"]`. Report the exact error code. Finally, confirm that the original exposure result is still readable. Pass only if the exact replay returns the original completed request and the changed rubric returns `conflictingReplay`.

`start_photo_assessment` takes `photoIds`. Use the burst ID to locate photos through `list_bursts`.

## 5. Measure a four-photo batch cold and warm

Fully quit RawCull before the cold run. Keep the source catalog accessible and use the same four distinct IDs for both runs.

> Use only RawCull MCP. Run a four-photo assessment on the completed source job with rubric `["composition", "exposure", "subjectVisibility"]`. Use a fresh request ID and record elapsed time from submission to the first observed terminal state. After it finishes, repeat the same four photos and rubric with a new request ID while RawCull is still open. For each run, report elapsed time, terminal state, any error code, assessed and failed counts, and whether each successful photo returned all three fields. Report the serialized result size in bytes if you can measure it. Check that the source rankings are still readable after both runs.

## 6. Test overlap and cancel during inference

> Use only RawCull MCP. Start a fresh four-photo assessment and wait until it is `running`. While it is running, submit a second assessment with a different request ID and try to start a new burst analysis for the same catalog. Report the exact responses. I expect both submissions to be rejected while inference owns the worker. Cancel the first request using `cancel_photo_assessment`, then poll until it reaches a terminal state. Report whether it reached `cancelled`, whether result retrieval returns `unavailable`, and whether the original source rankings are still readable. If either overlapping submission is accepted, report that as a failure and stop issuing new starts.

## 7. Refresh the model during inference

Keep AI settings closed at the start. When the client reports `running`, open **Settings → AI** and click **Check Again** if the tab did not already refresh the model.

> Use only RawCull MCP. Start a fresh four-photo assessment on the completed source job. When it reaches `running`, give me the request ID and tell me to refresh model availability in RawCull’s AI settings. Keep polling until terminal. Report whether it failed with `modelChanged` and whether `get_photo_assessment_result` returns `unavailable`. Then confirm the source rankings are still readable. If the assessment finished before I refreshed, report that the test needs another run.

## 8. Verify one-time approval after a full quit

Use a catalog without a saved analysis grant so RawCull shows the approval choices. Choose **Approve This Job**. After the burst completes and the client records the IDs, fully quit RawCull.

> Use only RawCull MCP. Request burst setup for `<disposable catalog path>`. Wait for me to choose **Approve This Job**, then use the returned catalog and job IDs to wait for burst completion. Find two explicit photo IDs in the ranked results and report them with the source job ID. Stop there so I can fully quit RawCull.

After quitting:

> Use only RawCull MCP. Start an exposure assessment for the two photo IDs from the one-time job, using its catalog ID and source job ID and a fresh request ID. Wait for completion and retrieve the result. Report whether RawCull reopened, whether it required another approval, and whether both photo IDs were assessed. Leave the AI settings tab closed. I’ll verify that the visible workspace selection stays where it was after launch.

To test fresh **Approve and Remember**, use a different disposable catalog:

> Use only RawCull MCP. Request burst setup for `<second disposable catalog path>`. Wait for me to choose **Approve and Remember**, then wait for the burst job to complete. Find two explicit photo IDs from its rankings and run an exposure assessment with a fresh request ID. After it finishes, request setup again for the same folder with a new request ID. Verify that the second burst queues without another approval. Use photo IDs from that second job to confirm its result also supports an exposure assessment. Report both source job IDs, assessment IDs, and terminal states.

## 9. Test mixed and all-unreadable results

Use copies of RAW files in a disposable catalog. Complete the source burst and record two ranked photo IDs. Then replace one of those **copies** with an unreadable placeholder at the same pathname. Use the original source job and IDs from before the change.

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
