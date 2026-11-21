# Plan: Code-quality follow-ups (findings 2–5)

Status: in progress · updated 2026-11-21 · branch `version-3.4.9`
Finding 1 (breaking up `RawCullViewModel`) is done; its plan has been removed.

## Verdict per finding

After a closer look, not every finding is worth acting on.

| # | Finding | Act? | Why |
|---|---|---|---|
| 2 | `RawCullFileItem` has 339 graph edges | **No** (one small check) | I overstated this. It's a 56-line, immutable, `Sendable` value type in `RawCullCore`. The core domain value *should* be used everywhere; that's healthy coupling, not a design smell. |
| 3 | MCP controller keeps its state machine in loose variables | **Yes, highest priority here** | The real correctness risk. Details below. |
| 4 | Too many features and overlapping "review" concepts | **Partly** | One code fix (shared primitives live in the wrong folder). The rest is a product decision for you, not a refactor. |
| 5 | 157 `try?` | **Yes, small and targeted** | About 85% are fine. About 8 hide failures that matter, including two cache-key functions that can map every input to the same key. |

---

## Finding 3: Make the MCP controller's state explicit

### What's wrong today

`MCPAnalysisController` (1,262 lines) runs a 1-second polling loop. It has three activities (catalog **setup**, catalog **analysis** and a photo-assessment **follow-up**) plus a quit lifecycle. Their state is spread across about 15 fields:

- `setup`, `setupDeadline`, `setupSheet`, `approvedSetup`
- `activeJob`, `analysis`
- `followUp`, `followUpID`, `followUpDeadline`, `followUpStopCode`
- `isTerminationPending`, `isQuitting`
- `monitor`, `inactiveRevision`, `cachedGrant`, `nextHostPublication`

The three activities are **mutually exclusive in practice**: every start path guards on `setup == nil, analysis == nil, followUp == nil`. But the type system doesn't know that. 33 assignment sites keep these fields consistent by hand, and the `defer` blocks in each `Task` clear several of them separately. The store (`AnalysisJobStore`) has good tests in `MCPJobLifecycleTests`, but **the controller's transitions have none**.

Two further problems:

- The error codes sent across the process boundary are string literals: `"executionTimeout"`, `"modelChanged"`, `"reauthorizationRequired"`, `"assessmentFailed"`, `"allPhotosFailed"`, `"busy"`, spread across `MCPAnalysisController.swift` and `AnalysisTools.swift`.
- `AnalysisJobStore.swift` (1,391 lines) holds three separate stores: the analysis job, the follow-up queue, and `CatalogSetupStore`. The app compiles it straight from `Tools/RawCullMCP/Sources` through file references in the pbxproj (8 references), so the IPC contract between app and helper isn't a module of its own.

### Steps (one PR each)

**3.1 Make the controller testable (S).**
- Inject the `AnalysisJobStore`/`CatalogSetupStore`, the grant store (currently `CatalogGrantStore.shared()`) and a clock through `init`, with today's values as defaults.
- Build a `FakeMCPWorkspace: MCPAnalysisWorkspace`. The protocol already exists, so this is straightforward.
- Add one test helper that drives a single loop iteration (`tick()`) instead of the 1-second sleep.

**3.2 Characterization tests for transitions (M).** Before changing any logic, pin today's behaviour:
- queued job → claimed → running → completed / failed / cancelled
- setup request while idle → sheet shown; it expires at the deadline; quit-pending suspends it, and cancelling the quit shows it again
- follow-up: admitted, refused as `busy` when the workspace is loading, `executionTimeout` after 180 s, `modelChanged` on lease invalidation, cancellation requested by the helper
- storage failure: retried for under 5 s, and the job fails after 5 s
- `stopForQuit()` during each of the three activities, checking the right terminal state is written and no `finish` happens after quit

**3.3 Introduce explicit state (M).**

```swift
private enum Activity {
    case idle
    case settingUp(SetupActivity)        // task, deadline, sheet
    case analyzing(AnalysisActivity)     // job, task
    case assessing(FollowUpActivity)     // id, deadline, stopReason, task
}
private enum Lifecycle { case running, terminationPending, quitting }

private var activity: Activity = .idle
private var lifecycle: Lifecycle = .running
```

- Every `setup == nil, analysis == nil, followUp == nil` check becomes `guard case .idle = activity`.
- Transitions go through two methods: `begin(_:) -> ActivityToken` and `end(_ token:)`. `end` only clears the state if the token still matches. Then a stale task's `defer` can never clear a newer activity. That's impossible today only because of guard ordering.
- `approvedSetup` deliberately outlives the setup activity: it's created by setup and consumed when the job is claimed. Keep it as its own field named for that (`pendingApprovalForClaim`), with a comment, rather than forcing it into the enum.
- Group the timers and caches (`inactiveRevision`, `cachedGrant`, `nextHostPublication`, `nextSetupMaintenance`) into one `PollBookkeeping` struct.

