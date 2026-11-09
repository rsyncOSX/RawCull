# Lightweight face and eye assessment for RawCull

Evaluation and implementation proposal — 8 November 2026.

**Status, 9 November 2026:** Automatic face close-ups and per-file face evidence caching are implemented in the local RawCull build. The next milestone is face-only TestFlight validation. The architecture and later phases below remain proposals.

| Phase | Current status |
|---|---|
| 0 · Feasibility | Ran the built-in face and eye pilot on 85 RAWs. The results support Vision face detection for close-ups. Eye-state warnings remain in evaluation. |
| 1 · Contracts and engine | PhotoAnalysisKit returns versioned face geometry and experimental face-local detail from upright previews. A controlled blur check lowered the score on all 96 measurable face crops. Real burst comparisons remain open. |
| 2 · Persistence and scheduling | RawCull caches evidence per file, skips Vision on compatible hits, and pauses face work during similarity indexing. Broader background scheduling remains open. |
| 3 · Evidence and close-up UI | Automatic face crops and detail scores appear in burst Close-ups, separately from manual regions. The unsigned Release build passed. The signed App Store archive and TestFlight validation are pending. |
| 4–6 · Ranking and optional additions | Pending. TestFlight will gather evidence about crop placement, cache reuse, and agreement on sharper versus softer faces before any ranking change. |

The [pilot report and TestFlight checklist](PeopleAssessmentPilot.md) record measurements, limitations, and test cases.

## 1. Recommendation

Add a lightweight, cached **People assessment** pipeline to the ordinary burst workflow. Start with human face location, useful face close-ups, face-local sharpness, and conservative eye-state evidence. Keep Combined Review optional and independent. Do not require Qwen, SAM, CLIP classification, or a developed full-resolution RAW for people assessment itself. Existing grouping may still have its own model requirements; this proposal does not make the entire burst preparation pipeline model-free.

Use Apple's Vision face detection and landmarks as the first candidate backend. Evaluate its face capture-quality score as a supporting signal, explicitly separate from sharpness. Compare two built-in eye-state baselines—Core Image closed-eye flags and geometry derived from Vision landmarks—before introducing a downloaded model. Adopt a compact Core ML eye classifier only if the built-in candidates fail measured accuracy requirements and a properly licensed model improves the result on RawCull's photographs.

The most useful first release is **honest evidence with quick access to the right crop**, even if eye assessment sometimes says “uncertain.” A confident but wrong blink warning is worse than a missing warning. Face and eye evidence can enter ranking in a later, separately validated phase.

Retain **Best frame** and **AF-point sharpness** as two sort modes. Best frame should eventually consume compatible people evidence automatically. Do not rename Best frame. The separate Suggest Best Frame button should not become the mandatory entrance to this feature. Decide its removal or repurposing after the new analysis lifecycle is defined; a cosmetic rename alone does not solve its current redundancy.

### Decisions this plan makes

- Human faces first. Wildlife eyes are a separate future investigation; human models must not be advertised as animal-eye detectors.
- All photographic analysis stays local. No cloud inference and no per-photo AI service credits.
- Detection, eye openness, local detail, capture quality, and recommendation confidence remain distinct concepts.
- Unknown, not yet analyzed, failed, and no face detected are different states.
- Automatic assessment never applies ratings, rejects, deletes, or replaces a manual winner.
- Progressive work must not make the filmstrip jump while the photographer is comparing frames.
- Numeric thresholds and runtime budgets below are proposed experiment/release gates, not measured capabilities.

## 2. What the code currently does

The following findings were checked against the repository, rather than inferred from button labels.

| Action or component | Current behavior | Consequence |
|---|---|---|
| Open burst workspace | `sortByAFPoint` initially equals `false`; reads stored candidate order. `onAppear` selects a valid frame and installs keyboard handling. | Opening is not a fresh ranking pass. An existing selection in the burst can remain selected; opening does not always select rank one. |
| Select Best frame | Uses `analysis.candidates`, falling back to group membership order. The sort-change handler selects the first frame. | It restores an existing order; it does not run new analysis. |
| Select AF-point sharpness | Calls `loadMissingAFPointScores`, then sorts by measured AF-center scores and selects the first frame. | This mode can do additional computation when measurements are missing. Switching modes is not entirely computation-free. |
| Suggest Best Frame | Calls `BurstRankingEngine.rankGroup` using existing scores, metadata, boundaries, and optionally existing subject classifications. | It recomputes the ranking, not the evidence. Identical inputs normally produce the same output. It preserves current selection, ratings, and manual winners. |
| Find Burst Groups | Coordinator loads compatible cache or prepares sharpness, similarity, groups, and rankings. | This is the natural integration point for scheduled people assessment, but its cache-hit path needs special attention. |
| Combined Review | Separate, explicitly run deeper analysis. | It need not be involved in the new lightweight path. |

Relevant application files:

- `RawCull/Views/ComparisonGridView/BurstWorkspaceHeader.swift`
- `RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift`
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator.swift`
- `RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator+Lifecycle.swift`
- `RawCull/Intelligence/BurstAnalysis/BurstAnalysisModels.swift`
- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`
- `RawCull/Model/ViewModels/FocusandSharpness/RawCullPhotoAnalysisAdapter.swift`
- `RawCull/Intelligence/Persistence/BurstAnalysisCache.swift`
- `RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift`
- `RawCull/Views/ComparisonGridView/BurstCloseUpsView.swift`
- `Docs/BurstFirstPass.md`

### Current ranking is not an eye-quality model

In `RawCullCore/BurstRankingEngine.swift`, the overall score currently combines:

