# Evaluation of Combined Review, phases 1–5

Date: 10 October 2026. Evaluation type: retrospective inspection of one complete six-image run, its persisted evidence, the supplied reference JPGs, and the current implementation.

## Overall assessment

The engineering foundation is substantial: immutable inputs, bounded requests, persisted provenance, explicit failures, retained crops and conservative selection abstention are present. This run does **not** establish reliable photographic evaluation. Two concrete problems undermine the technical evidence: grayscale masks are consumed as alpha by the focus scorer, and some persisted subject/head coordinates select the wrong image content. Structured acceptance also permits inaccurate overview statements and reports that merely repeat measurements rather than explain the photograph.

Phases 1–3 have useful engineering evidence, with additional integration corrections required. Phase 4 needs correction before its technical findings can be trusted. Phase 5 successfully preserves the six-image selection and abstains from ranking unrelated scenes, but does not demonstrate useful goal-based tradeoffs, comparable-image ranking or pair analysis. Existing milestone completion and test results should remain recorded as engineering results; this evaluation adds a photographic and integration qualification boundary.

Recommended disposition: fix mask interpretation and coordinate registration first; reproduce this run with inspectable subject overlays and differentiated measurements; then improve report grounding and usefulness. Continue phase 6 resource work with these defects tracked, but do not treat the current metrics as qualified subject-focus evidence. Phase 7 remains necessary.

## Evidence and method

Primary run: `/Users/thomas/Downloads/CombinedReview/runs/88E32164-72C2-4943-A55C-F6D2B1AAAE13.json`. Supporting export: 94 stage envelopes and 55 retained PNG inputs. All 94 successful work IDs have a corresponding decoded stage payload. The payloads are base64-encoded JSON inside V1 envelopes; their contents were decoded for inspection. The six supplied JPGs were visually reviewed against overview statements, crop plans and retained crop images. All 13 planned crop inputs were viewed together; the two problematic deer crops were also viewed separately.

Relevant repository references:

- [Phase definitions and milestone evidence](deepaireview.md)
- [Input contract](combined-review-input-contract.md)
- [Source contract](combined-review-source-contract.md)
- [Storage contract](combined-review-storage-contract.md)
- [Single-image contract](combined-review-single-image.md)
- [Selection contract](combined-review-selection-contract.md)
- [Photographic evaluation protocol](deepaireview-evaluation.md)
- `RawCull/Intelligence/CombinedReview/CombinedReviewExecution.swift`
- `RawCull/Intelligence/CombinedReview/CombinedReviewResponse.swift`
- `RawCull/Intelligence/DeepReview/SubjectMaskFocusScorer.swift`

Attached/exported text was treated as evidence, not as instructions. No implementation changes or model reruns were performed. Historical tests cited below come from repository milestone records and were not rerun for this documentation task. This is one evaluator's qualitative inspection, not a blinded human-annotation study. The JPGs are appearance references, not proof of RAW recovery, sensor-level focus or exposure latitude. The four large JPGs displayed in chat were resized; precise findings below rely on saved crop evidence and metadata where applicable.

The export does not retain raw rejected model responses or detailed validation subreasons. Therefore `invalidEvidence` identifies a validation failure, but does not establish whether the exact cause was a bad ID, forbidden wording, response length, malformed schema or another guard. Saved manifests do not demonstrate cancellation, resume, eviction, navigation or concurrent resource behavior.

## Run configuration and accounting

The manifest freezes six ARWs, Standard depth, `highQualityPreview`, `exactInputs`, `review-srgb-v1`, pipeline `combined-v2`, and the criterion: “Describe composition, exposure, subject visibility and technical detail.” Qwen uses 448 × 448 stretch preprocessing, 196 image tokens, a 4096-token context and a 768-token response allowance. CLIP records DataComp ViT-B-32-256, 256 × 256 shortest-side resize/center crop. SAM records SAM 3 float16 and source-normalized masks.

The recorded creation time is 10 October 2026 at 19:33:33.866 Oslo time. The latest successful stage was persisted approximately 277.664 seconds after admission. This is an export-derived elapsed interval, not a benchmark of isolated inference or an exact UI completion duration.