**3.4 Typed stop reasons (S).** Replace the string literals with an enum:

```swift
enum MCPAssessmentStopReason: String, Codable, Sendable {
    case busy, executionTimeout, modelChanged, modelUnavailable,
         reauthorizationRequired, assessmentFailed, allPhotosFailed
}
```

Put it next to `AnalysisJobStore` so the app and the helper share one definition. The `catch` chain that maps errors to codes becomes a pure `static func stopReason(for:)`, which also gets unit tests.

**3.5 Split the files (S, pure move).**
- `MCPAnalysisController.swift` → the loop and state, plus `+Setup`, `+Analysis` and `+FollowUp` extensions. Splitting by extension is fine *here* because the state is now explicit.
- `AnalysisJobStore.swift` → `AnalysisJob.swift`, `AnalysisJobStore.swift` (lock, read/update, worker lease), `AnalysisJobStore+FollowUps.swift`, `CatalogSetupStore.swift`.

**3.6 Optional: a shared IPC module (M).** Add a `RawCullMCPShared` library product to `Tools/RawCullMCP/Package.swift` with the store, grant store and stop reasons, and have the app target depend on it instead of compiling the helper's source files by path. This makes the app↔helper contract an explicit module with `public` API, and removes the cross-tree pbxproj file references. The cost is adding `public` modifiers.

**Not changing:** polling the file store every second. It's cross-process IPC through files with locks, and polling is simple, robust and cheap there. File-system watching would add complexity for little gain.

**Ordering with the view-model plan:** this touches different files, so it can run alongside view-model slices 0–5. Finish it before view-model slice 6, which moves catalog state that `MCPAnalysisWorkspace` reads.

---

## Finding 5: Fix the `try?` uses that hide failures

### The policy (add it to the contributor notes)

`try?` is fine for:
- best-effort cleanup (`removeItem`, `close()`), `Task.sleep`
- decoding optional fields with a default, for format compatibility (`SettingsViewModel`, `BurstAnalysisCache` init)
- validation used as a yes/no check (`(try? admit(...)) != nil`)
- tolerant parsing of model output where a fallback path exists

Everything else uses `do/catch` with a `Logger` line, or rethrows.

### Fix list (one PR, about half a day)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `BurstAnalysisCache.artifactSetDigest` (`(try? encoder.encode(entries)) ?? Data()`) | If encoding fails, the digest is the hash of empty data, **the same for every input**. `JSONEncoder` throws on NaN/±∞ floats, so a bad descriptor value is enough to trigger it. | Make it `throws`, or `preconditionFailure` with a message. Never fall back to a constant. |
| 2 | `PerFileAnalysisArtifactStore.cacheKey(for:)` (same pattern) | Every identity would map to **one file on disk**, so cached artifacts could be served for the wrong photo. | Same fix. Add a test that a NaN in the identity doesn't produce a shared key. |
| 3 | `RawCullAIModelRuntime` init, `objectMaskDiskStore = try? ObjectMaskDiskStore(...)` | Object masks silently lose disk caching. The subject-mask store next to it reports a `capability`; this one doesn't. | Mirror the subject-mask pattern: log, and expose the capability. (Since removed: the object mask store was deleted with Objects analysis.) |
| 4 | `CombinedReviewFeature.persistCancellation` (`try? await store.saveManifest`) | A failed save means the run's state is silently lost. | Log it. |
| 5 | `CombinedReviewFeature.clearRejectedResponses` / `clearRetainedInputs` | Settings "clear" actions report success even when they failed. | Return the error, or a Bool, and show it in `CacheSettingsTab`. |
| 6 | `CacheSettingsTab` (`(try? ...usage()) ?? 0`) | Shows "0 bytes" when reading usage failed. | Show "unavailable" instead. |
| 7 | `RawCullSemanticSearchModel` around line 236 (`try? await service.rank`) | Every prompt can fail silently and the result is just empty labels. | Log the first failure in each run. |
| 8 | `MCPAnalysisController` around line 886 (bookmark creation) | Already logs, but drops the error. | Include the error in the log line. |

**Guard against regression:** add a SwiftLint `custom_rules` entry that matches `try?` followed by `?? Data()` (pattern 1 and 2). It's narrow enough not to be noisy.

---

## Finding 4: Overlapping features