| Component | Weight | Meaning |
|---|---:|---|
| Sharpness | 62% | Normalized score, optionally blended with burst-relative sharpness |
| Focus point | 12% | Recorded normalized AF point exists: 0.70; otherwise: 0.45 |
| Subject classification | 10% | Coarse classification agreement with the dominant burst label |
| Metadata | 16% | Stability and heuristics involving capture metadata |

The focus-point component is an availability heuristic. It is not the separate measured AF-center sharpness used by the AF sort, and it does not establish that an eye is sharp. Existing PhotoAnalysisKit code includes an `eyeHeadHeuristicAdjustment` based on compact/ring detail and AF-relative geometry; this is not semantic eye localization or a trained human eye-state assessment.

Do not rename those existing fields to “face focus” or reuse their values as eye confidence. New measurements require new contracts, provenance, and ranking logic. Existing confidence also drives `isSafeForOneClickCulling`; adding a score must not accidentally make new people recommendations eligible for that destructive-to-ratings workflow without separate validation.

### Dependency state inspected

Application HEAD at inspection: `b0d7410ce0011cecf953c13581ec469121bde6be`.

Sibling package checkouts were read only. Their HEADs match the relevant pinned revisions in this app's `Package.resolved`:

| Package | Pin | Revision |
|---|---|---|
| RawCullCore | 1.1.2 | `d25a51e65ad32a82bf82f86fa0ec07d6e14498e9` |
| PhotoAnalysisKit | 1.3.1 | `2a1466e04d821fa2628d6985296643e0d0c7e465` |
| PhotoEvidenceKit | 1.0.7 | `7614fd1528bb7cf2549799fb937678ea39d90228` |

PhotoEvidenceKit currently provides crop/render/inspection contracts. Its `CloseUpRegion` explicitly describes a manual region, not a detected eye or face. Extend the contract deliberately rather than putting automatic detections into manual-region persistence.

## 3. Narrative as a workflow reference

Narrative documents per-face focus and eye assessments, contextual interpretation of closed eyes, scene grouping and ranking, and close-ups. This establishes a useful product target, but does not disclose the implementation, model sizes, or performance on RawCull's input files. We cannot infer its internals or claim that copying an API call reproduces its quality. [Narrative Select](https://narrative.so/select).

Its First Pass categories and filters are separate from saved user ratings. Scene rank compares nearby alternatives, and optional Auto-rate is a subsequent explicit action. RawCull should preserve the same useful distinction between evidence, ordering, and the photographer's saved decisions. Full five-category parity is outside the first face-assessment milestone. [First Pass](https://help.narrative.so/en/articles/7337372-ai-first-pass-image-assessments), [Scenes and rank ordering](https://help.narrative.so/en/articles/8119179-use-scenes-and-rank-ordering-in-narrative).

The priority is not the number of AI features. It is whether a photographer can open a burst, immediately see useful alternatives and faces, understand uncertainty, and make a decision without running an expensive review.

## 4. What each assessment can establish

| Signal | Useful question | What it cannot establish |
|---|---|---|
| Face detection | Where are likely human faces? | Identity, importance, or complete coverage of all people |
| Landmarks and pose | Where are eye contours and other facial features? Is the view suitable? | Guaranteed open/closed state or reliable geometry on every profile |
| Eye state | Does the visible eye appear open or closed? | Whether closure was an unwanted blink, a wink, a kiss, prayer, or an expressive moment |
| Face-local detail | Is there usable spatial detail in the face region? | Optical focus independently of noise, JPEG sharpening, texture, and motion |
| Eye-local detail | How does detail around a sufficiently resolved eye compare with alternatives? | Iris sharpness when the crop contains too few original pixels |
| Capture quality | A general face-capture quality signal | A pure focus score or an artistic judgment |
| Burst recommendation | Which comparable frame has stronger available evidence? | The photographer's desired expression, story, or final keeper set |

