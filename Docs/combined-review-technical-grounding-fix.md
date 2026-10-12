# Conservative technical synthesis — combined-v15

12 October 2026. Reviewed evidence: `/private/tmp/rawcull-six-982dg633`, combined-v14, six ARWs from `/Users/thomas/tmp`.

The run completed 114 of 115 work items in 1584 seconds. All six reports contained four criterion labels and were marked incomplete. One bird crop was rejected for a yellow-eye claim. The foal detail described grass and flowers while citing a foal observation; other accepted outputs added individual hairs, positive focus or resolution/motion prose under exposure. Comparison abstained for unrelated scenes.

Technical synthesis is now conservative and extractive. Detail requires a registered, positively identified crop with explicit texture wording, plus texture in the generated claim. Exposure requires lighting wording. Detail, exposure and any focus/sharp/blur claim must match a complete sentence from its cited observation after case/punctuation normalization. Whole-sentence matching avoids deleting a negation or modifier through substring selection. This constrains synthesis; it does not verify visual truth, anatomical identity or semantic entailment of the original observation. Valid paraphrases and observations without the explicit texture cue can abstain. Source observations and deterministic measurements remain inspectable.

Prompt eligibility mirrors texture and lighting checks. The prompt directs unsupported criteria to be omitted. Missing criteria keep the report incomplete and retain a criterion-specific coverage limitation. The installed-model probe accepts an omitted criterion only with that limitation; terminal work, model budgets and report presence remain required. No photographic qualification is claimed.

A crop.supportedDomain rejection can use the existing single repair attempt and existing repair budget. It receives fresh-generation feedback; the rejected response is not edited. Successful repairs retain the original diagnostic and bounded rejected text when enabled. Repeated failures still terminate through the existing failure path. No retry is added for unsupported report grounding.

Pipeline, reconciliation, report and comparison advance to combined-v15. Crop observation remains combined-v13. The prompt stays within the conservative verified context admission rule.

Regression tests cover the v14 foal/background mismatch, invented fox detail, positive focus additions, exposure misclassification, dropped negation, supported technical sentences, prompt eligibility and a charged anatomy repair with retained original text. The focused ReviewDiagnosticsTests, CombinedReviewFeatureTests and ReviewRunContractTests suites are validated in `/private/tmp/rawcull-v15-tests.log`.

The 96 MDB_MAP_FULL warnings remain unresolved. No LMDB map-size API or emitting source was found in RawCull or the inspected CoreAI Swift sources. No speculative cache or runtime change was made. A fresh installed-model run is still needed to assess generation and abstention behavior.
