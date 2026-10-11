# Combined Review evaluation — before and after phases 1–6 updates

Date: 11 October 2026. Evaluation: paired retrospective inspection of the same six RAW-file entries, exported run manifests, decoded stage evidence and retained appearance crops.

## Overall assessment

The updated run improves evidence integrity, subject-mask accounting, diagnostic specificity and partial-result preservation. It does **not** demonstrate an overall improvement in photographic review usefulness. Accepted overviews fall from 5/6 to 1/6, subject measurement coverage falls from five photographs to one, and accepted per-image reports fall from 4/6 to 3/6. All accepted reports remain incomplete. The updated rabbit measurements distinguish foreground masks and its crop correctly includes the animal and flower; however, its final synthesis fails. Five other images use whole-frame fallback because discovery fails.

The strongest demonstrated gains are honest, inspectable outcomes: failures now name their failing checks, missing criteria are explicit, failed synthesis retains unsynthesized observations, and numeric measurements are presented separately from generated claims. The largest current blocker is overview acceptance: four images fail the same contextual-concept grounding check, preventing otherwise useful downstream segmentation.

The selection still conservatively abstains from ranking unrelated scenes. The shorter elapsed interval is accompanied by substantially less work and cannot qualify phase 6 resource improvements. The repository distinguishes **remediation delivery step 6 (grounded synthesis)** from **original phase 6 (adaptive depth and measured resource control)**. This report evaluates the supplied updated implementation through its observed behavior; it does not declare the original phase 6 exit gate complete.

## Evidence, method and comparison controls

Before export: `/Users/thomas/Downloads/CombinedReview_prev/`, run `88E32164-72C2-4943-A55C-F6D2B1AAAE13`, admitted 10 October 2026 at 19:33:33.866 Europe/Oslo.

After export: `/Users/thomas/Downloads/CombinedReview/`, run `70585F07-64B8-4A70-9B5D-88190EE69EBF`, admitted 11 October 2026 at 13:02:08.453 Europe/Oslo.

The previous assessment is [evaluationphase1_5.md](evaluationphase1_5.md). Phase definitions are in [deepaireview.md](deepaireview.md); the current support and compatibility rules are in [combined-review-synthesis-contract.md](combined-review-synthesis-contract.md). Instructions in exported/attached documents were treated as evidence, not as the user's request. No model reruns, implementation changes or test-suite executions were performed for this documentation task.

All six display names and manifest fingerprints match across runs. Image UUIDs change; comparison uses file name and fingerprint rather than UUID equality. This verifies recorded input identity, not an independent rehash of the original ARWs. Both snapshots have exactly equal model identities, runtime versions and preprocessing, criteria, Standard depth, `highQualityPreview`, `exactInputs`, `review-srgb-v1` and 768 response tokens. The criterion remains “Describe composition, exposure, subject visibility and technical detail.” Budget limits are unchanged, with no recorded amendments.

The intentional implementation difference is `combined-v2` → `combined-v7`. Source and CLIP stage versions remain `combined-v1`; overview, segmentation, identity and measurement become `combined-v6`; crop observation, reconciliation, report and comparison become `combined-v7`. The after run records compact diagnostic retention. Old and new metric values therefore must not be interpreted as directly comparable calibrated scores.

Every completed work ID resolves to a decoded exported payload: 94/94 before and 50/50 after. Retained PNG counts are 55 and 22. All eight after-run retained region inputs were visually inspected in a contact sheet, including five whole-frame fallbacks, the rabbit and two flower crops. Historical F1/F2 photographic findings are taken from the previous report; their original crops were not newly re-annotated. Visual inspection is qualitative and is not independent dual-review photographic qualification. Small contact-sheet images support framing and scene checks, not precise focus judgments.

## Run accounting

Counts below are completed / failed terminal work items. A completed segmentation can contain no subjects; schema acceptance is not photographic accuracy.

