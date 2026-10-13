# RawCull AI verification summary and next steps

Updated 13 October 2026 (Europe/Oslo). Consolidates the dated AI run investigations and repair reports from 9–13 October, plus the four currently retained local script runs. This is a review of existing evidence; no inference, app build or Swift test suite was rerun during consolidation.

## Decision

Consolidating the test reports is appropriate: one maintained record makes the current result and remaining gates easier to assess. RawCull has substantial engineering verification for local AI inputs, evidence ownership, bounded inference, diagnostics and partial results. **Photographic accuracy, useful comparable-image ranking and resource qualification are still incomplete.** A successful Xcode run establishes the runner's checks, not that every generated sentence is true or every requested criterion is covered.

The latest retained Combined Review run uses **combined-v21** and passes all 125 scheduled stages. It retains 19 claims, but all six reports are incomplete and five have no detail claim. The three retained multi-mode diagnostic runs all fail Object Analysis checks, despite successful SAM/Deep Review and whole-image Qwen stages. Recurring `MDB_MAP_FULL` errors remain unresolved.

## Scope and evidence limits

Two scripts are present under `Scripts/Run*`:

- `RunCombinedReviewSix.py`: full Combined Review with Qwen, SAM3 and DataComp CLIP, six images and selection comparison, Standard depth and production source policies.
- `RunAIAnalysis.py`: sequential SAM/Deep Review, Qwen Vision and automatic Objects diagnostics on one to six ARWs. A separate CLIP embedding probe runs; the SAM 3 + CLIP tab's Deep Review path does not itself call CLIP.

Input SHA-256 inventories, manifests, accepted/rejected responses, request images, build logs and xcresults are the primary evidence. Many older temporary directories are unavailable now; their numbers below are historical recorded findings, not newly reproduced measurements. Missing records are marked unknown rather than treated as passes. This inventory covers the runs identifiable from Docs and currently retained local runner directories; it cannot reconstruct undocumented or deleted runs.

Three distinct six-image cohorts occur:

| Cohort | Files | Comparison boundary |
| --- | --- | --- |
| A: original Downloads wildlife | DSC00113, DSC00639, DSC02022, DSC05921, DSC09214, _DSC6564 (ARW) | Original v2/v7 evaluation and Downloads follow-ups |
| B: earlier tmp wildlife | _DSC0563, _DSC4595, _DSC4764, _DSC6640, _DSC6844, _DSC8590 (ARW) | Earlier tmp follow-ups through v20 |
| C: current tmp selection | _DSC0322, _DSC1394, _DSC6074, _DSC7753, _DSC7937, _DSC8202 (ARW) | Retained v21 and three multi-mode runs; all four runner SHA-256 inventories match exactly |

The same directory name `/Users/thomas/tmp` has contained different selections. Compare filenames and SHA-256 inventories before attributing changes to code. Runtime source fingerprints in a Combined Review manifest are distinct from the runner's original-file SHA-256 inventory.

## Engineering and source probes

| Verification | Recorded result | What remains outside its scope |
| --- | --- | --- |
| 9 October installed input probe | Both tests passed without skips; 11 synthetic fixtures × three model bundles, including detail inputs; eight EXIF orientations and aspect-ratio controls | Photographic accuracy and other bundles/preprocessing |
| Qwen input contract | 448 × 448 stretch, RGB Float32 NCHW, 196 image tokens, 4096-token context; exhausted-context and response-limit checks | Native multi-image input, alternate encoders and photographic detail lost through reduction |
| CLIP input contract | OpenAI 224 × 224 and DataComp 256 × 256, Float16 binding, center crop, 77 text tokens, 512-dimensional embeddings; finite repeatable outputs | Peripheral evidence excluded by center crop; similarity is not photographic quality |
| Input milestone checks | Smoke: 258 identifiers, 257 passed and one expected opt-in skip; targeted runtime, hostless Release contracts and import boundary passed | Current candidate validation; historical counts are not current suite totals |
| 10 October Qwen-only six-ARW source probe | 123.673 s; 19 responses; six incomplete reports with 11 claims total; unrelated/abstain selection | SAM/CLIP residency, full integration and photographic annotation |
| RAW source admission | Two 6000 × 4000 sources admitted for RAW decode/crop with declared alignment; four 8640 × 5760 sources refused full decode under the 24 MP/2 GB limits and reviewed through bounded previews | Broader camera formats, RAW recovery and measured system memory |
| Synthetic full-source memory | 6000 × 4000 raster; process high-water 863,830,016 bytes isolated and 1,001,422,848 bytes in smoke; retained image bytes 107,182,080 | Includes fixture/test-host allocations; no models or RAW demosaic, so not production peak-memory qualification |
| Repair regression phases 1–5 | Baseline freeze: two checks passed; corrected mask phase: 60 tests/81 executions passed; geometry/orientation, overlay, priority, storage/restore and diagnostic checks passed; final phase-5 aggregate: 71 tests/100 executions passed | Original deer/mallard/sparrow photographic controls and independent annotations remain open |

