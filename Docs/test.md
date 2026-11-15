# RawCull TestFlight test runs for builds 450–452

Use **/Users/thomas/Downloads** for the main catalog. Select that exact folder whenever a main-catalog prompt opens a picker. The replacement and recurring tests use copies of RAW photos in a temporary subfolder of Downloads so you can leave the originals in place.

## Before you start

1. Open the installed TestFlight copy. In **RawCull → About RawCull**, record the version and build. The original run used **3.4.6 (450)**. The November 15 rerun used build **451**. Quit with **⌘Q**.
2. Check that Downloads itself contains supported RAW photos, including at least one burst. RawCull's normal scan looks at files directly in the selected folder. If your RAW files are all nested, copy a representative set into Downloads before starting. Note the loaded photo count and a few known filenames. A folder with at least two bursts is needed to exercise burst pagination.
3. Start a fresh Codex chat for the run and use it throughout so Codex can refer to previous IDs. Paste one prompt at a time. When a prompt asks Codex to wait for you, send the follow-up after completing the UI action. Respond to pickers and approval sheets within 10 minutes except in the expiry test.
4. Paste the full Codex responses under the matching **Log** headings below. Include every follow-up response. Add your own UI observations, since Codex's tool output cannot show which sheets appeared. Mark each step **PASS**, **FAIL**, or **UNTESTED** and keep the exact tool error and request, catalog, and job IDs if available.

Results can contain filenames and camera metadata from Downloads. Check that you're comfortable sharing those in Codex before you authorize or run analysis. Keep one setup request or analysis job active at a time. A new job can replace the previous result, so collect the evidence for each step before starting the next.

## 1. Check the installed helper and existing access

With RawCull fully quit, paste this into the fresh chat.

> Use only the `rawcull` MCP server. Call `rawcull_status` and `list_catalogs`. Report the actual helper version, appBuild, transport, whether both setup tools are available, and each saved grant's display name, catalog ID, and analysis permission. Include any tool errors verbatim.

Expect helper **0.7.0**, the installed build number in `appBuild`, transport **stdio**, and both `request_catalog_setup` and `get_catalog_setup_status`. If the connection fails or the version differs, check `codex mcp get rawcull` in Terminal. The command should point to `/Applications/RawCull.app/Contents/MacOS/rawcull-mcp`. Start another fresh chat after correcting the registration or installed version.

If a grant exists, preserve the initial output as upgrade evidence. Start Step 2 with an empty grant list. When ready to remove the existing grant and its current result, open **Settings → MCP → Revoke Access**, quit RawCull, and repeat the prompt. If you want to keep that grant, defer Steps 2–5. Step 5 creates the Downloads grant needed by Step 6.

### Log 1

```bash
- Helper version: 0.7.0
- appBuild: null
- Transport: stdio
- Both setup tools available: Yes — request_catalog_setup and get_catalog_setup_status
- Saved grants: None (catalogs: []). Tool reported: “No catalog is authorized.”
- Tool errors: None
```

## 2. Cancel the folder picker and check the cooldown

Paste the first prompt. When RawCull appears, click **Choose Folder…**. Cancel the macOS picker without selecting a folder. Prepare to send the second prompt immediately after clicking Cancel. A manual send may miss the short cooldown window. If that happens, record the timing and proceed with the stated UI action.

> Use only `rawcull`. Submit exactly one `request_catalog_setup` with catalogHint "Downloads TestFlight picker check", jobType "burstAnalysis", and a fresh requestId. Show the request ID. Poll `get_catalog_setup_status` while I click Choose Folder… and cancel the macOS picker. Report the final state and any job ID. Call `list_catalogs` and report whether the list is empty.

> Use only `rawcull`. Immediately submit one `request_catalog_setup` with catalogHint "/Users/thomas/Downloads", jobType "burstAnalysis", and a fresh requestId. Report the UUID and exact response. If the helper reports a cooldown, stop after that call and wait for me. If an approval interaction opens, poll that same request while I select Downloads if asked and click Deny. Report the final state and any job ID.

Expect the picker cancellation to return `denied`, with no job ID and an empty grant list. A prompt sent during the first cooldown should return a wait time. When that time has passed, send the following if the cooldown blocked the second prompt.

> Retry the exact setup call that received the cooldown, using the same requestId, hint, and jobType. Poll while I select /Users/thomas/Downloads if asked and click Deny. Report final setup status, any job ID, and the current grant list.

On the approval sheet, verify that the resolved path is **/Users/thomas/Downloads** and the action is burst analysis. Denial should again leave no job or grant. Wait for the cooldown to pass before Step 3. Within the same 15-minute window, a second denial can increase the cooldown to 20 seconds.

### Log 2

```bash
Request UUID: 60e299f3-e90d-4fa7-8b74-0341772a0cd9
Exact response:
{"content":[{"type":"text","text":"A catalog setup request was declined. Wait at least 4 seconds and try again if the user wants to proceed."}],"isError":true}
The helper reported a cooldown. Stopped after that call; no state or job ID was returned.
```

## 3. Launch from a full quit, replay pending setup, and approve once

1. Quit RawCull with **⌘Q**. Send the first prompt. Leave the chooser visible and untouched until Codex returns the request ID and replay response.
2. Note whether the chooser appeared once and how it displayed the client-supplied hint. Choose **Choose Folder…**, select **/Users/thomas/Downloads**, and verify the resolved path.
3. Click **Approve This Job**. Keep RawCull open and send the second prompt.