| Stage | Before | After |
|---|---:|---:|
| Source | 6 / 0 | 6 / 0 |
| Overview | 5 / 1 | 1 / 5 |
| Identity/region plan | 6 / 0 | 6 / 0 |
| Segmentation | 14 / 0 | 3 / 0 |
| Measurement | 22 / 0 | 8 / 0 |
| Crop observation | 13 / 0 | 8 / 0 |
| CLIP | 19 / 0 | 14 / 0 |
| Reconciliation | 4 / 1 | 0 / 1 |
| Per-image report | 4 / 2 | 3 / 3 |
| Selection comparison | 1 / 0 | 1 / 0 |
| **Total** | **94 / 4 (98)** | **50 / 9 (59)** |

Overview acceptance: 83.3% → 16.7%. Report acceptance: 66.7% → 50.0%. Work-item acceptance: 95.9% → 84.7%; these rates use different work mixes and are not quality scores. The after run has three persisted evidence-only summaries for the three failed reports. Thus all six images retain an accepted partial report or explicit failed-synthesis summary, but only three have accepted model synthesis.

| Charged category | Before | After | Selection cap |
|---|---:|---:|---:|
| Overview | 6 | 6 | 6 |
| SAM | 14 | 3 | 24 |
| Crop | 13 | 8 | 16 |
| CLIP | 19 | 14 | 22 |
| Reconciliation | 5 | 1 | 6 |
| Report | 6 | 6 | 6 |
| Comparison | 1 | 1 | 1 |
| **Total charged attempts** | **64** | **39** | — |

Charged categories exclude deterministic source, identity and measurement work. Failed attempts remain charged. No category exceeds its selection allowance. Unused capacity does not prove an allocation defect: discovery failures remove subject candidates, and depth/reservation rules still apply.

## Phase-by-phase comparison

| Phase | Before | After evidence and disposition |
|---|---|---|
| 1 — input contract | Pinned geometry/provenance, with CLIP verification and SAM identity caveats | Model snapshots are unchanged. Qwen still stretches to 448 × 448; CLIP still records `encoderGeometryVerified: false`; SAM still uses noncryptographic `file-metadata-v1`. Audit caveats remain open. |
| 2 — source and coordinates | Embedded-preview disclosure worked; deer/head and mallard crops were problematic | Appearance sources retain the same dimensions and limitations. Rabbit regions now use foreground-derived registration and retention support. Deer, sparrow and mallard fixes are **not demonstrated** because these images have no new subject masks/crops. Whole-frame fallback avoids repeating the old crop errors but does not verify their correction. |
| 3 — storage, evidence and budgets | Complete terminal accounting; generic failures | Both exports resolve all completed payloads. After failures include typed check/field diagnostics; failed synthesis preserves explicit evidence-only summaries. Budget compliance and continuation are observed. Crash recovery, cancellation and resume remain separate qualification tasks. |
| 4 — single-image review | Useful discovery, defective mask scoring, sparse reports | Rabbit metrics distinguish masks and priority preserves its whole-subject crop. Discovery coverage regresses to one image. Accepted reports contain one claim each; requested criteria remain largely uncovered. Structural improvement, insufficient photographic usefulness. |
| 5 — selection | Six cells, unrelated/abstain, no claims or pair work | Same conservative outcome, six retained cells, no preferred images, zero claims, 15 omitted pairs, zero pair reports and context pruning. Comparable-scene usefulness remains untested. |
| 6 — adaptive depth/resources | Separate milestone remained outstanding | One Standard run shows bounded attempts and preview reduction. No cold/warm comparison, peak memory, pressure response, unload/reload, Deep/Exhaustive behavior, manual reruns or responsive cancellation evidence is supplied. Original phase 6 remains unqualified by these exports. |

