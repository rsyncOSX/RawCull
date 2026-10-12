# Follow-up installed-model investigation

12 October 2026. New evidence: `/private/tmp/rawcull-six-5c9y1lwy`. The user called this v19; the persisted snapshot records combined-v18, matching current source. The input inventory matches `/private/tmp/rawcull-six-hnakk1mh` exactly. This is an investigation, without production edits or another inference run.

## Outcome

The test fails the all-work-completed assertion after 1559.341 seconds. There are 103 completed items and 10 failed items, all crop observations. All six overviews and reports complete, as do 24 segmentation, 22 measurement, 22 CLIP, four reconciliation and one comparison stage. Crop acceptance is 6/16, compared with 5/16 previously. Repair calls rise from six to 14. Every terminal failed crop has two attempts, so the added repair eligibility is exercised but usually does not correct compliance.

Reports contain 20 accepted claims versus 19 previously. Four reports cover all four categories versus three previously. Every report remains incomplete. Selection retains unrelated-scene abstention. Report completion and category coverage do not establish full subject review or photographic truth.

| Image | Accepted / scheduled crops | Claims | Missing categories |
| --- | ---: | ---: | --- |
| _DSC0563.ARW | 2/2 | 4 | none |
| _DSC4595.ARW | 2/3 | 4 | none |
| _DSC4764.ARW | 1/3 | 4 | none |
| _DSC6640.ARW | 0/3 | 2 | exposure, detail |
| _DSC6844.ARW | 0/2 | 2 | exposure, detail |
| _DSC8590.ARW | 1/3 | 4 | none |

## Remaining failures and gaps

- Five terminal target/detail inconsistencies remain. Model responses still set targetIdentified=false while supplying non-null detail, including explicit unresolved texture or texture of background grass. The repair instructions do not reliably change this behavior.
- Three terminal length failures remain: puffin, squirrel and horse. All are after repair. Some also contain target inconsistency or forbidden sharpness wording hidden behind the first validation failure. More repair attempts or relaxing length alone would not resolve them.
- Two terminal domain failures contain “sharply resolved”, also paired with false target flags and non-null detail.
- An accepted squirrel context crop says “faint fur texture on the squirrel's back and tail, but not resolved”. The current validator treats any permitted non-null detail string as supported when targetIdentified=true. The prompt's null-abstention instruction is not enforced semantically. This crop is accepted evidence, though its detail is not selected by the final report.
- An accepted branch/foliage crop mixes background texture and bird feather pattern in its detail criterion. Target ownership of prose is not established merely by registered region ownership. This detail is also not the final selected detail claim.
- Puffin and hawk full-category reports now cite wing-concept regions while whole-target observations fail. Registration establishes geometry and IDs, not verified anatomy. These reports should not be read as complete review of the main animal.
- Squirrel visibility is now retained, but its current text contains no blur wording. The deterministic regression establishes the criterion-boundary fix; this run does not directly replay the original blurred-background claim.

## Recommended next change

The main problem is the crop response contract and criterion-level acceptance, rather than report JSON. Preserve valid composition/exposure/visibility independently when detail is invalid, with explicit persisted rejection notes and unsupported detail. Do not upgrade false target flags or substitute background texture. Enforce explicit unresolved-detail abstention and separate target presence from texture support in a representation the model can reliably produce. Retain hard bounds and inference caps. Test original failures and accepted negative-detail/background-detail responses; then repeat installed-model inference. Avoid broad keyword rules that would turn absence of one word into proof of photographic support.
