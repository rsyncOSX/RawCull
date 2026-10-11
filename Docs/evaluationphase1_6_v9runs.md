# combined-v9 six-ARW runs: report and recommended next work

Date: 11 October 2026. Runs: `/private/tmp/rawcull-six-l1h_xfl_` (Downloads set) and `/private/tmp/rawcull-six-tu78lzyo` (tmp set). Both manifests identify combined-v9. Comparison is against the recorded findings in `evaluationphase1_6_newruns.md`; the earlier temporary run directories are no longer available for fresh inspection. The current filename/hash inventories match the inventories recorded earlier in this conversation.

## Assessment

Discovery regresses from one accepted overview across the previous pair to zero across this pair. The rabbit loses the only remaining segmentation and measurement path. These runs do not demonstrate useful subject review: every image takes the whole-frame fallback, no segmentation or measurement work occurs, and no report covers all four criterion types.

The primary blocker is now structural decoding of optional metadata, before the new recovery logic runs. The previous fix recovered invalid values after typed decoding, but did not isolate optional fields whose JSON types differ from the requested schema. The saved-response regression fixtures covered the earlier shapes and therefore did not predict this new failure.

| Outcome | l1h_xfl_ — Downloads | tu78lzyo — tmp |
| --- | ---: | ---: |
| Completed / failed work items | 37 / 6 | 36 / 7 |
| Accepted overviews | 0/6 | 0/6 |
| Segmentation / measurement work | 0 / 0 | 0 / 0 |
| Reports with accepted claims | 6/6 | 5/6 |
| Reports with four criterion types | 0/6 | 0/6 |
| Reports marked incomplete | 6/6 | 6/6 |
| Selection result | unrelated / abstain | unrelated / abstain |

## Confirmed failures

### Optional discovery fields still invalidate core discovery

Eleven overviews return `primarySubjects` as strings, for example `["rabbit", "flower", "rock"]`, while the decoder requires objects with `concept` and `reason`. One overview returns primary objects correctly but returns `contextualConcepts` as objects, while the decoder requires strings. Ten of the twelve responses also have contextual objects, so correcting only primary decoding would leave another failure immediately behind it.

The failure is at `CombinedReviewResponse.overview`: its initial `Payload` decoding includes both optional typed arrays. It fails before validation notes, query aliases or invalid-point recovery can execute. Calling a property optional only permits absence or null; it does not permit a different JSON type.

Core observations are concise (65–137 characters), uncertainties are 98–178 characters, and queries are generally much shorter than in the previous pair. This is evidence of improved generated brevity and query shape, but those improvements never reach accepted discovery. There are no recorded length or geometry failures; however, the optional-field schema failure precedes core validation, so absence of those errors alone is not proof that all downstream validation passes.

### One report fails before partial-claim validation

The fox `_DSC6640.ARW` response omits `contradictions` from every claim. The `ReviewClaim` decoder requires that field, so the complete response fails at `claims.contradictions`. A potentially usable lighting claim never reaches canonicalization or individual validation. The fenced JSON envelope is retained; the diagnostic identifies the missing field rather than the fence as the failure.

### Remaining report rejections

Across the accepted partial reports, 11 claims fail the registered-subject focus guard, six fail the subject-detail crop requirement, and three fail claim-type validation (`texture`). These are individual rejection limitations, not additional failed work items.

The detail refusals are expected: there are no registered subjects. The prior pair's three reports containing all criterion type names included fallback detail; those were not qualified subject-detail coverage. The stricter guard removes that apparent success. Mapping `texture` blindly to `detail` would not create the missing registered subject support.

Both selections conservatively abstain for unrelated scenes. This does not test ranking usefulness. Less downstream work cannot establish a speed or resource-control improvement.

## Per-image accepted criterion types

| File | Types |
| --- | --- |
| DSC00113 | exposure |
| DSC00639 | composition, exposure, visibility |
| DSC02022 | composition, exposure, visibility |
| DSC05921 | composition, exposure |
| DSC09214 | composition, exposure |
| _DSC6564 | exposure |
| _DSC0563 | composition, exposure |
| _DSC4595 | exposure, visibility |
| _DSC4764 | composition, exposure |
| _DSC6640 | none; schema failure and evidence-only fallback |
| _DSC6844 | composition, exposure, visibility |
| _DSC8590 | composition, exposure, visibility |

These are structural acceptance results, not independently verified photographic accuracy. Generated daylight/time-of-day interpretations and statements such as “no signs of artificiality” should be assessed separately from schema success.

## Advice, in priority order

1. **Decode core discovery independently of optional priority metadata.** Strictly decode observations, uncertainty and concepts first. Decode each optional section separately; malformed or ambiguous sections must abstain with persisted notes without suppressing valid discovery. Never infer instance locations or photographic importance merely from the order of a string list. For an initial robust implementation, discard unsupported optional shapes rather than inventing reasons or priorities.
2. **Simplify the generated discovery contract.** Request only core discovery until optional priority metadata has an independently tested path. If the installed runtime supports constrained JSON schemas, use them to enforce the actual field types; more prose instructions alone have not provided a reliable contract. Preserve the existing one-attempt budget until there is a deliberate corrective-inference design.
3. **Allow omitted contradictions to mean an empty array.** This is a safe absence default, not an invented observation. A present malformed contradictions value, unknown evidence IDs and unsupported claim domains must still fail. Keep supported claims available when a sibling fails. Verify the exact fox response as a regression.
4. **Replay the current twelve overview responses plus the fox report.** Add shape variations: omitted/null optional sections, string/object/mixed arrays, malformed entries, unknown queries and ambiguous aliases. Assert that valid core discovery survives, notes persist, no unsupported priority or geometry is created, and invalid core evidence still fails. Keep the prompt-context integration check.
5. **Rerun only after this structural fix passes.** First run the Downloads set to verify that discovery and the rabbit path return; then the tmp set. Inspect actual masks, registered subject crops, foreground/rear-subject differentiation and photographic criterion meaning. Treat explicit abstention as honest but not as successful full coverage. Do not loosen focus/detail validation or manufacture four criterion labels to satisfy the test.

Disposition: retain the stricter detail guard, alias canonicalization and partial-report preservation. Make independent decoding of optional fields the next implementation priority. No code changes, test executions or new model inference were performed for this reporting request.

Subsequent implementation: [independent discovery decoding fixes](combined-review-schema-fixes.md) records the combined-v10 changes and passing regression checks. The findings above describe the supplied combined-v9 runs.
