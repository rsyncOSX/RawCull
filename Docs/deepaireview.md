# Combined Deep AI Review implementation plan

Date: 9 October 2026  
Status: phase 1 completed on 9 October 2026; phase 2 is next. Combined Review feature delivery is planned in phase 4.

## 1. Objective and guiding decision

Add a fourth view, **Combined Review**, inside AI Analysis. It should perform a deliberate, local analysis of a small selection of photographs, combining Qwen, SAM 3, CLIP, and RawCull's measured photographic evidence. Each stage should supply structured evidence to the next. The result should explain strengths, problems, uncertainties, and meaningful differences between comparable photographs.

The priority is to maximize **useful detail actually reaching the vision encoder**, not merely the dimensions of the image supplied by the app. Use an overview plus separate crops extracted from a high-quality source. Larger internal model inputs are a subsequent capability investigation, not a prerequisite for the first useful release.

Examples of intended questions:

- Which photograph has the clearest eye detail while retaining a good pose?
- Which portrait best balances expression, visibility, and technical quality?
- Is the main subject sharp, or is sharp background detail misleading the whole-image score?
- What are the strengths and weaknesses of this photograph, and which crop might improve its composition?

The feature provides review recommendations. It should not automatically reject, delete, rate, or edit photographs. Suggested exposure or crop changes are hypotheses unless an actual rendered variant has been evaluated.

## 2. Verified current implementation

These observations refer to the source inspected for this plan. Recheck them against the implementation revision when work begins.

| Component | Current behavior | Implication |
| --- | --- | --- |
| `RawCull/Views/AIAnalysis/AIAnalysisView.swift` | Three tools: SAM 3 + CLIP, Qwen Vision, Objects; selected/tagged input; tool changes cancel other analyses | Add an independently owned combined workflow and update cancellation routing |
| `RawCull/Intelligence/Qwen/RawCullQwenAnalysisFeature.swift` | Loads a thumbnail with `maxPixelSize: 2048`; default assessment covers composition, exposure, visibility, expression, and obstructions | Existing whole-image analysis is an overview, not a detailed inspection of every source pixel |
| `RawCull/Intelligence/Qwen/QwenInferenceRuntime.swift` | One `CGImage` per request; fresh session per generation; serialized generation gate; response limit validated in 1...4096 | Carry previous evidence explicitly; do not assume session memory or unlimited output |
| Core AI dependency: `CoreAILanguageModels/InferenceEngines/CoreAISequentialVLMEngine.swift` | Preprocessor targets `visionConfig.imageSize` by `visionConfig.imageSize` | Raising RawCull's thumbnail limit alone does not raise encoder resolution |
| Core AI dependency: `CoreAILanguageModels/Bundle/LanguageConfig.swift` | Vision configuration includes image size and image strategy; absent strategy defaults to stretch in the inspected dependency | Inspect selected bundle metadata and actual geometry transformation before drawing conclusions about detail or aspect ratio |
| Core AI dependency: `CoreAILanguageModels/VLM/CoreAIVisionLanguageModel.swift` | Executor selects the first image attachment from the transcript | Multiple attachments are not a supported comparison path in the inspected runtime |
| `RawCull/Intelligence/ObjectAnalysis/RawCullObjectAnalysisFeature.swift` | Automatic Qwen discovery → SAM 3 concepts/instances → Qwen object assessment | A substantial part of the desired sequential workflow already exists |
| `RawCull/Intelligence/ObjectAnalysis/ObjectReviewBoardRenderer.swift` | 2048-square board with overview and up to eight 512-square panels; headers reduce available crop area further | Useful for relationships and IDs, but a poor sole input for fine-detail assessment |
| `RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift` | Subject masks, broad/local/fine detail, AF evidence, confidence and cautions; embedded-preview or RAW-demosaic decoding | Reuse technical evidence and mask infrastructure; avoid duplicating the scoring algorithms |
| Existing deep review candidate selection | More than twelve candidates are reduced to eight ranked candidates | A new selection-based workflow must explicitly review every accepted selected image, rather than inherit silent burst filtering |
| `RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift` | Atomic per-file similarity artifacts with source/backend/pipeline compatibility | Reuse the persistence pattern, but add a separate typed combined-review artifact format |

The three views are workflows, not three independent opinions. Objects and Qwen Vision share Qwen; Objects and existing Deep Review share SAM 3. CLIP supplies embeddings and similarity, not freeform reasoning. Agreement between two passes of the same model is not independent confirmation.

The selected Qwen bundle's actual encoder dimensions, compression, context budget, supported tensor shapes, and preprocessing strategy remain to be verified. This plan deliberately does not invent a universal pixel limit or execution time.

## 3. Scope and user experience

Start with 2–8 selected images as the recommended comparison size; support a single image for detailed critique. This is a product default, not a model limit. If a user requests more images, show the estimated work and require an explicit choice between the full selection and a smaller selection. Never silently discard candidates.

Controls:

- Review goal: best technical detail, portrait/expression, wildlife/action, composition, or custom criteria.
- Depth: Standard, Deep, Exhaustive, with visible image/region/pass estimates.
- Source: high-quality preview or RAW detail where available; explain the practical difference.
- Optional subject or region selection, especially when the main subject is ambiguous.
- Start, cancel, resume, and rerun with changed settings.

Results should include an overall explanation, per-image evidence, per-subject detail, uncertainty, and comparable-image tradeoffs. A result such as “A has stronger eye detail; B has a better pose; no clear overall winner” is valid and preferable to a forced ranking.

