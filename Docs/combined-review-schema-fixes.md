# Plan and implementation: independent discovery decoding

11 October 2026. Follow-up to `evaluationphase1_6_v9runs.md`, using the retained responses from `rawcull-six-l1h_xfl_` and `rawcull-six-tu78lzyo`.

## Plan

1. Separate strict core discovery decoding from optional priority metadata. Keep invalid core fields fatal; reject malformed optional sections independently with persisted notes.
2. Request only observations, uncertainty and object concepts from the model until generated priority metadata has a reliable contract.
3. Default an omitted claim contradictions field to an empty array. Keep present malformed fields, including null, invalid references and unsupported domains rejected.
4. Replay the twelve recorded discovery failures and the fox report, test optional shape variations, and verify that recovered discovery reaches segmentation with one charged attempt.
5. Advance versions for affected consumers and verify focused regressions and the smoke manifest.

## Applied behavior

The overview payload decodes observations, uncertainty and concepts strictly before decoding optional sections. Each optional section uses its own decoding boundary. Missing, null or empty optional arrays need no recovery note; malformed arrays/objects/scalars produce `overview.optionalSchema` notes and no accepted hints for that section. A malformed section does not suppress another correctly typed section. Existing semantic validation continues to reject unknown or ambiguous nominations, discard invalid locations and enforce bounds. It does not manufacture primary-subject importance or locations from string lists.

The notes remain in the overview artifact and flow into report limitations. The model prompt now requests only core discovery. Segmentation still uses discovered object queries; photographic importance remains unassigned without supported cues.

ReviewClaim decoding defaults only an absent contradictions field. Present null, scalar, malformed array entries and unknown references remain invalid. Encoding continues to write an explicit contradictions array. The value-only initializer is nonisolated to match the evidence model and Swift 6 protocol requirements under the project's MainActor default isolation.

The shared claim decoder is used by comparison as well as report/reconciliation, so overview, reconciliation, report and comparison advance to combined-v10. Unchanged crop, measurement, segmentation, identity and source stage versions remain unchanged. The pipeline also advances to combined-v10. There are no extra inference calls or budget changes.

## Regression coverage

`Docs/CombinedReviewRegression/schema-responses-v9.json` retains all twelve failed overviews and the fox report. Tests assert unchanged core text, no invented geometry, discovered-query membership and persisted recovery notes. Separate shape tests cover omitted/null/empty metadata, strings, objects, mixed arrays, scalars and invalid entries; malformed core fields still fail.

The fox replay retains its supported lighting claim as exposure while rejecting unsupported siblings. Tests reject present malformed contradictions and unknown conflict references and verify Codable round trips. An integration test supplies the recorded rabbit discovery response to the fake backend, requires segmentation and measurements to run, checks limitations and verifies exactly one charged overview attempt.

Photographic qualification still requires fresh installed-model runs and inspection of registered subject crops. Replaying JSON and using a fake segmentation backend does not establish real mask accuracy or full photographic coverage.

## Verification result

All 58 focused test cases passed. The full smoke suite passed, and its manifest enumerated 336 unique identifiers. `git diff --check` passed. Logs: `/private/tmp/rawcull-v10-tests.log`, `/private/tmp/rawcull-v10-smoke.log` and `/private/tmp/rawcull-v10-enumeration.log`. No installed-model six-ARW inference was repeated during this update.
