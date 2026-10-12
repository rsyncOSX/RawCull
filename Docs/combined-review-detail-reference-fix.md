# Single-crop detail reference — combined-v14

12 October 2026. Evidence: `/private/tmp/rawcull-six-mxl3q1wv`, pipeline combined-v13, six files from `/Users/thomas/tmp`.

All 115 work items completed: six overviews, 24 segmentation stages, 22 measurements, 16 crop observations, 22 CLIP stages, six identities, six reconciliations, six reports and one comparison. Five reports covered all four criterion types. The only test assertion failure was missing detail in `_DSC6844.ARW`. Its generated detail combined two crop references and described both foals' coats and grass; validation correctly rejected it with `synthesis.targetCropRequired`. Five reports were incomplete. Selection abstained for unrelated scenes. Elapsed test time was 1596 seconds.

Synthesis now supplies a concrete one-element detail evidence array using the first eligible crop in the existing allocation order that actually fits the admitted prompt. This allocates a reference, without asserting photographic importance or upgrading the observation's content. The model must describe only that crop's subject, or omit detail when its observation does not support texture. If no eligible crop is admitted, the prompt explicitly omits detail. Context allocation reserves space for the new directive and existing validation feedback.

Grounding remains unchanged: multi-subject detail, unregistered or unidentified targets, unsupported focus and metric-only prose remain rejected. No response is rewritten by removing evidence or splitting its claim. No additional inference or repair budget is introduced. Pipeline, reconciliation, report and comparison contracts advance to combined-v14; crop observation stays combined-v13 and other contracts retain their versions.

Regression checks inspect the actual synthesis prompt, verify that its nominated reference belongs to an admitted eligible row, and check explicit abstention without qualified crops. A report replay of the two-crop pattern verifies preservation of the scene claim and rejection of detail with a persisted limitation.

The log also contains 96 `MDB_MAP_FULL` warnings. No LMDB implementation or map-size setting was found in RawCull or the searched local model packages. The emitting component and database path are not established by this log. No cache deletion or speculative runtime setting change was applied. All scheduled stages completed despite these warnings; their effect remains unresolved.

A fresh installed-model run is required to assess whether the concrete reference improves generation. Structural tests do not establish photographic accuracy or four-criterion usefulness.

Verification: all 55 focused tests in CombinedReviewFeatureTests, ReviewDiagnosticsTests and ReviewRunContractTests passed after the final changes. `git diff --check` passed. Log: `/private/tmp/rawcull-v14-tests.log`. No installed-model inference was rerun.
