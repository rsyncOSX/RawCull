# Recommendations for other AI analysis modes

12 October 2026. Advice based on Combined Review testing through combined-v15 and inspection of RawCull’s other analysis paths. The combined-v16 code has passed focused regression tests; a fresh installed-model run is pending.

The other AI analysis modes should be updated selectively. Combined Review testing exposed weaknesses that also exist in their implementation, but it does not prove those modes produce the same errors. Each mode should retain its purpose rather than adopt Combined Review wholesale.

| Analysis | Recommended changes | Priority |
|---|---|---|
| Qwen photo analysis | Separate criterion evidence from scores; allow unsupported criteria; default eye status to unknown without qualified evidence. Present scores and confidence as model judgments. | High |
| Object Analysis | Require each focus judgment and strength/problem to cite its own crop evidence. Keep expression unknown when anatomy is unverified. Validate consistency between `focusQuality` and descriptive prose. | High |
| SAM 3 + CLIP / Deep Review | Distinguish “requested head mask obtained” from “head anatomically verified.” Keep local detail measurements separate from photographic quality, and describe ranking confidence as relative separation. | Medium |
| Similarity and semantic search | Retain their matching purpose. Check preprocessing, geometry and cache compatibility; Combined Review’s prose restrictions offer little benefit here. | Low |

## Specific implementation concerns

Qwen photo analysis validates score ranges, but does not establish the evidence supporting those scores or `eyesOpen`. An invalid structured assessment can also become a successful freeform result. Consider distinguishing a failed structured assessment from an intentional freeform response so malformed output cannot silently count as a validated assessment.

Object Analysis already instructs the model to judge focus separately for each numbered crop and supports an uncertain focus classification. Its decoder validates IDs, enum values, confidence ranges and bounded lists, but does not establish that the prose supports the focus classification. Add evidence support and consistency checks rather than relying on prompt instructions alone.

Deep Review’s `promptVerified` depends on the selected SAM prompt, mask usability and fallback status. That establishes which segmentation request succeeded; it does not independently verify a head or face. Review both the naming and presentation of this status before treating it as anatomical evidence. Its confidence calculation reflects relative score separation and available measurement conditions, rather than calibrated photographic certainty.

## Shared improvements

Transfer evidence rules across modes where applicable:

- Report source fidelity and the limits of camera previews, resizing and model input resolution.
- Preserve ownership between a subject, its registered crop and the evidence supporting a claim.
- Keep observations, deterministic measurements and model judgments distinguishable.
- Allow explicit uncertainty or abstention when a criterion lacks evidence.
- Use bounded, charged repairs with retained diagnostics.
- Version prompts, response schemas and cache compatibility when their meaning changes.

Avoid copying Combined Review’s complete orchestration or sentence-copying restrictions into every mode. Matching and search need different contracts from photographic assessment. Successful structural validation alone does not establish photographic accuracy.

## Recommended sequence

1. Assess the next combined-v16 installed-model run, particularly criterion-specific usefulness, abstention and the repeated bird anatomy failure.
2. Run Qwen photo analysis and Object Analysis on the same six photographs and retain their prompts, outputs and exact model inputs.
3. Compare unsupported focus, eye/expression claims, criterion confusion, malformed structured output and uncertainty handling.
4. Update Qwen and Object Analysis based on those findings, then review Deep Review’s verification and confidence presentation.
5. Change similarity or semantic search only where their own evidence reveals a preprocessing, geometry or compatibility issue.

This sequence distinguishes broadly useful fixes from restrictions specific to Combined Review. No changes to the other analysis modes are proposed as already validated by the Combined Review tests.