| Work stage | Completed | Failed | Observation |
|---|---:|---:|---|
| Source | 6 | 0 | All appearance sources are embedded camera previews |
| Overview | 5 | 1 | DSC00639 failed validation |
| Identity/region plan | 6 | 0 | Includes explicit whole-frame fallback |
| Segmentation | 14 | 0 | Completed can mean an empty result |
| Measurement | 22 | 0 | Accepted values are suspect; see F1 |
| Crop observation | 13 | 0 | Schema success does not prove location/semantic correctness |
| CLIP | 19 | 0 | Six overviews and thirteen crops |
| Reconciliation | 4 | 1 | _DSC6564 failed validation |
| Per-image report | 4 | 2 | DSC02022 and DSC00113 failed validation |
| Selection comparison | 1 | 0 | Unrelated/abstain, zero claims |
| **Total** | **94** | **4** | **98 terminal work items** |

All four accepted per-image reports have `incomplete: true`. Report success is 4/6 (66.7%); overview success is 5/6 (83.3%). Work-item acceptance is 94/98 (95.9%), but this figure is dominated by deterministic and measurement stages and is not a photographic accuracy score.

Charged attempts / selection limits: overview 6/6, SAM 14/24, crop 13/16, CLIP 19/22, reconciliation 5/6, report 6/6, comparison 1/1. No budget amendments are recorded. These sum to 64 charged category attempts; this differs from work-item count because source, identity and measurement work is also persisted. Failed attempts remain charged. Three optional crop slots remain unused, consistent with the documented reservation policy; this alone is not evidence of a budget bug.

## Phase 1 — model input contract

**Assessment: useful verified baseline; current export contains qualification gaps.**

The repository records eleven synthetic input fixtures, orientation/aspect-ratio checks, actual pinned Qwen/CLIP preprocessing, compiled inputs, finite/repeatable CLIP embeddings and installed-model probes. Those support the declared input contract for the recorded bundles. This run preserves model identities, runtime revisions, preprocessing and encoder geometry, making its inputs more auditable than a prose-only review.

Qwen stretches landscape and nonsquare crop inputs to 448 × 448. Geometry is declared, but animals and scene proportions can be distorted. The 2048-square six-image comparison board reaches that same 448-square encoder: a 512 × approximately 341-pixel photograph cell becomes approximately 112 × 75 encoder pixels. Such a board can support coarse scene relationships, not subject focus or subtle detail.

CLIP's snapshot explicitly contains `encoderGeometryVerified: false` despite configured 256 × 256 geometry. Preserve this distinction: recorded configuration and geometry traces do not themselves prove compiled-tensor verification for this run. SAM's model identity uses `file-metadata-v1` and `isCryptographicallyVerified: false`; it is weaker than a content fingerprint. These are audit limitations, not proof that the encoders malfunctioned.

Required follow-up: reconcile the CLIP verification flag with the phase 1 gate; record observed verification separately from configured geometry; strengthen SAM identity where feasible. Exercise the actual installed SAM-to-crop and SAM-to-scorer path, because synthetic preprocessor tests did not prevent F1/F2.

## Phase 2 — source and coordinates

**Assessment: source fidelity disclosure works; semantic coordinate correctness fails in this sample.**

DSC00639 and DSC00113 appearance sources are 1616 × 1080 previews. The other four are 4096 × 2731 previews reduced from 8640 × 5760. All six declare sRGB SDR RGBA8, unknown camera sharpening/noise/exposure processing, and no RAW recovery claims. Separate technical source identities appear on measurements; the run should not be described as six full RAW technical decodes. The earlier phase 5 smoke probe's eligible RAW decode results are a separate experiment.

Region records retain requested, padded and clipped rectangles, source identities, encoder scales and input references. That makes wrong crops discoverable. However, `intendedRegionRetained: true` establishes geometric retention of the requested rectangle, not correct anatomical content. The deer head-labelled crop demonstrably contains a fawn torso; another deer-labelled crop contains mostly background. The main mallard's crop cuts off much of the bird at the lower edge. The source-space contract therefore needs an end-to-end semantic registration check, not just transform arithmetic.

## Phase 3 — evidence, storage and budgets

**Assessment: terminal accounting and inspectability pass; failure diagnosis and measurement validity need strengthening.**