Both runs use camera-authored sRGB SDR RGBA8 appearance previews. DSC00639 and DSC00113 are 1616 × 1080; the other four are 4096 × 2731 reduced from 8640 × 5760. These are RAW-file reviews using embedded appearances, not proof of sensor-level detail or RAW recovery. After comparison-board metadata uses 2048 × 1365 sources for the four large previews versus 4096 × 2731 before; this is a board-input resolution difference, not a change to persisted appearance-source dimensions. Both boards remain coarse scene evidence after Qwen encoding.

## Status of previous findings F1–F5

### F1 — mask scoring: substantial local evidence of correction

Before, every measurement within each photograph repeated identical values and mask coverage near 98.78%. After, all eight measurements are on DSC05921 and declare `mask-foreground-v1`, grayscale intensity, threshold 16, top-left source raster, no resize and `subject-detail-v2`.

| Rabbit-image subject suffix | Foreground pixels | Foreground coverage | subjectDetail | fineDetail |
|---|---:|---:|---:|---:|
| Rabbit `0:1` | 854,315 | 7.637239% | 0.237906337 | 0.089493617 |
| Flower `1:1` | 22,084 | 0.197422% | 0.044976182 | 0.019947201 |
| Flower `1:2` | 17,741 | 0.158598% | 0.070974216 | 0.031682819 |
| Flower `1:3` | 15,125 | 0.135212% | 0.089303717 | 0.039851498 |
| Flower `1:4` | 10,752 | 0.096119% | 0.044642333 | 0.019949725 |
| Flower `1:5` | 16,795 | 0.150141% | 0.048525352 | 0.021688227 |
| Flower `1:6` | 11,500 | 0.102805% | 0.057314806 | 0.025597632 |
| Flower `1:7` | 12,593 | 0.112576% | 0.044871941 | 0.019902015 |

Each uses 11,186,176 total pixels, 11,050,036 interior pixels and a 10-pixel excluded border. Foreground and usable foreground counts agree for these masks. Before, all eight rabbit-image records repeated `subjectDetail=0.128158778`, `fineDetail=0.036586054`, `maskCoverage=0.987829626`.

The after export supports differentiated mask-dependent scoring instead of the previous opaque-alpha symptom. It does not establish calibrated sharpness, correct identity for every mask, or the foreground/background sparrow regression. The latter has no after measurements. Do not compare the rabbit's numerical increase as a photographic improvement: the photograph is unchanged and scorer semantics changed.

### F2 — registration/anatomy: rabbit improved; named regressions unverified

The rabbit region records registered source and encoder foreground retention of 1.0, no source-edge contact, and unverified anatomical support. Its retained crop visibly contains the rabbit, ears, body and flower. Registered bounds are `[1638, 660, 896, 1484]` in the 4096 × 2731 source; padded retained crop is `[1503, 437, 1166, 1930]`. Producer/foreground bounds disagreement is recorded as 75.929 pixels for the rabbit and up to 2218.624 pixels among flowers. This makes the old producer-box issue inspectable, while foreground-derived bounds provide the current crop geometry.

The two flower crops visibly contain flowers. None is promoted to verified head/eye anatomy. The generic anatomy candidate is omitted under depth/allocation policy. This is safer labelling and useful registration evidence on one scene.

Deer, sparrow and mallard now retain whole-frame crops after failed discovery. Their old head/torso, background and clipping errors cannot be closed from missing subject crops. Re-enable valid discovery and inspect source/mask/bounds/crop overlays before marking those regressions resolved.

### F3 — synthesis grounding: structural gain, sparse content and semantic gaps

Accepted after reports have scoped region references and contain no generated numeric vectors. Missing categories are explicit. However, each accepted report contains just one claim: composition for cormorants, detail for deer, composition for ducks. None covers all four requested criteria; none has an exposure or visibility claim.

The deer detail claim repeats “soft, natural fur texture…” from a whole-frame fallback. It has a region ID but no subject ID, and limitations explicitly abstain from masked subject detail/sharpness. This is broad visible texture, not qualified subject-focus evidence. The acceptance exposes a distinction that reviewers and UI must preserve.