> Use only `rawcull`. Submit `request_catalog_setup` with catalogHint "Downloads TestFlight one-time check", jobType "burstAnalysis", and a fresh requestId. If pending, replay the identical call once with the same requestId. Report both responses, including request state, request ID, and any job ID. Stop so I can inspect the chooser.

> Use only `rawcull`. Poll `get_catalog_setup_status` for the one-time request from Step 3. When queued, report its catalog and job IDs, then poll `get_analysis_status` to completion. Report the terminal state and coverage, including scanned, analyzed, skipped or unevaluated photos, and similarity backend when returned. On success, call `list_bursts` and show up to five recommendations with filenames, alternates, and confidence. Call `list_catalogs` and report whether the grant list is empty.

Expect one pending request and one approval interaction. Successful analysis should produce a completed job and coverage that matches your Downloads fixture. It should leave the saved grant list empty. Record any count differences and whether the returned filenames match the known bursts.

### Log 3

```bash
| Call | State | Request ID | Job ID |
|---|---|---|---|
| Initial | pendingApproval | 5B346EE9-0C87-435A-8C1C-A0A82E2142DA | None returned |
| Identical replay | pendingApproval | 5B346EE9-0C87-435A-8C1C-A0A82E2142DA | None returned |
Both responses said: Catalog setup: pendingApproval.
No errors. Stopped so you can inspect the chooser.
```

```bash
Analysis completed successfully.
- Request ID: 5B346EE9-0C87-435A-8C1C-A0A82E2142DA
- Catalog ID: 81927B3C-F7ED-4F27-82AD-E39C00D9FDA3
- Job ID: 339F6967-B556-45BF-9EE2-80DD40098F82
- Coverage: 958 scanned, 958 analyzed, 0 skipped, 0 unevaluated
- Similarity backend: clip for all 958 photos
- Bursts: 64
First five returned recommendations:
| Recommended filename | Alternate | Confidence |
|---|---|---|
| _DSC7712.ARW | _DSC7711.ARW | Low |
| _DSC7743.ARW | _DSC7741.ARW | Low |
| _DSC7756.ARW | _DSC7755.ARW | Low |
| _DSC7757.ARW | _DSC7759.ARW | Low |
| _DSC7766.ARW | _DSC7765.ARW | Low |
All five reported “Top two are close” and high ISO noise risk.
list_catalogs returned {"catalogs":[]} — the saved grant list is empty. No tool errors.
```

## 4. Read rankings after quitting, then clear the result

1. After Step 3 completes, quit RawCull with **⌘Q**. Send the first prompt.
2. Reopen RawCull. In **Settings → MCP**, look for **Last shared result**. Record the visible result details, then click **Clear Last Shared Result**. Send the second prompt.

> Use only `rawcull`. With RawCull quit, call `get_analysis_status` and `list_bursts` for the Step 3 catalog and job IDs. Compare coverage and the returned recommendations with Step 3. Replay the exact Step 3 setup call with its original requestId, catalogHint, and jobType. Report whether the original job ID is returned.

> Use only `rawcull`. I cleared the shared result. Call `get_analysis_status` and `list_bursts` for the exact Step 3 catalog and job IDs. Then replay the original Step 3 setup call and try `list_bursts` with any IDs it returns. Report each exact response or error and whether any coverage or rankings are still accessible. Call `list_catalogs` to check saved access.

Expect identical rankings before clearing. Afterwards the old IDs should provide no shared coverage or rankings. A replay receipt can still return the original IDs. The grant list should remain empty.

### Log 4

```bash
Both reads succeeded with RawCull quit. Results match Step 3:
- Analysis: completed
- Coverage: 958 scanned, 958 analyzed, 0 skipped, 0 unevaluated
- Similarity: clip for 958 photos; 64 bursts
- Returned recommendations, alternates, scores, and confidence were unchanged.
| Recommended | Alternate | Confidence |
|---|---|---|
| _DSC7712.ARW | _DSC7711.ARW | Low |
| _DSC7743.ARW | _DSC7741.ARW | Low |
| _DSC7756.ARW | _DSC7755.ARW | Low |
| _DSC7757.ARW | _DSC7759.ARW | Low |
| _DSC7766.ARW | _DSC7765.ARW | Low |
Replayed the exact setup call:
{"catalogHint":"Downloads TestFlight one-time check","jobType":"burstAnalysis","requestId":"5b346ee9-0c87-435a-8c1c-a0a82e2142da"}
Response state: queued. The original job ID was returned: 339F6967-B556-45BF-9EE2-80DD40098F82, with the original catalog ID 81927B3C-F7ED-4F27-82AD-E39C00D9FDA3.
No tool errors.
```