Show previews with inspectable crop locations and optional masks. Keep the exact unannotated model input available in an evidence inspector. Put encoder dimensions and detailed timing in diagnostics; normal users need clear source-quality and progress information.

Preserve completed results when the user leaves the view. Snapshot the input selection at start so navigation does not silently change the running request. Define explicit cancellation on catalog closure, lost file access, or model replacement; avoid accidental cancellation merely because the display changes.

## 4. Phase A: expose and verify the real input contract

Before changing resolution settings, add a read-only Qwen input capability descriptor at the provider/runtime boundary:

- Model identity/fingerprint, name, compression, and dependency/runtime version.
- Configured encoder width/height and preprocessing strategy.
- Vision token count or supported token budget, if available.
- Total context capacity, and how image, instruction, evidence, and output consume it.
- Supported image count per request; initially one.
- Supported input shapes, distinguishing verified shapes from unknown capability.

Trace one diagnostic request through decoding, crop extraction, app preparation, runtime preprocessing, image encoding, and generation. Record dimensions at every step. Check that runtime diagnostics match bundle metadata and compiled function input descriptors.

Inspect aspect-ratio handling with a synthetic image containing a circle, corner markers, and a regular grid. Test landscape, portrait, square, and extreme aspect ratios. Determine whether the selected bundle expects stretch, center crop, or padding. Do not replace that strategy casually: model conversion and training assumptions may matter.

Add an equivalent CLIP descriptor at its provider boundary: model/asset fingerprint and runtime version, actual encoder dimensions and tensor layout, resize/crop/pad geometry, channel order, color conversion and normalization, embedding dimensions and normalization, and text tokenizer/truncation limits. Record vision patch/token counts where exposed; otherwise mark them unknown (CLIP has no Qwen-style generation context/output budget). Trace overview and crop inputs through the actual CLIP preprocessor using the same geometry fixtures, inspect compiled input descriptors, and verify finite, repeatable embeddings. Persist the descriptor with CLIP evidence.

**Owner and gate:** the engineer implementing provider/runtime diagnostics owns Phase A; the source/crop implementer reviews the evidence. Record the model fingerprints, dependency revision, fixture outputs, and reviewer decision in a diagnostic report. Phase B source/crop implementation cannot begin until this checklist passes:

- Qwen and CLIP metadata agree with observed encoder inputs and compiled descriptors.
- Orientation and all four aspect-ratio fixtures have recorded, reproducible transforms.
- One-image Qwen behavior and bounded context/output handling are verified.
- Unsupported or unknown capabilities are explicitly recorded; required geometry cannot be unknown. A missing CLIP provider requires a signed-off degraded mode that disables CLIP evidence.

Independent decoder inspection and fixture preparation may proceed while this gate is pending. Re-run the affected checks after model or preprocessing changes.

Acceptance: the app can state exactly what dimensions the encoder receives for the selected model and show which original pixels survived preprocessing. Unknown capabilities must remain explicit.

## 5. Phase B: create a consistent, high-quality source

Introduce a review image provider distinct from the grid-thumbnail loader. It should expose:

1. An orientation-normalized overview.
2. Source dimensions, source type, color-space/render settings, and fidelity information.
3. Region decoding/cropping from the best available source.
4. A deterministic coordinate transform linking source, overview, mask, crop, and encoder input.

Prefer the largest useful embedded camera preview for a fast first pass. For Deep/Exhaustive detail passes, use RAW demosaicing where supported and appropriate, or the full-resolution raster for JPEG/HEIF/TIFF. A preview may already include camera sharpening, noise reduction, exposure adjustments, and limited resolution. Increasing a requested thumbnail size cannot recover detail missing from that preview.

Use separate, recorded render policies for technical detail and photographic appearance:

- Technical detail: controlled RAW processing; avoid added sharpening that would bias the measurement. Preserve existing scoring behavior initially and document its parameters.
- Appearance: a consistent, color-managed display render used for composition/exposure critique.

Select policies explicitly per request; never mutate a shared render in place. Cache keys include the policy and its parameters. Use this stage matrix:

| Stage | Render policy | Rule |
| --- | --- | --- |
| 1: source preparation | Both as needed | Produce separately identified sources with one coordinate system |
| 2: Qwen overview | Appearance | Composition, exposure, and discovery |
| 3: SAM masks | Appearance | Map masks to source before technical measurements |
| 4: measured detail / CLIP | Technical / appearance respectively | CLIP overview and matching crops use consistent appearance preprocessing |
| 5: Qwen crops | Appearance by default; technical for detail questions | Label render and purpose; technical crops cannot establish appearance/exposure claims |
| 6: follow-up | Policy matching the question | A changed render is new evidence, not a replacement of earlier evidence |
| 7–8: synthesis/comparison | Existing evidence; appearance overview/board if required | Compare detail only across compatible technical renders |

Keep both linked to the same source coordinates. Do not silently compare a camera-rendered image against an unrelated RAW render. Exposure assessment of a rendered preview does not establish recoverable RAW highlight/shadow latitude; use RAW-specific evidence before making recovery claims.

For Qwen, prepare an appropriate RGB render; preserve higher-precision source data for technical calculations where useful. Verify orientation, ICC handling, wide-gamut conversion, and HDR tone mapping on fixtures. Report decoder fallback and unavailable RAW support without failing all other stages.

