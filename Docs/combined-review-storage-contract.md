# Combined Review V1 storage and run contract

Date: 9 October 2026. Engineering review: Codex, implementation/source reviewer.

Decision: approve the V1 envelope and stage compatibility contract for implementation.
The evaluation specification in `deepaireview-evaluation.md` has been reviewed: its
consented dataset, independent annotators, held-out split and development-derived
thresholds remain phase 7 prerequisites. This review approves the engineering schema,
not photographic accuracy or a release decision.

V1 freezes accepted file snapshots, criteria, depth, source/render settings, model and
runtime identities, stage versions, generation settings and budgets. IDs distinguish
images, subjects, regions, observations, measurements, limitations, reports and work.
Evidence contains provenance and explicit available/unknown/unavailable outcomes.

Artifacts and manifests use integer schemaVersion 1, kind, producer pipeline version
and structured compatibility keys. Compatibility is stage-specific: source/render
changes invalidate downstream work; goals invalidate goal-dependent stages; model,
preprocessing and prompt/schema changes invalidate their consuming stages and descendants.
Future envelopes are unavailable/read-only and cannot be overwritten. No migration is
invented before V2 exists. Preserve old artifacts; future migrations must write new copies
and must not manufacture evidence or compatible status.

Completed artifacts are written atomically before the manifest. A missing/incompatible
artifact never counts as completed after restore; interrupted work becomes pending and
invalidations propagate. Cancellation discards unfinished output, keeps completed evidence
and does not reset spent attempt allowances. Failed attempts consume budget. Retry requires
remaining category and image allowance or a separately recorded budget change/new run.

Reserve overview, reconciliation and per-image synthesis categories independently of
optional crops/follow-ups. Maintain per-image caps so one image cannot consume another's
mandatory allowance. SAM calls and CLIP inputs have separate counters. Deterministic crop
rounds prioritize first coverage for every accepted image. Selections above eight require
an explicit expanded plan. Comparison work remains reserved until phase 5 delivery.

The store owns a bounded content-addressed exact-input cache. Compact evidence survives
cache eviction; an evicted exact input is explicitly unavailable. Cache files and evidence
use opaque IDs, not source names. Catalog grants are retained by the run owner, not encoded
into storage. Resume rechecks access and source/model compatibility before starting work.

## Phase 3 verification

The eight `ReviewRunContractTests` contracts pass: mandatory coverage and attempt caps,
recorded amendments/fair crop rounds, stage-specific compatibility, independent evidence
survival on cancellation, invalidation propagation, complete accepted-image coverage and
cycle rejection, atomic partial-result restore/future-schema preservation/cancelled writes,
bounded input eviction/path rejection, and evidence-reference validation.

`make test-smoke` passes with 278 enumerated identifiers, zero failures and the expected
single opt-in model skip. Final targeted checks after attempt-category enforcement and
retention snapshot changes also pass. No model downloads are required. This approves
phase 4 implementation against V1; phase 7 external evaluation remains outstanding.
