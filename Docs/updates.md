# RawCull MCP review and update plan

The original static review examined `052764e`. Validation at `5c9f167f` found only documentation changes between those commits. The findings below reflect that code, the signed TestFlight results, and a local Swift Foundation check for Unicode filtering. The lifecycle failure cases were inspected in source. They still need targeted reproduction. This document proposes changes for a second review before implementation.

The signed workflow is the baseline. Build 448 verified setup, picker cancellation, denial, one-time approval, result retrieval after quitting, and idempotent replay. Build 449 verified cold-launch approval with a saved grant, reuse of that grant after quitting, and rankings for all five bursts in an 809-photo catalog. Ambiguous names and disconnected sources were exercised in the earlier Rekdal run. See [TestFlight results](mcp.md#testflight-results) and [user prompts](prompts.md).

## Findings and evidence

### 1. One-time analysis results lack a clear control in Settings

**Original severity — High. Confirmed consent and retention gap.**

- For a job using setup approval, the helper skips saved-grant checks and instead verifies the current catalog and job IDs. Both `list_bursts` and `get_analysis_status` can be called with those IDs. A client with the setup request UUID can retrieve the IDs from its setup receipt. This is access by possession of the IDs among clients that can reach the local helper. [AnalysisTools.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L138) · [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L276)
- Completed jobs have no expiry. The shared `analysis-job.json` can retain ranked filenames, scores, and coverage across app restarts for as long as the job occupies the sole slot. A later job, authorization, or successful revocation can remove or replace it. [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L87) · [CatalogGrantStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/CatalogGrantStore.swift#L61)
- **Approve This Job** creates no new catalog grant. With no saved grant and no storage error, Settings reports no authorized catalog and disables **Revoke Access**, even though the last result may still be shareable. The approval sheet says RawCull will share ranked bursts. It gives no retention information. [MCPSettingsTab.swift](../RawCull/Views/Settings/MCPSettingsTab.swift#L47) · [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L215)
- Retrieving the results after quit is intentional and passed the signed walkthrough. The usability and consent gap is the lack of visibility and a clear way to end future sharing. Results already delivered may remain with the client.

### 2. Client-supplied text and repeated prompts

**Original severity — Medium. The prompt path is confirmed. The Unicode claim was partly incorrect.**

- The helper limits relevant strings to 512 Unicode scalars and replaces characters in Foundation’s `CharacterSet.controlCharacters` with spaces. This applies to catalog hints, display names, filenames, and camera values where exposed. The local Foundation check confirmed that U+202E (right-to-left override) and U+200B (zero-width space) are caught. U+2028 (line separator) and U+2029 (paragraph separator) survive. Capture dates are formatted from typed dates using ISO 8601. Printable filenames can still contain misleading or instruction-like text. [main.swift](../Tools/RawCullMCP/Sources/RawCullMCP/main.swift#L57) · [RawCullViewModel+Catalog.swift](../RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift#L30)
- The native chooser displays the client-supplied hint as informative text. The subsequent approval sheet shows the resolved folder path and offers approve once, remember, or deny. A misleading hint can influence the chooser. The approval action remains a user decision. [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L215) · [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L307)
- `request_catalog_setup` asks macOS to activate RawCull whenever the returned request is pending and unexpired, including a replay in that state. The store allows one outstanding request, then permits another after denial or expiry. It has no client identity or cooldown. A client can repeatedly take focus and raise new prompts, creating consent fatigue. [AnalysisTools.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L84) · [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L295)

### 3. Setup receipts have no corruption recovery or retention policy

**Original severity — Medium. Confirmed with narrower corruption scope.**

- `CatalogSetupStore` decodes the `pending` pointer and per-request JSON with a plain decoder. Missing files are handled. A corrupt pointer or the corrupt receipt it references can block unrelated new submissions. A corrupt historical receipt affects lookup or replay of that UUID. The app can log the error each second while idle, and the helper reports that the setup request could not be read or saved. There is already a separate recovery path that reconstructs a queued receipt from its matching published job when the receipt still decodes as pending. [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L268) · [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L55) · [AnalysisTools.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L112)
- Nothing prunes the UUID-named receipts. They store the capped, sanitized catalog hint, which can be an absolute path. Authorization and revocation remove the job slot as applicable and leave setup receipts in place. The catalog manifest itself remains path-free. The separate setup directory retains paths and can grow indefinitely. [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L240) · [CatalogGrantStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/CatalogGrantStore.swift#L61)

### 4. No MCP-specific automated coverage

**Original severity — Medium. Confirmed for the checked repository.**

The helper package has one executable target and no test target. Searches across the app, release, and performance suites and test plans found no MCP-specific coverage. The manual TestFlight checks exercise the signed integration. Locking, corrupted state, cursor validation, idempotency, and expiry still need deterministic regression tests. [Helper package](../Tools/RawCullMCP/Package.swift#L5)

### 5. Job failure and recovery paths

**Original severity — Medium–Low. Source paths confirmed. Frequency and runtime impact remain unmeasured.**

- **Heartbeat expiry.** The main-actor monitor polls about once a second and writes progress heartbeats. A helper read can expire a job after 45 seconds without a heartbeat, using awake uptime on the same boot and wall time as a fallback. A sufficiently long stall can mark a live job failed or cancelled. When the worker resumes, the monitor or final write rejects the state, so results may never be published to MCP. A 45-second stall was not reproduced. [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L55) · [Heartbeat writer](../RawCull/Main/MCPAnalysisController.swift#L692) · [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L87) · [Result publication](../RawCull/Main/MCPAnalysisController.swift#L499)
- **Poll errors.** The busy-lock branch retries on the next poll. The generic catch cancels active analysis for other errors, including transient I/O failures. Setup-store polling is gated on the worker being idle, so setup corruption does not directly cancel an active analysis through that branch. [MCPAnalysisController.swift](../RawCull/Main/MCPAnalysisController.swift#L58)
- **Decode recovery.** `readRecoveringLocked` deletes the job after a `DecodingError`. An incompatible same-version change to required job or nested fields can trigger that deletion. An explicitly unsupported format version raises a distinct error and preserves the record. [AnalysisJobStore.swift](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L139) · [Decode recovery](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L201)
- **Contention message.** The retry loop waits up to two seconds, then lets a persistent busy error escape. The worker’s generic failure message advises checking access and reauthorizing. If writing the terminal state also fails, the persistence path logs an error. [Lock retry](../RawCull/Main/MCPAnalysisController.swift#L721) · [Worker error handling](../RawCull/Main/MCPAnalysisController.swift#L160) · [Terminal write](../RawCull/Main/MCPAnalysisController.swift#L738)

### 6. Smaller findings

| Finding | Evidence and assessment |
| --- | --- |
| Standalone helper and direct start | `start_catalog_analysis` marks a still-queued job failed if the helper cannot locate its enclosing app. A running app may claim it first. Setup instead leaves the request pending and asks the user to open RawCull. The launch comment applies to an app that can still claim the request or job. The signed analysis workflow uses the bundled helper. [Direct start](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L210) · [Setup](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L90) |
| Saved grant silently replaced | **Approve and Remember** can replace the single grant for a different catalog. The approval dialog identifies the requested folder and omits the replacement effect. The controller holds the job lock and writes the replacement grant while preserving the new job. [Approval](../RawCull/Main/MCPAnalysisController.swift#L215) · [Grant write](../RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift#L71) |
| Unbounded previous request IDs | Replacing a job through direct start for the same catalog appends the old ID to `previousRequestIds`. The history is written with each heartbeat. This growth applies to the direct-start chain. Setup uses separate receipts. [Direct-start replay](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L186) · [Heartbeat writer](../RawCull/Main/MCPAnalysisController.swift#L692) |
| Tool annotations | `get_analysis_status` and `list_bursts` use `readOnlyHint: false`. Their current paths can expire or recover persisted state. `start_catalog_analysis` uses `destructiveHint: true` and can replace old results. Whether clients show extra confirmations depends on the client. Revisit the annotations after reviewing the actual side effects. [Tool declarations](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L30) · [Dispatch](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L130) |
| Stdio compatibility shim | The transport parses incoming messages, then reserializes only matching `initialize` requests with incompatible experimental capabilities. The package pins SDK `0.12.1`. An SDK upgrade alone gives no evidence that the shim is safe to remove. Verify the Codex handshake with the replacement version. [Transport](../Tools/RawCullMCP/Sources/RawCullMCP/StatusStdioTransport.swift#L21) · [SDK pin](../Tools/RawCullMCP/Package.swift#L9) |
| Separate hard-coded helper version | `0.6.0` is hard-coded independently of the app. It can drift if releases forget to update it. A separate helper version can also intentionally identify the tool surface. [Version](../Tools/RawCullMCP/Sources/RawCullMCP/main.swift#L4) |
| Lenient cursor offsets | The numeric suffix accepts `+5`; a local Swift check confirmed the conversion. Catalog, snapshot or job, and range validation still apply. This is a minor format detail. [Photo cursor](../Tools/RawCullMCP/Sources/RawCullMCP/main.swift#L137) · [Burst cursor](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L298) |
| Stale Settings state | The view loads the grant in `.task`; its own actions update local state. A grant written through prompt-driven approval can leave an already-open Settings view stale until it reloads. [Settings load](../RawCull/Views/Settings/MCPSettingsTab.swift#L62) |

### Controls verified in source

- App and helper serialize shared transitions with the job lock. The main-thread acquisition uses `LOCK_NB`. The reviewed locked paths use the existing lock for nested updates. [Job lock](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisJobStore.swift#L160) · [Queue publication](../RawCull/Main/MCPAnalysisController.swift#L348)
- Photo cursors bind to the catalog and snapshot. Burst cursors bind to the catalog and job. [Photo cursor](../Tools/RawCullMCP/Sources/RawCullMCP/main.swift#L137) · [Burst cursor](../Tools/RawCullMCP/Sources/RawCullMCP/AnalysisTools.swift#L298)
- Burst analysis propagates cancellation through `withTaskCancellationHandler`. [Burst analysis entry point](../RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift#L14)
- The helper entitlement file declares App Sandbox and the shared app group. It declares no network entitlement. Security-scoped catalog access is released when its grant object deinitializes. [Helper entitlements](../Tools/RawCullMCP/RawCullMCP.entitlements) · [Catalog grant lifetime](../RawCull/Model/RawImageLoading.swift#L289)

## Proposed update sequence

### 1. Make shared results visible and removable

Implemented in the app and bundled helper. Completed results use explicit clearing with no automatic expiry. Clearing retains the job and request IDs for replay and removes the result payload. See [clearing shared results](mcp.md#clearing-shared-results) for the Settings and revocation behavior. The signed walkthrough below is the acceptance check for the new build.

- Show the last shareable result in MCP Settings independently of the persistent grant. Provide **Clear Last Shared Result** when appropriate and keep **Revoke Access** for saved authorization. Refresh visible state when prompt-driven approval writes or replaces a grant or changes the shared result.
- Define the approval copy around one run and its saved results. Preserve retrieval after quit. Propose explicit clearing as the initial policy. Review whether a documented automatic expiry is also needed.
- Clear completed results under the existing job lock with an expected job ID, so a stale button cannot remove a replacement job. Keep active-job cancellation explicit. Review how clearing and revocation interact with pending setup, saved-grant runs, and in-flight reads. Describe that clearing stops future reads and that copies already delivered may remain with a client.
- Tell users in the approval sheet when remembering the new catalog will replace another grant. During publication, recheck relevant state under the lock.
- **Acceptance.** Approve once, quit, and retrieve the rankings. Reopen Settings with no saved grant, clear the result, then confirm the original IDs and replayed receipt cannot retrieve results. Verify saved-grant behavior, clearing during concurrent replacement, cancellation, and Settings refresh.

### 2. Recover and bound setup storage

Implemented with a 24-hour replay window, seven-day ID retention, and a 128-receipt cap. The pending request and current job are protected during cleanup. Resolved legacy hints migrate to digests. Malformed records are recovered under the job lock, and transient I/O errors propagate without deleting the affected files. Isolated storage checks covered recovery, interrupted publication, migration, replay, revocation, and retention. See [setup request replay](mcp.md#setup-request-replay) for the client behavior.

- Under the job lock, distinguish a missing pointer, malformed pointer, malformed linked receipt, valid pending request, and transient I/O error. Recover from malformed state so an unrelated new request can proceed. Preserve a matching live job and the existing receipt reconstruction behavior when possible. Keep quarantine bounded if used and avoid duplicating path data.
- Define a replay window and receipt limit before choosing concrete values. Keep active requests and receipts needed to resolve the current job. Preserve duplicate handling and check how expired IDs are reported. Avoid allowing an old request to unexpectedly raise a fresh approval prompt.
- Persist the full hint only while needed for resolution. Review storing a digest or minimal identity for completed-request replay. Read existing receipts safely, then remove or migrate retained path data within the policy. Decide explicitly whether clearing or revocation also purges related receipts and which minimal replay records survive.
- **Acceptance.** Seed corrupt pointers, linked receipts, and unrelated historical receipts. Verify recovery, bounded storage, path removal, and successful replay within the promised window. Test an interrupted job/receipt publication, overlapping submissions, revoked results, and an upgrade with pre-existing receipts.

### 3. Reduce prompt abuse and clarify UI text

Implemented with fixed chooser instructions, a single-line client hint, and activation only when a newly submitted request needs interaction. Denial and picker cancellation start a 10-second cooldown shared by clients using the same store. See [RawCull MCP prompts](prompts.md) for retry instructions.

- Use fixed chooser copy that labels the client hint as data. Format it for a single-line display and handle Unicode line and paragraph separators. Keep the real resolved path visible for approval. Preserve valid path matching when display formatting changes.
- Activate RawCull for a newly accepted interactive request and avoid repeated activation on an idempotent replay. Review a brief cooldown or rate limit after denial that allows the user to recover from an accidental dismissal. With the current shared store, any cooldown applies across clients unless a trustworthy identity model is introduced.
- **Acceptance.** Exercise line separators, bidi and zero-width characters, long hints, and printable misleading filenames. Verify repeat submissions after denial, pending replay, and saved-grant launches, including a normal retry after the cooldown.

### 4. Make failure handling predictable

Implemented worker ownership with a process-held lock. Status reports stale progress while the worker owns the lock. Recovery transitions an interrupted job after the lock is released. Legacy records retain their heartbeat timeout, with awake uptime on the same boot and wall time across reboots. Polling allows five seconds of consecutive retryable storage failures, and ownership reads and writes retry for up to two seconds. Cancellation, storage failures, and unsupported formats have distinct outcomes. Format 2 is used only for a running job with a worker lock. A format-1 helper rejects that record, so use the app and helper from the same build. Queued and terminal records remain readable by the older helper.

- Add targeted cases with controlled clocks and injected storage failures. Separate a temporarily stale heartbeat, a confirmed dead or replaced worker, an explicit cancellation, and invalid authorization. Review whether status reads should report staleness while the app owns the terminal transition. Preserve bounded recovery when the app has exited and prevent an old worker from publishing over a replacement.
- Retry transient poll and persistence failures within a defined bound. Keep cancellation for loss of ownership, revoked authorization, explicit cancellation, or unrecoverable state. Report contention and unsupported format distinctly from folder access errors.
- Preserve unsupported-version files. Review version bumps and backward-compatible decoding before adding required fields. Define how confirmed corruption is recovered without deleting a compatible job owned by a running worker. Include older helper and newer app combinations in the review.
- **Acceptance.** Cover stale heartbeat with a live worker, confirmed interruption, sleep or reboot fallback, transient read failure, lock contention at completion, cancellation during progress, and unsupported versus malformed job records. Verify terminal states and messages after each fault.

### 5. Add regression tests and review follow-up items

Implemented automated setup-store, job lifecycle, Settings visibility, and cursor-boundary checks. Direct starts retain the most recent 128 replaced IDs in the current catalog chain. Standalone analysis submissions return bundled-helper instructions. Tool annotations reflect the remaining recovery writes in status calls and the read-only burst listing path. Helper 0.7.0 reports the enclosing app build. The transport shim and cursor formats remain compatible. The [TestFlight regression pass](mcp.md#testflight-regression-pass-for-helper-070) is ready for signed verification.

- Start with helper-store tests using isolated temporary directories and an injected clock or equivalent deterministic time control. Cover locks, pending and terminal receipts, replay, retention, clearing, corruption, expiry, and cursor boundaries. Add app-level coverage for Settings state and lifecycle transitions where the ownership rules live. Use a separate signed TestFlight pass for app-group access, cold launches, user prompts, and post-quit retrieval.
- Bound direct-start request history under an explicit replay policy. Revisit read-only and destructive hints once final tool side effects are defined. Decide whether standalone analysis is supported or should fail consistently with actionable bundled-helper guidance.
- Keep the transport shim until an SDK compatibility change is verified with Codex. Decide how to expose the helper version alongside the app build. Defer cursor canonicalization unless there is a defined need and a compatibility decision.
- Repeat the walkthrough for a new catalog, a remembered catalog, and the recurring-folder case with replacement photos. Verify updated counts and filenames, invalidation of stale cursors, and revocation. Use separate fixtures for ambiguous names and a disconnected removable source. Record the signed app build and helper version for each run.

## Review before implementation

Review the proposed changes against the current HEAD and the signed baseline. Agree on these decisions before code changes begin.

1. How long a one-time result can be read, what the approval sheet promises, and what **Clear Last Shared Result** and **Revoke Access** each remove.
2. Which request data persists, the replay and retention limits, how existing receipts are migrated, and what happens when old IDs are submitted.
3. Which component owns terminal job transitions and how it distinguishes a stalled worker from an interrupted one.
4. How approval throttling handles user retries and multiple clients sharing the local store.
5. What changes can ship together, what requires app-and-helper version coordination, and which automated and signed checks gate each change.

After that review, implement the approved scope in stages and attach the test evidence to the next review.
