# Combined-v20 report selection and deterministic assembly

12 October 2026. Based on `/private/tmp/rawcull-six-ah6ciowr` (combined-v19).

## Plan and change

1. Replace generated report prose and evidence arrays with four required nullable selections: composition, exposure, visibility and detail. Each non-null value selects a request-local observation row ID from the admitted eligible list for that category.
2. Build selectable criterion/row pairs from admitted observations. Use current ownership, target, detail and focus grounding, plus report text length and prohibited-domain checks, before offering a pair. Legacy whole-frame observations remain composition/visibility only. Metrics and reconciliation prose remain excluded from independent evidence.
3. Assemble each chosen claim in code from the exact validated criterion text, persisted observation ID and inferred subject/region scope. The response cannot rewrite prose, swap criterion text, generate contradictions or produce two claims for one category. Null remains explicit abstention; code does not fill a category the model declined.
4. Reject invalid selections independently with persisted report limitations. Preserve valid sibling selections. All-invalid responses fail and remain eligible for the existing charged repair path; missing keys, wrong types and legacy generated-claim responses remain invalid. Missing categories retain the existing explicit coverage limitations and incomplete report state.
5. Advance pipeline, reconciliation, report and comparison to combined-v20. Crop observation remains combined-v19; unchanged stages keep their versions. Inference attempts, caps and selection-comparison behavior are unchanged.

## Verification

All 68 focused cases pass in ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests. Tests check exact copied text and stored IDs, one claim per category, wrong-category/unknown row rejection, null abstention, required fields, actual eligible prompt rows, unidentified-crop detail exclusion, bounded repairs and persisted export/restore diagnostics. Three retained v19 report responses are replayed to confirm that legacy prose/reference payloads cannot silently enter the new selector boundary.

Smoke enumeration confirms 351 unique enabled test identifiers. `git diff --check` passes. Logs: `/private/tmp/rawcull-v20-validation.log` and `/private/tmp/rawcull-v20-enumeration.log`.

No installed-model inference was performed. The model must still follow the row-selection contract, and its selected evidence still needs photographic review. This change cannot establish visual truth, correct false target-presence judgments or remove unsupported factual inference already present in an accepted observation. Generated cross-row contradictions are no longer requested in per-image synthesis; code emits the selected observation as supported prose with existing limitations.

Run the same six-image set again:

```sh
python3 Scripts/RunCombinedReviewSix.py --directory /Users/thomas/tmp
```

The saved snapshot should record combined-v20. Engineering acceptance permits explicit criterion abstention; a pass does not establish complete photographic coverage.
