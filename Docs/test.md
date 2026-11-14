# RawCull 3.4.6 (450) TestFlight test run

Use **/Users/thomas/Downloads** for the main catalog. Select that exact folder whenever a main-catalog prompt opens a picker. The replacement and recurring tests use copies of RAW photos in a temporary subfolder of Downloads so you can leave the originals in place.

## Before you start

1. Open the installed TestFlight copy. In **RawCull → About RawCull**, confirm version **3.4.6 (450)**. Quit with **⌘Q**.
2. Check that Downloads itself contains supported RAW photos, including at least one burst. RawCull's normal scan looks at files directly in the selected folder. If your RAW files are all nested, copy a representative set into Downloads before starting. Note the loaded photo count and a few known filenames. A folder with at least two bursts is needed to exercise burst pagination.
3. Start a fresh Codex chat for the run and use it throughout so Codex can refer to previous IDs. Paste one prompt at a time. When a prompt asks Codex to wait for you, send the follow-up after completing the UI action. Respond to pickers and approval sheets within 10 minutes except in the expiry test.
4. Paste the full Codex responses under the matching **Log** headings below. Include every follow-up response. Add your own UI observations, since Codex's tool output cannot show which sheets appeared. Mark each step **PASS**, **FAIL**, or **UNTESTED** and keep the exact tool error and request, catalog, and job IDs if available.

Results can contain filenames and camera metadata from Downloads. Check that you're comfortable sharing those in Codex before you authorize or run analysis. Keep one setup request or analysis job active at a time. A new job can replace the previous result, so collect the evidence for each step before starting the next.

## 1. Check the installed helper and existing access

With RawCull fully quit, paste this into the fresh chat.

> Use only the `rawcull` MCP server. Call `rawcull_status` and `list_catalogs`. Report the actual helper version, appBuild, transport, whether both setup tools are available, and each saved grant's display name, catalog ID, and analysis permission. Include any tool errors verbatim.

Expect helper **0.7.0**, build **450**, transport **stdio**, and both `request_catalog_setup` and `get_catalog_setup_status`. If the connection fails or the version differs, check `codex mcp get rawcull` in Terminal. The command should point to `/Applications/RawCull.app/Contents/MacOS/rawcull-mcp`. Start another fresh chat after correcting the registration or installed version.

If a grant exists, preserve the initial output as upgrade evidence. Steps 2–5 require an empty grant list. When ready to remove the existing grant and its current result, open **Settings → MCP → Revoke Access**, quit RawCull, and repeat the prompt. If you want to keep that grant, mark Steps 2–5 untested.

### Log 1

Paste Codex output and UI notes here.

## 2. Cancel the folder picker and check the cooldown

Paste the first prompt. When RawCull appears, click **Choose Folder…**. Cancel the macOS picker without selecting a folder. Prepare to send the second prompt immediately after clicking Cancel. A manual send may miss the short cooldown window. If that happens, record the timing and proceed with the stated UI action.

> Use only `rawcull`. Submit exactly one `request_catalog_setup` with catalogHint "Downloads TestFlight picker check", jobType "burstAnalysis", and a fresh requestId. Show the request ID. Poll `get_catalog_setup_status` while I click Choose Folder… and cancel the macOS picker. Report the final state and any job ID. Call `list_catalogs` and report whether the list is empty.

> Use only `rawcull`. Immediately submit one `request_catalog_setup` with catalogHint "/Users/thomas/Downloads", jobType "burstAnalysis", and a fresh requestId. Report the UUID and exact response. If the helper reports a cooldown, stop after that call and wait for me. If an approval interaction opens, poll that same request while I select Downloads if asked and click Deny. Report the final state and any job ID.

Expect the picker cancellation to return `denied`, with no job ID and an empty grant list. A prompt sent during the first cooldown should return a wait time. When that time has passed, send the following if the cooldown blocked the second prompt.

> Retry the exact setup call that received the cooldown, using the same requestId, hint, and jobType. Poll while I select /Users/thomas/Downloads if asked and click Deny. Report final setup status, any job ID, and the current grant list.

On the approval sheet, verify that the resolved path is **/Users/thomas/Downloads** and the action is burst analysis. Denial should again leave no job or grant. Wait for the cooldown to pass before Step 3. Within the same 15-minute window, a second denial can increase the cooldown to 20 seconds.

### Log 2

Paste both responses, any retry, and what you saw in RawCull.

## 3. Launch from a full quit, replay pending setup, and approve once

1. Quit RawCull with **⌘Q**. Send the first prompt. Leave the chooser visible and untouched until Codex returns the request ID and replay response.
2. Note whether the chooser appeared once and how it displayed the client-supplied hint. Choose **Choose Folder…**, select **/Users/thomas/Downloads**, and verify the resolved path.
3. Click **Approve This Job**. Keep RawCull open and send the second prompt.