### 4.1 Code fix: shared primitives in the wrong place (S)

Combined Review depends on `SubjectMaskForeground`, `SubjectMaskFocusScorer` and `SubjectMaskFocusEvidence`, which live in `Intelligence/DeepReview/`. Six Combined Review files use them, including `ReviewMaskProcessing`, `ReviewMaskRegistration`, `ReviewEvidence` and `CombinedReviewExecution`. So one feature depends on the internals of another.

→ Move them to `Intelligence/SubjectMasks/`, or into `PhotoAIKit/PhotoAIWorkflows` if they don't depend on anything in the app. Pure move.

### 4.2 Optional tidy: `CombinedReview/` subfolders (XS)

24 files and about 4,000 lines in one flat folder. Group them as `Execution/` (`*Execution`, `ReviewRun*`, `ReviewBudget`), `Evidence/` (`ReviewEvidence`, `ReviewSubjectPriority`, `ReviewSynthesis*`), `Imaging/` (`ReviewImage*`, `ReviewMask*`, `ReviewInspectionOverlay`, `ReviewEmbeddedPreviewLoader`) and `Storage/` (`ReviewArtifactStore`, `CombinedReviewLease`).

### 4.3 Product decision (yours, not a refactor)

Accepted (2026-11-21): [ai-features-decision.md](ai-features-decision.md). One Review feature with Focus check, Describe and Full presets replaces Deep AI Review, Qwen Vision and Objects. The migration is done on branch `version-3.4.9`, which now includes the `version-3.5.0` work: Deep AI Review, Qwen Vision, Objects and the AI Analysis view are deleted. Open items are tracked in [ai-features-decision.md](ai-features-decision.md#follow-ups-from-the-code-review-2026-11-21).

The table and question below describe the app **before** the migration and are kept for history.

Correction to the table below: Deep AI Review is no longer in the burst workspace. It is the "SAM 3 + CLIP" tab in AI Analysis. The AI assessment badges, summary and "compare with sharpest" in the burst workspace come from the AI Assessments window (MCP results) and stay.

User-facing AI analysis existed in several places:

| Feature | Where in the UI | Engine |
|---|---|---|
| Deep AI Review | AI Analysis view, "SAM 3 + CLIP" tab (was: burst workspace) | Subject masks + focus scoring |
| Combined Review | Main view mode `.combinedReview` | CLIP + SAM + Qwen pipeline, also uses the subject-mask focus scorer |
| Qwen analysis | AI Analysis view | Qwen |
| Object analysis | AI Analysis view | SAM concepts + Qwen |
| Semantic search | Grid | CLIP |
| MCP photo assessment | External client | Qwen |

The question to answer: **is Deep AI Review now a subset of Combined Review?** If so, folding it into Combined Review as a "focus-only" mode removes a controller, a presentation-state enum, a protocol conformance on the view model and a separate entry point in the burst workspace. If they serve different moments (a quick per-burst check vs. a deep run), keep both. Either way, write the reason down so the next refactor doesn't have to work it out again.

---

## Finding 2: `RawCullFileItem` (no refactor, one check)

Leave it as is. One thing to verify: `==` and `hash(into:)` compare **only `id`**. That's fine as long as an item's metadata never changes while it keeps its `id`. If any path rebuilds a `FileItem` with the same `id` but new EXIF or size, SwiftUI `onChange(of: file)` and any set-based diffing will miss the change. If that can happen, either regenerate the `id` or compare all fields and use `id` only for `Identifiable`.

---

## Status (2026-11-21)

### Completed

| Item | Status |
|---|---|
| Finding 5 fix list | done |
| 4.1 Move subject-mask primitives | done |
| Finding 3, steps 3.1–3.5 | done |
| 4.2 `CombinedReview/` subfolders | done |
| 4.3 Product decision | done: accepted and migrated on `version-3.4.9`, see [ai-features-decision.md](ai-features-decision.md). Step 2 (output comparison) and the review follow-ups are open there. |

### Not yet completed

| Item | Status | Next step |
|---|---|---|
| Finding 2: identity-only `==` on `RawCullFileItem` | **not completed**: checked, no change to logic needed | `==` and `hash(into:)` still compare only `id`. No production code passes an existing `id` to `RawCullFileItem(...)`, so each scan gets fresh UUIDs and the stale-metadata case can't happen today. Remaining: add a comment on `==` saying this rule must hold. |
| 3.6 Shared MCP IPC module (optional) | **not completed**: not started | Add a `RawCullMCPShared` product to `Tools/RawCullMCP/Package.swift` and drop the pbxproj file references to the helper's sources. |
