# Six-ARW discovery and synthesis fixes

11 October 2026. Evidence: `/private/tmp/rawcull-six-2dcc0zim` and `/private/tmp/rawcull-six-_6nv7yqt`. These runs use different six-file sets; only the latter matches `evaluationphase1_6.md`.

## Plan and implementation

1. Remove literal bird, flower and centered-location examples from overview discovery. Describe field types and limits, default optional arrays to empty, and require exact references to discovered concepts. Reject copied character-limit instructions. Retain strict contextual-concept validation rather than silently removing invalid references.
2. Preserve observations in synthesis context: prioritize nominated subject crops, other registered subject crops, overview, then contextual/fallback crops, with stable input order within priorities. Remove individual measurement references from the prose prompt. Measurements remain available in deterministic presentation. Their references cannot displace the photographic observations that prose requires.
3. Remove the generated example that copied the last crop's text and implicitly labeled it composition. Provide an empty JSON envelope and field definitions. Explain focus-scope constraints and exposure semantics explicitly. Retain the registered-subject focus guard, including background blur wording, until structured focus scope is implemented.
4. Validate claims independently after parsing the report schema. Retain valid claims and attach compact rejection limitations for invalid siblings. All-invalid responses still fail with a retained rejected response and evidence-only fallback. Missing criteria and any rejected claim keep a report incomplete. Unknown IDs, measurement-only claims and unsupported domains remain rejected.
5. Advance the pipeline and overview/reconciliation/report stage versions to combined-v8; unchanged stages retain their versions. Add deterministic tests for copied discovery instructions, unmatched contextual references, mixed valid/invalid synthesis and the actual prompt's observation retention. Update smoke enumeration count for the three new tests.

## Validation and qualification

Run ReviewDiagnosticsTests, CombinedReviewFeatureTests, ReviewRunContractTests and ReviewSubjectPriorityTests. Then rerun both six-file sets using RunCombinedReviewSix.py, preserving input hashes and new evidence directories. Check actual prompts for primary-subject and overview retention, inspect registered crops, and assess each criterion's meaning rather than only its type name. Deterministic tests do not establish model or photographic qualification.

Automatic corrective inference is deliberately deferred: the current budget permits only one overview attempt per image. Adding a retry requires an explicit budget/scheduling design and tests demonstrating that it cannot consume mandatory downstream coverage. This patch does not silently increase attempts.

Partial rejection diagnostics are persisted as report limitations. The raw response remains retained for wholly rejected responses; partial acceptance does not currently retain the raw rejected sibling response separately.

## Verification result

The final focused Xcode test run passed for all four suites (50 reported cases, including parameterized cases). Log: `/private/tmp/rawcull-fix-final-tests.log`. `git diff --check` passed. No new installed-model six-ARW run was performed; photographic usefulness and full four-criterion model coverage remain unqualified.