Do not repeatedly encode crops as lossy JPEG. Prefer in-memory `CGImage` inputs and lossless cached review inputs when persistence is justified.

## 6. Phase C: crop planning that maximizes useful input

Run an overview discovery pass before planning detail work. Combine Qwen's proposed subjects with SAM 3 masks, existing subject labels, autofocus location, and user-selected regions. Treat Qwen proposals as candidates to verify, not established facts.

Build a deterministic region hierarchy:

| Region | Purpose | Preparation |
| --- | --- | --- |
| Whole image | Composition, context, relationships, large obstructions | Entire frame retained using verified preprocessing |
| Whole subject | Pose, visibility, subject separation | Mask bounding box plus contextual margin |
| Head/face | Expression, orientation, larger obstructions | Verified head/face region; fallback to subject with a warning |
| Eye or critical detail | Fine local detail | Only when reliably located; otherwise allow manual region selection |
| AF neighborhood | Camera focus evidence and local detail | Region around mapped AF location, checked against the intended subject |
| Ambiguous/problem region | Resolve a specific question | Targeted crop with enough nearby context |
| Overlapping tiles | Inspect large subjects without shrinking away detail | Deterministic source-space tiles under a bounded budget |

SAM 3 subject/head prompts do not guarantee precise eye localization. Do not infer an eye coordinate from a whole-head mask. A validated localization provider or a user region is needed for reliable eye-specific claims.

When reliable eye localization fails, skip automatic eye crops and record `eyeLocalizationUnavailable`. Continue with a verified head crop, then a whole-subject crop if the head is unavailable; include the AF neighborhood only if its mapping is valid. Do not block the run waiting for manual input. Offer a manual detail region for a later follow-up/rerun; user regions take priority within the same budget. A manual region establishes location, not an eye identity or sharpness finding. Without usable eye evidence, abstain from eye-specific comparisons. Fallback crops replace the unavailable planned crop and do not increase the crop allowance.

Crop from the original review source, never from the overview or existing object board. Use approximately 10–20% context padding as an initial tunable setting; retain unclipped geometry and record edge clipping. Prefer shapes compatible with the encoder's verified input strategy. Avoid distorting a narrow subject or allowing a center crop to remove it.

Use separate unannotated crops for detail judgment. Mask outlines and large labels can introduce artificial edges, obscure texture, or contaminate sharpness interpretation. Annotated boards remain optional relationship/identity aids, with prompts explicitly identifying overlays as annotations.

Track effective scale. If a source crop is C pixels wide and the useful encoder area is E pixels wide, the horizontal scale is E/C; record the analogous vertical scale and padding. Smaller source crops can preserve much more detail per encoder pixel. Upscaling a tiny source region does not create evidence and should reduce certainty.

For a large region, start tiling with 20–25% overlap and tiles sized near the useful encoder dimensions in source pixels. Adjust only after evaluating the actual model. Link overlapping tiles to one region/subject so repeated views are never counted as separate objects. Include one broader context crop when a tile's identity is ambiguous.

Prioritize user-designated subjects, heads/faces, AF regions, and unresolved questions. Deduplicate near-identical regions. Add a bounded second round only when it acquires new visual evidence. Stop when the pass budget is exhausted or additional crops no longer resolve uncertainty.

Acceptance: every crop has a stable ID, source rectangle, purpose, source fidelity, preparation transform, and actual encoder dimensions. Every accepted image gets analyzed; uninspected regions are disclosed.

## 7. Phase D: the combined evidence pipeline

### Stage 1 — snapshot, capability check, and source preparation

Freeze file identities, model fingerprints, criteria, depth, render policy, and region/pass budgets. Retain security-scoped access using the existing catalog-access pattern. Resolve available models before expensive decoding. Explain any degraded mode, such as Qwen critique without verified segmentation or technical detail.

### Stage 2 — independent overview assessment and discovery

Ask Qwen for a short structured scene assessment and candidate subjects. Run this before supplying earlier model opinions to preserve an initial visual judgment. Return observations, uncertainties, candidate concepts, and proposed areas to inspect. Validate schema and bounds; keep parse failures separate from photographic findings.

### Stage 3 — SAM 3 segmentation and identity mapping

Segment verified concepts, deduplicate instances using the existing object infrastructure, assess mask quality, and assign stable per-image subject IDs. Record rejected masks and fallback prompts. Map normalized coordinates into the orientation-normalized source. Reuse compatible cached masks; regenerate incompatible ones.

### Stage 4 — measured detail and CLIP evidence

For usable regions, reuse existing subject focus scoring for broad/local/fine detail and AF inclusion. Measure source detail separately from rendered board edges. If reusing the scorer requires new region-level inputs, extract a reusable service rather than copying algorithms.

Use CLIP for candidate-image similarity, semantic relevance to the stated goal, and supported subject/crop matching. Use the verified Phase A CLIP descriptor and preprocessing trace; its own encoder dimensions cannot be assumed to retain full source detail. CLIP similarity is not a calibrated photographic-quality score or a probability that a claim is true.

Compare technical scores only under compatible decode/render/scale settings. Record normalization and penalties. Do not average unrelated aesthetic, similarity, mask, and sharpness scores into an unexplained number.

### Stage 5 — independent Qwen crop inspection

Send individual crops as separate requests using the existing one-image runtime. Include only necessary region identity/context initially, not a prior conclusion such as “this is blurred.” Ask for visible observations, visibility, detail quality, expression where visible, obstructions, and uncertainty.

