# RawCull MCP prompts

## Culling workflow

Run **Analyze a new catalog**, then **Assess the top two picks in every burst** in the same Codex chat. The second prompt uses the catalog and burst job IDs returned by the first. The other follow-ups cover narrower reviews. Finish the follow-ups before starting another burst job, which can replace the shared result.

Use Codex on your Mac with the `rawcull` MCP server connected to the helper bundled with your installed app. Replace text in angle brackets before sending a prompt. RawCull processes photos locally. The MCP client receives ranking metadata and assessment findings, which it may send to its model provider. See the [MCP setup instructions](mcpserver.md#connect-codex-to-the-bundled-helper).

### Reuse IDs in follow-ups

In the same chat, you can refer to the latest burst job or assessment by name. Copy the labeled ID from the **Reuse in follow-ups** section when you want to specify an earlier result or continue in a different chat.

- **Setup request ID** checks a folder selection or approval request with `get_catalog_setup_status`.
- **Catalog ID** and **Burst job ID** identify a run for status and rankings. The burst job ID is also the `sourceJobId` for assessments.
- **Burst ID** identifies one burst in that job. A shortlist can show it beside each pair.
- **Assessment request ID** comes from `start_photo_assessment`. Use it to check that assessment's status or retrieve its findings. The assessment label and filenames help you choose when the chat has several results.

These IDs identify records. Read access depends on the current grant and shared result. Starting another burst job can replace the previous rankings and assessments.

For prompts that start work, a setup, queue, or progress update is an interim message. Keep the chat turn active, check the same request or job until it reaches a terminal state, and deliver the final report automatically in that turn. If RawCull needs a decision, tell the user what to do in the app and continue checking the same setup request while they decide. Status-check prompts return the current state on demand.

### Analyze a new catalog

Starts a new burst analysis for the folder you specify. RawCull scans the photos, groups similar frames, and ranks each burst using the app’s selected similarity backend. The report includes scan coverage, up to five ranked pairs, and the catalog and burst job IDs needed for follow-ups.

> Use RawCull MCP to analyze the photos in `<full folder path>` for bursts. If RawCull needs folder selection or approval, tell me what to do in RawCull and show the setup request ID. Keep checking that same setup request while I decide. Once it queues, poll the returned job until it reaches a terminal state and give me the final report in this turn without waiting for a follow-up message. Include the number of photos scanned and analyzed, the number of bursts, the similarity backend, and any skipped or unevaluated photos. Show up to five bursts with the recommended filename, alternate filename if available, and confidence. End with **Reuse in follow-ups** and list the catalog ID and burst job ID. If the run fails or is declined, report the reason.

For example, use `/Users/you/Pictures/LatestShoot` as the full folder path. Choose **Approve This Job** for a one-time run or **Approve and Remember** to save an analysis grant for the same photo set. RawCull keeps one saved MCP catalog grant.

### Assess the top two picks in every burst

Starts a fresh AI assessment pass on the completed burst job. It checks the saved recommendation and alternate in every eligible burst for composition, exposure, and subject visibility, one pair at a time. Running this prompt again starts a fresh pass. Use the resume prompt below to reuse earlier results.

Install Qwen3-VL-2B in **Settings → AI**, turn on **Enable MCP photo assessments** in **Settings → MCP**, and use the bundled helper with `burstId` support. See [assessment requirements and controls](mcpserver.md#follow-up-photo-assessments).

> Use RawCull MCP to assess the saved recommendation and alternate in every eligible burst from the completed **Analyze a new catalog** run in this chat. Use the exact **Catalog ID** and **Burst job ID** from that run’s **Reuse in follow-ups** section. Use only `list_bursts`, `start_photo_assessment`, `get_photo_assessment_status`, and `get_photo_assessment_result`. If the IDs are missing, ambiguous, or rejected, report the problem and stop. Do not set up a catalog, open a folder chooser, or start a new burst job.
>
> Call `list_bursts` with `limit: 25`, passing each `nextCursor` as `cursor` until it is null. Record each burst’s ID, confidence, total frame count, and the saved picks’ photo IDs, filenames, and original ranks. A burst is eligible when it has both a saved recommendation and a distinct alternate. Process all eligible bursts in low, medium, then high confidence order, keeping source order within each group. Process unknown confidence afterward in source order and label it unclassified.
>
> For each eligible burst, call `start_photo_assessment` with `catalogId`, `sourceJobId` set to the burst job ID, a fresh UUID as `requestId`, `burstId` as the only selector, and `rubric: ["composition", "exposure", "subjectVisibility"]`. Poll `get_photo_assessment_status` about every two seconds until terminal. If completed, fetch `get_photo_assessment_result` before starting the next burst. Use the same UUID for an identical retry. Record request errors and continue with the remaining eligible bursts unless the source job or catalog becomes inaccessible.
>
> Report progress after listing the bursts and after every five assessed pairs. Include completed pairs out of the eligible total and any failures, then keep processing the remaining bursts.
>
> Match the returned photo IDs to the saved picks. For each burst, show its ID, confidence, and total frame count. For each pick, show its filename, original rank, findings, and rubric scores out of 5. Keep missing scores as unknown. Include any reported occlusion and flag failed, missing, or unmatched frames. Compare the evidence and say which frame you would keep when it supports a choice. If the evidence is inconclusive, say so.
>
> Finish the assessments and deliver the full report in this turn. Give counts for bursts listed, eligible pairs, pairs with both picks assessed, incomplete or failed assessments, and bursts without an eligible pair. Identify every skipped or incomplete burst and its reason. If no eligible pair exists, say so. If pagination fails, report that coverage of the source job could not be verified. End with **Reuse in follow-ups**, listing the catalog ID and source burst job ID once, then each attempted burst ID with its **Burst comparison** request ID.

### Check the full-burst assessment status

Takes a read-only snapshot of a full-burst assessment. It verifies submitted requests and reports how many pairs are complete, active, failed or incomplete, awaiting submission, or unknown. While the assessment is active, use this prompt in a separate Codex chat and supply the exact title of the assessment chat. Once the assessment turn has ended, you can also use it in the original chat.

> Take a read-only snapshot of **Assess the top two picks in every burst** in Codex chat `<assessment chat title>`. Inspect that chat’s history without sending it a message or steering its active turn. Leave the assessment and its submission sequence running. If you run this prompt in the original chat after the assessment turn has ended, use this chat’s history.
>
> Recover the eligible burst count and the burst IDs and request UUIDs from the run’s actual `start_photo_assessment` tool arguments. Use only `get_photo_assessment_status` and `get_photo_assessment_result` to check RawCull. Check requests one at a time. Count a pair as fully assessed only if both saved picks succeeded, and count each burst once. Report the eligible total and counts for fully assessed, queued or running, failed or incomplete, not yet submitted, and unknown. Report a burst as not yet submitted only if the submission history is complete through the snapshot. Explain any gaps and give the latest request ID and state. Return the snapshot promptly. Do not wait, stop, cancel, pause, or resume the run, submit new requests, or create files or folders.

### Resume an interrupted full-burst assessment

Continues an interrupted AI assessment against the same completed burst job. It reuses completed comparisons, retrieves any in-flight result, and submits assessments for the remaining pairs. Run it in the original assessment chat after the previous turn has ended.

> Resume **Assess the top two picks in every burst** for the same catalog ID and source burst job ID. Recover the burst IDs and request UUIDs from the original run’s `start_photo_assessment` tool arguments. If you cannot verify the source IDs or recover a complete submission history, explain the gap and stop before submitting requests. Use `list_bursts` with a limit of 25 and follow `nextCursor` to null to rebuild the eligible list.
>
> Check prior requests one at a time. Wait for any queued or running request to reach a terminal state before submitting another. For completed requests, fetch the result and verify both saved photo IDs and frame outcomes. Reuse every verified two-frame result. Include previous failures, incomplete results, and unavailable results in the final report. Submit a fresh request only for an eligible burst whose assessment was never submitted. If a previous submission has an uncertain outcome, report it as unknown and keep its request ID.
>
> Use the same confidence order, rubric, polling, progress updates, and reporting format as **Assess the top two picks in every burst**. Deliver one report covering the reused and new results, including coverage counts and **Reuse in follow-ups** IDs. Do not set up a catalog, start a new burst job, or create files or folders.

### Review the closest calls

Turns the existing rankings into a short list of decisions worth reviewing by hand. This uses the evidence from the completed burst job and needs no Qwen model.

> Use RawCull MCP to read every page of ranked bursts from the job you just completed. Call `list_bursts` with a limit of 25 and pass each `nextCursor` into the next call as `cursor` until it is null. Find up to five low-confidence bursts where there is both a recommendation and an alternate. Put ties and the closest recorded scores first where the scores are available. For each pair, show the burst ID, the two filenames, confidence, and the reasons and cautions RawCull returned. Tell me what to inspect in each pair. If you find fewer than five, report the actual count. End with **Reuse in follow-ups** and list the catalog ID and burst job ID for this shortlist.

The next two prompts use the same Qwen and MCP assessment settings as the full-burst review.

If an assessment submission is rejected, check the tool's argument schema and correct the request before retrying. Use a fresh request UUID for changed arguments and reuse the original UUID for an identical retry.

### Compare the recommendation and alternate

Runs a closer visual assessment of the two saved picks in one burst. Use it when sharpness and similarity rankings leave you with a close choice.

> Use RawCull MCP to compare the recommendation and alternate in the lowest-confidence burst with both picks from the job you just completed. Use `list_bursts` with a limit of 25 and follow `nextCursor` until it is null. Order known confidence low, medium, then high, keeping source order for ties and leaving unknown values unclassified. Call `start_photo_assessment` with `catalogId`, `sourceJobId`, a fresh UUID as `requestId`, the selected `burstId` as the only selector, and `rubric: ["composition", "exposure", "subjectVisibility"]`. Include any reported occlusion in the comparison. Poll `get_photo_assessment_status` about every two seconds until terminal, then fetch the result if completed and give me the final report in this turn without waiting for a follow-up message. Match the returned photo IDs to the saved picks and show the filenames, original ranks, and how many frames were in the burst. Compare the findings and explain which frame you would keep if the evidence supports a choice. Show assessment scores out of 5 and keep unknown scores as unknown. Report any failed frame or request error. End with **Reuse in follow-ups** and list the assessment request ID labeled **Burst comparison**, the burst ID, the catalog ID, and the source burst job ID. If no eligible pair exists, say so.

### Assess photos from a completed burst job

Checks a specific concern across up to four frames from the same job. Use this when you already know which photos you want to inspect, including frames from different bursts.

> Use RawCull MCP to assess exposure for `<filenames from the rankings, up to four>` in the burst job you just completed. Resolve each filename to its photo ID using the same job's ranking evidence. When reading rankings, use `list_bursts` with a limit of 25 and follow `nextCursor` until it is null. If a filename is missing or ambiguous, ask me to clarify. Call `start_photo_assessment` with `catalogId`, `sourceJobId`, a fresh UUID as `requestId`, the `photoIds` array as the only selector, and `rubric: ["exposure"]`. Poll `get_photo_assessment_status` about every two seconds until terminal, then fetch the result if completed and give me the final report in this turn without waiting for a follow-up message. For each file, show the exposure score out of 5 and evidence, or the per-photo error. Keep unknown scores as unknown. Summarize any exposure issue worth checking before I keep or edit the photo. End with **Reuse in follow-ups** and list the assessment request ID labeled **Exposure assessment** with the filenames, the catalog ID, and the source burst job ID.

## Repeat shoots

### Analyze the next shoot in the same folder

Starts a new analysis when you reuse an ingest folder for successive shoots. Set it up once by opening the folder in RawCull and enabling **Allow MCP burst analysis and photo assessments** and **Allow analysis of future photos in this folder** in **Settings → MCP**, then choose **Authorize Selected Catalog**. Finish any follow-up work on the previous shoot first.

> Use RawCull MCP to analyze the current photos in my recurring shoot folder at `<full folder path>`. Check for a saved grant with the matching catalog name, analysis enabled, and recurring-folder access. If it is missing, tell me and stop. Use the exact folder path to start a fresh burst analysis. If RawCull needs folder selection or approval, tell me what to do and show the setup request ID. Keep checking that same setup request while I decide. Once setup queues the job, poll it until it reaches a terminal state and give me the final report in this turn without waiting for a follow-up message. On completion, show the scan coverage and up to five recommended frames with their alternates. If the run fails or is declined, report the reason. End with **Reuse in follow-ups** and list the catalog ID and the new burst job ID.

To rerun the same photo set using an existing **Approve and Remember** grant, reuse **Analyze a new catalog** with the same path.

## Status checks

These prompts only read status or results. They can be used independently of the culling workflow.

### Check the MCP connection and catalog access

Confirms which helper and app build Codex is using and shows the saved catalog grant, if one exists.

> Use RawCull MCP to check `rawcull_status` and `list_catalogs`. Report the helper version, bundled app build, and transport. Tell me whether burst analysis and photo assessment tools are available, whether photo assessments are enabled if the helper reports that setting, and whether the assessment tool accepts a burst ID. Show any saved catalog and whether it allows analysis or recurring-folder access. Report any connection or permission error.

### Check an analysis in progress

Checks the setup or scan already started in this chat. Use it to see whether RawCull is waiting for approval, scanning, finished, or reporting an error.

> Use RawCull MCP to check the analysis you started in this chat. If setup is still pending, report the approval or folder selection it needs. If setup has queued a job, check the job itself and report its current state, stage, and available progress. If it finished, report coverage and verify whether its rankings are still readable. Use the existing setup request ID or catalog and burst job IDs. If the IDs you need are missing from this chat, ask me for them. End with **Reuse in follow-ups** and show the setup request ID if setup is pending, or the catalog ID and burst job ID once a job exists.

### Revisit a photo assessment

Checks the state and findings of an existing request, including after RawCull quits. Assessment results are available for up to 24 hours while the source job and approval are current.

> Use RawCull MCP to check my most recent photo assessment in this chat. If I give you an assessment request ID or name an earlier assessment, use that one. If the intended assessment is unclear, show the assessment labels and IDs you found and ask me to choose. If I give you an ID that this chat identifies as a catalog setup or burst job ID, explain the mismatch and show the assessment IDs available in the chat. If no assessment ID is available, ask me for the one labeled **Assessment request ID** in the original reply. Check the original request with `get_photo_assessment_status` and fetch its result if available. Report the state, any error, the assessed frames, the requested findings, and any per-photo failures. Show scores out of 5 and keep unknown scores as unknown. If the result is cleared, expired, or otherwise unavailable, report what RawCull returned. Use read-only calls. If the result is available, end with **Reuse in follow-ups** and show the assessment label and its original request ID.
