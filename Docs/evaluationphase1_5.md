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

## Detailed remediation plan — review of the supplied proposal

Plan review date: 11 October 2026. This section reviews the supplied eight-phase proposal against F1–F5 and the current repository. It defines future implementation and qualification work; it does not change the historical findings above or claim that fixes or tests have been completed.

### Review conclusions and required adjustments

The proposal's representation-first approach is sound. Explicit mask semantics, versioned evidence, registered crops, grounded synthesis and bounded diagnostics address the central failures. Proceed with these corrections, subject to the following refinements:

- **Reproduce F1 before declaring the runtime cause proven.** The retained grayscale masks and alpha-reading implementation strongly support the diagnosis. A deterministic test plus the installed SAM/retention/scorer path must establish exactly where interpretation changes.
- **Extend existing geometry and inspection infrastructure.** `ReviewImageGeometry.swift` already defines top-left normalized coordinates, orientation transforms, region clipping and encoder traces. `ReviewRegionRecord` already stores requested, padded, clipped and retained rectangles. `CombinedReviewView.swift` already offers subject masks, source inspection and exact crops. Audit and connect these paths rather than introduce competing coordinate helpers or duplicate metadata.
- **Use the existing compatibility contract as the invalidation authority.** `ReviewPipelineContract`, `ReviewCompatibility` and `ReviewArtifactStore` already version and check stage artifacts. A scorer version is useful provenance, but checking an optional field during synthesis alone cannot prevent stale reconciliation or comparison reuse.
- **Distinguish storage representation from foreground interpretation.** Grayscale and alpha identify channels; binary describes value semantics and is not necessarily a third independent channel encoding. Specify channel, threshold, value range and resampling explicitly. Do not guess from an opaque alpha channel.
- **Do not reject valid edge cases by an arbitrary occupancy range.** Large subjects can fill the frame and true subjects can touch image edges. High occupancy should produce a traceable diagnostic or limitation; distinguish a declared whole-frame fallback from verified subject evidence. Empty or uninterpretable masks must abstain.
- **Do not prescribe a blanket vertical flip.** F2 could involve producer bounds, mask raster orientation, source mapping or anatomical association. The correctly located rabbit crop is a required positive control.
- **Add F5 explicitly.** Registration fixes alone do not ensure the rabbit takes priority over flowers or the principal mallard receives a useful crop. Main-subject coverage and omission reasons need their own work package.
- **Treat prose grounding as a bounded guarantee.** Valid IDs, subject ownership and claim types can be enforced deterministically. They do not prove visual truth or anatomical plausibility. Semantic acceptance still requires image inspection and independent evaluation; a list of forbidden generic phrases is insufficient.
- **Build tests with each change.** Regression work is a prerequisite and an acceptance gate for each package, not the last phase after implementation.

Correct the proposed acceptance statement “identical masks produce different scores when the subject location differs”: the deterministic control is **the same image with different masks over deliberately different textures**. Identical image/mask/parameters should produce repeatable results. Real masks over equally textured areas need not produce different scores.

### A. Freeze the baseline and reproduce the failures

**Scope:** establish repeatable evidence before changing semantics.

1. Keep run `88E32164-72C2-4943-A55C-F6D2B1AAAE13`, its stage envelopes and retained PNGs immutable. Create a separate fixture manifest recording available files, hashes, image/subject/region IDs, source dimensions and model/runtime/preprocessing identities.
2. Confirm availability and permission to retain the six evaluation appearances and masks as local integration fixtures. Do not assume the export or proprietary photographs are committed test assets. Use small synthetic fixtures for routine CI; document local asset requirements for real-image probes.
3. Add a synthetic image with a smooth area and a textured area, paired with disjoint grayscale masks. Exercise the real `SubjectMaskFocusScorer`, not the fake scorer used by feature tests. Record the current erroneous coverage and equal results as the reproduction.
4. Trace one installed SAM output through candidate creation, PNG retention, reload and scorer input. Record dimensions, channel/alpha metadata, foreground count and bounds at each boundary.
5. Annotate expected source-space subject extents for deer/fawns, primary mallard and both sparrows. Include the rabbit head as a positive control. Keep annotations separate from model-generated bounds.

**Gate:** the F1 regression fails for the observed reason, and F2 has an inspectable source/mask/crop trace. If reproduction differs from the hypothesis, update the diagnosis before choosing the repair.

### B. Correct mask decoding and version the resulting evidence

**Primary files:** `SubjectMaskFocusScorer.swift`, `ReviewEvidence.swift`, `CombinedReviewExecution.swift`, mask producer/retention adapters, `ReviewRunContract.swift`, `ReviewArtifactStore.swift`.

