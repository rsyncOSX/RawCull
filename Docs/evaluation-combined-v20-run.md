# Installed-model combined-v20 run investigation

13 October 2026. Evidence: `/private/tmp/rawcull-six-rj7ryy6o/evidence`. The run was described as v19, but the retained manifest and stage compatibility identify `combined-v20`. No production changes or new inference were performed during this investigation.

Xcode reports TEST SUCCEEDED. The six-file inference test passed after 1411.840 seconds (about 23 minutes 32 seconds); the other two opt-in tests were skipped. All 115 scheduled work items completed: six each of source, overview, identity, reconciliation and report; 24 segmentation, 22 measurement, 22 CLIP, 16 crop observations and one comparison. One repair attempt is recorded. The retained rejected report response selects comma-separated rows for the horse rather than a single row per criterion.

All six reports remain incomplete. There are 13 accepted claims, equal to the preceding v19 investigation, but distributed differently:

| Image | Claims | Retained categories |
| --- | ---: | --- |
| _DSC0563.ARW | 3 | composition, exposure, visibility |
| _DSC4595.ARW | 2 | composition, detail |
| _DSC4764.ARW | 1 | exposure |
| _DSC6640.ARW | 3 | composition, exposure, visibility |
| _DSC6844.ARW | 3 | composition, exposure, visibility |
| _DSC8590.ARW | 1 | detail |

No report has all four categories. Eleven selected categories are rejected with `selection.eligibleCriterionRow` limitations. The row-selection contract therefore still loses coverage. The horse now has one exposure claim instead of the duplicate exposure claims observed in the preceding v19 run. Selection comparison retains six cells and abstains because the scenes are unrelated.

Fourteen of sixteen crop observations still report `targetIdentified=false`. Retained validation notes reject 14 detail criteria (12 target-consistency and two domain failures) and one exposure criterion. Partial crop preservation continues to allow stage completion; it does not establish target understanding or photographic correctness.

The runtime log contains 96 `MDB_MAP_FULL` commit errors. The evidence manifest and all 115 stage artifacts are present, but the successful test alone does not establish that every affected storage operation succeeded. Investigate the storage errors separately from model and row-selection compliance.

The next model-contract investigation should compare selected rows with the eligible rows provided in each report request. Photographic acceptance still requires inspection of retained source and crop images; this document records contract and coverage evidence only.