Detailed reproducibility records remain in the [input contract](combined-review-input-contract.md), [source contract](combined-review-source-contract.md), [source fixtures](CombinedReviewSourceFixtures/phase5-arw-smoke.json), and [regression evidence](CombinedReviewRegression/README.md).

## Combined Review run history

Counts are completed/failed scheduled work items unless stated otherwise. Accepted claims and criterion labels measure coverage, not correctness. All `/private/tmp/rawcull-six-*` names below identify historical evidence roots; only `f09u63a3` was available for fresh inspection during this consolidation.

| Date / pipeline / cohort | Evidence root or run | Recorded outcome |
| --- | --- | --- |
| 10 Oct, v2, A | Run `88E32164-72C2-4943-A55C-F6D2B1AAAE13`; original Downloads export | 94/4; overviews 5/6, crops 13/13, reports 4/6, all accepted reports incomplete. Mask scoring and crop registration defects found. |
| 11 Oct, v7, A | Run `70585F07-64B8-4A70-9B5D-88190EE69EBF`; updated Downloads export | 50/9; overviews 1/6, measurements only on rabbit, reports 3/6 with one claim each. Three failed reports preserve evidence-only summaries. |
| 11 Oct, v7, A | `rawcull-six-ra2k6bn7` | Initial script reproduction: 50/9, runner correctly fails. Five overview failures; rabbit reconciliation/report and swan/sparrow reports fail grounding. |
| 11 Oct, pre-v8, A/B | `rawcull-six-_6nv7yqt` / `rawcull-six-2dcc0zim` | Investigations motivated v8. Historical follow-up records report 3/6 and 4/6 accepted reports respectively; exact full counts are not preserved in these repair notes. |
| 11 Oct, v8, A | `rawcull-six-hfyluja1` | 54/6; overview 1/6, accepted claims in all six reports; two contain four criterion labels. Fallback detail acceptance hole discovered. |
| 11 Oct, v8, B | `rawcull-six-bfenbcao` | 37/6; overview 0/6, accepted claims in all six reports; one contains four labels. No qualified subject detail from fallback. |
| 11 Oct, v9, A | `rawcull-six-l1h_xfl_` | 37/6; overview 0/6, no segmentation/measurement; all six reports retain some claims, none four categories. |
| 11 Oct, v9, B | `rawcull-six-tu78lzyo` | 36/7; overview 0/6, no segmentation/measurement; five reports retain claims; fox schema failure. |
| 12 Oct, v11, A/B | `rawcull-six-dhzy03il` / `rawcull-six-2da_k1xh` | Each accepts six overviews and 16 crops. All 32 crops across both runs declare target absent; no report retains detail. Downloads also has two report and one reconciliation failure. |
| 12 Oct, v13, B | `rawcull-six-mxl3q1wv` | All 115 stages complete; five reports have four category labels. Runner fails missing horse detail; multi-crop detail correctly rejected. About 1596 s. |
| 12 Oct, v14, B | `rawcull-six-982dg633` | 114/115 complete; all six reports have four labels and are incomplete. One prohibited bird-eye crop; accepted prose has background/target and technical grounding defects. About 1584 s. |
| 12 Oct, v15, B | `rawcull-six-yo7ajhuz` | 114/115 complete; 17 claims, five repairs; repeated prohibited eye crop and criterion conflation. |
| 12 Oct, v16, B | `rawcull-six-0xl4guf6` | All 16 crop and six report stages fail; 22 repairs and zero claims. Redundant support flags and report schema prove difficult for the installed model. |
| 12 Oct, v17, B | `rawcull-six-hnakk1mh` | 102/11; crop acceptance 5/16, reports 6/6, 19 claims, six repairs; three reports have four categories. Runner fails terminal crop work. 1539.866 s. |
| 12 Oct, v18, B | `rawcull-six-5c9y1lwy` | 103/10; crops 6/16, 20 claims, 14 repairs; four reports have four categories. All reports incomplete; runner fails. 1559.341 s. Manifest identifies v18 despite the run being described as v19. |
| 12 Oct, v19, B | `rawcull-six-ah6ciowr` | All 121 work items complete; TEST SUCCEEDED, zero repairs, 13 claims. Fourteen crops retain valid siblings with rejected criteria; only squirrel report has all four categories. All reports incomplete. |
| 13 Oct, v20, B | `rawcull-six-rj7ryy6o` | All 115 work items complete; TEST SUCCEEDED, one repair, 13 claims; no report has all four categories. Eleven ineligible category selections, 14/16 crops target absent. 1411.840 s. Manifest identifies v20 despite being described as v19. |
| 13 Oct, v21, C | `rawcull-six-f09u63a3` | All 125 work items complete; TEST SUCCEEDED, one repair, 19 claims. One report has all four categories; all six incomplete. 1433.151 s. Different cohort from v20. |