Use task-specific output schemas. Do not force eye/expression questions on landscapes or infer non-visible features. A low-resolution crop should allow “insufficient evidence.” Each response must cite its assigned region ID rather than invent additional IDs.

### Stage 6 — reconcile evidence and targeted follow-up

Give Qwen validated measurements and its independent observations, clearly identified by evidence source. Attach the corresponding appearance overview to reconciliation and per-image synthesis requests to satisfy the current image-required runtime; supplied typed evidence remains authoritative for detail claims. Ask it to explain agreement and disagreement. Example: apparent sharpness from a high-contrast feather edge does not establish that the eye is sharp.

A disagreement can trigger a fresh, tighter crop or a different source render within the budget. Repeating the same image and prompt is not independent verification. Keep unresolved contradictions visible. Mask uncertainty should propagate into subject-specific measurements and conclusions.

### Stage 7 — per-image synthesis

Produce a structured report containing subject inventory, composition observations, exposure/appearance observations, measured technical evidence, important crop findings, strengths, problems, uncertainty, and goal-specific recommendation. Every substantive claim should reference evidence IDs.

Validate references and reject unsupported IDs. Distinguish measured values, model observations, and recommendations. Treat model-reported confidence as uncalibrated until evaluated; do not multiply or average it into a statistical certainty.

### Stage 8 — compare selected photographs

Determine whether images are comparable using scene/subject evidence, time/burst metadata where available, CLIP similarity, and user intent. Present unrelated photographs as individual reviews unless the user explicitly requests a broader comparison.

Initially compare typed per-image evidence in application logic and supply a bounded evidence summary to Qwen with one app-rendered comparison board as the single `CGImage`. Build a deterministic 2048 × 2048 appearance board, ordered by stable image ID: two columns for 2–4 images, four for 5–8, with enough rows for all images. Reserve a 48-pixel header per cell for its image ID; aspect-fit the full frame into the remaining area with neutral padding, without cropping or stretching. Record each cell transform and mark labels as annotations in the prompt. For one image use its appearance overview. Validate all image/evidence references; board resolution is an initial layout choice, subject to the verified encoder preprocessing and evaluation. The inspected runtime requires an image and selects only one attachment, so a text-only synthesis request or true multi-image request needs a deliberate runtime extension. A comparison board is for composition/relationships, not the authoritative source of fine-detail findings.

For difficult near-ties, use limited pairwise comparisons with matched subject crops prepared at comparable scales. Use one side-by-side board per pair, with matched appearance crops and cited technical measurements; this remains one image attachment. Cap pair requests at 0/2/4 for Standard/Deep/Exhaustive respectively, including retries. Select pairs deterministically from goal-specific near-ties, record omitted pairs, and abstain if the cap leaves a tie unresolved; eight images already imply 28 all-pairs comparisons. Prefer a shortlist or goal-specific comparisons while retaining reports for every image.

Return separate technical and aesthetic tradeoffs, explicit tie/abstention states, and reasons for the chosen recommendation. Changing the goal may change the recommendation without requiring all visual evidence to be recomputed.

## 8. Proposed architecture and boundaries

Add a dedicated combined-review namespace, for example `RawCull/Intelligence/CombinedReview/`. Keep the existing burst `DeepAIReviewFeature` intact and reuse its backend services. Suggested components are design proposals, not existing APIs:

- `CombinedAIReviewController`: UI actions, immutable request snapshots, presentation state.
- `CombinedAIReviewCoordinator`: stage ordering, cancellation, progress, retries, evidence dependencies.
- `ReviewImageProvider`: overview/detail sources and render policies.
- `ReviewRegionPlanner`: crop hierarchy, tiling, prioritization, deduplication, budget enforcement.
- `ReviewEvidenceRepository`: typed artifacts and provenance.
- `ReviewSynthesisService`: schema validation and bounded evidence assembly.
- `ReviewComparisonService`: comparability, goal-specific rankings, ties, pairwise budgets.
- `ReviewResourceBudget`: decoded-image lifetime and model residency policy.

Compose these through `RawCullAIModelRuntime` and existing provider boundaries. Extract reusable discovery/segmentation/assessment operations from `RawCullObjectAnalysisFeature` instead of invoking the three UI features in sequence. Those features own separate state, caches, cancellation, and batch filtering that are unsuitable as orchestration APIs.

Keep UI updates on the main actor and inference, decoding, and scoring off the UI execution path. Preserve Qwen's generation gate. Coordinate SAM 3 and CLIP work explicitly; actor isolation alone does not prove bounded memory or serialized accelerator execution.

Update `AIAnalysisTool`, combined result presentation, availability checks, and cancellation routing. Give the combined coordinator ownership of its tasks; a sibling tool must not cancel one of its shared backends behind its back.

## 9. Evidence format, caching, and resumability

Define versioned Codable artifacts for run manifests, source renders, regions, masks, measurements, model observations, synthesis, and comparisons. A claim should contain its text/type, evidence IDs, uncertainty, and any contradictory evidence.

Compatibility keys must include:

- Source identity using established source-fingerprint semantics; optional stronger hashing as a separate policy.
- Orientation, dimensions, decoder/render parameters, color policy, source fidelity.
- Region geometry, crop preparation and actual encoder preprocessing.
- Model fingerprint, runtime version, prompt/schema version, generation settings.
- Criteria/goal for goal-dependent stages and pipeline version.