```bash
Exact response:

{"content":[{"type":"text","text":"Catalog setup: queued."},{"type":"text","text":"{\"catalogId\":\"81927B3C-F7ED-4F27-82AD-E39C00D9FDA3\",\"state\":\"queued\",\"createdAt\":816372734.408464,\"jobId\":\"339F6967-B556-45BF-9EE2-80DD40098F82\",\"jobType\":\"burstAnalysis\",\"requestId\":\"5B346EE9-0C87-435A-8C1C-A0A82E2142DA\"}"}],"structuredContent":{"catalogId":"81927B3C-F7ED-4F27-82AD-E39C00D9FDA3","createdAt":816372734.408464,"jobId":"339F6967-B556-45BF-9EE2-80DD40098F82","jobType":"burstAnalysis","requestId":"5B346EE9-0C87-435A-8C1C-A0A82E2142DA","state":"queued"}}

4. list_bursts with those returned IDs:

{"content":[{"type":"text","text":"That job was cleared, replaced, or revoked."}],"isError":true}

5. list_catalogs:

⚠ Heads up, you have less than 10% of your 5h limit left. Run /status for a breakdown.
Using catalog 81927B3C-F7ED-4F27-82AD-E39C00D9FDA3 and job 339F6967-B556-45BF-9EE2-80DD40098F82:

1. get_analysis_status returned:

{"content":[{"type":"text","text":"That job was cleared, replaced, or revoked."}],"isError":true}

2. list_bursts returned:

{"content":[{"type":"text","text":"That job was cleared, replaced, or revoked."}],"isError":true}

3. Replayed the original setup call:

{"catalogHint":"Downloads TestFlight one-time check","jobType":"burstAnalysis","requestId":"5b346ee9-0c87-435a-8c1c-a0a82e2142da"}

Exact response:

{"content":[{"type":"text","text":"Catalog setup: queued."},{"type":"text","text":"{\"catalogId\":\"81927B3C-F7ED-4F27-82AD-E39C00D9FDA3\",\"state\":\"queued\",\"createdAt\":816372734.408464,\"jobId\":\"339F6967-B556-45BF-9EE2-80DD40098F82\",\"jobType\":\"burstAnalysis\",\"requestId\":\"5B346EE9-0C87-435A-8C1C-A0A82E2142DA\"}"}],"structuredContent":{"catalogId":"81927B3C-F7ED-4F27-82AD-E39C00D9FDA3","createdAt":816372734.408464,"jobId":"339F6967-B556-45BF-9EE2-80DD40098F82","jobType":"burstAnalysis","requestId":"5B346EE9-0C87-435A-8C1C-A0A82E2142DA","state":"queued"}}

4. list_bursts with those returned IDs:

{"content":[{"type":"text","text":"That job was cleared, replaced, or revoked."}],"isError":true}

5. list_catalogs:

{"content":[{"type":"text","text":"No catalog is authorized."},{"type":"text","text":"{\"catalogs\":[]}"}],"structuredContent":{"catalogs":[]}}

No coverage or rankings remain accessible through these calls. The replay returns the original IDs and queued state, but reading the result still fails. Saved access is empty.
  Worked for 20s • 19:19
```
## 5. Remember Downloads and reuse it after a full quit

Quit RawCull and send the first prompt. Select Downloads if asked. Verify the path and click **Approve and Remember**. After the run completes, quit with **⌘Q** and send the second prompt.

> Use only `rawcull`. Request `burstAnalysis` for the exact path "/Users/thomas/Downloads" with a fresh requestId. Poll setup while I select the folder if asked and click Approve and Remember. Poll the job to completion. Report the request, catalog, and job IDs, final state, coverage, and whether `list_catalogs` shows an analysis-enabled grant with that catalog ID.

> Use only `rawcull`. RawCull is fully quit. Submit a fresh `request_catalog_setup` for "/Users/thomas/Downloads" and `burstAnalysis`. Poll setup and analysis. If setup needs my input, report its state and wait. Report the request ID, catalog ID, new job ID, terminal state, and photo counts.

Expect the saved grant to match the first job's catalog ID. The second job should reuse the catalog ID, have a different job ID, and complete without a picker or approval sheet. Keep Downloads unchanged during both runs.

### Log 5

```bash
Analysis completed for /Users/thomas/Downloads.

- Request ID: 4B9C6D02-865E-4A17-99F3-B7C8F126DE40
- Catalog ID: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE
- Job ID: B419EE1B-0E48-4B4D-A8FD-A0613AA1B94A
- Coverage: 958 scanned, 958 analyzed, 0 skipped, 0 unevaluated
- Results: 64 bursts, 0 singletons
- Similarity backend: clip for all 958 photos

list_catalogs confirms a saved Downloads grant with that exact catalog ID and analysisEnabled: true (recurringFolder: false).
```

```bash
The fresh request completed without needing your input. Setup initially returned pendingApproval, then polled as queued.

- Request ID: 743A6F90-81C2-4D09-A50B-10E378E50C84
- Catalog ID: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE
- New job ID: 4AD7F2BF-1FF7-42D0-AF2A-3752F4D5F538
- Terminal state: completed
- Photos: 958 scanned, 958 analyzed, 0 skipped, 0 unevaluated
- Results: 64 bursts, 0 singletons; clip similarity for all 958 photos

No tool errors.
```

## 6. Check metadata from the saved grant

Quit RawCull before sending the prompt.

> Use only `rawcull`. Call `list_catalogs`, then use the saved Downloads catalog ID for `catalog_summary` and `list_photos` with limit 5. Fetch the second page using the first page's nextCursor if present. Report the photo count, camera and date coverage, both pages, and whether their photo IDs overlap.

Expect the same count as the loaded catalog, metadata available with RawCull closed, and distinct photos on each page. If there are five or fewer photos, record the missing second page as expected.

### Log 6