1. Define an explicit mask contract at the producer boundary: foreground channel, polarity, threshold/value semantics, raster origin and source registration. Carry it through retained input metadata and subject evidence. Unsupported or missing semantics must remain unknown rather than silently default to alpha.
2. Separate foreground decoding from image color conversion. Decode grayscale intensity for grayscale masks and actual alpha for alpha masks; define how binary values are stored. Respect row stride, bit depth, alpha layout and mask dimensions. Specify interpolation separately for soft masks and categorical masks.
3. Use the same decoded foreground for score support, AF membership and foreground bounds. Distinguish total foreground coverage from the scorer's usable interior-pixel coverage; retain the denominator and border policy so the original 98.78% pattern is explainable.
4. Report empty masks, insufficient usable pixels, unsupported encoding and unsafe registration explicitly. Treat unexpected near-full occupancy as suspect evidence with a documented policy, rather than a universal anatomical rejection. Whole-frame fallback must not establish subject-specific focus.
5. Persist a scorer semantics version with measurements and their compatibility inputs. Keep the metrics described as render-dependent and uncalibrated. A new version does not establish a sharp/blur threshold.
6. Update stage versions and dependency compatibility for all affected consumers, including reconciliation, image report and selection/pair comparison. If registered bounds change, invalidate identity/region and crop stages too. Verify the actual dependency graph rather than assuming parent changes propagate.
7. Preserve old artifacts for historical inspection. Under the current exact snapshot validation, prefer an explicit incompatible-resume explanation and a new run with current settings; do not promise selective recomputation unless it is deliberately implemented and tested. Legacy missing scorer versions are unqualified, not current by default.

**Verification:** grayscale and alpha equivalents select the same support; empty/sparse/full masks behave explicitly; disjoint smooth/textured masks produce different metrics; save/reload preserves interpretation; identical inputs remain repeatable. Feature tests must prove stale artifacts never enter a new qualified report or comparison and that old runs remain inspectable.

**Gate:** the installed-path reproduction passes with foreground-derived coverage, and the corrected six-image run cannot consume F1 measurements or their dependent reports.

### C. Repair registration and qualify crop labels

**Primary files:** `ReviewImageGeometry.swift`, `ReviewImageSource.swift`, segmentation/candidate bounds producers, `CombinedReviewExecution.swift`, `ReviewEvidence.swift`.

1. Audit the producer and consumer conventions at each boundary: SAM raster and bounds, normalized appearance source, technical source, Core Graphics rendering/cropping, retained PNG and encoder input. Extend `ReviewCoordinateSpace` and `ReviewOrientationTransform` where needed; prohibit local ad hoc flips.
2. Compute foreground bounds using the registered decoded mask. Compare them with producer bounds and the requested region. Record disagreement with units and a documented tolerance derived from rasterization/resampling. Inspect F2 examples before setting a rejection threshold.
3. Confirm appearance-to-technical alignment independently of equal dimensions. The current measurement path requires matching mask/technical dimensions; dimensions alone do not establish content registration. Abstain when alignment cannot be established, and avoid an undocumented resize to make dimensions match.
4. Reuse existing requested/padded/source/retained rectangle fields. Add only missing registration provenance, transform identifiers and foreground-retention diagnostics. Track true source-edge truncation separately from avoidable crop or encoder truncation.
5. Qualify whole-subject crops by registered foreground retention. Qualify head candidates by supported anatomical evidence and parent association, beyond the existing containment/relative-area guard. An uncertain candidate becomes a generic region or is omitted with a reason; it never implies verified eyes.
6. Preserve legitimate partial-subject observations with a visibility limitation. Do not claim “no clipping” when the animal is already cut off by the source frame.

**Verification:** asymmetric synthetic masks at every frame edge, all eight EXIF orientations, nonsquare sources, fractional bounds, clipped padding, stretch and center-crop retention, and appearance/technical mismatch. Inspect deer torso/background errors, mallard truncation and sparrow face clipping against annotations; rabbit must remain correctly registered.

**Gate:** every named regression has aligned source/mask/bounds/crop evidence, or an explicit unsupported-geometry outcome. Correct rectangle arithmetic alone cannot pass this gate.

### D. Extend inspection and correct crop priority

**Primary files:** `CombinedReviewView.swift`, `CombinedReviewExecution.swift`, `ReviewEvidence.swift`, `ReviewBudget.swift` as needed.

