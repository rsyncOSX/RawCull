# Combined Review small-selection contract

Date: 10 October 2026

## Scope

Combined Review accepts one image or a selection of 2–8 images. Larger selections
are refused with an explanation that an explicit expanded coverage plan is required;
they must currently be split into smaller runs. Existing burst workflows are unchanged.
A manually chosen region is admitted only for a single-image run, so a region cannot
silently transfer from one photograph to another.

The run freezes all file identities, criteria, source policy, models, depth, and
retention settings. Sources are decoded sequentially; selection synthesis retains
only bounded overviews. Every image receives a report or an explicit terminal failure
before selection synthesis. A failed image cannot stop the other admitted images.

Crop allowances use deterministic round-robin allocation in stable image-ID order,
with worst-case candidate counts. This reserves coverage for later images and can
leave unused optional crop capacity when an image has fewer candidates. Per-image
report and selection-comparison attempts have separate reserved budgets.

## Evidence and comparison

The appearance board is 2048 × 2048, with two columns for 2–4 images and four for
5–8, enough rows for all images, and a 48-pixel image-ID header in each cell. Full
orientation-normalized frames are aspect-fit onto neutral padding. Persisted cell
rectangles describe the board transform in top-left coordinates. Labels are prompt
annotations; the board does not establish fine detail or individual subject identity.

Every image contributes a bounded independent observation before optional crop and
measurement evidence is admitted. Excerpts and omitted optional evidence are disclosed.
An unavailable overview may be replaced by a validated independent crop observation;
this does not remove the missing-stage limitation or authorize a winner.

Responses record comparability (`comparable`, `unrelated`, `insufficient`) separately
from decision (`preferred`, `tie`, `abstain`). Unrelated groups cannot receive a winner.
Missing per-image reports or incomplete technical evidence prevent a preference or tie
recommendation. Unresolved cited contradictions prevent a preference. A recommendation
must reference its preferred images in supported claims.

Each claim names image IDs and must cite evidence belonging to every named image.
Only references actually supplied in the request are accepted. Technical detail needs
independent crop observations, compatible source fidelity, policy, dimensions and crop
scale; eye detail, RAW recovery and asserted cross-image individual identity are rejected.
CLIP relevance remains separate from photographic quality. Composition and appearance
tradeoffs remain separate from technical detail; no combined quality score is created.

Deep/Exhaustive may inspect up to 2/4 deterministic near-tie pairs; Standard uses zero.
Pair admission requires exactly one candidate subject per image, matching concepts,
compatible appearance crops and encoder scale within 10%. A matching concept is a
candidate, not proof that the photographs show the same individual. Ambiguous multi-subject
matching abstains. Pair boards, evidence, limits and omitted pairs remain inspectable.
Pair suggestions cannot silently override a selection-wide tie.

## Persistence and compatibility

The V1 storage envelope remains unchanged. The pipeline contract is `combined-v2`;
older pipeline runs require a fresh run. Comparison compatibility includes the complete
selection's stable image IDs and fingerprints. Resuming validates every saved file,
model and artifact, preserves spent attempts and restores completed comparisons without
new inference. Changing a selected file refuses resume. Cancellation retains completed
independent artifacts and discards unfinished outputs.

## Qualification boundary

The opt-in local probe is reproducible with `make combinedselectiontest`, using
`RELEASE_CATALOG` (six ARWs, default `~/Downloads`) and `RELEASE_QWEN` (an installed
Qwen bundle). It runs without SAM/CLIP and must abstain from a winner. It records
source admission, actual eligible RAW decodes, RAW crop/technical alignment, individual
reports and raw model responses as an xcresult JSON attachment.

Engineering validation and the six-file ARW probe are recorded with the phase 5 milestone
in `deepaireview.md`. The ARWs remain outside the repository; no photographic binary is
added to Git. A small local source probe cannot establish photographic accuracy, camera
coverage, RAW recovery, or memory behavior with all resident models. Phase 7 still requires
the consented dataset and independent human annotations in `deepaireview-evaluation.md`.