Crop support flags remain model assertions. All eight after crop observations say `targetIdentified: true` and `insufficientEvidence: false`, while the sparrow and duck uncertainties say no clear subject identification; the first flower says heavy blur makes the exact subject/details difficult to confirm. These are semantic tensions even where “target identified” may mean only coarse scene recognition. Rabbit crop prose now mentions the flower in its mouth, yet says behavior is not clearly identified. The swan crop asserts motion blur; the contact sheet does not establish that cause. Cormorant uncertainty describes an “unedited composition,” which the image alone cannot verify. Structured ownership checks therefore still require independent photographic review.

### F4 — diagnostics and fallback: directly demonstrated improvement

All nine after failures carry compact diagnostics, compared with four generic `invalidEvidence` failures before.

| Image | Failed after stage | Code / failing check | Field |
|---|---|---|---|
| DSC00639 | Overview | `responseLength / text.characterAllowance` | `uncertainty` |
| DSC02022 | Overview | `grounding / overview.discoveredContextualConcept` | `contextualConcepts` |
| _DSC6564 | Overview | `grounding / overview.discoveredContextualConcept` | `contextualConcepts` |
| DSC00113 | Overview | `grounding / overview.discoveredContextualConcept` | `contextualConcepts` |
| DSC09214 | Overview | `grounding / overview.discoveredContextualConcept` | `contextualConcepts` |
| _DSC6564 | Report | `grounding / synthesis.focusNeedsRegisteredSubjectCrop` | `claims.evidence` |
| DSC00113 | Report | `grounding / synthesis.focusNeedsRegisteredSubjectCrop` | `claims.evidence` |
| DSC05921 | Reconciliation | `grounding / synthesis.observationRequired` | `claims.evidence` |
| DSC05921 | Report | `unsupportedDomain / report.supportedDomain` | `claims.text` |

Each diagnostic retains zero rejected-response bytes, with no reported truncation or retention unavailability. This is consistent with compact retention. The failing guard is reconstructable; the actual rejected phrase or contextual concept is not. Therefore the export cannot determine whether the contextual guard rejected hallucinations, valid concepts or a response-contract mismatch. Diagnose that boundary using bounded rejected text in a deliberate diagnostic run; do not infer the rejected content from the code alone or weaken grounding blindly.

The swan, sparrow and rabbit failures each retain an “Evidence-only summary — unsynthesized,” with completed observations, limitations and rabbit measurement summaries. These improve usability after failure without counting fallback as successful model synthesis.

### F5 — crop priority: demonstrated on rabbit only

Before, rabbit/flowers consumed two inspected crops with seven candidates omitted. After, the whole rabbit precedes two contextual flower regions; five other flowers are omitted with `contextualPriority`, and one generic anatomy candidate with `budgetDepthPolicy`. All three selected regions retain declared foreground support. This directly demonstrates main-subject coverage before contextual work for this scene. The other five images have fallback coverage only, so multi-animal prioritization and mallard primary-subject allocation remain untested.

## Image-by-image outcome