Selections with recorded decisions consistently retain the six cells and abstain on unrelated scenes. This is useful conservative behavior, but it does not qualify burst ranking, ties or Deep/Exhaustive matched-pair analysis. Historical stage totals differ as subject discovery, measurement coverage and scheduling change; stage-count improvements alone cannot measure quality or speed.

### Latest retained v21 evidence

Evidence: `/private/tmp/rawcull-six-f09u63a3/evidence`; run `DE2EBBE7-5EAD-4F9A-B542-F9BB5CB11738`, admitted 13 October at 11:58:51 Europe/Oslo. Manifest: combined-v21, Standard. Xcode's selected inference test passed; the other two opt-in tests were skipped.

All work completes: six each of source, overview, identity, reconciliation and report; 24 segmentation, 32 measurement, 22 CLIP, 16 crop observations and one comparison. Budget records one repair and no amendments.

| File | Accepted categories | Claims |
| --- | --- | ---: |
| _DSC0322.ARW | composition, exposure, visibility | 3 |
| _DSC1394.ARW | composition, exposure, visibility | 3 |
| _DSC6074.ARW | composition, exposure, visibility, detail | 4 |
| _DSC7753.ARW | composition, exposure, visibility | 3 |
| _DSC7937.ARW | composition, exposure, visibility | 3 |
| _DSC8202.ARW | composition, exposure, visibility | 3 |

Fifteen of 16 crop observations declare `targetIdentified=false`. Fourteen detail criteria are rejected for target consistency, one detail for domain, and one visibility for domain. Three report selections are replaced with already validated rows: exposure and visibility for _DSC7753, composition for _DSC7937. Rejection and substitution limitations persist; missing detail remains explicit. This demonstrates live deterministic recovery without upgrading false target flags. It does not establish that the chosen observations describe the correct pixels.

The selection says unrelated/abstain with no claims. The log contains 96 `MDB_MAP_FULL` occurrences. The 19 claims versus v20's 13 are from different images and must not be presented as a paired improvement.

## Other AI modes: all three retained script runs

All runs use cohort C and identical original-file SHA-256 inventories. Each completes 18 diagnostic rows. All three Xcode runs end **TEST FAILED**, with evidence retained.