File UUID alone is insufficient. Model name alone is insufficient. Changing criteria should invalidate goal-specific assessment/synthesis while retaining compatible source renders, masks, and technical measurements. Changing encoder preprocessing must invalidate affected visual observations.

Use an envelope with integer `schemaVersion` (initially 1), artifact kind, producer pipeline version, and compatibility keys. Increment schema version for incompatible storage changes; version prompts, response schemas, preprocessing, and scoring independently. Decode through explicit version-specific types (for example `CombinedReviewRunV1`) and tested V1→V2 migrations. Migrations may preserve facts and geometry but must not fabricate missing evidence or mark stale results compatible. Unsupported future schemas are read-only/unavailable to this build. Retain older artifacts until explicit cleanup or normal bounded-cache eviction; never overwrite the only old copy during migration. A prompt/pipeline change invalidates affected stages and their descendants rather than migrating old observations into new ones.

Commit completed stage artifacts atomically and persist a run manifest. Cancellation stops new work but retains valid completed evidence. Resume only after compatibility checks; retry failed stages without regenerating everything. Preserve partial reports with an explicit incomplete status.

Track each image/region work item as pending, running, completed, failed, cancelled, or skipped-with-reason, with dependency IDs. On cancellation, discard unfinished output and stop enqueueing work; completed atomic items survive. Resume revalidates access, compatibility, and dependencies, returns interrupted items to pending, and runs missing prerequisites first. Stage 5 requires completed crop/source/identity preparation for that region, but deliberately does not require Stage 4 measurements because its observations are independent. Stage 6 requires terminal Stage 4 and Stage 5 outcomes (completed or explicitly unavailable); missing measurements permit an explicitly degraded report, never an implied measurement. Stage 8 waits for a terminal per-image report or explicit failure for every accepted image. Thus cancellation during Stage 4 can retain completed Stage 5 observations, but reconciliation cannot consume an unfinished measurement. Changed dependencies invalidate descendants even when those descendants previously completed.

Store derived images under a bounded cache with cleanup controls. Persist compact evidence by default; retain exact inputs when needed for reproducibility under an explicit storage policy. Respect catalog access and avoid exposing source paths in unnecessary diagnostic output.

## 10. Depth profiles and resource management

Initial budgets below are tunable starting points, not accuracy or speed promises:

| Profile | Initial Qwen overview/crop budget per image | Follow-up allowance | Source policy |
| --- | --- | --- | --- |
| Standard | One overview plus up to three prioritized crops | None by default | Best useful preview; explicit fallback |
| Deep | One overview plus up to eight crops/tiles | Up to two additional evidence requests | RAW detail where useful and supported |
| Exhaustive | One overview plus up to sixteen crops/tiles | Up to four additional evidence requests | Best source; user regions and bounded tiling |

Apply fixed selection-wide crop caps of 16/32/64 and follow-up caps of 0/8/16 for Standard/Deep/Exhaustive. For N accepted images, the initial crop limit is min(N × per-image cap, selection cap); follow-ups use the same rule. Allocate one prioritized crop per image before additional crops, then deterministic rounds across images. Always reserve one overview and one per-image synthesis per image; reserve any admitted reconciliation and selection-synthesis requests before optional crop work. Stage 6 gets at most one reconciliation request per image when both measurement and observation evidence exist. Stage 8 gets one selection synthesis for N > 1 plus the pair caps above. Total Qwen attempts, including retries, therefore cannot exceed 3N + crop limit + follow-up limit + (1 + pair cap when N > 1). For eight Deep images this is at most 67 attempts (24 + 32 + 8 + 1 + 2), rather than 64 initial crops alone. Context summaries must also fit the verified token budget; prune optional evidence by priority and disclose omissions.

Reserve mandatory coverage before optional work. Every request attempt consumes its category allowance; failures do not unlock unlimited retries. On overflow, omit lowest-priority optional regions, disclose coverage, and retain every image report. If mandatory work cannot fit configured limits, ask for an increased budget or smaller selection before starting. Selections above eight require an explicit expanded coverage/budget plan. Count SAM concept calls separately with a starting cap of four per image (including fallback/retry attempts); additional calls require a recorded budget change. Count CLIP inputs separately with at most one overview plus each admitted region per image. Display total estimated calls including synthesis and comparison stages. Count SAM concept calls separately. Permit configurable budgets for powerful machines without implying that unrestricted calls improve reliability.

Start with sequential inference, one source/detail working set, and bounded decode/scoring concurrency. Release full source buffers, masks, crop images, and response contexts once their consumers finish. Where region decoding is unavailable, decode a full source once under a budget and reuse it rather than decoding for every crop.

Estimate memory using actual pixel formats and buffers: an 8000 × 6000 RGBA8 buffer is about 192 MB in decimal units; float intermediates, RAW decode buffers, masks, model weights, and generation caches add more. For the same 48-megapixel source, a packed 16-bit single-channel RAW plane is about 96 MB, RGBA16F is 384 MB, and RGBA32F is 768 MB. An illustrative simultaneously live RAW plane + two RGBA16F processing buffers + RGBA8 output totals 1,056 MB before decoder scratch space, masks, model weights, and caches. Two RGBA32F intermediates instead raise that example to 1,824 MB. These are allocation examples, not CIRAWFilter guarantees: compressed files, decoder tiling, retained textures, and temporary copies change the peak. Inspect actual allocations and reserve headroom; do not admit a source solely from compressed file size. Unified memory is shared with the system.

