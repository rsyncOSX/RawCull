# Decision: One AI review feature

Status: accepted · 2026-11-21 · migration on branch `version-3.5.0`
Answers [code-quality-followups-plan.md, finding 4.3](code-quality-followups-plan.md#43-product-decision-yours-not-a-refactor).

## Summary

RawCull has four in-app ways to run an AI analysis of a photo: Deep AI Review, Qwen Vision, Objects and Combined Review. They run nearly the same models on the same photos, but each one has its own controller, view, result store and tests. None of the four ends in a decision. The photographer reads the result, then has to switch views to rate or tag the photo.

The proposal:

- **Combined Review becomes the only in-app AI review.** It gets three depth presets that replace the three AI Analysis tabs.
- **Every review result screen gets Tag, Rate and Mark Reviewed.**
- **Burst groups and semantic search stay as they are.** They answer different questions.
- **MCP stays a trigger, not a feature.** Its results open in the same results window as in-app reviews.
- **The burst workspace keeps its AI assessment features:** the badge on filmstrip thumbnails, the assessment summary and "compare with sharpest". They read from the AI Assessments window, not from the AI Analysis tabs.

## What exists today (2026-11-21)

| Feature | Entry point | Models | Ends in a decision? | Code |
|---|---|---|---|---|
| Deep AI Review | AI Analysis → "SAM 3 + CLIP" tab (`SAMCLIPAnalysisView`, `DeepAIReviewSheetView`) | SAM 3, CLIP, subject-mask focus scoring | No | `Intelligence/DeepReview/`, 1,335 lines |
| Qwen Vision | AI Analysis → "Qwen Vision" tab (`QwenAnalysisView`) | Qwen, via `QwenPhotoAssessment` | No | `RawCullQwenAnalysisFeature`, 213 lines |
| Objects | AI Analysis → "Objects" tab (`ObjectAnalysisView`) | SAM concepts, Qwen | No | `Intelligence/ObjectAnalysis/`, 1,393 lines |
| Combined Review | Main view mode `.combinedReview`, gated by `RawCullAI.combinedReviewEnabled` | Qwen, SAM, CLIP, focus measurement | No | `Intelligence/CombinedReview/`, 4,070 lines |
| Semantic search | Similarity grid | CLIP | Not applicable (it finds photos) | `Intelligence/SemanticSearch/`, 1,048 lines |
| MCP photo assessment | External MCP client; results in the AI Assessments window | Qwen, via the same `QwenPhotoAssessment` | Yes: tag and mark reviewed in `AIAssessmentComparison` | `Main/MCPAnalysisController*`, `Views/AIAssessments/` |

The three AI Analysis tabs together, with `AIAnalysisView` and its input picker, are about 1,850 lines of views. Their tests (`DeepAIReviewFeatureTests`, `ObjectAnalysis*Tests`, `QwenFeatureTests`, `AIAnalysis*Tests`) are about 2,350 lines.

Correction to finding 4.3: Deep AI Review is no longer in the burst workspace. It is the "SAM 3 + CLIP" tab in AI Analysis.

### Combined Review already covers the three tabs

`ReviewStage` (`CombinedReview/Execution/ReviewRunContract.swift:141`) has these stages:

| Stage | Model | Covers |
|---|---|---|
| `source` | none | |
| `overview` | Qwen | Qwen Vision |
| `segmentation` | SAM | Deep AI Review, Objects |
| `identity` | none | Objects (instances) |
| `measurement` | none (focus) | Deep AI Review |
| `clip` | CLIP | Deep AI Review |
| `cropObservation` | Qwen | Objects (per-object assessment) |
| `reconciliation`, `report`, `comparison` | Qwen | Combined Review only |

Combined Review also already uses the subject-mask focus scorer that Deep AI Review uses (`Intelligence/SubjectMasks/`).

## Decision

Organize AI by the photographer's question, not by model:

| Question | Feature | Change |
|---|---|---|
| "Which frame in this burst is best?" | Burst groups: similarity, sharpness, faces | None. This is the core of the app, and it does not need generative AI. |
| "Where is that photo of …?" | Semantic search | None. |
| "What is wrong with this photo?" | **Review** (today's Combined Review) | Add three presets. Remove the setting that gates it. Remove the AI Analysis view. |
| Batch work from an agent | MCP | None to the trigger. Results open in the shared results window. |

### Review presets

| Preset | Stages | Replaces | Needs |
|---|---|---|---|
| **Focus check** | `source`, `segmentation`, `identity`, `measurement`, `clip` | Deep AI Review | SAM 3, CLIP. No Qwen, so it is fast and works without the large model. |
| **Describe** | `source`, `overview` | Qwen Vision | Qwen |
| **Full** | all stages | Combined Review and Objects | Qwen, SAM 3, CLIP |

Objects becomes a section of the Full result, built from `segmentation`, `identity` and `cropObservation`. It does not get its own preset, because it needs both SAM and Qwen anyway.

`ReviewDepth` already exists on `CombinedReviewFeature`. Check whether the presets fit as new `ReviewDepth` values or need a separate type. Each preset still validates against `ReviewPipelineContract.stageVersions`, so saved results stay compatible.

### Rule: a review ends in a decision

Every review result screen has these actions, using the same code as the grid and `AIAssessmentComparison`:

- **Tag** and **Untag**
- **Rate** (the same keys as the grid)
- **Mark Reviewed**, when the photo belongs to a burst

As the AI Assessments window already does for MCP results: opening, running or comparing a review never changes a tag or a rating. Only the photographer's action does.

## Options considered

| Option | For | Against |
|---|---|---|
| **A. Keep all four** | No work. Each is tuned for its job. | Four pipelines to keep working through every model update. Four places to look. Nothing ends in a decision. |
| **B. One Review with presets** (chosen) | One pipeline, one result format, one viewer. Fast paths stay, as presets. | Migration work. Some outputs of the old tabs may be lost (see step 2). |
| **C. Remove generative AI, keep only burst groups and search** | Smallest app. No large model downloads. | Throws away working features and the MCP workflow. |

## Migration (one PR per step)

| Step | What | Size | Risk | Status |
|---|---|---|---|---|
| 1 | Accept this decision; update finding 4.3 | XS | none | done |
| 2 | Compare outputs: presets against the old tabs | S | none | not started |
| 3 | Add the presets to Combined Review | M | medium | done |
| 4 | Add Tag, Rate and Mark Reviewed to the review results | S | low | done |
| 5 | Make Review the default; hide the old tabs behind a setting | S | low | done |
| 6 | Delete the old tabs, after one TestFlight release | M | low | done (before a TestFlight release, at the owner's decision) |
| 7 | Send in-app review results to the AI Assessments window | M | medium | dropped (see below) |

### Step 2: Compare outputs

Run the old tab and its preset on the same 20 photos from one real catalog: birds, people and landscapes, sharp and soft.

- **Focus check vs Deep AI Review:** the same subject masks, focus scores within ±2%, and the same candidate order per burst.
- **Describe vs Qwen Vision:** the same `QwenPhotoAssessment` fields filled in. The wording will differ between runs; compare the fields, not the text.
- **Full vs Objects:** the same object instances (after `ObjectInstanceDeduplicator`) and a per-object assessment for each.

Write every difference into this document. For each one, decide whether to add it to the preset or accept losing it.

Differences known from the code (step 3), before any run:

- **Focus check segments the generic "subject".** Deep AI Review picks prompts from the burst's subject label (bird head, face, animal head, then the broader prompt). Focus check has no Qwen overview to name concepts, so it asks SAM for "subject" and then tries a head region inside it. Check whether bird and portrait masks are as good.
- **Focus check has no per-burst candidate order.** Deep AI Review ranks the frames of a burst. Focus check measures each selected photo; it does not rank them.
- **Describe uses Combined Review's overview format** (observations, uncertainty, concepts), not the `QwenPhotoAssessment` fields that Qwen Vision fills in.

Done when: every difference has a decision.

### Step 3: Presets

1. Add the three presets and a picker in the Combined Review controls.
2. Skip the stages a preset does not need, both when running and when checking the run parameters, so Focus check never loads Qwen.
3. Tests: each preset runs exactly its stages (use a fake per model, and record which ones were called); saved results from today's Full run still load; Focus check works with no Qwen model installed.

What was built:

- `ReviewPreset` (`CombinedReview/Execution/ReviewRunContract.swift`) is a separate type, not new `ReviewDepth` values. Depth only sets crop and follow-up limits, which apply to Full alone, so the Depth picker is disabled for the other presets.
- The run snapshot saves the preset. Runs saved before presets have none and load as Full. Full runs keep their old compatibility keys, so saved artifacts stay valid.
- `CombinedReviewBackendServing.models(for:)` returns only the models a preset uses. The live backend no longer needs Qwen installed; Focus check never checks or loads it.
- Focus check results have no report. Their subject detail measurements are shown as findings.

### Step 4: Decision actions

Add Tag, Rate and Mark Reviewed to `CombinedReviewInspector`, reusing `RatingsModel` and the review action from `AIAssessmentComparison`. Add the same keyboard shortcuts as the grid. Test that running, opening and comparing a review never changes a rating or tag.

What was built:

- `ReviewDecisionActions` (`RawCull/Model/ReviewDecisionActions.swift`) holds the tag, rate and Mark Reviewed calls. `AIAssessmentComparison` now uses it too, so both screens run the same code.
- The decision bar sits under the result header, not in `CombinedReviewInspector`, because the inspector only shows in the Evidence view when an input was retained. The bar shows in both views.
- The grid's rating keys work in Review: X, P or 0, 1–5, and T.
- Before any action, the photo must be in the open catalog, have a unique filename and be unchanged on disk since the review. Otherwise nothing changes and the bar says why.

### Step 5: Make Review the default

- Remove the `RawCullAI.combinedReviewEnabled` gate. Keep its key readable, so old settings don't fail.
- Rename the toolbar item "Combined Review" to "Review".
- Add a setting "Show legacy AI Analysis", off by default. When it is off, the toolbar has no AI Analysis button.

What was built:

- The opt-in toggle and its memory sheet are gone. The old 16 GB minimum now applies only to the presets that load Qwen: below 16 GB, Describe and Full are disabled with a reason and Review starts on Focus check, which has no memory gate, like Deep AI Review. Below 32 GB, Describe and Full show a memory note. AI settings states this Mac's memory.
- `RawCullAI.combinedReviewEnabled` is no longer read; the key is kept and a test checks that an old saved value does no harm.
- The toolbar item, window title and About entry say "Review". The preset picker moved out of the collapsed settings section into the run bar.
- "Show legacy AI Analysis" (`RawCullAI.showLegacyAIAnalysis`) is off by default. Turning it off while the old view is open switches to Review.
- Full stays the default preset on Macs with 16 GB or more.
- After step 5: the "Photo-first / Evidence workspace" switch is gone. Review has one view; the evidence (findings with their masks and crops, coverage and limits, technical record) is a collapsed "Evidence & details" section under the findings. Clicking a finding opens it there.

### Step 6: Delete

After one TestFlight release with no report that needs an old tab, delete:

- `MainViewMode.aiAnalysis`, `AIAnalysisView`, `AIAnalysisInputPicker`, `SAMCLIPAnalysisView`, `QwenAnalysisView`, `ObjectAnalysisView` and the `DeepAIReview*` and `Object*` views that nothing else uses
- `DeepAIReviewController`, `DeepAIReviewFeature`, `RawCullQwenAnalysisFeature`, `RawCullObjectAnalysisFeature`
- their tests, and the legacy setting

Keep everything Combined Review or MCP uses: `Intelligence/SubjectMasks/`, `QwenPhotoAssessment`, `QwenInferenceRuntime`, the mask outline renderers and `ObjectInstanceDeduplicator`, if Full uses it. Use the graph (`graphify-out/`) to check that nothing else depends on a type before deleting it. Run `periphery scan` after the delete to find code that is now unused.

Also clear the old result stores on disk, or leave them and document that they are no longer read.

Done when: the app builds, `make test-smoke` passes and `make lint` shows no new violations.

### Step 6: what was done

- Deleted the AI Analysis view and its three tabs, `DeepAIReviewController`, `DeepAIReviewFeature`, `RawCullQwenAnalysisFeature`, `RawCullObjectAnalysisFeature`, the Object analysis helpers, `MainViewMode.aiAnalysis`, the "Show legacy AI Analysis" setting, and their tests, release test and runner script.
- Kept what Review and MCP use: `QwenPhotoAssessment`, `QwenInferenceRuntime`, `Intelligence/SubjectMasks/`, `ObjectInstanceDeduplicator` (with `ObjectInstanceDescriptor`) and the mask outline renderer, now `SubjectMaskOutlineRenderer`.
- Deep AI Review masks also drove the subject outline (S key) in the loupe, zoom and burst workspace and the mask badge on thumbnails. These now read the main subject mask from Review results (`ReviewSubjectMasks`), matched by file location and used only while the file is unchanged.
- Old Deep AI Review, Qwen Vision and Objects results are not converted and are no longer shown. The Objects mask cache (`SAM3ObjectMasks`) is deleted at launch. The SAM 3 subject-mask cache (`SAM3Masks`) is still created and shown in AI settings; nothing writes to it now (see the `periphery` note below).
- Step 2 (comparing outputs) was not run before deleting. The known differences are listed under step 2.

### Step 7: dropped

The AI Assessments window is built around MCP job records: a burst, a recommendation and Qwen assessment fields per frame. Review results are a different record (findings, measurements, regions), and the window's design is out of scope here. Review already ends in a decision (step 4), so in-app results stay in Review and MCP results stay in the AI Assessments window.

## Expected effect

- **Code:** about 4,800 app lines and 2,350 test lines are involved. Combined Review reuses some of the primitives, so roughly half is expected to go away. Measure after step 6 and write the real number here.
- **Product:** one AI entry point instead of four, and every AI result ends in a decision.
- **Maintenance:** a model update (Qwen, SAM, CLIP) is tested in one pipeline instead of four.

## Risks

- **Focus check is slower than Deep AI Review.** Combined Review's run has more steps (source selection, run snapshot, artifact store). Time both on the 20 photos in step 2. If Focus check is more than 20% slower, find the cause before step 5.
- **Someone depends on an old tab.** Step 5 keeps them for one release behind a setting.
- **Saved results.** Old Deep AI Review, Qwen and Objects results are not converted. After step 6 they are no longer shown. Say so in the release notes.
- **MCP.** MCP uses `QwenPhotoAssessment` directly, not `RawCullQwenAnalysisFeature`. Run `make test-mcp` and `make test-mcp-release` after steps 3 and 6.

## Not in scope

- Changes to burst grouping, sharpness, faces or similarity.
- Changes to semantic search.
- The design of the AI Assessments window itself (`RawCull/Views/AIAssessments/`).