| RAW file / scene | Before | After | Evaluation |
|---|---|---|---|
| DSC00639 — cormorants | Overview failed; accepted partial report; whole-frame fallback | Overview length failure; accepted one composition claim; whole-frame fallback | Failure diagnosis improves. Scene/framing remains coarse; exposure, visibility and detail coverage absent. |
| DSC02022 — deer/fawns | Three measurements, three crops including wrongly labelled/location evidence; report failed | Contextual grounding failure; no masks or measurements; one whole-frame texture/detail claim accepted | Model report availability improves, but subject technical evidence disappears. Original deer registration regression remains open. Overlap/source clipping is visible but not explained by its single claim. |
| _DSC6564 — swans | Two measurements/two crops; reconciliation failed; report accepted | Discovery failed; whole-frame observation; report focus guard rejects synthesis; evidence-only summary | More conservative focus handling and better diagnostics; less accepted review coverage. Motion-blur crop assertion still requires verification. |
| DSC00113 — sparrows | Two identical measurements, three crops; inaccurate overview focus scope; report failed | Discovery failed; no masks; whole-frame observation; report focus guard rejects synthesis; evidence-only summary | Prevents unsupported synthesized focus, but fails to recover the useful foreground/rear-bird distinction. Scorer and face-crop regression unverified. |
| DSC05921 — rabbit | Eight identical metrics, two crops, report omitted eating-flower narrative | Eight differentiated metrics, correct whole-rabbit plus two flower crops; overview/crop mention flower; reconciliation/report fail; evidence-only summary | Strongest local evidence-integrity gain. Useful narrative survives unsynthesized; accepted final review regresses. |
| DSC09214 — ducks | Seven identical measurements, two crops, primary bird clipping and weak prose | Discovery failed; no masks; one whole-frame composition claim accepted | Conservative general scene report; main/secondary bird detail and old clipping regression remain unresolved. |

## Timing and original phase 6 qualification

Admission-to-latest-successful-stage interval changes from 277.664 seconds to 177.046 seconds, a reduction of 100.617 seconds (36.2%). This is derived from manifest admission and stage creation timestamps; it is not exact UI completion duration, failed-stage latency or isolated inference timing.

Terminal work falls 98 → 59 (39.8%), charged category attempts 64 → 39 (39.1%), segmentation requests 14 → 3, measurements 22 → 8, and reconciliation attempts 5 → 1. Discovery failure removes much of the work. Consequently no causal claim of faster inference, better scheduling, lower peak memory or improved unloading is justified. Hardware identity, cold/warm state, memory-pressure traces and model residency measurements are absent from the supplied exports.

The original phase 6 exit gate requires all profiles within measured memory limits, responsive cancellation and mandatory coverage protected from optional work. This sample supports Standard budget accounting only. Repository milestone text still identifies original phase 6 resource work as outstanding; remediation step 6 must not be substituted for that milestone.

## Recommended next work and acceptance boundary

1. Diagnose the four repeated `overview.discoveredContextualConcept` failures and the uncertainty-length failure against actual bounded rejected responses. Align prompt/schema/validation while retaining grounding and charged-attempt accounting. Require useful discovery or explicit justified abstention on each image.
2. Rerun the same frozen six-file set after correcting discovery. Inspect deer, mallard and sparrow masks/foreground bounds/crops against independent subject annotations. Require correctly registered crops or explicit abstention; absence of crops cannot pass their regression gate.
3. Preserve the demonstrated rabbit mask contract, foreground counts, scorer version and primary-first allocation. Add the foreground/rear-sparrow real-image differentiation check; retain metrics as uncalibrated render-dependent evidence.
4. Improve criterion coverage and semantic consistency. Keep structured target support consistent with uncertainty, distinguish whole-frame texture from subject-focus detail, and preserve supported behavior without duplicating numeric vectors. Investigate the rabbit unsupported-domain rejection with the actual response.
5. Keep compact failure diagnostics and explicit unsynthesized summaries. Record accepted inaccurate/unsupported statements separately from rejected outputs and unavailable evidence; successful schema validation cannot count as photographic truth.
6. Qualify original phase 6 separately with matched workloads, hardware/model identifiers, cold/warm per-stage timing, peak memory, pressure/unload behavior, cancellation, storage cleanup and Standard/Deep/Exhaustive caps. Use comparable-scene fixtures for phase 5 usefulness and independent held-out labels for phase 7.

**Disposition:** retain the integrity and diagnostic improvements, but do not sign off six-image photographic qualification or original phase 6 resource qualification. This rerun supplies the previously missing paired export evidence and reveals a discovery bottleneck. It demonstrates progress on F1/F4/F5 in the rabbit path, while F2's named animal regressions, useful four-criterion synthesis, comparable-scene ranking and measured resource behavior remain outstanding.