Apple's capture-quality API is a broad score. The installed Vision SDK header describes comparison against other captures of the same face in a set. Treat it as a within-subject hint, not a universal score for ranking different people or skin/face appearances. Apple's sample illustrates detection followed by quality and landmarks using the same observations; that avoids unnecessary repeated face detection. [Apple face analysis sample](https://developer.apple.com/documentation/vision/analyzing-a-selfie-and-visualizing-its-content), [capture-quality request](https://developer.apple.com/documentation/vision/vndetectfacecapturequalityrequest).

### Single images are not video

A closed eye in one exposure is an appearance observation. A blink is a temporal event. A photographic burst can have irregular intervals and missing exposures, so it must not be passed to a video blink algorithm under invented frame timing. Neighboring images may support a cautious “possible blink” interpretation later, but initial UI should say “eyes appear closed.” No inference of intent is required for the first release.

## 5. Backend options and the selection experiment

| Candidate | Strength | Main limitation | Proposed role |
|---|---|---|---|
| Vision rectangles + landmarks | Built into macOS; face and eye geometry; no app model download | No documented direct eye-open probability in the inspected face APIs; difficult small/occluded faces | Preferred location/geometry baseline |
| Vision capture quality | Built-in broad quality hint | Conflates several factors; cannot explain a low score as blur | Advisory experiment, low influence initially |
| Core Image `CIDetectorEyeBlink` | Built-in left/right closed-eye flags on macOS | Boolean outputs lack calibrated uncertainty; older face-analysis route; must match detections to Vision geometry | Required low-cost comparator, not an automatic winner |
| Landmark eye-aperture geometry | Tiny extra computation after landmarks | Sensitive to pose, anatomy, landmarks, squinting, and resolution | Diagnostic baseline; may suffice for conservative warnings |
| Compact Core ML eye classifier | Can learn appearance directly and provide richer output | Training/data/model rights, conversion, calibration, deployment and maintenance work | Conditional fallback after built-in evaluation |
| MediaPipe Face Landmarker | Dense geometry and expression coefficients | Additional runtime/platform integration; native macOS packaging needs proof; expression coefficients are not calibrated blink probabilities | Research comparator, not default dependency |
| Qwen/SAM/Combined Review | Existing deeper contextual tools | Far larger workload and different purpose | Optional escalation only |

Core Image exposes `CIDetectorEyeBlink` and `CIFaceFeature.leftEyeClosed/rightEyeClosed` on macOS. The installed headers confirm their availability and the option needed to obtain them. The same headers recommend Vision for feature analysis. That recommendation is not evidence that every Core Image face symbol is formally deprecated or unusable. [Eye-blink option](https://developer.apple.com/documentation/coreimage/cidetectoreyeblink), [closed-eye property](https://developer.apple.com/documentation/coreimage/cifacefeature/righteyeclosed-swift.property).

The eye-aspect-ratio literature provides a cheap geometric starting point, but the original method detects blinks over video. Its published results do not establish accuracy for Apple's different landmark topology or RAW burst photographs. Do not copy six-point indexes or a published threshold into Vision output without defining and validating the mapping. [Soukupová and Čech, 2016](https://cmp.felk.cvut.cz/ftp/articles/cech/Soukupova-CVWW-2016.pdf).

MediaPipe documents face geometry and expression output, including single-image use. This is evidence of an alternative architecture, not proof of a supported drop-in Swift macOS solution. Verify binary support, model asset terms, runtime cost and coefficient calibration before selecting it. [Google Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker).

### Experiment design

Run the same held-out photographs through the built-in candidates. Record per-eye predictions, geometry, resolution, latency, and failure states. Associate Core Image and Vision faces using conservative box overlap/center/pose checks; ambiguous association must produce unknown. Do not match arrays by position. Evaluate each candidate independently before any fusion; two correlated wrong signals do not constitute independent confirmation.

Choose the simplest backend meeting the precision/coverage/performance gates. It is acceptable for the first production version to expose face crops and local detail while keeping eye-state evidence advisory or unavailable. No particular external classifier is approved by this document.

If a custom classifier is needed, specify a small eye/eye-pair image input, three conceptual outcomes (open, closed, not assessable), pose/visibility gating, and source-pixel requirements. Benchmark paired eyes versus independent eyes: a pair provides context but can fail when only one eye is visible. Validate full-precision and any compressed deployment artifact separately. Pin exact weights and preprocessing; do not select by model filename or claimed parameter count alone.

Before shipping third-party weights, record source, checksum, version, redistribution/commercial rights, training-data restrictions, notices, supported deployment target, and reproducible evaluation. Framework code licensing does not automatically cover pretrained weights or training images. Avoid training in this phase; it is a contingent project if built-in APIs fail.

## 6. Image pipeline: affordable computation without false detail

### Stage A: bounded detection

Decode an orientation-corrected embedded preview at a bounded size. Experiment with 1,024, 1,536 and 2,048 pixels on the long edge. These are candidate sizes, not chosen defaults. Do not reuse the current 512-pixel sharpness input blindly: a full-body or group portrait can leave eyes only a few pixels wide.

Detect faces before landmarks. Reuse observations for landmark and capture-quality requests where the selected API supports it. Record detector revision, source dimensions, orientation, and preprocessing. Prefer the modern Swift Vision surface when its available SDK behavior is verified; keep it behind an adapter so request-type differences do not leak into ranking or persistence.

### Stage B: targeted face and eye assessment

For relevant, sufficiently large detections, request a larger embedded preview only when needed and obtain face/eye crops. A crop from an upscaled thumbnail cannot recover detail. Express adequacy in **original source pixels**, not the classifier's resized input dimensions.

Sweep source eye widths such as 16/24/32/48 pixels and measure where state/detail assessment becomes reliable; do not adopt those values as facts before testing. Face detail and eye detail may require different minima. Severe pose, clipped eyes, sunglasses, occlusion, poor contrast, or unresolved geometry should independently gate the affected eye to unknown.

Decode each source once per assessment stage and share it across faces; do not decode the full preview for every eye. Crop promptly and release large images. JPEG “crop” operations may still require a substantial decode; verify the loader rather than assuming region decoding is cheap. A 6,000 × 4,000 RGBA image alone is about 96 MB before additional buffers. Four concurrent such decodes can overwhelm a nominally tiny model.

Avoid automatic full-resolution RAW development. If the embedded image lacks useful resolution, show the limitation. A future explicit higher-detail check can use existing developed-preview infrastructure and a distinct artifact signature. It must not silently substitute measurements between differently sharpened sources.

### Stage C: local detail metrics

Experiment with gradient/detail measurements at multiple controlled scales, robust noise estimates, saturation/contrast checks, and both face and eye regions. Reuse suitable PhotoAnalysisKit primitives only after verifying they support explicit regions without AF-driven patch selection overriding the face region.

A simple Laplacian variance is an experiment baseline, not a finished focus measure: high ISO noise, JPEG sharpening, eyelashes, glasses and specular reflections can increase it. Keep native pixel geometry available; blindly rescaling every eye to the same size changes blur evidence. Compare similarly sized captures of the same face at compatible scales and report inadequate resolution separately.

Store raw metrics plus their descriptor. Calibrated categories such as “good detail,” “possible softness,” and “uncertain” belong to a versioned interpretation layer. UI percentages must not imply that an arbitrary normalized detail score is a probability of being in focus.

## 7. Geometry and face association

Use one canonical persistent geometry: normalized coordinates in the orientation-corrected image, top-left origin, matching the conceptual convention in PhotoEvidenceKit. Convert Vision coordinates at the boundary. Preserve the transforms to source pixels and crop pixels, including mirrored EXIF orientations. Test all eight orientations and non-square images; no repeated orientation correction.

Distinguish image-left/image-right from the subject's anatomical left/right. Store an explicit convention in the contract; UI can simply highlight the corresponding eye rather than label a side incorrectly.

Within a frame, assign stable artifact-local face identifiers after deterministic spatial ordering. Do not rely on detection array order across runs. Across a burst, build temporary correspondences only when necessary for comparison:

1. Start with adjacent capture order and conservative normalized position, size and pose compatibility.
2. Use one-to-one assignment with explicit unmatched and ambiguous cases.
3. Reject association across large movement, missing faces, crossing subjects, or changed composition unless evidence supports it.
4. Do not force an association because two frames contain the same number of faces.
5. Do not create persistent person identities or face-recognition embeddings for this feature.

For the initial single-primary-face ranking experiment, require a comparable primary face across candidate frames. For groups, treat face-set changes and uncertain correspondences as reasons to withhold automatic people-based winner changes. A later manual “important face” selection can resolve ambiguity without identity recognition.

## 8. Data contracts and package ownership

Proposed names are illustrative; implementation should follow each repository's conventions.

| Proposed value | Required content |
|---|---|
| `PeopleAssessmentDescriptor` | Backend/request revisions; optional model checksum; preprocessing, geometry, detail metric and schema versions; source-size policy |
| `PeopleAssessmentArtifact` | Source fingerprint and representation; descriptor; actual analyzed dimensions; outcome; face records; completion/coverage information |
| `FaceAssessment` | Artifact-local ID; normalized box; pose; localization quality; visibility limitations; optional capture quality; face detail; eyes |
| `EyeAssessment` | Geometry; original pixel dimensions; state; optional calibrated confidence; detail metric; limitations; backend evidence |
| `AssessmentOutcome` | Completed with faces, completed without detected faces, unsupported source, decode failure, backend failure; cancellation remains resumable pending work |
| `BurstPeopleEvidence` | Comparable face cohort/associations; relevant-face policy; per-frame coverage; reason codes; interpretation version |
| `BurstRankingDescriptor` | Existing ranking version plus people evidence policy/version and evidence-set digest |

Do not store a generic confidence float shared by detection, openness, focus, and final recommendation. A backend Boolean is not a probability; if no confidence is available, record that fact. Store observed state and the reason it may not be usable for ranking separately.

Suggested ownership:

- **PhotoAnalysisKit:** decoded-image face/eye analysis contracts and engine, source-independent numerical detail computation, backend descriptors. Avoid a dependency on application models or catalog paths. Keep heavy PhotoAIKit models out of this baseline.
- **RawCull:** file access and preview selection, scheduling, per-file persistence, user preferences, current catalog/generation checks, review state, and integration adapters.
- **RawCullCore:** pure ranking inputs, people evidence summaries, reason codes, deterministic ranking and confidence rules. No Vision objects or image decoding here.
- **PhotoEvidenceKit:** optional automatic face/eye inspection targets and presentation support. Keep automatically derived targets separate from the photographer's manual region.

Confirm package dependency directions before adding types. If reusing the full analysis engine would force RawCullCore to depend on image-processing implementations, use a compact neutral value contract instead. Cross-repository changes require versioned package releases and updated app pins; editing a sibling checkout alone will not update the app's remote package dependency.

## 9. Caching and compatibility

Persist people evidence per source independently from similarity embeddings, current user ratings, and burst grouping. Changing eye interpretation or ranking weights should not force re-embedding or regrouping.

A compatible key must cover source revision, actual preview/sidecar identity, decode representation, orientation/crop transformation, backend/request revision, model checksum if any, preprocessing, image-size policy, and measurement version. A RAW file's unchanged timestamp does not establish that its sidecar JPEG is unchanged. Reuse existing fingerprint patterns, but do not assume the similarity store already captures every new preview dependency.

Separate raw evidence invalidation from derived ranking invalidation:

- Source/model/preprocessing changes: recompute affected per-file evidence.
- Ranking weights or “prefer open eyes” setting changes: reinterpret cached evidence and rerank only.
- Group membership changes: rebuild associations/rankings using compatible per-file artifacts.
- OS/backend revision changes: reuse only under a documented compatibility rule; if the OS model has no stable exposed version, conservatively version by relevant OS/backend descriptor and validate upgrades.

Use atomic per-file commits and checkpoint progress. Stable no-face results should be cached. Transient I/O/backend failures need bounded retries/backoff, not permanent “no face” artifacts or an endless loop on every redraw. Cancellation should leave completed artifacts reusable and unfinished sources pending. Purging derived caches must preserve ratings, manual winners and manual close-up choices.

Important integration trap: `BurstAnalysisCoordinator.run` returns early on a compatible existing burst snapshot. Adding people assessment only after the existing cache-miss preparation steps would skip old catalogs indefinitely. Hydrate/schedule missing people evidence independently on cache hits as well as misses. Extend ranking compatibility so old rankings can be distinguished from rankings using new evidence without invalidating unrelated similarity work.

## 10. Scheduling and resource limits

Proposed sequence:

1. Load existing catalog and burst artifacts; publish usable existing rankings immediately.
2. Hydrate people artifacts without decoding photos on the UI actor.
3. Prioritize the open burst, then nearby queued bursts, then remaining catalog work if enabled.
4. Detect and assess missing sources in bounded workers, checkpoint artifacts, and publish batched progress.
5. Build a complete, comparable burst evidence snapshot before proposing a ranking revision.
6. Preserve current selection and manual decisions when the new snapshot is published.

Use an app-owned scheduler with explicit priorities and bounded decoded-image memory. Begin experiments with one decode/assessment worker; compare two workers only after profiling. Do not set worker count equal to CPU core count. Give foreground navigation, previews, and zoom priority over background face scans; avoid simultaneous unrestricted sharpness, similarity, people assessment and Combined Review workloads.

Keep requests/images within isolated workers and return immutable value results. Request cancellation where supported and check cancellation/catalog generation before and after each await and before publishing. Some framework work may finish after cancellation; stale results must not alter the current catalog. Per-source cache writes are permissible only if their source/descriptor still match, independently of UI publication.

Respond to memory pressure by releasing decode/crop buffers and pausing background work. Under serious thermal pressure or Low Power Mode, reduce or pause background scans; foreground assessment should remain explicit and bounded. Resume from checkpoints. A pause is not a failure or a completed no-face result.

The user should see useful progress: “Checking people: 18 of 64,” “Paused,” “No faces detected,” “Some faces too small,” or “Assessment unavailable.” Do not make opening every burst wait for completion. Offer an Off setting and a pause control. Suggested product default after validation: automatic visible-burst priority during burst preparation, with background completion while idle. Keep catalog-wide opt-in/default behavior reviewable after measurements; do not secretly scan every catalog on application launch.

## 11. How the evidence should affect Best frame

### First ship evidence, then change winners

Initially publish badges and face crops while running the new ranking in an internal shadow mode. Compare its ordering to the existing baseline and human choices. This avoids coupling “face detection works” to the much harder claim “the automatic winner is better.”

For the first ranking-enabled release:

- Use only a reliably associated primary human face, or an explicitly chosen important face.
- Keep existing ranking exactly when the burst lacks comparable adequate people evidence.
- Prefer stronger face-local detail when the difference exceeds measurement uncertainty.
- Use a conservative closed-eye disadvantage only when the photographer enabled the open-eye preference and a comparably sharp alternative has confidently open eyes.
- Do not treat unknown eyes as open, closed, or zero quality.
- Preserve manual winners and never mutate ratings during reranking.
- Lower recommendation confidence on small face crops, conflicting signals, uncertain association, incomplete coverage, or close alternatives.

Do not simply append a 20% eye score to the current weighted sum. That would double-count blur, reward missing evidence depending on normalization, and allow a tiny uncertain signal to flip a recommendation. Develop a versioned policy using a **fixed comparable evidence cohort for the burst**. If a required face is unassessable in one competing frame, withhold that people-based comparison or retain a cautious baseline ranking for the affected burst. An unknown frame must not automatically win because it escapes an eye penalty.

A practical experimental policy is: retain baseline score as the fallback; build per-frame people detail/eye categories only for the shared valid cohort; apply a bounded calibrated adjustment uniformly across that cohort; use the baseline order for ties. Tune adjustment bounds on held-out bursts. Freeze the shared cohort before sorting. Do not use an ad-hoc pairwise sort comparator, because pair-dependent missing evidence can produce inconsistent/non-transitive ordering.

### Groups require a second ranking milestone

An average face score can hide one badly blurred person. A minimum can overreact to a tiny background face. Define relevant faces by explicit selection where available, otherwise conservative size/prominence and comparable visibility. Show what was excluded. For group portraits evaluate a lower-tail detail summary and number of confidently closed relevant eyes, with coverage displayed. Do not optimize a mathematical group score until a labeled group dataset shows it helps.

If nobody has all relevant eyes open, present alternatives and per-person cautions. If a person disappears, turns away, crosses another person, or falls outside assessment limits, mark the changed/unknown coverage rather than declaring the frame better. Intentionally closed eyes and winks remain legitimate user choices. Avoid scoring smiles, attractiveness, emotional desirability, or gaze direction as universal quality.

New ranking confidence must be calibrated separately from raw score margin. During rollout, people-derived changes must not newly grant `isSafeForOneClickCulling`; existing eligibility should be conservatively withheld where unresolved people evidence conflicts with the winner. Any later restoration of automatic culling eligibility needs its own evaluation and explicit action semantics.

## 12. Burst review controls and presentation

| Control | Proposed behavior |
|---|---|
| Best frame | Display stored best-frame order, incorporating validated compatible people evidence when available. No expensive work on each click. |
| AF-point sharpness | Retain explicit measured AF-center ordering and missing-score loading. Do not silently change it into face ordering. |
| People status | Show ready/pending/paused/limited; allow start or retry when needed. |
| Eye preference | “Prefer open eyes” affects ranking interpretation, not detection results or saved ratings. |
| Close-ups | Offer detected face/eye targets alongside existing manual and AF inspection. |
| Combined Review | Remains a separate, explicitly started deeper review. |

Recommend removing Suggest Best Frame once ordinary ranking updates automatically and it has no distinct purpose. If a deliberate action is needed, make it concrete: **Assess people in this burst** for missing analysis, or **Recheck people** in a menu for explicitly invalidating/rerunning this evidence. Do not make a sort toggle secretly invoke Combined Review. Settings affecting only interpretation should not require a separate analysis button.

Opening a burst should preserve a valid selected frame, show current evidence, and schedule missing foreground evidence if enabled. When results arrive, preserve the selected photo and viewport. To avoid moving targets, defer changing the current filmstrip order until the user leaves/reopens the burst or accepts “Updated ranking available.” Offscreen bursts may adopt complete new orders automatically. Define the pending-order snapshot separately from the displayed order so badges and ranks remain internally consistent.

Use concise labels such as “Face detail: good,” “Eyes appear closed,” “Eye state uncertain,” and “2 of 3 relevant faces assessed.” Color must be accompanied by text or symbols and accessibility labels. Do not display “all eyes open” when some are unknown, and do not make a low capture-quality score a red “out of focus” badge.

Automatic crops should be selectable per face; a group photo needs more than a single center crop. Keep manual crop choices authoritative. Add automatic targets as derived data with source revision and geometry, not as saved manual `CloseUpRegionRecord`s. Reference-image comparisons need independently located faces rather than copying one face's coordinates to every frame.

## 13. Evaluation dataset and accuracy gates

Use consented/appropriately licensed photographs with real RAW embedded previews, not just webcam benchmark images. Do not upload user photographs. Public datasets may supplement evaluation only after their use terms are checked; no dataset or training license has been approved in this exercise.

Suggested starting corpus: 300–500 diverse bursts and at least 5,000 labeled visible eyes, expanded until each important failure stratum has meaningful coverage. These counts are planning targets, not a guarantee of statistical sufficiency. Split by person and shoot, not randomly by adjacent frame, to prevent nearly identical examples leaking between calibration and test sets.

Cover frontal and profile portraits, groups, children and adults, varied face/eye appearance, glasses/sunglasses, makeup, squinting, intentional closures, winks, looking down, kissing, partial occlusion, low light, high ISO, motion blur, backlighting, tiny faces, mirrored orientation, different lenses/cameras and preview resolutions. Include non-people scenes and false face-like patterns. Keep animal photographs as a no-human-assessment regression set.

Label detection boxes, visible eyes, open/closed/ambiguous state, detail sufficiency, important subjects, comparable faces, acceptable winning frames, and intentional closed-eye moments where known. Use at least two reviewers for difficult subsets and adjudicate disagreements. “Unclear” must remain a valid ground truth; forcing every example into open/closed overstates model quality.

| Metric | Proposed acceptance direction |
|---|---|
| Closed-eye warnings | At least 98% precision on assessable eyes overall; report confidence intervals and each difficult subgroup. Increase abstention if needed. |
| Open-eye claims | Independently measure false-open rate; never infer openness from missing closed-eye flags alone. |
| Coverage | Report proportion assessed at each resolution/pose and unknown reasons. Precision without coverage is not sufficient product evidence. |
| Face detection | Recall/precision by face size and pose, including the missed-important-face rate. |
| Detail judgment | Agreement on human-labeled sharper/softer same-face pairs, ties allowed; compare to baseline and simple metrics. |
| Ranking | Human-acceptable winner rate and top-three recall versus existing ranking, with paired uncertainty estimates. |
| Intentional closures | Rate of inappropriate demotions and visible caution behavior; explicitly inspect this subset. |
| Groups | Correct coverage and association; no quiet improvement caused by a missed person. |
| Stability | Repeated/cached runs produce the same order for identical evidence; any platform tolerance is documented. |

The 98% threshold is a proposed product gate. It is not supported by a completed experiment. For example, even zero mistakes in 150 warnings gives only limited evidence about a 2% error bound; meaningful per-subgroup claims require larger samples. If precision passes but almost every image is uncertain, improve resolution/backend or narrow the advertised feature. If reliable open-eye classification is unavailable, ship closed-eye cautions without a green open-eye assurance.

## 14. Performance validation for ordinary Macs

The baseline target should be an 8 GB M1-class Mac, including a fanless MacBook Air, plus a representative 16 GB newer base-series Mac. A high-memory Pro/Max machine is an additional data point, not a substitute. Use the app's supported macOS version, record OS and request revisions, and compare cold and warm runs.

Candidate engineering budgets to validate:

| Area | Initial target, subject to measurement |
|---|---|
| Cached burst opening | No new decode/inference required for compatible evidence; minimal metadata hydration |
| Visible burst | Useful partial evidence within roughly 1 second; a typical 10-frame portrait burst within roughly 3 seconds on baseline hardware |
| Background throughput | Aim for at least 5 typical images/second including I/O/decode; report group-photo costs separately |
| Incremental memory | Aim below 200 MB peak for one worker, no sustained growth across a 10,000-image run |
| Cancellation | Stop scheduling immediately; discard stale publications, release buffers after the in-flight framework request finishes |
| Navigation | No material regression in input-to-image latency or sustained UI stalls while assessment runs |

These are go/no-go questions, not promises. If the visible-burst goal fails, keep evidence progressive, lower scan resolution only where accuracy remains acceptable, narrow expensive crop work, or make broad background scans optional. Do not conceal slower behavior behind an optimistic average.

Measure stage-level p50/p95 latency, bytes decoded, face count, time spent waiting for decoder slots, peak resident memory, cache hit rate, thermal behavior, power impact, and cancellation latency. Use cold internal/external storage and sustained 15–30 minute workloads. Benchmark against the same navigation-only and existing burst-preparation baselines. Record total wall time as well as inference time.

Instrument cache read, image decode, detection, landmarks, eye backend, local detail, persistence, and ranking publication with signposts. Use Instruments/Time Profiler and memory/energy tools available in the installed Xcode. Before scripting `xctrace`, inspect current help and command-specific help; trace schemas and CLI commands vary by version. This plan follows the installed Apple `xctrace` skill guidance; no traces were captured in this documentation exercise.

For a custom Core ML model, compare allowed compute-unit configurations rather than assuming a model runs on the Neural Engine. Hardware selection and conversion compatibility need actual profiling. Vision likewise should not be described as “free” or “always ANE.” [Core ML compute units](https://developer.apple.com/documentation/coreml/mlmodelconfiguration/computeunits).

## 15. Implementation sequence and completion criteria

Each phase is a separately reviewable change. Phase 0 results can revise the backend and later estimates without invalidating the document's workflow goals.

### Phase 0 — Feasibility and decision record

Prepare a consented sample corpus and an isolated evaluation harness after implementation is authorized. Compare Vision detection/landmarks/quality, Core Image flags, and geometric eye aperture. Run the image-size/source-pixel sweeps and profile one/two workers on baseline hardware. Capture failure examples locally. Write a backend selection report with measured precision, coverage, latency, memory and limitations.

**Exit:** select a built-in baseline or establish, with evidence, why a compact classifier experiment is needed. No product claim about blink reliability before this gate. Estimated effort: 3–5 engineering days, excluding dataset collection and access to hardware.

### Phase 1 — Contracts and engine

Add independent versioned values and a decoded-image analysis API in PhotoAnalysisKit. Implement coordinate conversion, per-eye limitations, deterministic face IDs and failure states. Keep every backend behind an adapter. Unit-check geometry using synthetic reference points; use representative real images for backend tests. Add no ranking change yet.

**Exit:** source-independent results, documented descriptors, all orientations verified, no Vision objects crossing into core ranking. Estimated effort: 3–5 days.

### Phase 2 — Persistence and scheduling

Add app adapters and per-source artifact storage. Integrate source/sidecar signatures and atomic writes. Add priority scheduling, bounded decoding, cancellation, retry/backoff and progress. Cover cache-hit and cache-miss burst paths. Verify catalog switching and partial resume before broad background scanning.

**Exit:** reopening compatible evidence runs no inference; changed sources invalidate only affected artifacts; no stale catalog publication or review-state loss. Estimated effort: 4–6 days.

### Phase 3 — Evidence and close-up UI

Show per-face/eye evidence, unknown reasons and coverage. Extend PhotoEvidenceKit with automatic inspection targets separate from manual choices. Preserve selected image/viewport and displayed order while work completes. Retain both existing sort modes; place start/pause/recheck controls according to actual work state. Keep Combined Review independent.

**Exit:** useful portrait and group inspection without a large model, usable keyboard/accessibility behavior, no inference triggered by ordinary sorting. Estimated effort: 3–5 days.

### Phase 4 — Primary-face ranking in shadow mode

Add compact people summaries and a new ranking descriptor in RawCullCore. Implement shared-cohort eligibility, fallback, stable ties, bounded adjustments and explicit reasons. Preserve manual winners and saved ratings. Separate recommendation confidence from existing one-click eligibility. Evaluate against human labels and the old ranking.

**Exit:** measured ranking improvement with documented uncertainty and no unacceptable regressions. If the evidence only helps inspection, ship that benefit without forcing ranking changes. Estimated effort: 4–6 days including initial calibration, more if the corpus needs expansion.

### Phase 5 — Enable validated ranking and polish controls

Publish people-aware rankings only for validated cases. Implement pending/displayed ranking snapshots, setting changes without new inference, cache compatibility, explanatory messages, and rollback to baseline. Remove Suggest Best Frame if redundant; replace it only with a clearly distinct assessment/recheck action if justified.

**Exit:** opening and sorting behavior is documented, predictable, and tested; existing burst decisions survive upgrades. Estimated effort: 2–4 days.

### Phase 6 — Group ranking and optional model fallback

Treat these as two independent optional projects. Group ranking needs validated associations and relevance policy. A compact eye classifier needs licensed artifacts, representative calibration, Core ML deployment checks and performance evidence. Neither should block shipping useful built-in face inspection.

**Exit:** each addition independently passes its own gates. Effort cannot be responsibly fixed before Phase 0 and the group corpus; allow at least an additional development/evaluation iteration, potentially several weeks if training is required.

### Phase 7 — Release validation

Run correctness, migration, real-image accuracy and sustained hardware tests. Compare results to the declared gates and document actual supported limits. Release behind a reversible feature preference first, with face-informed automatic culling eligibility withheld until separately justified. Publish package versions in dependency order, update app pins and release notes, and retain baseline fallback.

**Exit:** no unsupported accuracy/performance claims, reproducible reports, and a clear rollback path. Estimated effort: 3–5 days plus device availability. Overall baseline effort is roughly 4–7 engineering weeks for one developer, highly dependent on data and the eye-state gate; this is a planning estimate, not a commitment.

## 16. Required verification before shipping

- Geometry: all EXIF orientations, mirroring, crop edges, non-square frames, normalized/source/crop round trips, anatomical-side conventions.
- Evidence: tiny/hidden eyes, nil quality, invalid values, no faces, false detections, extreme pose, one visible eye, conflicting backends, ambiguous face matches.
- Ranking: identical baseline when ineligible/disabled; no zero-for-unknown bug; stable ties; no metadata/blur double-counting; manual winner and ratings untouched; one-click gate remains conservative.
- Lifecycle: cancel during decode and backend work; change catalogs; remove or replace source; change sidecar; pause/resume; memory pressure; retry failure; no work caused by view recomputation.
- Persistence: old catalogs, cache hits with missing people evidence, model/OS/descriptor changes, corrupt artifacts, partial commits, remapped runtime IDs, cache cleanup without user-decision loss.
- UI: asynchronous evidence does not move the selected frame or viewport; pending order is explicit; AF and Best frame remain distinct; manual close-ups are not overwritten; coverage and uncertainty are accessible.
- Integration: no Qwen/SAM load for people assessment; existing grouping/model behavior reported separately; foreground navigation retains priority; package pins match released compatible contracts.
- Product accuracy: held-out precision/coverage and paired ranking reports, subgroup failures, intentional closures, missed important faces and group-set changes.
- Performance: baseline 8 GB machine, warm/cold cache, sustained workload, many-face photos, external storage, Low Power Mode and thermal pressure.

Tests should target these behaviors and failure modes rather than merely mirror field assignments. Real-image accuracy tests need pinned fixture provenance and tolerant measured expectations; framework output can change across OS revisions. Deterministic ranking/geometry/cache tests should remain independent of model downloads and framework nondeterminism.

## 17. Risks and answers

| Risk | Response |
|---|---|
| Built-in closed-eye flags are insufficient | Compare to labeled data; abstain; evaluate a compact classifier only if justified. |
| Eye state is confused with artistic desirability | Use appearance wording; optional open-eye preference; no automatic reject. |
| Face quality favors frontal expressive conventions | Keep it advisory/low influence and compare the same subject; measure difficult subsets. |
| Eye crops lack original detail | Record original pixels; escalate embedded resolution within budget or return unknown. |
| Whole-image decode dominates | Bound workers and buffers; reuse per-frame decode; measure I/O and decode separately. |
| Missing detections make a group look better | Track coverage and unmatched faces; withhold people ranking on unstable cohorts. |
| New scores accidentally unlock one-click culling | Explicitly separate eligibility from the new ranking and test migration. |
| Existing burst cache bypasses the new pipeline | Schedule per-file evidence independently on cache hits; version derived rankings separately. |
| Model additions defeat the ordinary-Mac objective | Require baseline hardware gates and a built-in useful fallback. |
| Scope expands into animal eyes, expression grading or identity | Keep those outside baseline; write separate requirements and evaluation if requested. |

## 18. Original proposal handover

This section records the state at the end of the 8 November documentation exercise. See the status at the top and the pilot report for implementation and measurements completed since then.

I am satisfied that this document defines an implementable, staged direction and the important failure boundaries. **It cannot be 100% certain about accuracy, speed, or the best eye backend without implementing and benchmarking the candidates.** More speculative reading cannot replace those experiments. The evaluation therefore ends at a concrete decision-and-validation plan rather than inventing measurements.

Unresolved empirical questions, in priority order:

1. Can Core Image flags or Vision landmark geometry meet the closed-eye precision target at useful coverage on real photographic previews?
2. Which detection size/source-pixel thresholds give the best accuracy/latency tradeoff on an 8 GB base Mac?
3. Does a region-specific detail metric outperform existing global/AF scores for the same face without being dominated by noise and JPEG sharpening?
4. Can primary-face correspondence be conservative enough without persistent identity recognition?
5. How much people evidence improves actual keeper choices, especially intentional closures and groups?
6. Is a custom classifier necessary, and if so which licensed weights/data and deployment configuration pass the gates?

No code experiments, model downloads, training, product benchmarks or accuracy measurements were performed. No paid external inference service was used. This session does not expose the user's remaining AI-credit balance, so exact credits spent/remaining cannot be reported. Research was bounded to targeted repository/SDK inspection and primary-source checks; no autonomous agents or repeated large-model photo reviews were used.

### Five-hour checkpoint and continuation instructions

The documentation exercise was completed within the first five-hour window; no timeout handover is required. The following handover remains useful for a future authorized implementation/evaluation session:

- Read this document first, then recheck repository HEAD and dependency pins; do not assume they still match the revisions above.
- Keep the first next step to Phase 0, not immediate changes to ranking weights or the sort buttons.
- Obtain a suitable local, permitted photo corpus and baseline hardware. Do not assume existing wildlife fixtures cover human-eye evaluation.
- Confirm that implementation/prototype work is authorized; the instruction for this session was documentation only.
- Compare the two built-in eye baselines with Vision location/geometry, preserving unknown states. Record latency including preview decode and memory.
- Produce a measured backend decision report, dataset manifest and failure examples before committing to a model or shipping eye-based ranking.
- If another five-hour research window expires before that report is ready, append what was actually measured, exact commands/artifact locations, failed assumptions, remaining questions, and the smallest next experiment. Never mark unrun tests or unmeasured budgets as passed.

## 19. Sources and evidence boundaries

Primary external sources were checked on 8 November 2026. Some Apple web pages expose only JavaScript shells to the reader; the installed SDK headers were also inspected for the specific API contracts. No source documents performance for this exact proposed pipeline.

- [Narrative product overview](https://narrative.so/select): public workflow/features, not architecture or benchmark evidence.
- [Narrative First Pass](https://help.narrative.so/en/articles/7337372-ai-first-pass-image-assessments): assessments, filtering and explicit ratings.
- [Narrative scene ranking](https://help.narrative.so/en/articles/8119179-use-scenes-and-rank-ordering-in-narrative): within-scene order and user decisions.
- [Apple face-analysis sample](https://developer.apple.com/documentation/vision/analyzing-a-selfie-and-visualizing-its-content): detection, capture quality and landmarks.
- [Apple face capture quality](https://developer.apple.com/documentation/vision/vndetectfacecapturequalityrequest): built-in quality request.
- [Apple face landmarks](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest): face-feature localization.
- [Apple Core Image eye-blink option](https://developer.apple.com/documentation/coreimage/cidetectoreyeblink): enables closed-eye detection.
- [Apple closed-eye property](https://developer.apple.com/documentation/coreimage/cifacefeature/righteyeclosed-swift.property): Boolean evidence, not calibrated confidence.
- [Apple Core ML compute units](https://developer.apple.com/documentation/coreml/mlmodelconfiguration/computeunits): compute configuration; actual placement/performance requires measurement.
- [Google Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker): alternative geometry/expression pipeline, not validated macOS integration.
- [Soukupová and Čech, Real-Time Eye Blink Detection using Facial Landmarks](https://cmp.felk.cvut.cz/ftp/articles/cech/Soukupova-CVWW-2016.pdf): eye geometry and temporal blink research, not a direct RAW-culling accuracy claim.
- Installed macOS SDK: `CoreImage.framework/Headers/CIDetector.h`, `CoreImage.framework/Headers/CIFeature.h`, and `Vision.framework/Headers/VNObservation.h` under the SDK returned by `xcrun --show-sdk-path`.
- Local [xctrace skill](/Users/thomas/.agents/skills/xctrace/SKILL.md) and its overview reference: performance-investigation procedure. No profiling results are claimed.

All proposed architecture, resource budgets, acceptance thresholds, phase estimates and product decisions above are engineering recommendations derived from the inspected app and the stated goal, rather than facts attributed to Narrative or Apple.