Qwen currently retains its loaded model, and SAM 3 also retains loaded resources. Sequential calls do not guarantee that only one model is resident. Audit actual unload/reload APIs; introduce a measured residency policy where supported. Account for reload cost when deciding whether to group model stages across images or finish one image at a time.

Record cold/warm latency, per-stage durations, peak memory, and hardware/model identifiers. Use measured moving estimates for progress after the first image. On memory pressure, reduce queued work or unload supported resources; do not silently reduce analysis fidelity. Record any profile downgrade in the report.

## 11. Optional larger encoder inputs

Pursue this after the crop-first baseline is working:

1. Inspect the selected bundle's vision function tensor descriptors, patch/merge settings, projector shapes, position handling, and token limits.
2. Determine whether alternate shapes are supported by the converted assets and the complete inference path.
3. If supported, implement a capability-tested preprocessing option and verify image embeddings and language integration at each shape.
4. If unsupported, evaluate a new conversion/bundle or an alternative runtime with the required dynamic-resolution support.
5. Benchmark additional detail against memory, latency, and output reliability on the same photographs.

Do not simply edit `vision.image_size` in metadata. Encoder/projector/position/token assumptions can make a larger value invalid even if memory is plentiful. Do not assume upstream Qwen capabilities are preserved in converted Core AI assets.

Keep crop-first review available regardless of outcome. A larger whole-image encoder can still lose a tiny subject, while a focused crop can allocate most encoder pixels to it.

## 12. Validation and acceptance criteria

Follow the proposed [Combined Review evaluation specification](deepaireview-evaluation.md) for set size, annotations, reviewers, and metric definitions. Create a consented, reusable photographic evaluation set with human annotations. Include sharp backgrounds/soft subjects, tiny distant subjects, motion blur, noisy RAWs, multiple similar animals/people, partial occlusion, closed eyes, portrait orientation, low-resolution previews, unsupported RAWs, and unrelated selections.

Evaluate three baselines on the same model and source policies:

1. Existing whole-image Qwen analysis.
2. Existing Objects board analysis.
3. Combined overview plus individual source crops, measurements, and synthesis.

Measure incorrect sharp/blur claims, missed obstructions, subject-ID mix-ups, unsupported claims, ranking agreement, abstention behavior, and human usefulness. Report latency/memory separately from quality. Longer answers are not a success criterion.

Required deterministic tests:

- Orientation/coordinate round trips and mask-to-source mapping.
- Crop padding, bounds, tile coverage/overlap, and stable IDs.
- Encoder preprocessing preserves intended regions and records effective scale.
- Budgets include all stages; accepted images are never silently omitted.
- Unknown evidence IDs and malformed structured responses are rejected.
- Changed source/model/prompt/render/region settings invalidate the correct artifacts.
- Cancellation, resume, catalog access, partial failure, and model replacement preserve valid evidence safely.
- Comparable and unrelated selections, ties, and missing-stage results behave correctly.

Add optional real-model integration probes for actual preprocessing, single-image attachment behavior, token/context boundaries, and evidence fidelity. Do not make normal unit tests depend on downloadable models. Follow repository Swift Testing conventions when implementing tests.

Release criteria: demonstrable improvement over existing views on difficult detail cases; no unexplained source-coordinate mismatch; inspectable evidence for key claims; responsive cancellation; compatible resume; measured operation within configured memory budgets. Set numerical quality thresholds after collecting baseline results, before declaring release readiness.

## 13. Delivery sequence

### Milestone 1 — input diagnostics and source/crop foundation

Deliver capability inspection, actual encoder-input diagnostics, consistent source decoding, coordinate mapping, and manual/automatic crop extraction. Validate geometry and fidelity before connecting synthesis. Record Phase A sign-off before Phase B implementation; approve the storage-version contract and evaluation specification before implementing persisted evidence or quality scoring.

### Milestone 2 — useful single-image combined review

Deliver overview → segmentation → measured detail → individual Qwen crops → per-image report, with one selected image, progress, cancellation, and evidence inspection. Use current supported encoder size.

### Milestone 3 — persistence and small-selection comparison

Deliver typed stage artifacts, compatibility/resume, every-image coverage, comparability detection, goal-based tradeoffs, and selection-wide reports for the recommended 2–8 image range.

### Milestone 4 — adaptive depth and resource policy

Deliver bounded tiling, targeted follow-ups, user regions, depth profiles, timing estimates, and verified model residency behavior. Tune using both a smaller Apple Silicon Mac and a high-memory Mac Studio-class machine.

### Milestone 5 — larger-input research and qualification

Investigate alternate encoder shapes/bundles and true multi-image support separately. Ship only capabilities demonstrated by the converted model/runtime and evaluation results. Keep the established crop-first behavior as the fallback.

## 14. Open decisions to resolve during implementation

- What are the installed Qwen bundle's exact input size, strategy, context capacity, and supported shapes?
- Which RAW formats and full-resolution region operations are reliable in the current decoder stack?
- Can current model providers release heavy resources without losing configuration or corrupting active work?
- Should combined review continue when hidden, and how does it arbitrate shared inference with other tools?
- What retention policy balances exact-input reproducibility against disk usage?
- How should users assign priority among multiple subjects or aesthetic versus technical criteria?
- Does a stronger supported Qwen bundle improve crop reasoning enough to justify its memory/latency cost?

Resolve these through inspection and measured probes; they do not prevent documenting the crop-first baseline. Required input geometry blocks Phase B until the section 4 gate passes; optional capabilities may remain unknown under an explicit degraded mode.

