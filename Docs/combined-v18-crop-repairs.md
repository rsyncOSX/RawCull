# Combined-v18 crop repair and synthesis update

12 October 2026. Based on `/private/tmp/rawcull-six-hnakk1mh` (combined-v17); see `evaluation-combined-v17-run.md`.

The crop prompt now requests visible generic-target presence before criteria, separates species uncertainty from target presence, requires null rather than negative texture prose for unresolved detail, and requests 80-character sentences under the unchanged 120-character bound.

Target/detail inconsistency and criterion-length failures now qualify for the existing single charged repair attempt. Feedback names the relevant correction. Caps, token allowances and strict original-response validation remain unchanged. No target flag is upgraded and no prose is truncated. Successful repairs use the existing rejected-response retention path.

Synthesis focus validation checks exact supported criterion text when criterion observations exist. This fixes the squirrel visibility rejection caused by checking one criterion against four observations joined without sentence boundaries. A registered subject crop and visible target remain required; legacy observations retain whole-sentence validation.

Pipeline, crop, reconciliation, report and comparison advance to combined-v18; other stage versions remain unchanged.

Verification: 66 cases passed across ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests. Coverage includes all 11 retained v17 failed crops (still rejected with the same checks), null abstention, repair eligibility, exact registered visibility grounding and rejection when target presence is false. Smoke enumeration has 349 unique enabled identifiers; the Makefile expectation is updated to the observed count (the previous 338 was already stale before these two additions). `git diff --check` passes. Logs: `/private/tmp/rawcull-v18-tests.log` and `/private/tmp/rawcull-v18-enumeration.log`.

No installed-model inference was run. The next six-ARW run must establish actual compliance and photographic usefulness. Visual hallucinations such as orange puffin wings are not proven fixed by structural checks. Acceptance criteria remain unchanged.
