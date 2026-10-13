# Combined-v21 next-run plan

The 13 October combined-v20 run completed every work item, but lost report coverage through eleven ineligible category selections. Fourteen crop observations reported absent target support. The next run tests two changes without increasing inference caps or weakening criterion grounding.

1. Supply the registered subject's generic concept explicitly in the crop request. Unspecified targets still abstain, and target presence must still come from the image. No parser code upgrades false target flags.
2. Recover an invalid non-null report selection using the first eligible criterion in the existing stable evidence priority order. Candidate rows have already passed domain, ownership, category and focus validation. Preserve original text and stored evidence IDs. Record both rejection and substitution as limitations; the report remains incomplete. Valid model selections remain selected and explicit nulls remain abstentions. A response with no valid model selections still fails and uses the existing bounded repair path.
3. Advance pipeline, crop, reconciliation, report and comparison contracts to combined-v21 so restored older runs cannot resume under changed semantics.

Regression checks cover invalid comma-separated selections, category isolation, unavailable fallback IDs, null abstention, wholly invalid responses, exact evidence preservation and feature-level substitution persistence across restore.

Validation: all 68 focused cases pass in ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests. All six runner checks pass. `git diff --check` passes. Focused Xcode log: `/private/tmp/rawcull-v21-focused.log`. MDB_MAP_FULL also recurs in this fake-backend suite, so its occurrence is not specific to live model inference.

For the next installed-model run, use the same six sources:

```sh
python3 Scripts/RunCombinedReviewSix.py --directory /Users/thomas/tmp
```

Compare input hashes and retained pipeline identity before comparing outcomes. Inspect accepted claims by category, substitution limitations, null abstentions, target flags, repair attempts and rejected crop criteria. Review retained images for photographic correctness; higher claim coverage alone is insufficient. Preserve the engineering checks and budgets.

The prior log's 96 MDB_MAP_FULL errors remain unresolved. No LMDB implementation or map-size configuration was found in app Swift source or the checked-out Swift packages. The next log should be checked for recurrence; do not infer storage correctness from TEST SUCCEEDED alone.

No new installed-model inference was performed as part of this change.
