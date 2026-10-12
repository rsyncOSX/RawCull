# Nullable criterion responses and explicit report schema — combined-v17

12 October 2026. Evidence: `/private/tmp/rawcull-six-0xl4guf6`, combined-v16, same six ARWs as v15. All 16 crop stages and all six report stages failed, using 22 repair calls. The crop responses copied false support flags while filling observation text. Report responses omitted text and put prose into evidence. No claims were accepted. Focused fake-backend tests had not established installed-model compliance.

## Changes

The crop request now uses four required nullable strings: composition, exposure, visibility and detail. A string is supported evidence; null is explicit abstention. Empty strings, missing keys and legacy supported/text objects are rejected. Support and insufficient-evidence status are derived internally rather than requested as redundant Boolean flags. targetIdentified remains an explicit required Boolean for generic-target support. All-null criteria can abstain even when a generic target is identified. Empty uncertainty is accepted at this request boundary.

The existing stored criterion observations retain their support/text representation, derived from the validated request. This preserves the downstream grounding and persistence model. The wire encoder writes explicit null values, so nullable keys survive round trips. No response text is silently rewritten or a negative support flag upgraded.

Report synthesis again supplies a full JSON claim example, including text/type/uncertainty strings and evidence/contradictions arrays of reference objects. The example is explicitly identified as schema rather than evidence. The prompt remains concise to preserve evidence admission within the verified model context.

Repair feedback selects an instruction from the validation check and field. Crop feedback requests strings/nulls and explains prohibited anatomy, exposure, visibility or duplicate-text failures when applicable. Report feedback requires every claim field, puts observation prose in text and requires supplied reference objects in evidence. Unrelated crop instructions no longer appear in report repairs. The existing single charged repair attempt and inference budgets remain unchanged.

Pipeline, crop observation, reconciliation, report and comparison advance to combined-v17. Overview and other unchanged stage contracts retain their versions.

## Verification and limits

The focused ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests suites pass. Tests replay four original v16 rejected responses, validate nullable strings and all-null abstention, enforce required nullable keys, verify null encoding, inspect the actual full report prompt, and check stage-specific repair feedback. The original malformed responses remain rejected. Fixtures are saved in `Docs/CombinedReviewRegression/schema-responses-v16.json`.

Log: `/private/tmp/rawcull-v17-tests.log`. `git diff --check` passes. No installed-model inference was run during this update. A fresh run must establish model compliance and photographic usefulness. The unresolved LMDB warnings are not changed.