```bash
Downloads catalog: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE

- Photos: 958
- Camera: SONY ILCE-1M2 (all 958)
- Capture coverage: May 6, 2026, 02:19:04–03:29:33 UTC
- Saved snapshot: November 14, 2026, 18:21:45 UTC

Both pages used limit 5. Photo IDs below show the suffix appended to the catalog ID.

| Page | ID suffix | Photo | Capture time (UTC, May 6) |
|---|---|---|---|
| 1 | :0 | _DSC7847.ARW | 02:22:56 |
| 1 | :1 | _DSC8590.ARW | 03:28:14 |
| 1 | :2 | _DSC8547.ARW | 03:26:21 |
| 1 | :3 | _DSC8023.ARW | 02:57:35 |
| 1 | :4 | _DSC8037.ARW | 02:57:39 |
| 2 | :5 | _DSC8221.ARW | 03:06:09 |
| 2 | :6 | _DSC7853.ARW | 02:22:59 |
| 2 | :7 | _DSC8584.ARW | 03:28:14 |
| 2 | :8 | _DSC8235.ARW | 03:06:14 |
| 2 | :9 | _DSC8553.ARW | 03:27:32 |

Page 2 used page 1’s nextCursor (80ACA98A-2225-4B49-B1AB-9370F7E1EDAE:5). Its next cursor ends in :10.

Photo ID overlap: none — 10 distinct IDs across both pages.
```
## 7. Force-quit a running job and verify recovery

1. Use the saved Downloads grant. Open the macOS **Force Quit Applications** window with **⌥⌘Esc** so it's ready.
2. Send the first prompt. Once Codex reports `running`, force-quit **RawCull**. If the run completed first, mark the interruption untested or retry with more RAW photos copied into Downloads. If you change the set, reauthorize Downloads for analysis before retrying.
3. Send the follow-up, then the recovery prompt once the interrupted job is terminal.

> Use only `rawcull`. Start one new setup request for "/Users/thomas/Downloads" using `burstAnalysis` and a fresh requestId. Report the request, catalog, and job IDs. Poll `get_analysis_status` until it first reports running or reaches a terminal state, then return immediately so I can force-quit RawCull while it is running.

> I force-quit RawCull after seeing running. Use only `rawcull`. Query the same catalog and job IDs with `get_analysis_status`. If the job is still active, poll every few seconds for up to one minute. Report the timing, terminal state, and exact message. Leave RawCull closed during this check.

> Use only `rawcull`. Start a fresh `burstAnalysis` setup request for "/Users/thomas/Downloads". Report its new request and job IDs, poll to completion, and report the terminal state and coverage. On success, fetch the first page of rankings.

Expect the live job to report `running`. For a new build 450 job, once the worker has exited and its lock is released, the next status reads should promptly report `failed` with a worker-exit message. The new job should complete.

### Log 7

```bash
Analysis first reported running at stage openingCatalog. Stopped polling; you can force-quit RawCull now.

- Request ID: 9C62AC5B-41D3-4976-AC28-40A0B761FDE9
- Catalog ID: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE
- Job ID: CD5820DF-30ED-456E-8A7E-A6210519764A
```

```bash
The first query returned terminal state failed immediately (0.013 seconds), so no further polling was needed. The failure timestamp was 73.28 seconds after the last heartbeat and 77.15 seconds after job creation.

Exact message:

> The RawCull analysis worker exited. Start a new job with a new request ID.

I made only the status query; no app-open or new-job request was sent.
```

```bash
Analysis completed in about 15.8 seconds.

- Request ID: 4BA1E5EC-A39D-40F1-B4C7-356A49D9C208
- Job ID: DA13168E-256C-4373-B6E3-D01F53A504FC
- Catalog ID: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE
- Coverage: 958/958 photos analyzed, 64 bursts, 0 singletons, 0 unevaluated, no skips. CLIP covered all 958 photos.

Fetched the first rankings page, containing 5 of 64 bursts:

| Burst | Frames | Recommended photo | Score | Alternate |
|---|---:|---|---:|---|
| 0 | 26 | _DSC7712.ARW | 0.377885 | _DSC7711.ARW |
| 1 | 20 | _DSC7743.ARW | 0.564368 | _DSC7741.ARW |
| 2 | 13 | _DSC7756.ARW | 0.393275 | _DSC7755.ARW |
| 3 | 5 | _DSC7757.ARW | 0.377129 | _DSC7759.ARW |
| 4 | 8 | _DSC7766.ARW | 0.399245 | _DSC7765.ARW |

All five have low confidence, with “Top two are close” and high-ISO noise cautions.

Next cursor: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE:DA13168E-256C-4373-B6E3-D01F53A504FC:5
```
## 8. Cancel an active job through MCP

Leave RawCull open. This test needs enough photos to get a `running` response before analysis finishes.

> Use only `rawcull`. Submit a fresh setup request for `burstAnalysis` at "/Users/thomas/Downloads". Report the IDs. Poll the returned job until it is running, then immediately call `cancel_analysis` with the same catalogId and jobId. Poll until terminal. Report the cancellation response, final status, and whether `list_catalogs` still shows the saved Downloads grant. If analysis finishes first, report that the cancellation test could not run.

Expect `cancelled` and the same saved grant.

### Log 8

```bash
The cancellation test succeeded.

- Request ID: B1D7E8A4-69F2-4C35-A028-5FD936BC7E10
- Catalog ID: 80ACA98A-2225-4B49-B1AB-9370F7E1EDAE
- Job ID: CC6AE07E-89C5-476F-AB8F-D2EA4FE2C228

Immediately after observing running, I called cancel_analysis with the same catalog and job IDs. It returned state: running, stage: scoringSharpness, and cancellationRequested: true.

The next poll reported terminal state cancelled: 958 files scanned, 0 analyzed.

list_catalogs still shows the saved Downloads grant with analysisEnabled: true.
```

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

