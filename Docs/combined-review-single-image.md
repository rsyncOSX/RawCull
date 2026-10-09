# Single-image Combined Review contract

Implementation date: 9 October 2026. Phase 3 was committed as `ee89f0b`
before phase 4 implementation began.

## Ownership and cancellation

`RawCullIntelligenceRuntime` owns one stable `CombinedReviewFeature`. The fourth
AI Analysis view injects it; switching tools, selection, or display does not
cancel or replace its run. Input files, goal, depth, source preference, optional
normalized user region, model snapshots and retention policy freeze at admission.
Exactly one image is accepted in this phase. Larger selections require phase 5.

A run reserves `CombinedReviewLease` before starting. Existing Qwen, Objects and
Deep Review workers are cancelled and awaited, including handles already cleared
by tool navigation. New sibling analyses and CLIP search/index admission are
blocked while reserved. The existing Qwen generation gate remains in use. Catalog
replacement requests cancellation; retained file grants last until the worker
ends. Managed model replacement/refresh cancels and awaits the combined worker
before replacing resources. The reservation stays held until native work returns;
unfinished output is checked for cancellation and discarded before persistence.
In-flight background CLIP operations retain their provider actor serialization;
this phase does not promise exclusive GPU residency or measured memory peaks.

## Ordered evidence

1. Load the full declared appearance source and verify its persisted identity.
2. Request an independent overview/discovery response, with up to three concrete
   concepts. Malformed responses are failed stages, never findings.
3. Use an uncached SAM instance service, existing mask rejection/deduplication,
   stable subject IDs, and a fourth optional head query. A head candidate must be
   smaller than and contained within exactly one retained subject. This is a
   geometric association, not eye localization. Ambiguous candidates abstain.
4. Persist a deterministic region plan: user region, contained head candidates,
   whole subjects, or an explicit whole-frame fallback. Apply depth crop caps and
   disclose omitted regions. Sources/crops preserve the phase 2 geometry contract.
5. Reuse `SubjectMaskFocusScorer` on the separately decoded technical source only
   when source registration and mask dimensions agree. Scores stay uncalibrated,
   render-dependent detail metrics. No duplicate scoring algorithm is introduced.
6. Run independent unannotated Qwen crop requests. CLIP overview/crop embeddings
   and goal cosine relevance remain separate from quality or probabilities; model
   configuration and actual center-crop retained geometry are recorded.
7. Reconcile terminal measurements and available crop observations with at most
   one bounded Qwen request; synthesize a final report with explicit evidence IDs.
   Reconciliation is the same model, not independent corroboration.

Eye localization and AF registration remain unavailable in this baseline. Head
masks do not establish eyes. Eye/iris detail claims and recovery claims fail closed;
no RAW recovery or evaluated-edit claim is accepted. Suggested edits are explicitly
untested. Missing measurements, missing CLIP, malformed outputs and missed regions
produce partial reports. Unknown IDs, invalid schemas, excessive response fields,
and overview-only detail claims are rejected. These deterministic checks do not
prove that every natural-language claim is photographically correct: phase 7
requires independent photographic evaluation.

## Persistence, context and inspection

Each attempted inference is charged before execution and the running manifest is
saved first. Successful typed artifacts and the completed manifest commit atomically.
Cancellation retains completed evidence and spent attempts. Resume revalidates
files, source render identity, model/runtime snapshots, pipeline/stage versions,
artifacts and dependencies; changed inputs require a rerun. Interrupted attempts
consume another allowance if resumed. Failed stages remain explicitly failed;
resume does not secretly retry them. Dependent outputs are invalidated when a
required artifact disappears. Evicted masks cannot support new measurements.

User-region/depth settings participate in consuming-stage compatibility keys.
The optional `userRegions` field is additive to V1; older V1 manifests decode it
as absent. Future storage versions remain rejected and read-only.

A conservative UTF-8/token bound admits prompts under the verified Qwen context,
reserving image/output/template tokens. Optional evidence is pruned by priority
with a visible limitation. Required schemas and IDs are never truncated. No
unbounded retries, tiles or follow-ups run in this phase.

The view shows frozen image identity, source fidelity, crop locations, available
masks, separate observations/measurements, report evidence IDs, coverage and
limitations. The input inspector displays the exact unannotated overview/crop
under the frozen retention policy. Compact retention, bounded-cache eviction and
explicit cache cleanup make unavailable inputs visible; they never substitute a
new rendering for the missing input. Masks are bounded derived artifacts even in
compact mode. Choosing a region on the retained preview affects only a new rerun.

## Verification and scope

Nine fake-provider integration contracts cover grounded degraded review, SAM and
technical provenance, malformed crop output, unknown report IDs, cancellation
through native work and charged resume, stored-result hydration/file changes,
frozen user regions/compact retention, structured-response abstention and lease
lifetime. A Qwen arbitration regression verifies workers cancelled before the
combined run are still awaited. Tests isolate stores/providers and do not download
models. The smoke inventory contains 288 identifiers after these additions. The final
smoke run passed with one expected opt-in skip; targeted cancellation regressions
also passed. Formatting, whitespace, lint error and import-boundary checks pass.

The opt-in `make combinedreviewtest` probe uses only an already installed verified
Qwen bundle and a supplied image:

```sh
TEST_RUNNER_RAWCULL_COMBINED_REVIEW_RUN=1 \
TEST_RUNNER_RAWCULL_COMBINED_REVIEW_QWEN="$HOME/ModelAssets/Release/Models/Qwen/qwen3_vl_2b" \
TEST_RUNNER_RAWCULL_COMBINED_REVIEW_IMAGE="/absolute/path/to/image.png" \
make combinedreviewtest
```

Its deliberately degraded SAM/CLIP mode exercises admission, actual structured
Qwen requests, budgets and retained inputs. A failed real-model response remains
a failed stage/partial report. It is a workflow probe, not the photographic
quality study or a release qualification. Phase 1 remains the source of real
preprocessing/tensor evidence. Phases 5–7 retain selection comparison, adaptive
coverage/resource measurements, and photographic qualification respectively.

The strengthened installed-Qwen probe passed on the retained landscape geometry
fixture with an accepted crop observation and a nonempty grounded report
(33.958 seconds on this host). The model content fingerprint and preprocessing
were admitted through the phase 1 registry. This result verifies the single-image
workflow, not photographic quality or resource qualification.