The export has one immutable run envelope, 98 terminal work items and decoded payloads for all 94 completed items. Every accepted image has a report or explicit report failure. Later images continue after failures. Category allowances are respected, and missing/omitted evidence remains visible. These are positive results.

Limitations: four failures share the generic `invalidEvidence` reason; raw failed outputs and exact rejection checks are unavailable. Detailed provenance cannot rescue incorrect mask semantics. Context pruning is recorded but the saved selection outcome does not explain which useful evidence was excluded. This run alone cannot verify atomic crash recovery, future-schema handling, transitive invalidation, cancellation or compatible resume. Repository contracts report tests for those behaviors, but they need separate execution evidence if release qualification requires it.

## Phase 4 — single-image evidence and reports

**Assessment: partial workflow succeeds; technical trust and report usefulness fail important checks.**

Discovery generally recognizes the scene. SAM produces retained identities for five photographs, crop observations are accepted for all thirteen regions, and four reports are persisted with limitations. The cormorant image falls back to a whole-frame crop after overview validation fails; it remains represented throughout the selection.

The main defects are masked detail scoring (F1), crop registration/head association (F2), and insufficiently discriminating prose (F3). Report content is often one texture sentence plus duplicated numeric vectors. That does not adequately satisfy composition, exposure, visibility and technical-detail criteria. The rabbit report omits the strongest narrative feature—eating a flower—and cites flower subjects for numeric “detail.” The mallard report treats a blurred secondary crop as composition and repeats metrics from other subjects. The two failed reports also leave useful independent evidence unsynthesized.

Reconciliation is generated by the same model and is not independent corroboration. _DSC6564's reconciliation fails while its final report succeeds, showing graceful continuation, but not validation of the final photographic interpretation.

## Phase 5 — small-selection comparison

**Assessment: conservative selection handling passes; comparative usefulness is unproven.**

The selection artifact contains all six board cells in stable image-ID order, `comparability: unrelated`, `decision: abstain`, no preferred images, no claims, `contextPruned: true`, fifteen omitted pairs and no pair reports. The reason is “Different scenes; retain individual reports.” This is appropriate for different wildlife subjects/scenes under descriptive criteria, especially with two missing reports and questionable measurements.

Fifteen is the number of possible pairs among six images. Standard depth permits zero pair requests; omitted pairs are expected and do not indicate fifteen failed comparisons. The saved outcome provides no comparative strengths/weaknesses or goal-specific tradeoffs. It supports the safe unrelated-selection path, not tie resolution, comparable burst selection, matched-scale technical ranking or Deep/Exhaustive pair behavior. The comparison's manifest image ID is DSC00639's ID, but its payload contains all six cells; this is not evidence that five images disappeared.

## Detailed findings

### F1 — subject masks are effectively scored as whole-frame coverage (high priority)

All measurements within each photograph are exactly identical across every recorded numeric field, despite different subject masks and positions:

| Image | Measurements | subjectDetail | fineDetail | maskCoverage |
|---|---:|---:|---:|---:|
| DSC02022 | 3 | 0.287525594 | 0.081336632 | 0.987829626 |
| _DSC6564 | 2 | 0.056534167 | 0.015829748 | 0.987829626 |
| DSC00113 | 2 | 0.082788453 | 0.019920580 | 0.987678766 |
| DSC05921 | 8 | 0.128158778 | 0.036586054 | 0.987829626 |
| DSC09214 | 7 | 0.069827639 | 0.026216865 | 0.987829626 |

The first retained subject mask from each of these five images is an opaque grayscale PNG (`L`, range 0–255). `SubjectMaskFocusScorer.maskAlpha` draws the mask into RGBA and returns every fourth byte—the alpha channel—rather than grayscale intensity. An opaque grayscale mask supplies opaque alpha even where its intensity is black. The scorer then admits nearly every interior pixel. The approximately 98.78% coverage agrees with full interior-frame coverage after the scorer's border exclusion.

**Conclusion:** the export and code strongly support a mask-representation integration defect, not twenty-two independent subject-detail findings. Background texture can drive the resulting scores, and the foreground/background birds cannot be differentiated. The exact runtime conversion should be confirmed with an installed-path regression before calling the root cause fully reproduced.