```bash
Analysis completed.

- Request ID: A84C397F-21B6-4E59-91D3-07F2C8E64A10
- Catalog ID: CF3AED28-16A6-4DFD-8F81-C5441612B1ED
- Job ID: 7A1D6768-C6FC-4F15-8A8A-2E0B086486B7
- Coverage: 13/13 photos analyzed, 1 burst, 0 singletons, 0 unevaluated, no skips; CLIP covered all 13.

list_catalogs now shows only RawCull-TestFlight-Recurring, with the matching catalog ID and analysisEnabled: true. Downloads is no longer listed.

The grant reports recurringFolder: false, so the catalog change is confirmed, but that flag does not confirm a recurring-folder grant.
```

```bash
Confirmed RawCull-TestFlight-Recurring has analysisEnabled: true and recurringFolder: true.

The new analysis completed: 13 scanned, 13 analyzed, 1 burst, no skips or unevaluated photos.

- Request ID: D6A2E930-7F84-4CB1-9A65-E308B21F4C79
- Catalog ID: DC64BA70-F140-4B58-A969-ED4969C4F8BD
- Job ID: AC8F7D52-888A-4123-8626-F3FE33A7F688

Both listing calls used limit 1. The first photo was _DSC8644.ARW, ID:
DC64BA70-F140-4B58-A969-ED4969C4F8BD:AC8F7D52-888A-4123-8626-F3FE33A7F688:0

The first burst contains 13 frames. Its returned rankings were:

| Rank | Filename | Score |
|---|---|---:|
| 1 | _DSC8643.ARW | 0.9309999943 |
| 2 | _DSC8644.ARW | 0.9309999943 |
| 3 | _DSC8646.ARW | 0.9309999943 |
| 4 | _DSC8649.ARW | 0.9296809435 |
| 5 | _DSC8647.ARW | 0.9283439517 |

Recommended: _DSC8643.ARW; alternate: _DSC8644.ARW. Confidence: low; caution: “Top two are close.”

Exact cursors preserved for the next prompt:

- Photos nextCursor: DC64BA70-F140-4B58-A969-ED4969C4F8BD:AC8F7D52-888A-4123-8626-F3FE33A7F688:1
- Bursts nextCursor: null
```

```bash
The fresh analysis completed with 12 scanned and 12 analyzed, 1 burst, 0 singletons, 0 unevaluated, and no skips. CLIP covered all 12 photos.

- Request ID: F092B61D-8C43-4E75-A209-67D15B3C8E94
- Catalog ID: DC64BA70-F140-4B58-A969-ED4969C4F8BD
- Job ID: 50E59481-1053-47AF-A02A-8AC822258CD1

Filenames in returned order: _DSC8630.ARW, _DSC8631.ARW, _DSC8622.ARW, _DSC8625.ARW, _DSC8626.ARW, _DSC8627.ARW, _DSC8624.ARW, _DSC8623.ARW, _DSC8620.ARW, _DSC8621.ARW, _DSC8629.ARW, _DSC8628.ARW.

The 12-frame burst returned these rankings:

| Rank | Filename | Score |
|---|---|---:|
| 1 | _DSC8625.ARW | 0.9309999943 |
| 2 | _DSC8629.ARW | 0.9309999943 |
| 3 | _DSC8631.ARW | 0.9309999943 |
| 4 | _DSC8630.ARW | 0.9206074476 |
| 5 | _DSC8624.ARW | 0.9175561666 |

Recommended: _DSC8625.ARW; alternate: _DSC8629.ARW. Confidence: low; caution: “Top two are close.”

The first-run photo cursor, tested against the current catalog ID, was:
DC64BA70-F140-4B58-A969-ED4969C4F8BD:AC8F7D52-888A-4123-8626-F3FE33A7F688:1

Exact response:

{"content":[{"type":"text","text":"Invalid cursor. Use nextCursor from a page of this catalog snapshot."}],"isError":true}

The first-run burst cursor was null: untested, because no cursor was available.
```

## 10. Clear a result while keeping the grant, then revoke access

1. Use the most recent recurring catalog and job IDs. If rerunning this step after revoking access, authorize the recurring folder again and complete a fresh analysis first.
2. In **Settings → MCP**, verify that both **Authorized catalog** and **Last shared result** show the recurring folder. Click **Clear Last Shared Result** and record what both sections show afterward. Send the first prompt and save the response before continuing.
3. Click **Revoke Access** if enabled, record what Settings shows, quit RawCull, and send the second prompt.

> Use only `rawcull`. After I cleared the last shared result, call `list_catalogs`, `catalog_summary` for the recurring grant, and `get_analysis_status` and `list_bursts` for the last job. Report each actual response or error. Verify whether the grant and photo metadata remain available and whether the old coverage and rankings are blocked.

> Use only `rawcull`. I revoked access and quit RawCull. Call `list_catalogs`, then try `catalog_summary`, `get_analysis_status`, and `list_bursts` with the former catalog and job IDs. Report each actual response or error.

Expect clearing to preserve the grant and metadata while removing rankings. Revoking should empty the grant list and block reads using the former IDs.

### Log 10

```bash
Saved access, metadata, and old rankings are unavailable after clearing the shared result.

- list_catalogs: catalogs: [] — “No catalog is authorized.”
- catalog_summary for the previous recurring grant: “No authorized catalog matches that ID. Call list_catalogs for the current ID.”
- list_bursts for job 50E59481-1053-47AF-A02A-8AC822258CD1: “That job was cleared, replaced, or revoked.”

Both read attempts returned isError: true.
```