> Use only `rawcull`. Submit `request_catalog_setup` with catalogHint "Downloads TestFlight one-time check", jobType "burstAnalysis", and a fresh requestId. If pending, replay the identical call once with the same requestId. Report both responses, including request state, request ID, and any job ID. Stop so I can inspect the chooser.

> Use only `rawcull`. Poll `get_catalog_setup_status` for the one-time request from Step 3. When queued, report its catalog and job IDs, then poll `get_analysis_status` to completion. Report the terminal state and coverage, including scanned, analyzed, skipped or unevaluated photos, and similarity backend when returned. On success, call `list_bursts` and show up to five recommendations with filenames, alternates, and confidence. Call `list_catalogs` and report whether the grant list is empty.

Expect one pending request and one approval interaction. Successful analysis should produce a completed job and coverage that matches your Downloads fixture. It should leave the saved grant list empty. Record any count differences and whether the returned filenames match the known bursts.

### Log 3

Paste the initial and replay responses, analysis output, and your chooser and approval observations.

## 4. Read rankings after quitting, then clear the result

1. After Step 3 completes, quit RawCull with **⌘Q**. Send the first prompt.
2. Reopen RawCull. In **Settings → MCP**, look for **Last shared result**. Record the visible result details, then click **Clear Last Shared Result**. Send the second prompt.

> Use only `rawcull`. With RawCull quit, call `get_analysis_status` and `list_bursts` for the Step 3 catalog and job IDs. Compare coverage and the returned recommendations with Step 3. Replay the exact Step 3 setup call with its original requestId, catalogHint, and jobType. Report whether the original job ID is returned.

> Use only `rawcull`. I cleared the shared result. Call `get_analysis_status` and `list_bursts` for the exact Step 3 catalog and job IDs. Then replay the original Step 3 setup call and try `list_bursts` with any IDs it returns. Report each exact response or error and whether any coverage or rankings are still accessible. Call `list_catalogs` to check saved access.

Expect identical rankings before clearing. Afterwards the old IDs should provide no shared coverage or rankings. A replay receipt can still return the original IDs. The grant list should remain empty.

### Log 4

Paste both responses and what Settings showed before and after clearing.

## 5. Remember Downloads and reuse it after a full quit

Quit RawCull and send the first prompt. Select Downloads if asked. Verify the path and click **Approve and Remember**. After the run completes, quit with **⌘Q** and send the second prompt.

> Use only `rawcull`. Request `burstAnalysis` for the exact path "/Users/thomas/Downloads" with a fresh requestId. Poll setup while I select the folder if asked and click Approve and Remember. Poll the job to completion. Report the request, catalog, and job IDs, final state, coverage, and whether `list_catalogs` shows an analysis-enabled grant with that catalog ID.

> Use only `rawcull`. RawCull is fully quit. Submit a fresh `request_catalog_setup` for "/Users/thomas/Downloads" and `burstAnalysis`. Poll setup and analysis. If setup needs my input, report its state and wait. Report the request ID, catalog ID, new job ID, terminal state, and photo counts.

Expect the saved grant to match the first job's catalog ID. The second job should reuse the catalog ID, have a different job ID, and complete without a picker or approval sheet. Keep Downloads unchanged during both runs.

### Log 5

Paste both responses and note whether any sheets appeared on the second run.

## 6. Check metadata from the saved grant

Quit RawCull before sending the prompt.

> Use only `rawcull`. Call `list_catalogs`, then use the saved Downloads catalog ID for `catalog_summary` and `list_photos` with limit 5. Fetch the second page using the first page's nextCursor if present. Report the photo count, camera and date coverage, both pages, and whether their photo IDs overlap.

Expect the same count as the loaded catalog, metadata available with RawCull closed, and distinct photos on each page. If there are five or fewer photos, record the missing second page as expected.

### Log 6

Paste the output and your comparison with RawCull.

## 7. Force-quit a running job and verify recovery

1. Use the saved Downloads grant. Open the macOS **Force Quit Applications** window with **⌥⌘Esc** so it's ready.
2. Send the first prompt. Once Codex reports `running`, force-quit **RawCull**. If the run completed first, mark the interruption untested or retry with more RAW photos copied into Downloads. If you change the set, reauthorize Downloads for analysis before retrying.
3. Send the follow-up, then the recovery prompt once the interrupted job is terminal.

> Use only `rawcull`. Start one new setup request for "/Users/thomas/Downloads" using `burstAnalysis` and a fresh requestId. Report the request, catalog, and job IDs. Poll `get_analysis_status` until it first reports running or reaches a terminal state, then return immediately so I can force-quit RawCull while it is running.

> I force-quit RawCull after seeing running. Use only `rawcull`. Query the same catalog and job IDs with `get_analysis_status`. If the job is still active, poll every few seconds for up to one minute. Report the timing, terminal state, and exact message. Leave RawCull closed during this check.

