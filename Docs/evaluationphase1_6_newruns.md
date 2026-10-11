# Follow-up investigation: two runs after the first discovery/synthesis patch

Date: 11 October 2026. Evidence: `/private/tmp/rawcull-six-hfyluja1` (Downloads set) and `/private/tmp/rawcull-six-bfenbcao` (tmp set). Both use combined-v8. Input SHA-256 inventories match the corresponding preceding runs `_6nv7yqt` and `2dcc0zim`; the two sets are different photographs.

## Observed outcome

The first patch eliminated copied `flower` context and measurement-only synthesis failures in these runs. Partial claim preservation works: every image retains accepted claims. However, discovery still succeeds only for the rabbit. Three reports contain all four criterion type names, but that is not proof of correct photographic coverage: some accepted detail claims cite an unregistered whole-frame fallback. All reports remain incomplete.

| Outcome | Downloads: hfyluja1 | tmp: bfenbcao |
| --- | ---: | ---: |
| Completed work items | 54 | 37 |
| Failed work items | 6 | 6 |
| Accepted overviews | 1/6 | 0/6 |
| Reports with some accepted claims | 6/6 | 6/6 |
| Reports with all four criterion type names | 2/6 | 1/6 |
| Overview uncertainty length failures | 3 | 4 |
| Overview primary concept mismatch | 1 | 0 |
| Overview optional priority count failure | 1 | 0 |
| Overview invalid point failure | 0 | 2 |
| Reconciliation contradiction-subject failure | 1 | 0 |

The two Downloads reports with all type names are DSC00639 and DSC02022; the tmp report is _DSC4764. These use fallback observations after failed discovery and therefore cannot qualify registered subject detail. In comparison with their preceding runs, accepted reports increase from 3 to 6 and from 4 to 6 respectively, while overview counts remain 1 and 0.

## Causes confirmed in retained responses

1. **Text constraints suppress otherwise usable discovery.** Seven overview uncertainty strings exceed 200 characters; the observed range for these is 201–320. Two concept reasons are 172–173 characters and also exceed the shared discovery decoder's 160-character bound, hidden behind earlier failures. Core observations remain within 500 characters.
2. **Optional metadata takes down the complete overview.** The model uses discovered display names in primary nominations, gives pixel-like points such as (100, 400) or (500, 400), and lists undiscovered context. These are unusable priority hints, not evidence that all visible object discovery must be discarded. Swans has three distinct queries sharing the same display name, so alias resolution must abstain when ambiguous.
3. **Queries are still verbose or abstract.** Some queries describe scenes or actions instead of objects. `flight` and `motion` appear alongside real object concepts. Segmentation must not receive these action labels as object queries.
4. **Generated criterion spelling differs from the contract.** Four partial-rejection limitations across the new reports cite `synthesis.claimType`: two `lighting`, one `subject visibility` and one `behavior`. These spellings recur despite the prompt's requested criterion names. Lighting is the documented exposure criterion; subject visibility and behavior use visibility. These exact aliases can be canonicalized without inventing a new claim.
5. **Focus rejection remains appropriate for subject claims.** Whole-frame observations still induce blur/focus prose without registered subject crops. These are retained as partial rejection limitations. This patch does not infer subject sharpness from whole-frame descriptions.
6. **Rabbit reconciliation incorrectly treats different subjects as contradictions.** All four generated claims cite the rabbit crop and mark a flower crop as a contradiction. Subject-detail contradictions must stay subject-local. Scene composition and visibility may reference a disagreement spanning registered subjects in the same image, with no inferred single-subject scope; merely different textures are not a contradiction.
7. **Fallback detail has a validation hole.** The previous detail guard accepts zero registered subjects if `targetIdentified` is true. Several full-type reports therefore pass type coverage without subject registration. Close this hole rather than counting these reports as successful subject review.

## Code update: combined-v9

- Keep overview uncertainty and concept reasons intact up to 500 characters; retain nonempty checks and hard bounds. Crop/report uncertainty limits stay unchanged. No text is silently truncated.
- Independently process optional priority hints. Resolve only exact normalized queries or a unique display-name alias. Drop undiscovered/ambiguous hints with explicit persisted validation notes. Discard invalid locations rather than converting arbitrary pixel coordinates or clamping them. Retain concept-level nominations with location unverified.
- Request short singular object queries and no generated location in the overview prompt. Drop exact abstract `motion`, `flight`, and `lighting` queries with a diagnostic; do not invent replacement objects.
- Preserve validation notes in overview artifacts and surface them as result/report limitations.
- Canonicalize `lighting` to `exposure`, and `subject visibility`/`behavior` to `visibility`, then run the same evidence/domain/ownership validation. Other unknown types remain rejected.
- Require exactly one registered subject for generated detail; the fallback target flag alone does not qualify.
- Allow scene-level cross-subject contradictions only through already validated evidence in the same image. Explicit subject claims and detail retain subject-local checks. Infer subject/region scope from both support and contradictions, avoiding false single-subject attribution.
- Clarify contradiction use and per-row subject-detail support in synthesis. Preserve the observation-first allocation and partial-result behavior from combined-v8.
- Advance overview/reconciliation/report and pipeline versions to combined-v9 to invalidate stale artifacts. No additional inference attempts or budget changes.

## Verification boundary

Replay the 11 retained rejected overview responses as deterministic fixtures, asserting unchanged core text, discovered-concept membership and no fabricated locations. Test ambiguous aliases, invalid points, hard bounds, persisted notes, scene versus subject contradiction scopes, lighting canonicalization and fallback detail rejection. Run the four affected unit/integration suites and verify smoke enumeration.

These checks establish parser and grounding behavior, not photographic truth or installed-model qualification. No new six-ARW model inference is implied by replaying saved JSON. A fresh run must inspect segmentation registration, criterion meaning, observed behavior and actual focus detail; successful type-name coverage alone is insufficient. Original phase 6 resource qualification remains separate.

## Verification result

Final focused Xcode run: all 54 reported cases passed in ReviewDiagnosticsTests, CombinedReviewFeatureTests, ReviewRunContractTests and ReviewSubjectPriorityTests. This includes replay of all 11 saved overview failures and an assertion on the actual synthesis evidence rows. Log: `/private/tmp/rawcull-v9-validation.log`. `git diff --check` passed. Installed-model six-ARW inference was not repeated during this update.

Smoke manifest enumeration verified: 332 unique test identifiers.
