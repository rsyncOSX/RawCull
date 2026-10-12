# Investigation of the combined-v17 six-ARW run

12 October 2026. Evidence: `/private/tmp/rawcull-six-hnakk1mh/evidence`. Run ID: `7C7A2E46-62E0-4C64-8C52-CBBABCB302F6`. Input inventory exactly matches the preceding v16 run `/private/tmp/rawcull-six-0xl4guf6`. Investigation only; no production changes or new inference.

## Outcome

The installed-model integration test failed its all-work-completed assertion after 1539.866 seconds (about 25 minutes 40 seconds). There are 102 completed work items and 11 failed items, all crop observations. This is a substantial schema-compliance improvement over v16: crop observations improve from 0/16 to 5/16, reports from 0/6 to 6/6, and accepted claims from zero to 19. All six overviews, 24 segmentation stages, 22 measurements, 22 CLIP stages and the selection comparison complete. Four reconciliation stages complete. Six repair calls were used, compared with 22 in v16.

All reports remain marked incomplete. Three have all four criterion categories, but incomplete crop coverage remains. Selection retains six cells and abstains with no preferred image because the scenes are unrelated; all 15 pair comparisons are omitted.

| File | Accepted crops / scheduled | Accepted claims | Missing categories |
| --- | ---: | ---: | --- |
| _DSC0563.ARW | 2/3 | 4 | none |
| _DSC4595.ARW | 1/3 | 3 | visibility |
| _DSC4764.ARW | 0/2 | 2 | exposure, detail |
| _DSC6640.ARW | 1/3 | 4 | none |
| _DSC6844.ARW | 0/2 | 2 | exposure, detail |
| _DSC8590.ARW | 1/3 | 4 | none |

## Confirmed causes

1. Seven terminal crop failures are `crop.criterionTargetConsistency`. Each supplies a non-null detail string while setting targetIdentified=false. Several uncertainty strings explicitly confuse species/individual identification with visible generic-target presence, despite the prompt distinguishing them. Two detail strings describe no resolved target texture, but use a string rather than the required null abstention. This is model contract noncompliance; false must not be silently promoted to true.
2. Two failures are `crop.criterionLength`: squirrel visibility is 123 characters and puffin composition is 128, exceeding the 120-character bound. The puffin response remains too long after repair. These are localized text violations, not malformed JSON. Current repair eligibility in CombinedReviewExecution accepts json/schema/unknownID or crop.supportedDomain; length and target-consistency failures do not generally qualify for a corrective attempt themselves. An attempts=2 terminal failure may have started with a different eligible issue.
3. Two failures are `crop.supportedDomain`: squirrel visibility contains “in focus”; horse detail contains “sharply resolved”. Both have two attempts. The horse response also has the target/detail inconsistency hidden behind the earlier domain check.
4. The squirrel report loses visibility through `synthesis.focusNeedsRegisteredSubjectCrop`. The claim exactly matches the accepted crop criterion: “squirrel fully visible, no occlusion, clear outline against blurred background”. Its evidence is a registered subject crop and subject scope is correctly inferred from the support row. However, validateFocusScope checks isExcerpt against the concatenated observation text. The four criteria are joined with spaces without sentence delimiters, so the exact visibility criterion is not a whole sentence under that legacy check. The broad blur trigger therefore rejects this crop-supported background description even after the criterion-specific exact-match check passes. Using the validated criterion text in focus grounding and defining treatment of contextual blur deserve a retained-response regression; weakening all focus checks is not justified.
5. Puffin and horses retain only overview composition/visibility. Their exposure/detail claims are rejected by synthesis.criterionRequired, correctly preserving the absence of accepted crop evidence. Nullable crop schema and full report-reference examples now work in real inference: this run has no terminal report schema failures.

## Photographic limitations

Visual inspection of the retained selection sheet confirms six different wildlife scenes. It also reveals factual issues that accepted category coverage cannot establish: the puffin overview describes orange-tipped wings although the visible orange features are its feet; the fox composition says “no obstructions” while its visibility text says partially obscured by grass; the fox exposure infers midday sun without establishing the time of day. Accepted detail still mentions ear shape, posture, wings and head pattern despite the prompt excluding anatomical detail. Current domain validation does not enforce every prose instruction.

These observations are a visual spot check, not full source-space mask/crop or fine-detail qualification. Every report has ambiguous/unassigned main-subject priority and anatomy-unverified limitations. Producer bounds discrepancies are recorded and crops recomputed from foreground masks; their correctness still needs separate visual validation. The selection sheet supports unrelated-scene abstention.

## Next implementation priorities

- Add deterministic fixtures for the seven target/detail inconsistencies, the two length failures and the registered squirrel visibility claim. Keep original invalid responses rejected.
- Make generic-target presence and null detail abstention easier for the model to express, without fabricating identification or increasing inference caps implicitly.
- Preserve valid sibling criteria when a single criterion is rejected, with explicit persisted diagnostics and abstention for invalid detail; evaluate the schema/grounding consequences before implementation.
- Make focus validation respect validated criterion boundaries and explicitly distinguish scene/background blur from unsupported subject-focus claims.
- Resolve prompt/validator mismatch for anatomical language and unsupported factual inference; do not count type coverage as photographic acceptance.

No test rerun is needed for this read-only investigation. The existing integration failure is retained as evidence. Production source and acceptance checks were not modified.