> Use only `rawcull`. Start a fresh `burstAnalysis` setup request for "/Users/thomas/Downloads". Report its new request and job IDs, poll to completion, and report the terminal state and coverage. On success, fetch the first page of rankings.

Expect the live job to report `running`. For a new build 450 job, once the worker has exited and its lock is released, the next status reads should promptly report `failed` with a worker-exit message. The new job should complete.

### Log 7

Paste the three responses and record when you force-quit and when failure appeared.

## 8. Cancel an active job through MCP

Leave RawCull open. This test needs enough photos to get a `running` response before analysis finishes.

> Use only `rawcull`. Submit a fresh setup request for `burstAnalysis` at "/Users/thomas/Downloads". Report the IDs. Poll the returned job until it is running, then immediately call `cancel_analysis` with the same catalogId and jobId. Poll until terminal. Report the cancellation response, final status, and whether `list_catalogs` still shows the saved Downloads grant. If analysis finishes first, report that the cancellation test could not run.

Expect `cancelled` and the same saved grant.

### Log 8

Paste the output and any UI observations.

## 9. Replace the saved grant and test a recurring folder

In Finder, create **/Users/thomas/Downloads/RawCull-TestFlight-Recurring**. Put copies of a small set of RAW photos in it. Prepare a second set with different names and a different count. Use multiple distinct bursts in the first set if possible so you can get a burst cursor. Keep both sets' originals in Downloads.

1. Keep **Settings → MCP** open while sending the first prompt. If a picker opens, select **RawCull-TestFlight-Recurring**. On the approval sheet, look for the saved-grant replacement notice before clicking **Approve and Remember**. After analysis, check that Settings now shows the subfolder.
2. Open the subfolder as a catalog in RawCull and let it load. In **Settings → MCP**, enable **Allow MCP to start burst analysis** and **Allow analysis of future photos in this folder**, then click **Authorize Selected Catalog**. Send the second prompt while the first set is still in the folder.
3. Once the run finishes, move the first set's copies out of the subfolder and put in the second set. Keep the folder itself at the same path. Quit RawCull and send the third prompt.

> Use only `rawcull`. Request `burstAnalysis` for "/Users/thomas/Downloads/RawCull-TestFlight-Recurring" with a fresh requestId. Poll while I choose Approve and Remember, then poll analysis to completion. Report the IDs, coverage, and current grants. Check that the saved grant is now for RawCull-TestFlight-Recurring.

> Use only `rawcull`. Check that `list_catalogs` shows an analysis-enabled recurringFolder grant for RawCull-TestFlight-Recurring. If present, submit a new setup request for the exact path "/Users/thomas/Downloads/RawCull-TestFlight-Recurring" with jobType "burstAnalysis". Poll to completion. Report scanned and analyzed counts and capture the IDs, first photo filenames, and first burst rankings. Use limit 1 for `list_photos` and `list_bursts` and preserve the actual nextCursor values for the next prompt.

> Use only `rawcull`. I replaced the photos in "/Users/thomas/Downloads/RawCull-TestFlight-Recurring". Submit a fresh `burstAnalysis` setup request for that exact path and poll to completion. Report the new IDs, coverage, filenames, and rankings. Try the first run's photo cursor against the current catalog ID and its burst cursor against the new job ID. Report each exact response. If either first-run cursor was absent, mark that cursor check untested.

Expect Settings to refresh after grant replacement. The second recurring job should reflect the new photo count and filenames, and reject the old cursors. Compare the two runs with your actual fixture contents. If no bursts are found, log the coverage and mark burst-specific checks untested.

### Log 9

Paste all three responses. List both fixture counts and filenames, and note what the replacement sheet and Settings showed.

## 10. Clear a result while keeping the grant, then revoke access

1. In **Settings → MCP**, click **Clear Last Shared Result** and send the first prompt.
2. Click **Revoke Access**, quit RawCull, and send the second prompt. Use the most recent recurring IDs.

> Use only `rawcull`. After I cleared the last shared result, call `list_catalogs`, `catalog_summary` for the recurring grant, and `list_bursts` for the last job. Report whether saved access and metadata are still available and whether the old rankings can be read.

> Use only `rawcull`. I revoked access and quit RawCull. Call `list_catalogs`, then try `catalog_summary`, `get_analysis_status`, and `list_bursts` with the former catalog and job IDs. Report each actual response or error.

Expect clearing to preserve the grant and metadata while removing rankings. Revoking should empty the grant list and block reads using the former IDs.

### Log 10

Paste both responses and your Settings observations.

## 11. Quit and resume a pending setup request

With RawCull quit, send the first prompt. When the chooser appears, leave it unanswered and quit RawCull with **⌘Q**. Confirm the app quit, then send the second prompt before the 10-minute setup deadline. When the chooser returns, select Downloads and click **Approve This Job**.