```bash
Used former catalog DC64BA70-F140-4B58-A969-ED4969C4F8BD and job 50E59481-1053-47AF-A02A-8AC822258CD1.

| Call | Actual response | Error |
|---|---|---|
| list_catalogs | “No catalog is authorized.” — {"catalogs":[]} | No |
| catalog_summary | “No authorized catalog matches that ID. Call list_catalogs for the current ID.” | isError: true |
| get_analysis_status | “No current job matches that catalog and job ID.” | isError: true |
| list_bursts | “That job was cleared, replaced, or revoked.” | isError: true |
```

```bash
The identical resubmission returned terminal state denied.

- Request ID: E3478A91-6F25-4DB0-A8C3-92B51E7D064F
- Original creation time: 816415263.532646
- Deadline: not provided
- Exact message: “Catalog setup was cancelled or denied in RawCull.”

No job ID was returned, so there is no analysis job to poll.
```


#### Build 451 rerun on 2026-11-15

The initial `rawcull_status` reported helper `0.7.0` and `appBuild: null`. The initial `list_catalogs` returned an empty list. After authorizing `/Users/thomas/Downloads/RawCull-TestFlight-Recurring` in RawCull, Codex confirmed an analysis-enabled recurring grant and ran a fresh `burstAnalysis`.

- Catalog ID `35A085F3-93DA-4879-9B96-6F0F1BD8ABD5`
- Job ID `F7225B70-836F-4B25-85AF-8B20760A0846`
- Terminal state `completed` with 12 photos analyzed and 1 burst

After **Clear Last Shared Result**:

```json
{"catalogs":[{"recurringFolder":true,"displayName":"RawCull-TestFlight-Recurring","id":"35A085F3-93DA-4879-9B96-6F0F1BD8ABD5","analysisEnabled":true}]}
```

```json
{"photoCount":12,"snapshotAt":"2026-11-15T06:52:00Z","earliestCaptureDate":"2026-05-06T03:29:30Z","cameraCounts":{"SONY ILCE-1M2":12},"scanStatus":"saved_snapshot","latestCaptureDate":"2026-05-06T03:29:31Z","catalogId":"35A085F3-93DA-4879-9B96-6F0F1BD8ABD5"}
```

Both `get_analysis_status` and `list_bursts` returned `isError: true` with “That job was cleared, replaced, or revoked.”

After **Revoke Access** and quitting RawCull:

| Call | Response |
| --- | --- |
| `list_catalogs` | “No catalog is authorized.” with `{"catalogs":[]}` |
| `catalog_summary` | `isError: true` with “No authorized catalog matches that ID. Call list_catalogs for the current ID.” |
| `get_analysis_status` | `isError: true` with “No current job matches that catalog and job ID.” |
| `list_bursts` | `isError: true` with “That job was cleared, replaced, or revoked.” |

**PASS** for the MCP clear and revoke checks. The Settings display after each action was unrecorded.

## 11. Quit and resume a pending setup request

With RawCull quit, send the first prompt. When the chooser appears, leave it unanswered and quit RawCull with **⌘Q**. Confirm the app quit, then send the second prompt before the 10-minute setup deadline. When the chooser returns, select Downloads and click **Approve This Job**.

> Use only `rawcull`. Make one new `request_catalog_setup` with catalogHint "Downloads TestFlight pending relaunch", jobType "burstAnalysis", and a fresh requestId. Return the request ID, state, and original creation time or deadline if available. Stop after the submission.

> Use only `rawcull`. RawCull quit with that request pending. Resubmit the identical Step 11 call with the original requestId, hint, and jobType. Report the returned state, ID, and creation time or deadline if provided. Poll while I select Downloads and approve once, then poll the job to completion. Report the job ID and terminal state.

Expect the same request to resume with its original creation time and deadline. Record whether RawCull reopened and whether the chooser returned.

### Log 11

#### Build 451 attempt on 2026-11-15

RawCull did not start and the chooser never appeared. The initial submission response was unrecorded. The identical resubmission and subsequent status poll both returned the following.

- Request ID `A978464F-12B8-4AA9-BDCB-55E0D4CE1DC2`
- State `denied`
- Original `createdAt` value `816418540.867627`
- Deadline and job ID were absent.
- Exact message “Catalog setup was cancelled or denied in RawCull.”

**FAIL** for launch and chooser visibility. **UNTESTED** for recovery after quitting with the chooser open because the chooser never appeared.

#### Build 451 retry

The replay returned:

```json
{
  "createdAt": 816418845.778556,
  "jobType": "burstAnalysis",
  "message": "Catalog setup was cancelled or denied in RawCull.",
  "requestId": "4CBBD8A2-13BE-4D75-9D38-76BC597F021E",
  "state": "denied"
}
```

RawCull did not reopen after replay. The replay was terminal and returned no job ID. Codex stopped after replay. The initial submission response and the chooser behavior before quitting are unrecorded for this retry.

#### Build 451 chooser check with RawCull already open

The folder chooser appeared after a fresh request while RawCull was running. After the tester clicked **Cancel**, one `get_catalog_setup_status` call returned the following.

- Request ID `A17E6D90-4B53-48AF-B2C8-5D093FC176EA`
- State `denied`
- Original `createdAt` value `816418969.398638`
- Exact message “Catalog setup was cancelled or denied in RawCull.”
- Job ID was absent. The request was checked once and was not replayed.

**PASS** for showing the chooser with RawCull already running and closing the request on cancellation.

#### Build 451 quit with the chooser open

With RawCull already running, the tester submitted a fresh request, left the folder chooser unanswered, and quit with **⌘Q**. The first `get_catalog_setup_status` call after quitting and the subsequent identical replay both returned:

```json
{
  "createdAt": 816419095.518444,
  "jobType": "burstAnalysis",
  "state": "denied",
  "message": "Catalog setup was cancelled or denied in RawCull.",
  "requestId": "7EB6C45F-9D2A-4FE8-A102-3C861B0D5749"
}
```

**FAIL** for quit-and-resume recovery. The first status check already returned a terminal denial, and replay preserved that state. Neither response contained a job ID. The initial submission payload and whether replay reopened RawCull were unrecorded.

#### Next check on build 451

The quit-and-resume failure is now reproduced with the chooser open. Investigate what transitions the request to `denied` during normal quit or on the first status read after exit. On a build with a fix, repeat the quit-with-chooser-open trial above. Use the full-quit launch check below to verify automatic launch separately.

1. Verify that `codex mcp get rawcull` points to the helper in the installed RawCull app. Check the installed build in About RawCull or the app's `Info.plist` and record it alongside the helper's `appBuild` response.
2. With the grant list empty and RawCull fully quit, send the first Step 11 prompt with a fresh request ID. Save the initial submission response before replaying it. Record whether the app launches and whether the chooser appears.
3. If the chooser appears, leave it unanswered and press **⌘Q**. Confirm the app exited and immediately send the second Step 11 prompt with the same request ID. Complete the one-time approval if the chooser returns.
4. If the app or chooser fails to appear, capture the request status before replaying. Once that request is terminal, open RawCull manually and retry the first prompt with a fresh request ID. Record whether the chooser appears with the app already open. If it appears, cancel it and record the terminal state to close the trial.

#### Local build retest with the quit-handling fix

The test used `rawcull-local` from `/Applications/RawCull-MCP-Test.app/Contents/MacOS/rawcull-mcp`. The helper reported version `0.7.0` and `appBuild: null`.

The initial submission returned `pendingApproval` for request `A2F87E1D-C954-4B06-9A73-028C1E64FB95`, with `createdAt: 816419940.57585`, hint `Downloads TestFlight pending relaunch`, and job type `burstAnalysis`. The tester reported that RawCull reopened. Setup finished under the original request ID and creation time.

- Catalog ID `4E16CB10-C654-4123-A9E5-6323D30896C4`
- Job ID `30EEF112-E6A9-459A-83D2-46B95B6B1779`
- Terminal state `completed` with 958 photos analyzed and 64 bursts

**PASS** for resuming the original request and completing analysis on the local build. The first post-quit status and replay response payloads were unrecorded.

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

### TestFlight build 452 release validation

Run on 2026-11-15 with RawCull 3.4.6 (452) and MCP helper 0.7.0 over stdio. **About RawCull** and the installed app’s `Info.plist` both reported 452. The registered helper path was `/Applications/RawCull.app/Contents/MacOS/rawcull-mcp`.

| Step | Release verdict | Evidence |
| --- | --- | --- |
| 1. Installed helper and access | **APPROVED** | Helper version, transport, both setup tools, and the empty initial grant list matched expectations. The connected helper returned `appBuild: null`. Accepted for this release. |
| 2. Picker cancellation and cooldown | **PASS on 452** | Picker cancellation returned `denied` with no job ID. The immediate follow-up was blocked for 10 seconds. Retrying with the same request ID opened setup. Explicit **Deny** returned `denied` with no job ID and no saved grant. |
| 3. Cold launch, replay, and approve once | **PASS on 452** | RawCull opened from a full quit and showed the chooser. Replay preserved the pending request ID and creation time. One-time job `45E6CBB2-D664-410A-91A6-DB05341E9225` analyzed 958 photos with CLIP, found 64 bursts, and left the grant list empty. |
| 4. Read after quit and clear | **PASS on 452** | Coverage and the first five rankings matched after quit. Clearing blocked status and rankings, including with the IDs returned by replay. The grant list stayed empty. |
| 5. Remember and reuse Downloads | **PASS on 452** | The analysis-enabled grant was saved. After a full quit, a fresh request reused the catalog ID without another approval and completed job `BC101DA1-5B2E-4E01-B9C3-F68E580CF79E` with 958 analyzed photos and 64 bursts. |
| 6. Saved metadata and pagination | **PASS on 452** | The saved snapshot reported 958 Sony ILCE-1M2 photos with capture-date coverage. Two pages returned 10 distinct photo IDs. |
| 7. Force-quit and recovery | **PASS carried forward from 450** | The 452 job completed before the force-quit interrupted it. Worker-exit recovery was untested on 452. |
| 8. Cancel a running job through MCP | **PASS on 452** | Job `230475FC-59E1-47AA-B8E7-CB9E36025D48` transitioned from `running` to `cancelled`. The Downloads grant remained analysis-enabled. |
| 9. Replace grant and refresh recurring folder | **PASS carried forward from 450 for MCP grant replacement, refresh, and photo cursor rejection** | The burst cursor check and Settings replacement UI remain unverified. Step 9 was deferred on 452. |
| 10. Clear result and revoke access | **PASS carried forward from 451 for the MCP checks** | Revocation on 452 left an empty grant list before Step 11. The full Step 10 sequence was deferred on 452. |
| 11. Quit with the chooser open and resume | **PASS on 452** | With the chooser unanswered, **⌘Q** left request `30BE848C-8C12-4285-9C56-9BCC08C5DD54` in `pendingApproval` on the first read after exit. Replay preserved its ID and creation time (`816422891.35488`), relaunched RawCull, and restored the chooser. One-time approval completed job `184BB754-E83B-464B-943D-15E38C0063F5` with 958 analyzed photos, 64 bursts, and no skipped or unevaluated photos. The grant list stayed empty. |
| 12–14. Expiry, hint limit, and ambiguous or unavailable hints | **DEFERRED** | Untested in this release run. |

