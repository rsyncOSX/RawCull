# RawCull MCP prompts

## Culling workflow

Start with **Analyze a new catalog**, then use any of the three follow-ups in the same Codex chat. Codex can reuse the catalog and job IDs from the first prompt. Run the follow-ups before starting another burst job, which can replace the shared result.

Use Codex on your Mac with the `rawcull` MCP server connected to the helper bundled with your installed app. Replace text in angle brackets before sending a prompt. RawCull processes photos locally. The MCP client receives ranking metadata and assessment findings, which it may send to its model provider. See the [MCP setup instructions](mcpserver.md#connect-codex-to-the-bundled-helper).

### Analyze a new catalog

Scans one folder, groups similar frames into bursts, and ranks the frames so you can start culling. RawCull uses the similarity backend selected in the app.

> Use RawCull MCP to analyze the photos in `<full folder path>` for bursts. If RawCull asks me to choose a folder or approve the job, tell me and wait for my decision. Follow the setup and analysis through completion. Give me the number of photos scanned and analyzed, the number of bursts, the similarity backend, and any skipped or unevaluated photos. Show up to five bursts with the recommended filename, alternate filename if available, and confidence. Keep the catalog and job IDs for my follow-up prompts. If the run fails or is declined, report the reason.

For example, use `/Users/you/Pictures/LatestShoot` as the full folder path. Choose **Approve This Job** for a one-time run or **Approve and Remember** to save an analysis grant for the same photo set. RawCull keeps one saved MCP catalog grant.

### Review the closest calls

Turns the existing rankings into a short list of decisions worth reviewing by hand. This uses the evidence from the completed burst job and needs no Qwen model.

> Use RawCull MCP to read every page of ranked bursts from the job you just completed. Find up to five low-confidence bursts where there is both a recommendation and an alternate. Put ties and the closest recorded scores first where the scores are available. For each pair, show the two filenames, confidence, and the reasons and cautions RawCull returned. Tell me what to inspect in each pair. If you find fewer than five, report the actual count. Keep this shortlist for my next prompt.

The next two prompts require Qwen3-VL-2B to be available in **Settings → AI** and **Enable MCP photo assessments** to be on in **Settings → MCP**. Use the bundled helper from the build you are running. The direct burst comparison needs a helper that advertises `burstId`. See [assessment requirements and controls](mcpserver.md#follow-up-photo-assessments).

### Compare the recommendation and alternate

Runs a closer visual assessment of the two saved picks in one burst. Use it when sharpness and similarity rankings leave you with a close choice.

> Use RawCull MCP to compare the recommendation and alternate in the lowest-confidence burst with both picks from the job you just completed. Follow every rankings page. Order known confidence low, medium, then high, keeping source order for ties and leaving unknown values unclassified. Submit that burst by `burstId` from the same job and assess composition, exposure, and subject visibility, including any occlusion. Wait for the assessment to finish. Match the returned photo IDs to the saved picks and show the filenames, original ranks, and how many frames were in the burst. Compare the findings and explain which frame you would keep if the evidence supports a choice. Preserve unknown scores and report any failed frame. If no eligible pair exists, say so.

### Assess photos from a completed burst job

Checks a specific concern across up to four frames from the same job. Use this when you already know which photos you want to inspect, including frames from different bursts.

> Use RawCull MCP to assess exposure for `<filenames from the rankings, up to four>` in the burst job you just completed. Resolve each filename to its photo ID using the same job's ranking evidence. If a filename is missing or ambiguous, ask me to clarify. Submit those explicit photo IDs with the exposure rubric and wait for the result. For each file, show the exposure score and evidence, or the per-photo error. Preserve unknown scores. Summarize any exposure issue worth checking before I keep or edit the photo.

## Repeat shoots

### Analyze the next shoot in the same folder

Starts a new analysis when you reuse an ingest folder for successive shoots. Set it up once by opening the folder in RawCull and enabling **Allow MCP burst analysis and photo assessments** and **Allow analysis of future photos in this folder** in **Settings → MCP**, then choose **Authorize Selected Catalog**. Finish any follow-up work on the previous shoot first.

> Use RawCull MCP to analyze the current photos in my recurring shoot folder at `<full folder path>`. Check for a saved grant with the matching catalog name and recurring-folder access. If it is missing, tell me and stop. Use the exact folder path to start a fresh burst analysis. If RawCull asks for approval, tell me and wait. When the job finishes, show the scan coverage and up to five recommended frames with their alternates. Use this new job for any follow-up prompts.

To rerun the same photo set using an existing **Approve and Remember** grant, reuse **Analyze a new catalog** with the same path.

## Status checks

These prompts only read status or results. They can be used independently of the culling workflow.

### Check the MCP connection and catalog access

Confirms which helper and app build Codex is using and shows the saved catalog grant, if one exists.

> Use RawCull MCP to check `rawcull_status` and `list_catalogs`. Report the helper version, bundled app build, and transport. Tell me whether burst analysis and photo assessment tools are available, whether photo assessments are enabled if the helper reports that setting, and whether the assessment tool accepts a burst ID. Show any saved catalog and whether it allows analysis or recurring-folder access. Report any connection or permission error.

### Check an analysis in progress

Checks the setup or scan already started in this chat. Use it to see whether RawCull is waiting for approval, scanning, finished, or reporting an error.

> Use RawCull MCP to check the analysis you started in this chat. If setup is still pending, report the approval or folder selection it needs. If analysis has queued, report its current state, stage, and available progress. If it finished, report coverage and whether its rankings are still readable. Use the existing request or job IDs. If those IDs are missing from this chat, ask me for them.

### Revisit a photo assessment

Checks the state and findings of an existing request, including after RawCull quits. Assessment results are available for up to 24 hours while the source job and approval are current.

> Use RawCull MCP to check the photo assessment from this chat, or request `<assessment request ID>` if I provided one. Report its state and any error. If a result is available, show the assessed frames, the requested findings, and any per-photo failures. If the result is cleared, expired, or otherwise unavailable, report what RawCull returned. Use the original request ID without submitting a new assessment.