1. Extend the existing source/mask UI with selectable subject and region IDs, foreground tint/outline, requested/padded/clipped/encoder-retained rectangles, origin/dimensions and registration warnings. Ensure black mask background does not obscure the photograph.
2. Show exact retained crop beside the source overlay and declared encoder geometry. Clearly distinguish an actual retained/preprocessed artifact from a geometry simulation; do not label a reconstruction as model input.
3. Display scorer version, measurement availability, clipping and validation diagnostics beside relevant evidence. Keep overlays an inspection aid, not photographic corroboration.
4. Make main-subject relevance explicit, with provenance and uncertainty. Do not substitute SAM confidence or discovery order for photographic importance. Allow ambiguous primary-subject assignments to remain visible.
5. Within existing caps and reservations, prioritize one valid main-subject region per image before extra anatomy and contextual objects. Preserve fallback when no subject can be verified. Document the policy for multiple equally important subjects.
6. Record omission reasons separately: budget/depth policy, geometry failure, ambiguous anatomy, contextual priority and unavailable input. Retain unused reserved capacity in accounting.

**Verification:** rabbit versus flowers, primary mallard versus secondary birds, ambiguous multi-subject scenes and no-subject fallback. Check allocation fairness across images and immutable budgets; visually inspect overlay alignment at different view sizes.

**Gate:** all six images have inspectable coverage or an explained limitation; priority never promotes an invalid crop solely to satisfy coverage.

### E. Ground synthesis and provide useful partial outcomes

**Primary files:** `CombinedReviewExecution.swift`, `CombinedReviewResponse.swift`, `ReviewEvidence.swift`, `CombinedReviewView.swift`.

1. Build a typed evidence lookup that resolves image, subject, region, observation, measurement and source ownership. Validate references after request-local aliases are mapped back to persisted IDs. Make subject scope explicit in prompt rows and persisted claims where needed.
2. Require each detail claim to use available evidence for its stated subject and registered region. Measurement-only support cannot establish behavior, composition, anatomy or calibrated focus. Unavailable, stale or omitted evidence cannot support a claim.
3. Generate numeric summaries deterministically from measurement ID and subject ID. Remove model transcription of numeric vectors. Use distinct fixture values to catch the DSC09214 `0:7`/`0:6` substitution that equal F1 values concealed.
4. Preserve overview/crop disagreement with evidence references and uncertainty. Validate contradiction ownership and relevance where structurally possible; do not treat any valid referenced ID as proof of a real contradiction.
5. Align structured insufficiency with supported evidence. A crop reporting no identifiable target cannot establish subject detail; retain its observation as a limitation or negative finding. Add structured support fields rather than depend only on phrase matching.
6. Cover composition, exposure, visibility and detail when supported; explicitly mark absent coverage. Keep unsupported whole-scene focus/visibility claims out of qualified synthesis. Behavioral details such as rabbit eating a flower must come from supported observations, not annotations injected as answers.
7. When synthesis fails, display a deterministic evidence-only summary of completed observations, available measurements and limitations, explicitly labelled as unsynthesized. Preserve the failed report outcome; fallback is not successful model synthesis. Do not weaken validators or add uncharged retries.

**Verification:** foreground/rear sparrow separation, overlapping deer, mallard selective focus, insufficient deer crop, subject/value swaps, unknown IDs, cross-image references, incompatible claim types, conflicting observations and failed synthesis. Combine deterministic rejection tests with visual review of accepted prose; neither substitutes for the other.

**Gate:** accepted claims have correct evidence ownership and supported scope, failed synthesis remains useful and explicit, and photographic accuracy is assessed separately from schema success.

### F. Persist bounded failure diagnostics

**Primary files:** `CombinedReviewResponse.swift`, `CombinedReviewExecution.swift`, `ReviewRunManifest.swift`, `ReviewArtifactStore.swift`, `ReviewEvidence.swift`, inspection/export UI.

1. Add a typed diagnostic payload retaining stage/work ID, stable validation code, compact reason, field path and relevant evidence reference. Distinguish JSON/schema, unknown ID/ownership, unsupported domain, response length, grounding, mask decoding and geometry failures. Keep runtime timeout, cancellation and budget outcomes distinct from validation errors.
2. Capture diagnostics at the failing guard or decoder boundary before errors collapse to `invalidEvidence`. Preserve the existing terminal status/error contract where appropriate; a new enum alone does not make an exported failure reconstructable.
3. Define separate diagnostic retention settings: compact metadata by default; bounded rejected text only when explicitly enabled. Specify per-response byte cap, per-run cumulative cap, truncation marker, export behavior and cleanup policy before implementation.
4. Store rejected payloads outside accepted evidence. Treat them as untrusted inspection data, never as findings or instructions. Avoid leaking unrelated file paths or sensitive content into compact reasons.
5. Persist failure metadata atomically with terminal work outcomes. Keep charged-attempt accounting, later-image continuation, cancellation behavior and compatible restore intact.