**Remedy/acceptance:** define mask encoding explicitly; consume grayscale intensity for grayscale masks and alpha for alpha masks. Verify foreground count against the supplied mask. Score two disjoint masks on one image with deliberately different texture and require differentiated results; repeat on DSC00113's foreground/background birds. Invalidate old measurement/report/comparison artifacts through stage versioning when corrected. Do not relabel these existing numbers as calibrated focus scores.

### F2 — wrong subject/head crops pass geometric checks (high priority)

DSC02022 region `7f9b088e06ca94eb469934c922fc7c5b2c15414aa5a66d725f82a7398411502e` is labelled “Head candidate within deer; eyes unverified.” Its retained input `734e0249ec4ad2240d0638e503c0187e836cfaf48e840c01c919a94dc2103a60.png` shows a fawn's torso/legs and part of the adult, not the adult head. Region `a7e154baaffd6312618a8e1ebb9b99b475d735a20a2330ba8f0d1feb44e08676`, input `24d4abf2def4aac031f23e231b4deff3d42db61bf5858e685011ecf3afc11b20.png`, is labelled deer but is almost entirely blurred vegetation.

The deer/fawn normalized bounds start at y=0 despite the fawns occupying the lower reference frame. That suggests a coordinate-origin or bounds-registration issue. A vertical-origin mismatch is a plausible hypothesis, **not a proven universal root cause**: inspect SAM mask/bounds conventions, normalization, Core Graphics drawing and crop transforms separately. The rabbit head crop is correctly located, so a blanket flip would be unjustified.

DSC09214's primary bird crop (`999ca382e3f04bee2f9e0732261dfcb1c0b918ec518bfeba499646e0d0fbba08.png`) includes much background and clips the bird near the bottom. DSC00113's second head crop clips the lower face. The left swan crop also places anatomy against the edge despite a nominal whole-subject request.

**Remedy/acceptance:** overlay actual retained masks and bounds on the same normalized source; verify every known subject and head location. Recompute crop bounds from registered foreground pixels where appropriate. Require semantic/anatomical head support beyond containment inside one subject rectangle; otherwise label it a generic candidate region. Test real SAM outputs with subjects near all frame edges.

### F3 — accepted prose can be inaccurate or unhelpful (medium/high priority)

DSC00113's overview says the birds are in focus; the reference clearly distinguishes a detailed foreground bird from a blurred rear bird. DSC09214's uncertainty says “consistent focus and exposure” despite varied subject focus. DSC02022 says “no obstructions” even though animals overlap and the fawns are clipped. These are accepted statements, not rejected outputs.

DSC09214 reconciliation additionally repeats the values of subject `0:7` while citing subject `0:6`; exact equality makes that numerically invisible. F1 must be fixed before provenance/value mismatches can be meaningfully tested. The crop reporting no clear deer subject still has `insufficientEvidence: false`, exposing a mismatch between prose and the structured flag.

**Remedy/acceptance:** require subject-specific scope and uncertainty; preserve conflicting overview/crop findings; check insufficient-evidence consistency. Generate numeric summaries deterministically rather than asking Qwen to transcribe vectors. Require useful coverage of the requested criteria without inventing absent evidence. Test accepted semantic errors, not only malformed responses and unknown IDs.

### F4 — report failures are safe but insufficiently diagnosable (medium priority)

DSC00639 overview, _DSC6564 reconciliation, DSC02022 report and DSC00113 report fail with `invalidEvidence`. Rejection keeps invalid outputs out of stored findings. The precise causes cannot be reconstructed from this export.

**Remedy/acceptance:** persist bounded rejection diagnostics and, under an appropriate diagnostic retention setting, rejected response text. Distinguish schema, ID, unsupported-domain, length and grounding errors. Preserve completed independent observations and show an evidence-only deterministic summary when synthesis fails, explicitly labelled as such. Do not silently retry or weaken validators.

### F5 — crop priority does not guarantee subject coverage (medium priority)

The rabbit plan has eight subjects: one rabbit plus seven flower subjects, nine candidate regions including a head. Two crops are inspected and seven omitted. The mallard plan retains seven birds, inspects two and omits five. Deer and sparrow plans each omit one region. Across the run, thirteen crops are inspected and fourteen candidate regions omitted. “Candidate regions” is not a count of missed animals: flower subjects and head/whole-subject alternatives contribute.

