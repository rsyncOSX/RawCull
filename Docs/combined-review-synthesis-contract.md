# Subject-grounded synthesis — delivery step 6

Implemented 11 October 2026. This is delivery step 6 in
[the consolidated AI verification summary](ai-verification-summary.md), not the original phase 6 resource milestone.

## Structural support

`ReviewSynthesisGrounding` resolves persisted observation, region, subject and
measurement ownership after request-local evidence aliases are resolved. Available
independent observations require current stage semantics and the correct image.
Crop observations require a matching registered region/source; subject regions
require an available subject with current foreground registration. Reconciliation
is never independent evidence. Measurements require current mask/scorer semantics,
finite values and a registered subject.

Claims retain subject/region scope derived from their unique supporting owners.
If the model supplies scope, it must match those owners. Detail requires one crop
region, at most one subject and structured positive target support. A measurement
cited with a crop must belong to that crop's subject. Measurement-only support
cannot establish composition, behavior, anatomy, exposure or visible detail.
Contradictions must be independent eligible evidence, cannot cite a supporting
reference itself, and cannot substitute another subject for a scoped claim.

Crop responses carry optional `targetIdentified`; absence means unknown. A false
value may accompany a useful background/framing observation, but cannot establish
subject detail. `insufficientEvidence: true` together with positive target support
is rejected as `crop.targetSupportConsistency`. Unknown/absent target support is
also disclosed as a limitation. Structured flags remain model assertions; they
do not establish visual truth, anatomical plausibility or correct segmentation.

## Presentation and bounded outcomes

Synthesis rows declare subject, region and target support. Measurement rows contain
availability and subject ownership, never numeric vectors. Deterministic summaries
read the stored measurement by ID and show its subject ID, scorer and sorted values.
The model cannot supply numeric detail claims. Metrics remain render-dependent and
uncalibrated; no sharp/blur threshold is introduced.

Requests permit four descriptive claims for composition, exposure, visibility and
detail, preserve conflicting evidence references/uncertainty, and allow visible
behavior under visibility. Missing claim categories are explicit report limitations
and mark coverage incomplete. This is coverage accounting, not proof that prose
accurately addresses those criteria. Exact values, claim scope and report limitations
are visible in the review inspector.

Failed synthesis retains the existing terminal failure, charged attempt, compact
rejection diagnostics and explicitly unsynthesized evidence-only summary. Validators
are not weakened and no uncharged inference retries are introduced.

## Compatibility

Pipeline `combined-v7` changes crop-observation, reconciliation, report and comparison
stage versions to `combined-v7`. Overview/segmentation/identity/measurement remain
`combined-v6`; source and CLIP contracts remain unchanged. New target support and
claim scope are optional Codable fields so historical artifacts remain readable.
Older snapshots cannot resume into the new pipeline; create a new run. There is no
promise of selective recomputation. Legacy absent crop support is unqualified.

## Qualification boundary

Regression fixtures use deliberately different subject values (0.125 and 0.875),
subject/region swaps, cross-image ownership, unrelated contradictions, missing
registration, absent/unknown target support, stale scorer semantics and metric-only
claims. Existing feature contracts cover charged failures, continuation, unsynthesized
summaries, export/restore, cancellation, immutable budgets and capped comparison.

The frozen export remains unavailable according to
[baseline-availability.json](CombinedReviewRegression/baseline-availability.json).
Independent wildlife annotations and the frozen six-image/comparable-scene reruns
remain delivery step 7 prerequisites. This implementation provides structural
support checks; accepted photographic prose still requires visual review and the
original phase 7 independent qualification. Original phase 6 resource measurements
remain outstanding.

The installed Qwen synthetic-landscape probe passed in 35.986 seconds with one
accepted, region-scoped composition claim and no detail claim for its unidentified
target. Its overview failed `overview.discoveredContextualConcept`; continuation
and incomplete coverage remained explicit. Visual inspection found an accepted
source-geometry error: the cyan circle was described as an oval. Declared stretch
preprocessing is a plausible explanation, not independent corroboration. See the
[compact probe evidence](CombinedReviewRegression/step6-synthesis-probe.json).

Focus/sharp/blur wording additionally requires a registered subject crop irrespective
of claim type, so placing a whole-scene focus assertion in `composition` cannot bypass
detail support. This supplementary text guard is intentionally narrower than a claim
of semantic validation. The regression explicitly exercises that claim-type bypass.

## Verification commands and results

- `make test-smoke`: passed; 325 unique identifiers, 377 passing invocations and
  one expected opt-in Qwen skip. The smoke manifest and its integrity expectations
  now include the four previously omitted mask/registration/priority/diagnostic suites.
- Focused `xcodebuild test` for `CombinedReviewFeatureTests`, `ReviewDiagnosticsTests`,
  `ReviewRunContractTests`, `ReviewMaskRegistrationTests` and `ReviewSubjectPriorityTests`
  exercised ownership, compatibility, budgets, cancellation and restore. Final smoke
  includes these suites and the real scorer regressions.
- Installed probe: `TEST_RUNNER_RAWCULL_COMBINED_REVIEW_RUN=1`,
  `TEST_RUNNER_RAWCULL_COMBINED_REVIEW_QWEN=/Users/thomas/ModelAssets/Release/Models/Qwen/qwen3_vl_2b`,
  `TEST_RUNNER_RAWCULL_COMBINED_REVIEW_IMAGE=<repository>/Docs/CombinedReviewInputFixtures/source-landscape.png`,
  followed by `xcodebuild test -project RawCull.xcodeproj -scheme RawCull
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile
  -enableCodeCoverage NO -only-testing:RawCullTests/CombinedReviewRealModelTests`.
  Passed; SAM/CLIP were omitted in this synthetic probe. It does not qualify wildlife
  interpretation, full RAW focus or concurrent model residency.
- `make verify-ai-import-boundary`, `git diff --check` and changed-file SwiftFormat
  lint passed. SwiftLint reports the same three pre-existing complexity errors in
  `ReviewEvidence` and `CombinedReviewExecution`; the new grounding code introduces
  no lint errors. Formatting/line-length warnings remain distinct from those errors.

Default rejected-text retention remains unchanged. New `targetIdentified` and
`subjectID` decoder fields are included in the bounded diagnostic field-path allowlist.
No proprietary photographs or baseline exports were added to Git.