| 13 October evidence root | SAM/Deep Review | Whole-image Qwen | Objects | Test duration | MDB_MAP_FULL occurrences |
| --- | --- | --- | --- | ---: | ---: |
| `/private/tmp/rawcull-analysis-v2_jvald` | 6/6 | 6/6 | 3/6 | 640.072 s | 12 |
| `/private/tmp/rawcull-analysis-pbdjxz4k` | 6/6 | 6/6 | 4/6 | 650.189 s | 12 |
| `/private/tmp/rawcull-analysis-7m1uy35l` | 6/6 | 6/6 | 4/6 | 580.916 s | 12 |

_DSC6074 and _DSC7753 fail Objects in every run after two assessment attempts: sharp judgments lack evidence describing resolved subject texture or edges. In the first listed run, _DSC0322 also fails an object focus-consistency value. The other two runs accept that file. Thus Objects compliance remains incomplete and shows run variation. A keyword or a successful retry is not independent verification of focus.

SAM stage times summed across six files are about 58–60 s; Qwen about 94–103 s; Objects about 429–487 s. These diagnostic times include mode-specific work and retries and are not controlled cold/warm benchmarks. Successful SAM/Qwen rows mean no recorded stage failure; no independent visual accuracy assessment was performed here. The CLIP embedding outputs are separate probes, not evidence that Deep Review fused CLIP judgments.

The [other-mode evidence rules](updateotheraimodels.md) record schema-v2 abstention, criterion/crop evidence, rejected-response retention, unverified anatomy wording and inspector changes. Their historical checks passed: 48 focused cases, an additional 17-case Objects check, app build and smoke enumeration of 355 identifiers. That document's “no new inference” statement describes its implementation task; the three runs above supply subsequent live evidence.

## Repairs and regression checks consolidated

These are recorded implementation validations, not new runs during this documentation task. Test counts include parameterized cases where the original record says so; they cannot be added together as unique tests.

| Contract version / change | Recorded verification |
| --- | --- |
| v3–v7: grayscale foreground decoding, scorer compatibility, foreground-derived registration, generic unverified anatomy, inspection/priority, typed failures and evidence-only fallback, grounded synthesis | Regression phase records retained in `CombinedReviewRegression/README.md`; synthetic geometry and restored-store tests pass; real named-photo gates remain pending |
| v8: remove copied example context, preserve observations ahead of metrics, independent claim rejection | 50 focused cases passed; `rawcull-fix-final-tests.log` |
| v9: independent optional priority hints, 500-character overview bounds, exact type aliases, registered-subject detail requirement | 54 focused cases passed, including 11 saved overview failures; 332 smoke identifiers; `rawcull-v9-validation.log` |
| v10: optional discovery fields cannot invalidate core discovery; malformed individual claims isolated | 58 focused cases and full smoke passed; 336 identifiers; `rawcull-v10-tests.log`, `rawcull-v10-smoke.log` |
| v12: target means visible generic target, separate from species/anatomy uncertainty | Focused diagnostics/feature/run-contract suites passed; `rawcull-v12-tests.log` |
| v14: single admitted registered crop reference for detail | 55 focused cases passed; `rawcull-v14-tests.log` |
| v15: conservative exact technical sentence grounding and bounded domain repair | Focused suites passed; `rawcull-v15-tests.log` |
| v16: separate supported criterion observations and text, no cross-criterion borrowing | Focused suites passed; `rawcull-v16-tests.log` |
| v17: four required nullable crop strings and explicit full report schema | Focused suites and saved v16 response replays passed; `rawcull-v17-tests.log` |
| v18: bounded target/length repair and exact criterion focus validation | 66 focused cases passed; 349 smoke identifiers; `rawcull-v18-tests.log` |
| v19: independently reject crop criteria and preserve valid siblings/limitations | 67 focused cases passed; 350 smoke identifiers; `rawcull-v19-tests-final.log` |
| v20: choose eligible criterion rows; assemble exact text and IDs in code; one claim/category | 68 focused cases passed; 351 smoke identifiers; `rawcull-v20-validation.log` |
| v21: explicit generic target in crop prompt; recover invalid non-null selections with validated rows, preserve null abstention | 68 focused cases and six runner checks passed; `rawcull-v21-focused.log`; subsequent live run recorded above |
| Runner selection and execution detection | Combined runner evolved from three to five to six passing checks, covering filename selection, executed-test evidence and failure status; optional suites compiled with inference disabled |