Segmentation confidence/ordering is not necessarily photographic importance. Main-subject relevance should be explicit, with a separate policy for contextual flowers/rocks. Fix registration first, then prioritize one valid main-subject region per image before secondary anatomy or background concepts. Keep omissions and unused reserved capacity visible.

## Image-by-image photographic evaluation

These observations describe the supplied appearances; they do not assign calibrated ratings or automatic keep/reject decisions.

| Image | Reference appearance | Run result and assessment |
|---|---|---|
| DSC00113 | Two sparrows on a fence; strong foreground/background focus separation, cool blue background, dark facial tones and visible foreground feather detail. | Two subjects, three crops, one omitted region; report fails. Overview incorrectly generalizes focus to both birds. Identical per-bird measurements miss the defining technical difference. |
| DSC00639 | Multiple cormorants on rocks; broad pale water/sky space, distant subjects, wing/pose variety and a partial bird at the right edge. | Overview fails; no subjects or measurements; one whole-frame fallback crop. Accepted report describes rocks and diffused light but undercovers bird visibility, spacing and composition. Safe partial output, low descriptive usefulness. |
| _DSC6564 | Two swans with inward-curved necks and reflections; bright subjects against dark surroundings, extensive environmental space and foreground reeds. | Two subjects/two crops, no omitted regions; reconciliation fails; report succeeds partially. Main scene description is accurate. Numeric detail cannot distinguish the swans; crop visibility uncertainty is overly broad. |
| DSC02022 | Adult deer with two overlapping nursing fawns; adult face/coat detail, bright greenery, tight lower/right framing and a strong behavioral moment. | Three subjects, three crops, one omitted region; report fails. Wrong head/background crops undermine anatomy and technical evidence. Overview misses overlap/framing limitations. |
| DSC09214 | A central mallard stands out in focus against several softer birds and autumn reflections; small subjects, dark tones and a sloping waterline. | Seven birds, two crops, five omitted; report succeeds partially. Primary crop clips the bird; overview's focus consistency is inaccurate. Final claims favor generic blurred texture and repeated measurements over focus separation and scene composition. |
| DSC05921 | Rabbit on rock eating a purple flower; visible fur, upright ears, flower foreground, soft green background and a clear behavioral story. | Rabbit plus seven flower subjects, two crops, seven omitted; head crop is useful. Partial report describes fur but neglects behavior and composition; two numeric claims cite flower subjects and duplicate the same frame-derived values. |

## Prioritized completion and verification plan

1. **Correct mask semantics and invalidate dependent measurements.** Verify with real retained grayscale masks and contrasting foreground/background texture. Establish that subject coverage reflects foreground rather than opaque alpha.
2. **Correct bounds/crop registration and head labelling.** Use DSC02022, DSC09214 and DSC00113 as concrete regressions; confirm overlays and crops against the normalized appearance source. Keep rabbit as a positive control.
3. **Improve accepted report grounding and utility.** Preserve selective focus and occlusion evidence; avoid numeric transcription and unsupported blanket claims; expose failed synthesis with bounded diagnostic reasons.
4. **Rerun the six images under the same frozen settings.** Require all six terminal outcomes, explicit failures where needed, valid per-subject scores, anatomically justified labels and retained input inspection. Compare corrected evidence with this export rather than only checking stage completion.
5. **Evaluate phase 5 on genuinely comparable photographs.** Add bursts/near-ties, one intentionally blurred frame, exposure differences and ambiguous multi-subject scenes. Exercise Standard abstention and Deep/Exhaustive matched pairs; verify compatible crop scales and evidence ownership.
6. **Complete resource and independent photographic qualification.** Measure peak memory, thermal behavior, cancellation and latency distributions in phase 6. In phase 7 use independent human labels and the repository protocol to measure claim accuracy, missed subjects, unsupported anatomy, abstention and preference agreement.

## Qualification decision

This sample supports bounded orchestration, source disclosure, inspectable retained inputs, failure isolation and conservative unrelated-selection handling. It exposes an important gap between valid evidence IDs and valid photographic evidence. Technical subject-detail claims from this run should be treated as unreliable until F1/F2 are corrected and rerun. The accepted selection abstention is appropriate; no winner or quality ranking is justified. The report is an engineering and photographic evaluation of this export, not general camera/model qualification or proof that phases 1–5 meet every product-quality gate.
