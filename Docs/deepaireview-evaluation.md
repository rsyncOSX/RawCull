# Combined Review evaluation specification

Date: 9 October 2026  
Status: proposed protocol; dataset and results have not yet been collected. Companion to [the implementation plan](deepaireview.md), section 12.

## Dataset and split

Start with 120 consented photographs in 30 groups of four, including comparable sequences and unrelated selections. Reserve 60 images/15 groups for development and 60 images/15 groups for held-out qualification. Split by scene/session and subject identity to avoid near-duplicate leakage. Include at least ten examples each of soft subjects with sharp backgrounds, tiny subjects, motion blur, noisy RAWs, similar subjects, occlusion, closed eyes, portrait orientation, limited previews, and unsupported RAW handling; categories may overlap. Include at least four unrelated groups. Keep original sources and available preview/RAW alternatives linked to one image ID. Synthetic geometry fixtures are separate from this photographic set.

The evaluation owner curates consent and source provenance; a second reviewer verifies category coverage and split isolation before model runs. This pilot is a starting qualification set, not a population-wide accuracy claim. Expand it when category denominators are too small or uncertainty prevents a release decision.

## Annotation contract and review

Store versioned JSONL annotations with image/group IDs, source fingerprint, render policy, normalized source-space subject/region rectangles, subject identity, goal, annotator ID, and annotation version. Never use source filenames as identities. Record:

- Visible detail per region: sharp, soft, mixed, or unjudgeable, with a reason and evidence rectangle.
- Eye state where visible: open, closed, obscured, or unjudgeable; mark absent/inapplicable separately.
- Obstructions: category, affected subject/region, and severity (none/minor/material).
- Comparable subject/group membership and goal-specific preferred image, tied set, or abstention, with a short reason.
- Technical and appearance judgments separately, including source limitations and RAW-recovery claims only when tested with an appropriate render.

Two human annotators independently inspect every image and group, blinded to workflow/model outputs. At least one should have photographic editing experience. A third reviewer adjudicates disagreements without deleting the original labels. Report pre-adjudication agreement and disagreement counts; inherently subjective aesthetic preferences may retain a tie or disagreement. Do not force binary labels for insufficient evidence.

## Paired experiment

Run whole-image Qwen, Objects board, and Combined Review on the same frozen model/runtime revisions, eligible sources, criteria, and generation settings. Record actual source and render differences that are intrinsic to a workflow. Freeze the development-derived thresholds before opening held-out results. Keep all failures and degraded outputs in the report; do not select only successful runs. Preserve inputs, evidence references, timings, peak memory, and emitted claims under the chosen retention policy.

Compare Standard and Deep separately. Have annotators rate usefulness of anonymized, randomly ordered reports on a 1–5 scale (1 misleading/unhelpful, 3 partially useful, 5 accurate/actionable), with correctness and omission notes. Record order/randomization seed. If generation is nondeterministic, run each workflow three times and report variation rather than selecting the best answer.

## Metrics and unsupported claims

A substantive claim is a falsifiable statement about a photograph or comparison; separate compound statements into atomic claims. A claim is unsupported when cited evidence is missing, incompatible, insufficiently visible/resolved, or cannot establish the asserted property. Correct-looking guesses still count as unsupported. Examples include an eye-sharpness claim from only a whole-head mask, recoverable RAW highlights inferred from a clipped JPEG, subject A's measurement attributed to B, and a precise winner inferred solely from CLIP similarity. A recommendation framed as a hypothesis is assessed for its stated evidence and rationale; it does not require an untested edit to be presented as fact.

Report unsupported claims / all substantive claims, plus per-report counts. Separately report contradicted claims, invalid evidence IDs, and unsupported-claim annotation agreement. Two reviewers label claims independently and adjudicate disagreements.

Report incorrect sharp/soft claims / judgeable region claims, missed material obstructions / annotated material obstructions, subject-ID errors / subject references, and goal-specific ranking agreement / comparable groups. Count tie/abstention predictions explicitly; report abstention coverage and error rate among non-abstained predictions so silence cannot appear as perfect accuracy. Report unrelated-group forced-ranking frequency, incomplete-run frequency, and usefulness distributions. Publish denominators and uncertainty intervals; comparisons are paired by image/group, with scene-level resampling when estimating intervals.

## Qualification decision

Before held-out evaluation, the evaluation owner and implementation reviewer must record numerical tolerances for error, unsupported claims, ranking agreement, usefulness, latency, and peak memory from development baselines. No numerical release thresholds are asserted before those baselines exist. Require zero invalid evidence references and coordinate/identity contract violations in deterministic tests, plus measured improvement on difficult-detail cases without exceeding the recorded error tolerances. Held-out failures require documented fixes and a new untouched qualification split when tuning would otherwise reuse test labels.


## Input-contract prerequisite

Phase 1's synthetic geometry and runtime probes are recorded separately in
[the input-contract report](combined-review-input-contract.md). Their success
qualifies the recorded model inputs for source/crop implementation; it is not a
photographic quality baseline, annotation result, or release qualification.
Re-run affected probes when assets, dependency revisions, or preprocessing change.
The dataset, independent annotation, development thresholds, and held-out decision
above remain required for phase 7.