Log basenames in this table refer to historical `/private/tmp/` files and may no longer exist. Retained response fixtures in `CombinedReviewRegression/` preserve v8/v9 overview, v16 schema, v17/v18 crop and v19 report regressions.

## Findings that remain open

1. **Photographic truth.** Structural validation cannot detect every wrong animal color, inferred sunset, motion described as occlusion, background texture attributed to a subject or incorrect target flag. Higher claim counts and four category labels are insufficient.
2. **Subject geometry and scoring.** The original scorer consumed grayscale support as alpha, producing nearly identical values and about 98.78% coverage across different masks. Foreground decoding and scorer versions fix the engineering defect; the v7 rabbit shows differentiated measurements and correctly retained framing. Deer torso/background crops, mallard clipping and foreground/rear sparrow separation still need fresh visual qualification against source-space annotations. Scores remain render-dependent and uncalibrated.
3. **Target and detail compliance.** v19/v20 had 14/16 absent targets; current v21 has 15/16 on a different cohort. Generic target wording has not established reliable detail coverage. Objects repeatedly rejects unsupported sharpness.
4. **Source and model limitations.** Embedded JPEG previews, Qwen stretch and reduced boards cannot establish sensor-level focus, verified eyes or RAW recovery. SAM requested head masks are not anatomical verification. CLIP similarity is not an independent focus or quality measurement. Historical SAM identity is metadata-based rather than cryptographically verified; arbitrary providers retain unverified encoder-geometry flags.
5. **Storage.** MDB_MAP_FULL occurs in live runs and was also recorded in fake-backend focused tests. Its emitter, database and impact are not established. Completed review artifacts do not establish success of every affected storage operation. No speculative database deletion or map-size change has been justified.
6. **Comparable scenes and resources.** The unrelated-photo controls do not qualify goal-based winners, near ties or pair reasoning. Standard budget accounting does not qualify Deep/Exhaustive memory, cold/warm latency, pressure behavior, unloading or responsive cancellation. The v2→v7 shorter export interval accompanied less work and is not proof of faster inference.

## What next to complete verification

### 1. Freeze and preserve a reproducible candidate

Record app commit/build, model content fingerprints, dependency pins, OS/hardware, source SHA-256 inventories, pipeline/schema versions, settings and generation parameters. Retain the private evidence, logs and xcresults outside temporary storage before cleanup; keep photographs and raw responses out of Git. Name cohorts explicitly. Run instances sequentially because they share heavyweight resources and build cache.

**Exit evidence:** each result resolves to the exact candidate and immutable input inventory; no claims based on unavailable logs are treated as newly verified.

### 2. Resolve storage errors and repeated Objects failures

Identify the MDB_MAP_FULL emitting component and affected database from a controlled reproduction, then verify write/read/relaunch behavior before and after any repair. Diagnose Objects failures against their actual numbered crops, prompts and rejected responses. Preserve subject-specific evidence, abstention, retry accounting and original failures; do not insert sharpness keywords simply to pass validation.

**Exit evidence:** no unexplained storage errors in the candidate run; affected persistence operations verified; Objects either produces supported crop judgments or explicit useful uncertainty, with failures reported accurately.

### 3. Run paired regressions on the same photographs

Rerun cohort B under v21 for an actual comparison with v19/v20, and retain cohort C as an additional control. Rerun the original frozen cohort A to inspect deer, mallard, sparrow and rabbit regressions. Use both scripts on the same eligible sources and document source/render differences. Inspect masks, original source, foreground bounds, retained crops and actual request rasters alongside every accepted claim. Record category coverage, target flags, partial rejections, substitutions, repairs and run variation. Do not tune by weakening evidence ownership or upgrading target flags.

