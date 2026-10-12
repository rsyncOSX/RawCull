# Crop target presence contract

12 October 2026. Follow-up to the combined-v11 installed-model runs in
`/private/tmp/rawcull-six-dhzy03il` and `/private/tmp/rawcull-six-2da_k1xh`.

Both runs accepted all six overviews and completed sixteen crop observations.
All thirty-two crops explicitly declared `targetIdentified: false`; twenty-nine
still declared sufficient evidence for a visible observation. No report retained
a detail claim. The Downloads run also failed two reports and one reconciliation
on the registered-subject focus guard.

The crop prompt now defines target identification as visible presence of the
intended generic target, separately from species, individual identity, anatomy
and fine-detail quality. It requires a visible basis, prohibits assuming presence
from the region purpose, and preserves abstention for absent, indistinguishable
or unspecified targets. The contradictory positive-target/insufficient-evidence
combination remains invalid. No decoder default, text-based upgrade, grounding
relaxation or extra inference attempt was introduced.

Pipeline and crop-observation contracts advance to combined-v12. Other stage
versions retain their existing contracts. Old crop observations are ineligible
under the new contract and old pipeline snapshots cannot resume into it.

Existing integration coverage now inspects the actual admitted crop prompt and
checks the new versions. Decoder coverage verifies that species uncertainty can
coexist with explicit positive support, while a negative flag from the supplied
response pattern remains negative. Existing grounding tests continue to reject
negative, absent, unregistered and inconsistent target support.

This prompt change does not establish photographic accuracy. Fresh installed-model
crop inspection is still needed to determine whether the model recognizes target
presence correctly and whether masks separate foreground and rear subjects. Full
four-criterion acceptance and comparable-scene ranking remain unqualified.

Verification: focused Xcode tests for CombinedReviewFeatureTests,
ReviewDiagnosticsTests and ReviewRunContractTests passed. `git diff --check`
passed. SwiftFormat lint reported existing violations on unchanged lines in
three touched files; the new lines introduced no reported violations.
Log: `/private/tmp/rawcull-v12-tests.log`. No installed-model inference was rerun.