> Use only `rawcull`. Make one new `request_catalog_setup` with catalogHint "Downloads TestFlight pending relaunch", jobType "burstAnalysis", and a fresh requestId. Return the request ID, state, and original creation time or deadline if available. Stop after the submission.

> Use only `rawcull`. RawCull quit with that request pending. Resubmit the identical Step 11 call with the original requestId, hint, and jobType. Report the returned state, ID, and creation time or deadline if provided. Poll while I select Downloads and approve once, then poll the job to completion. Report the job ID and terminal state.

Expect the same request to resume with its original creation time and deadline. Record whether RawCull reopened and whether the chooser returned.

### Log 11

Paste both responses and the observed sequence.

## 12. Check setup expiry at each screen

Each trial takes about 10 minutes. Run the three trials separately using the prompt below. Start with the unmatched hint in the prompt for each trial.

1. **Chooser.** Leave **Choose a catalog for burst analysis** open.
2. **Picker.** Click **Choose Folder…** promptly and leave the macOS folder picker open.
3. **Approval.** Choose **/Users/thomas/Downloads** promptly and leave the approval sheet open.

For each trial, wait until just over 10 minutes after submission, then send the follow-up. Observe whether the open screen closes on its own or when status is next checked. For the final trial, run the recovery prompt and select Downloads and approve once. This confirms a new request works after expiry.

> Use only `rawcull`. Submit one `request_catalog_setup` with catalogHint "Downloads TestFlight expiry check", jobType "burstAnalysis", and a fresh requestId. Report the new ID, creation time if available, and initial state. Return now so I can leave the test screen open.

> The Step 12 request is over 10 minutes old. Use only `rawcull`. Call `get_catalog_setup_status` with the current trial's original requestId. Report the state, exact message, and any job ID.

> Use only `rawcull`. Start a fresh setup request for "/Users/thomas/Downloads" using `burstAnalysis` and a fresh requestId. Poll while I select Downloads if asked and approve once. Report whether setup queued and whether analysis completed.

Expect `failed` with an expiry message and no job ID for each expired trial. Wait for any reported cooldown before attempting recovery.

### Log 12

Paste a separate set of output and UI notes for the chooser, picker, approval, and recovery.

## 13. Check the catalog hint limit

Send the prompt with no setup pending. Watch whether a RawCull interaction appears.

> Use only `rawcull`. Build a catalogHint consisting of exactly 513 ASCII lowercase a characters and submit one `request_catalog_setup` with that literal string, jobType "burstAnalysis", and a fresh requestId. Report the length you submitted, the requestId, and the exact response. If the helper accepts it and opens a chooser, report that so I can cancel it.

Expect an error mentioning the **512 Unicode scalar** limit and no chooser or job.

### Log 13

Paste the response and whether RawCull opened a sheet.

## 14. Check ambiguous and unavailable catalog hints

All photos for this optional edge-case step can stay in Downloads. Use copies to create **/Users/thomas/Downloads/Test-A/RawCull-TestFlight-SameName** and **/Users/thomas/Downloads/Test-B/RawCull-TestFlight-SameName**. Open both catalogs in RawCull so both are known. Use the first prompt and cancel the picker if it opens. If RawCull instead shows approval for a specific folder, deny it and record which path appeared.

For the unavailable-path trial, rename the copy under **Test-B** to **RawCull-TestFlight-Moved** in Finder. Wait for any cooldown after cancelling the first trial. Use the second prompt with the original path. If a picker appears, open it and cancel. This simulates a moved folder within Downloads. A removable-volume disconnect is a separate test if you have that fixture.

> Use only `rawcull`. Submit a fresh `request_catalog_setup` with only "RawCull-TestFlight-SameName" as catalogHint and jobType "burstAnalysis". Poll while I check the RawCull UI and cancel folder selection. Report the request ID, terminal state, and whether any job ID was returned.

> Use only `rawcull`. Submit a fresh `request_catalog_setup` for the old exact path "/Users/thomas/Downloads/Test-B/RawCull-TestFlight-SameName" and jobType "burstAnalysis". Report any error or request state, and poll while I cancel the picker if it appears. Report the terminal state, message, and any job ID. If a job queues, report its IDs and state so I can investigate the selected source.

Expect the ambiguous hint to ask which folder to use. An unavailable exact path should prompt for a readable folder or report an actionable error. Cancelling a picker should return `denied` with no job ID.

### Log 14

Paste both responses. Note exactly which UI appeared and any resolved path shown.

## Run summary

- Date and macOS version
- App build and helper version
- Main catalog count and sample filenames
- Steps passed, failed, and untested
- Most useful request and job IDs for any failures
- Any screenshots or observations that differ from the tool output