**Release readiness: Ready for release.** The build 451 cold-launch and quit-and-resume failures both passed on TestFlight build 452. The observed `appBuild: null` is accepted and does not block release. The last-window-close variant and automated quit-versus-deny coverage remain open follow-ups.

### Local retest before build 452

- Step 11 **PASS** on the local build with the quit-handling fix. The original request resumed and analysis completed. Retest on the next TestFlight build and capture the first post-quit status and replay responses.
- Step 1 build reporting was fixed after the local retest. On the next TestFlight build, check that `rawcull_status.appBuild` matches **About RawCull**.
- Steps 12–14 are deferred and remain **UNTESTED** for this release run.

### Build 451 rerun

- The helper reported `0.7.0` and `appBuild: null`. Build reporting still fails.
- Step 10 passed the MCP clear and revoke checks. The Settings display was unrecorded.
- Step 11 failed on the full-quit launch attempt. With RawCull already running, the chooser appeared and cancellation worked. Quitting with the chooser unanswered also failed the recovery check. The first status check after exit already returned `denied`.

### Original build 450 run

- Reviewed on 2026-11-14. The macOS version was not recorded.
- Installed app version 3.4.6 (450). Helper version 0.7.0 over stdio.
- Downloads analysis scanned and analyzed all 958 photos with CLIP and returned 64 bursts. Sample recommendations include `_DSC7712.ARW` and `_DSC7743.ARW`. The fixture count and known filenames from the RawCull UI were not recorded independently.

| Step | Verdict | Evidence and follow-up |
| --- | --- | --- |
| 1. Helper and existing access | **FAIL** | `rawcull_status` returned `appBuild: null` on the original run and on review. The registered command points inside `/Applications/RawCull.app`, and that app's `Info.plist` reports build 450. Helper version, transport, tool discovery, and the empty grant list matched expectations. |
| 2. Picker cancellation and cooldown | **PASS** for cooldown, **UNTESTED** for the remaining checks | Request `60e299f3-e90d-4fa7-8b74-0341772a0cd9` returned a four-second wait. The log lacks the first request ID and terminal status, the grant list after cancellation, and the retry followed by **Deny**. |
| 3. One-time approval and replay | **PASS** for MCP, UI checks unverified | The replay returned the same pending request. Job `339F6967-B556-45BF-9EE2-80DD40098F82` completed and the grant list stayed empty. Record chooser and approval counts, displayed hint, resolved path, and the fixture comparison. |
| 4. Read and clear | **PASS** for MCP, Settings display unverified | Reads succeeded after quitting. Clearing blocked status and rankings even when replay returned the original IDs. The grant list stayed empty. Record what **Last shared result** showed before clearing. |
| 5. Remember and reuse | **PASS** for MCP, sheet visibility unverified | The second job reused catalog `80ACA98A-2225-4B49-B1AB-9370F7E1EDAE` with a fresh job ID and matching coverage. Setup briefly returned `pendingApproval` before queuing without input. Record whether either sheet appeared during the second run. |
| 6. Metadata from saved grant | **PASS** for MCP | The Downloads snapshot returned 958 photos with camera and capture-date coverage. Two pages returned 10 distinct photo IDs. |
| 7. Force-quit and recovery | **PASS** | The running job reported `failed` on the first status query after force-quit, with the worker-exit message. A fresh job analyzed all 958 photos and returned rankings. |
| 8. Cancel an active job | **PASS** | Cancellation was requested while the job was running. The next poll returned `cancelled`, and the saved Downloads grant remained analysis-enabled. |
| 9. Replace grant and refresh recurring folder | **PASS** for MCP grant replacement, refresh, and photo cursor rejection. Burst cursor **UNTESTED**. | The recurring run reflected the change from 13 to 12 photos and rejected the old photo cursor. The first run contained one burst and returned no burst cursor. The Settings replacement notice and refresh remain unverified. |
| 10. Clear result and revoke access | **FAIL** for clearing. Post-revoke reads blocked. | Clearing blocked rankings, but the grant list was already empty and metadata was unavailable before revocation. The post-revoke calls also showed no saved access and blocked reads with the former IDs. |
| 11–14 | **UNTESTED** | Logs 11–14 have no complete results. |

### Historical follow-ups from the build 450 run

1. To diagnose Step 1, run `codex mcp get rawcull` and `/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' /Applications/RawCull.app/Contents/Info.plist`. If the registered command points to a standalone helper, register the bundled helper and start a fresh chat. This run already had the expected registration and installed build.
2. The updated helper reads `CFBundleVersion` from the validated enclosing app's `Contents/Info.plist`. In a fresh chat using the bundled helper, confirm that `appBuild` matches the installed build. A standalone helper should still report `null`.
3. On the Step 2 rerun, save the first request ID, record `denied` with no job ID and an empty grant list, and capture the second request's cooldown response. After the wait, retry the exact second request with the same UUID. Verify the approval sheet path and action, click **Deny**, and record the terminal status, job ID field, and grant list.
4. Add any UI observations you can confirm from the original run to Logs 3–5. Record the remaining observations when repeating those steps in order, since Step 4 uses the shared result from Step 3.
