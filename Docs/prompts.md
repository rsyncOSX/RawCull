# RawCull MCP prompts

Connect the installed app’s `rawcull` MCP helper first. See [MCP setup](mcpserver.md#connect-codex-to-the-bundled-helper). Replace `<placeholders>`. Run analysis before assessment, and finish follow-ups before another analysis replaces the shared result.

RawCull analyzes photos locally. Your MCP client receives metadata and findings and may send them to its model provider. Photo assessments require Qwen3-VL-2B in **Settings → AI** and **Enable MCP photo assessments** in **Settings → MCP**.

## Shared workflow rules — send once per chat

Copy this block once, then use any short prompt below. In a new chat, include it again with the saved progress file or exact source IDs. The short prompts depend on these rules.

> For RawCull MCP work: follow tool schemas. Persist source IDs, request UUIDs/arguments, pagination cursors, and status/results in `~/RawCullMCPProgress.json`; preserve existing runs. Save request identity before submission and checkpoint each page/result atomically. Use a fresh UUID for changed arguments; reuse it for identical retries. Read every ranking page (`limit: 25`, follow `nextCursor` to null), checkpointing without duplicates; report incomplete coverage. Guide app approvals and keep polling the same setup/job/request about every two seconds until terminal. Setup already queues analysis. Assess one burst at a time; retrieve its result before submitting another. Continue to the final report in this turn. On interruption, retain progress and admitted work. Never replace source analysis during follow-ups. If source IDs are missing, ambiguous, or inaccessible, stop and explain. Keep unknown scores unknown, match findings by photo ID, and report failures. End reports with labeled source/request IDs. Read-only status prompts never submit work, wait for completion, or modify progress.

Use a different progress path in that block if desired. Reuse the same file to resume; keep it available until follow-ups finish. Saving client progress does not extend RawCull’s result retention or access grants.

## Culling workflow

### Analyze a new catalog

> Use RawCull MCP to analyze `<absolute folder path>` for bursts. Report scanned/analyzed/skipped counts, similarity backend, and up to five recommendation/alternate pairs with confidence. Show the setup request ID while approval is pending and the catalog/job IDs afterward.

Approve or select the folder in RawCull when prompted. **Approve and Remember** saves a grant for that photo set.

### Assess the top two picks in every burst

> Assess every distinct saved recommendation/alternate pair from this chat’s completed burst job. Start a fresh pass using `burstId` only and rubric `["composition", "exposure", "subjectVisibility"]`. Process low, medium, high, then unclassified confidence, preserving source order within groups. Report progress every five pairs. Continue past pair errors unless the source becomes inaccessible. Report each burst’s ID/confidence/frame count, filenames/original ranks, findings/scores /5, occlusion, and evidence-supported keeper choice. Summarize listed/eligible/fully assessed/incomplete/skipped counts and reasons; list every attempted burst/request ID.

Repeating this prompt starts a new pass. Use **Resume** to reuse previous work.

### Check the full-burst assessment status

> Snapshot the assessment in chat `<exact chat title>` read-only, without messaging or steering it. Recover eligible bursts and actual submissions from its history/progress. Check requests sequentially. Count fully assessed pairs, active, failed/incomplete, not submitted, and unknown; claim “not submitted” only with complete history. Show gaps and latest request ID/state. Return promptly.

Use a separate chat while assessment runs; after it ends, “this chat” can replace the title.

### Resume an interrupted full-burst assessment

> Resume the full-burst assessment from `<progress JSON path>` and this chat’s actual submissions. Verify source IDs and submission history before submitting. Rebuild all eligible pairs; wait for active requests. Reuse results only when both saved photo IDs succeeded. Report previous failed/incomplete/unavailable or uncertain requests without replacing them. Submit only never-submitted pairs, using the original order/rubric/report format. Finish with combined coverage and request IDs; do not start new analysis.

### Review the closest calls

> Read all bursts from the completed job. Show up to five low-confidence saved pairs, prioritizing ties/closest recorded scores. Include burst IDs, filenames, confidence, returned reasons/cautions, and what to inspect. Report the actual count found. Read-only.

### Compare the recommendation and alternate

> Assess the lowest-confidence burst with two distinct saved picks from the completed job, after reading all pages. Order low/medium/high/unclassified, preserving source ties. Use `burstId` only and rubric `["composition", "exposure", "subjectVisibility"]`. Report burst ID/frame count, filenames/original ranks, findings/scores /5, occlusion/errors, and a keeper choice only if supported. Say if no eligible pair exists. Label the request **Burst comparison**.

### Assess photos from a completed burst job

> Assess exposure for `<up to four filenames>` from the completed job. Resolve photo IDs from its rankings; ask if missing/ambiguous. Use `photoIds` only and rubric `["exposure"]`. Report each filename’s score /5, evidence/errors, and issues worth inspecting. Label the request **Exposure assessment**.

## Repeat shoots

### Analyze the next shoot in the same folder

> Verify `<absolute folder path>` has a matching saved grant allowing analysis and recurring-folder access; stop if missing. Analyze its current photos as a fresh shoot. Report coverage and up to five recommendation/alternate pairs with confidence, plus setup/catalog/new job IDs.

Authorize the folder first in **Settings → MCP**, enabling **Allow MCP burst analysis and photo assessments** and **Allow analysis of future photos in this folder**. Finish previous follow-ups before starting a new shoot. To rerun the same photo set, use **Analyze a new catalog**.

## Status checks — read-only

### Check the MCP connection and catalog access

> Check `rawcull_status` and `list_catalogs`. Report helper/app versions, transport, analysis/assessment availability, assessment setting if reported, `burstId` support, saved catalog permissions, and errors.

### Check an analysis in progress

> Check this chat’s existing setup/job. Report approval needs or state/stage/progress; if completed, coverage and whether rankings remain readable. Show setup or catalog/job IDs. Ask for missing IDs; do not start work.

### Revisit a photo assessment

> Check `<assessment request ID, or latest in this chat>` using status/result tools only. Clarify missing/ambiguous or wrong-type IDs. Report state/errors, filenames, findings/scores /5, and per-photo failures; explain unavailable results. Show its original request ID and label.

Assessment results can remain available for up to 24 hours while the source job and approval are current.

## Script alternative — no prompt needed

The scripts implement polling, pagination, UUID retries, and saved JSON progress directly, without an LLM client:

```sh
python3 Scripts/PrepareBursts.py
python3 Scripts/AssessBursts.py
```

`PrepareBursts.py` exports rankings without photo assessments. `AssessBursts.py` runs assessments in source order and stops on a request failure; it does not implement the prompt’s low-confidence-first ordering or written comparisons. Both print resume commands. Wait for other RawCull clients to finish before running them. See [script usage and options](../Scripts/README.md#prepare-bursts-without-photo-assessments).
