# RawCull MCP prompts

Use these prompts to open a photo folder in RawCull, analyze it, and get a ranked burst list with the findings that matter for culling. Replace placeholders in angle brackets with your own values. Use the folder’s full Mac path, such as `/Users/you/Pictures/LatestShoot`.

## Where these prompts work

Use **Codex on your Mac** with the `rawcull` MCP server configured to launch the helper bundled in the installed RawCull app over local `stdio`. Prompt-driven setup and analysis were verified with the signed TestFlight app and helper `0.6.0`. For connection and verification steps, see [RawCull MCP setup](mcp.md#test-the-bundled-helper-with-testflight).

RawCull runs the analysis on your Mac. The MCP server returns filenames, ranked candidates, scores, and coverage to the client, which may send those results to its model provider. Other clients need local stdio MCP support and are unverified for this workflow. Image previews and saved review drafts require future tools.

| Catalog state | Prompt | What to expect in RawCull |
| --- | --- | --- |
| New folder or no analysis grant for this folder | [Analyze a new catalog](#analyze-a-new-catalog) | RawCull can launch from a full quit. Select the intended folder if asked and approve the job. |
| Same photos in a folder with a saved analysis grant | [Analyze a remembered catalog again](#analyze-a-remembered-catalog-again) | RawCull can launch and reuse the grant without another approval. This passed from a full quit on TestFlight build `449`. |
| New photos in the same folder with a recurring analysis grant | [Analyze the next shoot in the same folder](#analyze-the-next-shoot-in-the-same-folder) | RawCull rescans the folder and refreshes the saved photo list on success. Signed TestFlight verification for replacing photos is still open. |
| Completed job with results still available | [Review the closest calls](#review-the-closest-calls) | Reads the completed rankings with RawCull open or closed. A new job can replace the previous result. |

Keep RawCull open while analysis runs. Send one analysis request at a time. Starting a new run uses a fresh request UUID. A retry of the same submission uses its original UUID.

## Analyze a new catalog

> Use the `rawcull` MCP server to open and analyze the catalog at `<absolute folder path>`. Submit `request_catalog_setup` with the exact path, job type `burstAnalysis`, and a fresh request UUID. If RawCull needs me to choose a folder or approve the job, tell me what to do and wait while polling setup. When it queues, use the returned catalog and job IDs to poll analysis to completion. If setup is denied or the job fails, report the reason and stop. On success, page through the ranked bursts and show up to ten in a table with burst ID, frame count, recommended filename, alternate filename, scores when available, and confidence. Report the total number of bursts and how many are shown. Summarize the most important findings, including close picks, recurring cautions, and any gaps in coverage. Include photos scanned and analyzed, singleton and unevaluated counts, any reasons for skipped photos, the similarity backend, and the job ID.

In RawCull, choose **Approve This Job** for one run or **Approve and Remember** to reuse the grant for the same set of photos. Choose the exact folder in the picker if it appears.

## Analyze a remembered catalog again

> Use the `rawcull` MCP server to run a new burst analysis of `<absolute folder path>` using its saved analysis grant. Submit `request_catalog_setup` for the exact path with job type `burstAnalysis` and a fresh request UUID. If RawCull still needs folder selection or approval, tell me and wait for my response. Poll the queued job to completion using its returned catalog and job IDs. If it fails, report RawCull’s reason. On success, read the ranked bursts and give me up to ten recommended frames with their alternates, scores when available, and confidence. Report the number of bursts and photos scanned and analyzed, and highlight the closest picks, recurring cautions, and any unevaluated photos. Include the job ID.

A saved grant from **Approve and Remember** is tied to the approved photo snapshot. If you replace the photos between shoots, use the recurring folder setup below.

## Analyze the next shoot in the same folder

Set this up once in RawCull. Open the folder, let the photos load, then go to **Settings → MCP**. Turn on **Allow MCP to start burst analysis** and **Allow analysis of future photos in this folder**, then choose **Authorize Selected Catalog**. That grant covers future photos placed in the same folder. Wait for each run to finish before replacing the files again.

> Use the `rawcull` MCP server to analyze the current photos in my recurring shoot folder at `<absolute folder path>`. Use `list_catalogs` to check for an analysis-enabled grant with `recurringFolder` enabled and a display name matching the folder. If there is no such grant, tell me how to enable it and stop. The grant list omits paths, so use the exact path for setup. Otherwise submit `request_catalog_setup` for the exact path with job type `burstAnalysis` and a fresh request UUID. Tell me if setup needs my attention. Poll the new job to completion and use its returned IDs to read the current rankings. On success, report the counts scanned and analyzed, the total bursts, the job ID, and up to ten bursts with their recommended frames, alternates, scores when available, and confidence. Highlight the close picks, recurring cautions, and any coverage gaps. If the job fails, report RawCull’s reason.

Use the new job’s results for each shoot. A successful recurring run refreshes photo IDs and pagination cursors.

## Review the closest calls

> Use `rawcull` to read the completed burst analysis for catalog `<catalog ID>` and job `<job ID>`. Follow `list_bursts` cursors until you find five low-confidence bursts or reach the end. For each, show the recommended frame and alternate, both scores when available, and the reasons or cautions RawCull returned. Call out any ties and tell me which pairs to compare first in RawCull. If there are fewer than five, report how many you found. Base the report on the ranking evidence returned by RawCull.

Use this follow-up in the same chat by referring to “the job you just completed” in place of the two IDs.
