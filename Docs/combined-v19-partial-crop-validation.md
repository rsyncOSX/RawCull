# Combined-v19 criterion-level crop validation

12 October 2026. Based on `/private/tmp/rawcull-six-5c9y1lwy`, which persisted combined-v18.

Production crop parsing now validates each decoded criterion independently. Valid strings retain their original text. Invalid siblings become unsupported entries with empty text and persisted validation notes. Wrong IDs, malformed required fields, oversized envelopes and invalid global uncertainty remain whole-response failures. If every criterion is invalid, the response still fails and may use the existing bounded repair path. Explicit all-null abstention remains supported.

Detail still requires targetIdentified=true. Explicit unresolved-detail phrases and explicit background-texture statements now reject that criterion. This conservative text check does not prove that remaining texture prose belongs to the intended subject; mixed background/target prose and visual hallucinations still require photographic inspection. Target flags are never upgraded, prose is not truncated, and budgets are unchanged.

Inspection artifacts preserve rejection notes. The feature adds them to report limitations on both live execution and artifact restore. Any rejected crop criterion keeps the generated report incomplete, even when other crops supply every category. Rejected criterion text is excluded from synthesis evidence. Partial responses avoid corrective inference; wholly invalid responses retain the existing failure/repair behavior.

Pipeline, crop, reconciliation, report and comparison versions advance to combined-v19. Other stage contracts retain their versions.

Verification: all 67 focused cases pass in ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests. Fixtures cover ten terminal v18 failures, the accepted unresolved squirrel detail and an explicit background-detail case. The wholly invalid puffin response still fails. Tests verify saved notes, false target flags, rejected-detail abstention, wrong-ID rejection and feature-level anatomy rejection without losing valid siblings. Smoke enumeration confirms 350 unique enabled identifiers. `git diff --check` passes.

Logs: `/private/tmp/rawcull-v19-tests-final.log`, `/private/tmp/rawcull-v19-enumeration.log`. No installed-model inference was performed; another six-ARW run is required to establish model behavior and photographic usefulness.