## 15. References

- RawCull source paths listed in section 2 are the primary evidence for current app behavior.
- Core AI dependency paths listed in section 2 must be checked against the revision selected by the project when implementing changes; local DerivedData paths are not stable project references.
- [Official Qwen3-VL repository and inference guidance](https://github.com/QwenLM/Qwen3-VL): upstream capabilities and image handling; not a guarantee of converted Core AI behavior.
- [CLIP research paper](https://cdn.openai.com/papers/Learning_Transferable_Visual_Models_From_Natural_Language_Supervision.pdf): image/text embedding role; similarity must not be presented as calibrated photographic quality.


## 16. Numbered implementation plan and milestone tracking

This is the executable delivery plan. Each numbered phase is a milestone; sections 4–12 define its technical requirements and the companion evaluation specification defines qualification. The earlier lettered phases remain design references; this numbered sequence supersedes section 13 for implementation tracking. Complete each exit gate before starting dependent implementation. No phase is complete merely because code builds.

### Phase 1 — establish the model input contract

**Status: complete, 9 October 2026. Dependencies: none. Milestone: verified Qwen and CLIP input diagnostics.**

1. Inspect the pinned PhotoAIKit and Core AI providers, runtime preprocessing, metadata defaults, and attachment handling. Record dependency revisions from Package.resolved with the diagnostic report.
2. Expose read-only Qwen identity, compression, configured vision dimensions/strategy/image tokens, context capacity, single-image request contract, and response bounds through `QwenInferenceServing`. Expose validated CLIP preprocessing/tokenizer configuration through `RawCullAIModelRuntime`, paired with its existing backend fingerprint. Missing metadata remains unknown with a diagnostic reason; it must not break the existing Qwen workflow.
3. Separate declared settings from observed encoder inputs. A provider identifier is not a verified content hash; compiled shape support, runtime version, total context accounting, and observed geometry require additional evidence.
4. Add landscape, portrait, square, extreme-ratio, and orientation fixtures with circles, corner markers, and grids. Capture decode dimensions, actual preprocess transforms, tensor descriptors, and encoder dimensions for Qwen and CLIP. Check repeatable finite CLIP embeddings and Qwen single-image/context/output boundaries using opt-in real-model probes.
5. Save a reproducible diagnostic report containing model fingerprints, dependency revisions, fixture outputs, unknowns, and the section 4 gate decision. Obtain the implementation/source reviewer decision; degraded CLIP operation requires an explicitly recorded decision.

**Exit gate:** all section 4 checks pass for the selected models. Required geometry cannot remain unknown. Tests must not download models. Phase 2 remains gated until observed geometry is verified.

**Delivered:** read-only Qwen and CLIP capability snapshots, Qwen configuration hashing and safe unknown geometry handling, model lifecycle tests, and the opt-in `make combinedinputstest` hostless diagnostic runner. Eleven synthetic fixtures verify all eight orientations and four aspect-ratio categories against the exact pinned preprocessors and compiled inputs. Actual Qwen overview/crop encoding, single-image generation, image/context/output token accounting, CLIP finite/repeatable embeddings, source crops, Float16 binding, and tokenizer truncation passed. The [input-contract decision](combined-review-input-contract.md) records content fingerprints, dependency revisions, retained fixture previews, unknowns, and the engineering source-contract review. The geometry gate passes for the three recorded installed bundles; revalidate changed models/preprocessing. `make test-smoke` passed with 258 enumerated identifiers (257 passed; one opt-in model test skipped), and hostless Release contracts passed. Commit this milestone before beginning phase 2.


**Inspected dependency baseline:** `coreai-models` at `1953c4f90ba0214c1abc7bebcb9be5107e329a46`; `photoaikit` at `7f9adfcd69661c6bae4a640c16a4056dfc7393df`. These revisions identify source inspection, not successful real-model verification.

### Phase 2 — build the source and coordinate foundation

**Dependencies: phase 1 geometry gate. Milestone: reproducible source-space crops.**

1. Introduce a review source service independent of grid thumbnails, returning normalized orientation, source identity/fidelity, dimensions, color/render policy, and coordinate transforms.
2. Reuse preview/RAW decoding; keep technical and appearance renders distinct, with explicit unsupported RAW fallback. Verify ICC, gamut, HDR, and orientation fixtures. Record technical sharpening/noise settings.
3. Implement source-space crop extraction, padding/clipping, mask/overview mapping, stable region IDs, effective encoder scale, and lossless exact-input retention hooks.
4. Add deterministic round-trip, bounds, aspect-ratio, source-fidelity, and policy-isolation checks. Measure one full-source working set before admitting large RAWs.

**Exit gate:** crops originate from the best declared source, intended pixels survive verified preprocessing, and every coordinate round trip passes. No synthesis or quality claims yet.

### Phase 3 — define run, evidence, storage, and budgets

**Dependencies: phases 1–2. Milestone: resumable, bounded run contract.**

1. Define immutable selection/criteria/model/render snapshots and typed image, subject, region, observation, measurement, limitation, and report IDs. Include evidence provenance and unknown/unavailable states.
2. Implement the section 9 V1 envelope, stage compatibility keys, atomic artifacts/run manifests, bounded derived-image cache, unsupported-version handling, and migration policy. Review the storage contract and evaluation protocol before persisted evidence/scoring work.
3. Model pending/running/completed/failed/cancelled/skipped work with dependencies. Implement invalidation propagation, interrupted-item reset, retry accounting, and compatibility-checked resume.
4. Implement section 10 coverage-first budgets for Qwen, SAM, CLIP, reconciliation, and comparison. Reserve mandatory work; every failed attempt consumes allowance. Snapshot all accepted files and retain catalog access.
5. Test cancellation/resume, source/model/prompt/render changes, future schemas, atomic partial results, budget overflow, and complete accepted-image coverage without real models.

**Exit gate:** cancellation preserves only completed compatible evidence; resumed work respects dependencies and fixed budgets; no accepted image disappears.

### Phase 4 — deliver single-image Combined Review

**Dependencies: phases 1–3. Milestone: usable single-image review with evidence inspection.**

1. Add an independently owned Combined Review feature and fourth AI Analysis view, with criteria, source, depth, progress, start/cancel/resume, and preserved results. Define shared inference arbitration and catalog/model replacement cancellation explicitly.
2. Connect independent overview/discovery, existing SAM instance deduplication, subject IDs/mask quality, and deterministic crop planning. Prioritize user regions, verified head/subject regions, and valid AF mapping. Skip unavailable eyes with recorded fallback; never infer eyes from head masks.
3. Extract reusable technical measurement services where necessary; do not duplicate focus algorithms. Add CLIP relevance/matching with recorded configuration, without presenting similarity as quality or probability.
4. Run independent unannotated Qwen crop requests, validate structured schemas/evidence IDs, reconcile only terminal measurement/observation outcomes, and produce a per-image report with coverage and uncertainty.
5. Provide inspectable locations/masks, exact inputs under retention policy, and explicit partial/degraded reports. Exercise integration with fake providers and opt-in real models.

**Exit gate:** one image produces a grounded report, absent evidence prompts abstention, malformed output is a stage failure, and navigation/cancellation preserve valid results. No automatic rating, rejection, deletion, or editing.

### Phase 5 — deliver small-selection comparison

**Dependencies: phase 4. Milestone: complete 2–8 image review and goal-based tradeoffs.**

1. Run all accepted images under selection-wide budgets, with deterministic fair crop allocation and per-image terminal outcomes before selection synthesis.
2. Detect comparability using subject/scene evidence and compatible technical render/scale settings. Handle unrelated images, ties, conflicting criteria, and insufficient evidence explicitly.
3. Implement bounded pair comparisons using the section 7 contract, stable image/subject references, and validated selection reports. Keep CLIP scores separate from photographic judgments.
4. Show per-image strengths/weaknesses and comparisons with evidence links. Require an explicit expanded coverage plan for selections above eight.
5. Test unrelated groups, missing stages, subject identity swaps, ties, resume after selection changes, and mandatory synthesis reservation.

**Exit gate:** every image has a report or explicit failure; unrelated selections are not forced into a ranking; all comparison claims reference compatible evidence.

### Phase 6 — add adaptive depth and measured resource control

**Dependencies: phase 5. Milestone: predictable Standard, Deep, and Exhaustive execution.**

1. Add deduplicated overlapping tiles, bounded question-driven follow-ups, manual region reruns, and effective-scale warnings using section 6 priorities.
2. Enforce profile and selection caps, context-pruning disclosure, separately counted backend attempts, and immutable recorded budget changes.
3. Measure cold/warm timings, peak allocations, working-set release, memory pressure response, and supported model unload/reload. Tune on smaller and high-memory Apple Silicon systems.
4. Add measured progress estimates and storage cleanup controls. Record any chosen fidelity/profile change rather than silently applying one.

**Exit gate:** all profiles stay within admitted budgets and measured memory limits, cancellation remains responsive, and optional work never displaces mandatory image coverage.

### Phase 7 — qualify the crop-first feature

**Dependencies: phases 4–6; dataset preparation may begin earlier. Milestone: documented release decision.**

1. Execute `deepaireview-evaluation.md`: 120 consented images/30 groups, isolated development/held-out split, independent dual annotations, adjudication, and versioned JSONL provenance.
2. Run whole-image Qwen, Objects board, and Combined Review with frozen settings; evaluate Standard and Deep separately, including failures/degraded runs and repeated generations when nondeterministic.
3. Record development-derived numerical thresholds before held-out access. Measure unsupported/contradicted claims, detail errors, obstructions, identity errors, rankings, abstention, unrelated forced rankings, usefulness, latency, and memory with denominators/uncertainty.
4. Verify all section 12 deterministic contracts and evidence inspection. Publish results and a go/no-go decision; failed held-out tuning requires a new untouched split.

**Exit gate:** demonstrated difficult-detail improvement, zero deterministic identity/coordinate/evidence-reference violations, and all frozen quality/resource tolerances met. Dataset consent and reviewer decisions are real external prerequisites, not simulated test results.

### Phase 8 — investigate larger encoder and multi-image capabilities

**Dependencies: qualified crop-first baseline. Milestone: evidence-backed capability decision.**

1. Inspect converted tensors/projectors/positions/tokens and runtime attachment support. Evaluate alternate shapes/bundles only through the entire supported inference path.
2. Compare detail, quality, latency, and memory against identical crop-first cases. Version preprocessing/compatibility keys for any supported extension.
3. Ship only verified improvements and rerun affected qualification checks. Record an unsupported/no-change outcome as a valid research milestone.

**Exit gate:** each enabled capability has reproducible end-to-end evidence; crop-first review remains available. Editing `vision.image_size` alone never qualifies a capability.