**Verification:** exercise each diagnostic class, export/reload, truncation and cumulative caps, default absence of raw text, cleanup and continuation after failure. New runs must reveal exact rejection checks; historical rejected responses cannot be reconstructed retroactively.

**Gate:** an exported rejection can be explained without repeating inference, within declared retention limits.

### G. Make comparison qualification meaningful

**Primary files:** selection/pair paths in `CombinedReviewExecution.swift`, `ReviewSelectionReport` in `ReviewEvidence.swift`, `combined-review-selection.md`, comparison tests and local model probes.

1. Extend existing comparability/decision/reason fields with structured supporting reasons and omitted-pair records. Separate unrelated scenes, insufficient evidence, depth policy, exhausted allowance, invalid scale and failed pair work. Do not turn Standard's zero pair requests into failures.
2. Record which evidence was excluded by context pruning and why, within bounded metadata. An omitted item cannot support a comparison claim.
3. Retain current evidence ownership, source fidelity and matched-scale checks. Add scorer-version and registration qualification to technical comparisons. The overview board remains coarse scene evidence, not subtle focus evidence.
4. Use comparable burst/near-tie fixtures, a deliberate blur difference, exposure changes and ambiguous multi-subject priorities. Define human expectations per criterion; exposure variation need not imply a universal winner.
5. Exercise Standard abstention and Deep/Exhaustive matched pairs under actual caps. Check tie/abstain/preferred reasoning, independent per-image outcomes, pair charging and compatible restore.

**Gate:** the original unrelated six-image set still abstains appropriately; comparable fixtures yield supported tradeoffs or explained abstention. Do not force a ranking to demonstrate usefulness.

### Delivery sequence and release evidence

Deliver reviewable changes in this order, with regression coverage in each change:

| Step | Deliverable | Prerequisite / completion evidence |
|---|---|---|
| 1 | Immutable fixture manifest and F1/F2 reproduction | Saved-path trace; failing synthetic scorer regression; annotated geometry controls |
| 2 | Mask contract, corrected scoring and compatibility/version policy | Correct foreground support; legacy-read/new-run isolation; downstream stale-artifact tests |
| 3 | Registered bounds and qualified crop labels | Edge/orientation tests; deer, mallard, sparrow and rabbit visual controls |
| 4 | Inspection extensions and subject-priority policy | Aligned overlays; main-subject coverage and omission/budget tests |
| 5 | Typed diagnostics and evidence-only fallback | Exported guard-specific failures; bounded retention and restore checks |
| 6 | Subject-grounded synthesis and deterministic numeric presentation | Ownership/value-swap tests; accepted-prose photographic review |
| 7 | Frozen six-image rerun and comparison fixture runs | Artifact-by-artifact comparison; meaningful comparable-scene evidence |
| 8 | Phase 6 resource and phase 7 independent qualification | Separate performance results and independent photographic labels |

Diagnostics can progress alongside representation work, but grounded technical synthesis depends on corrected scoring and geometry. Resource work may continue independently; it does not qualify defective photographic evidence.

For the six-image rerun, create a new run and keep baseline settings unchanged wherever compatible: files, criteria, depth, appearance preference, retention, render policy and pinned model/runtime/preprocessing. Record every intentional version or setting difference. Retain all six terminal image outcomes, budgets, exact inputs, overlay evidence, omission reasons and diagnostics. A valid explicit failure is preferable to invented evidence; six successful reports are not a substitute for accuracy.

Publish a compact before/after evidence table per image: mask foreground and usable coverage, scorer version, subject ownership, source/mask registration, crop/anatomy support, criteria coverage, accepted inaccurate claims, failures and diagnostic codes. Scores need not all differ; they must be traceable to their actual masks and image content. Count unknown or unavailable evidence separately from correct findings.

Also close the phase 1 audit follow-ups: reconcile CLIP's `encoderGeometryVerified: false` with observed installed-input verification, and document or strengthen SAM's noncryptographic identity. Retain these limitations until verified; do not erase them because F1/F2 are fixed.

Run focused unit/integration suites and the relevant existing Combined Review source, storage, budget, resume and selection checks. Run installed-model probes separately and identify asset/model prerequisites. Document test commands, configuration and results when implementation occurs. This documentation-only review does not rerun those suites.

**Completion boundary:** F1–F5 have explicit regression evidence; stale semantics cannot qualify new results; known crops are correctly registered or abstain; accepted claims retain subject scope and limitations; failures are diagnosable; original unrelated selection stays conservative; comparable-scene behavior is demonstrated. General photographic qualification still requires phase 7 independent labels, and resource qualification still requires phase 6 measurements.