```sh
python3 Scripts/RunCombinedReviewSix.py --frozen
python3 Scripts/RunCombinedReviewSix.py --directory /path/to/frozen-cohort-b
python3 Scripts/RunCombinedReviewSix.py --directory /path/to/frozen-cohort-c
python3 Scripts/RunAIAnalysis.py --directory /path/to/frozen-cohort-c --limit 6
```

For diagnostics and options, use the [six-ARW runner guide](CombinedReviewRegression/six-arw-runner.md) and [multi-mode diagnostics guide](ai-analysis-diagnostics.md).

**Exit evidence:** named crop/scorer regressions visually aligned or explicitly unsupported; exact evidence ownership preserved; unsupported detail abstains; useful supported criteria survive to final presentation. Success is assessed against annotations, not stage or claim count alone.

### 4. Qualify the remaining AI workflows and app behavior

Add comparable bursts, near ties, deliberate subject/background focus differences, occlusion and exposure variation. Test Standard, Deep and Exhaustive tradeoffs and supported selection/tie/abstention. Exercise semantic search and similarity separately using relevant/irrelevant queries and known matches; the two scripts do not fully qualify those features. Check mask instance separation and measured AF/focus-map presentation without confusing locations with sharpness evidence.

In the app, verify cancellation, compatible resume, changed-model/cache invalidation, catalog switching, failed/partial results, relaunch, export/cleanup, unavailable or removed models, download retry and offline inference. Check keyboard and VoiceOver presentation of uncertainty and failed results. Record real-model latency and peak memory under cold/warm runs and pressure/unload/reload, protecting mandatory coverage from optional work.

**Exit evidence:** correct selection behavior and persistence under failure; defined latency/memory limits met on supported hardware; responsive cancellation; core culling remains usable without optional models.

### 5. Complete independent photographic qualification

Follow the retained [evaluation specification](deepaireview-evaluation.md): start with 120 consented images in 30 groups, split by scene/session/identity into 60 development and 60 held-out images. Include difficult subjects, blur, noise, occlusion, portrait orientation, limited previews and unsupported RAWs. Use two independent blinded annotators and adjudicate disagreement. Compare whole-image Qwen, Objects and Combined Review on pinned candidate inputs; compare Standard and Deep separately and repeat nondeterministic workflows three times.

Freeze numerical tolerances from development results **before** held-out evaluation. Report unsupported/contradicted claims, identity/coordinate errors, incorrect detail judgments, missed material obstructions, ranking agreement, abstention coverage, incomplete reports, usefulness, latency and peak memory with denominators and uncertainty intervals. Require zero invalid evidence references and deterministic coordinate/identity violations. The small wildlife controls alone cannot set general accuracy thresholds.

**Exit evidence:** held-out performance meets the recorded tolerances without tuning on the held-out answers; photographic reviewers find the reports accurate and actionable within disclosed source limits. Resource phase 6 and independent evaluation phase 7 require their own evidence; grounded-synthesis remediation step 6 does not close either gate.

### 6. Record the release decision

Run the relevant focused checks, required smoke/full candidate checks, model-provenance and AI import-boundary verification, and real-model release probes after the final implementation change. Record every skip and its reason. Attach the candidate's actual results, unresolved limitations and reviewer decision here. Historical passing test counts do not qualify a newer build.

**Completion criterion:** engineering, storage, app behavior, resource and independent photographic gates all have candidate-specific evidence, or the release deliberately excludes unsupported capabilities and clearly discloses the remaining limits. Current status: **verification still in progress**.

## Documentation consolidation

The dated evaluations (`evaluationphase1_5`, `evaluationphase1_6`, its newruns/v9runs follow-ups, and the v17–v20 investigations), six short `combined-review-*fix*` reports, the v16 criterion-observation report, and v18–v21 repair/next-run reports are superseded by this document and removed from Docs. Their source history remains in Git.

Keep the implementation plan, photographic evaluation specification, input/source/storage/single-image/selection/synthesis contracts, runner guides, other-mode evidence rules and machine-readable regression fixtures. They define current behavior or reproduction procedures rather than duplicate run summaries. Existing private photos, model outputs and xcresults are retained; this cleanup removes superseded repository documents only.
