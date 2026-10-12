# Installed-model combined-v19 run investigation

12 October 2026. Evidence: `/private/tmp/rawcull-six-ah6ciowr`. Snapshot confirms combined-v19. The six input hashes match the preceding combined-v18 run exactly. Investigation only; no production changes or new inference.

## Result

Xcode reports TEST SUCCEEDED. All 121 scheduled work items complete: six sources, overviews, identities, reconciliations and reports; 24 segmentation, 22 measurement, 22 CLIP, 16 crop observations and one comparison. No repair calls are recorded. Previous run: ten terminal crop failures and 14 repair calls.

This establishes that partial crop preservation works in live inference. It does not establish complete photographic review. Fourteen crops retain valid siblings while rejecting criteria; only two crops have no rejection notes. There are 14 target/detail rejections (11 target-consistency, three domain) and one exposure rejection. Detail survives only in the main squirrel crop and one hawk wing crop. All six reports remain incomplete.

The current integration test accepts missing categories when the report is incomplete and contains the corresponding explicit coverage limitation. Its pass therefore establishes completion and explicit abstention, not four accepted categories per image. This distinction matters when reading the older runner documentation.

| Image | Accepted report claims | Categories retained |
| --- | ---: | --- |
| _DSC0563.ARW | 2 | composition, visibility |
| _DSC4595.ARW | 4 | composition, exposure, visibility, detail |
| _DSC4764.ARW | 1 | exposure |
| _DSC6640.ARW | 1 | composition |
| _DSC6844.ARW | 3 | composition, exposure twice |
| _DSC8590.ARW | 2 | composition, visibility |

Accepted claim count drops from 20 to 13. Only squirrel retains all four categories, compared with four reports previously. Selection remains unrelated-scene abstention.

## Confirmed remaining problems

1. Target presence is still false in 14 crops. The new parser correctly keeps scene criteria and rejects target-specific detail rather than upgrading the flag. This avoids terminal crop failure but does not solve model understanding of target presence.
2. Report synthesis fails to copy the matching row and criterion reliably. Puffin and fox reports reject request-local references; other reports reject criterion text copied from a different row or unsupported overview exposure. Valid exposure/visibility criteria are retained in crop artifacts but often lost in final synthesis.
3. The horse report accepts two exposure claims, despite the prompt requesting one per type. Its visibility text comes from one crop but references the other and is correctly rejected. Category uniqueness is a prompt instruction not presently enforced by the validator.
4. The hawk wing detail is available in retained evidence, but the generated detail claim fails exact criterion support. Thus rejected detail in other crops is not the sole cause of missing report detail.
5. Photographic quality remains uncertain: a horse exposure statement infers sunset; hawk visibility describes motion as occlusion. Text validation and registration cannot establish these statements' visual truth.

## Recommended next work

Use deterministic assembly for already validated criterion strings and evidence IDs, or explicitly constrain synthesis to choosing criterion/row pairs rather than rewriting text and generating references. Preserve the separation between scene criteria and target-specific detail, enforce one claim per category, and retain explicit abstentions. This addresses evidence that is already available but lost in synthesis without increasing inference caps or promoting false target flags. Target-presence compliance and visual qualification remain separate problems.
