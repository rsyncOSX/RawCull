# Sharpness scoring review — 2026-09-28

Reviewed RawCull commit `1f57ba1` and PhotoAnalysisKit 1.3.1, revision
`2a1466e04d821fa2628d6985296643e0d0c7e465`, against the technical reference at
`/Users/thomas/GitHub/DocsyDocs/TechDocRawCull/content/en/docs/detailsharpnessscoring.md`.

The reference's dependency pin and principal formulas match current code.
The algorithm is a useful subject-oriented relative-detail metric, but there is
insufficient photographic ranking evidence to call it optimal. Keep the current
formula until alternatives have been compared on representative photographs.
The first candidate change should address missing subject evidence.

## Findings and recommended priorities

| Priority | Finding | Evidence and proposed evaluation |
| --- | --- | --- |
| High | Missing evidence is treated as severe softness. | `FocusMaskEngine+Scoring.swift:799` uses `full * (1-weight)^3`. At wildlife weight 0.85 it retains 0.3375% of global detail. Evaluate a confidence-aware fallback that distinguishes unavailable subject localization from measured blur. Avoid simply using the full score without checking sharp-background mistakes. |
| High | The nominal density factor does not independently measure edge support or noise. | `FocusMaskEngine+Scoring.swift:251` uses the population of a percentile band. Distinct continuous samples place about 7% of values in p90...p97, saturating the factor at 1. Retain the robust-tail reduction as a baseline; compare spatial edge support or a measured noise estimate against high-ISO and low-contrast fixtures before adding either. |
| Medium | Landscape is still affected by AF-local detail. | `SharpnessPresets.swift:37` disables the broad AF region, while `FocusMaskEngine+Scoring.swift:722` still searches the AF neighborhood. With no saliency, AF-local detail alone can switch the computation from the full-only fallback to a full/subject blend. Decide whether this is intended, and test identical pixels with and without AF metadata. |
| Medium | Local scalar scoring depends on several mask-file heuristics. | `FocusMaskEngine+Scoring.swift:706` selects the first composite-ranked patch and returns its robust-tail score, rather than maximizing that metric. Ranking in `FocusMaskEngine+MaskGeneration.swift:488` and `:575` includes proximity, coverage, silhouette, and ring/compact/linear shape heuristics. Validate subject/background mistakes and bump scalar algorithm identity whenever changing these shared helpers changes scores. |
| Medium | Blur gating and source/scale tuning are unvalidated across conditions. | Fixed sigma thresholds act on the already amplified and pre-blurred energy. ISO and image size change pre-blur; preview JPEG processing and CIRAWFilter detail processing change input. Test each condition independently. The code does not demonstrate that High Precision always improves ranking. |
| Medium | UI labels can overstate absolute quality. | `SharpnessScoringModel.swift:48` normalizes the current score set. A positive lone score above the denominator floor becomes 100%, and an all-soft set can still contain Sharp labels. Clarify relative quality in UI and documentation before using these labels as absolute culling judgments. |

## Documentation corrections

The reviewed detail page and focus overview were updated to correct:

- calibration's separate 1616 px maximum and visual-only role;
- Auto preserving the wildlife-oriented shared config, rather than detecting a preset;
- distinct behavior of Auto versus the explicit wildlife weight override;
- nonpositive requested size resolving to 2048;
- candidate filtering, sample-count requirements, and composite local-patch selection;
- Landscape's retained AF-local contribution;
- silhouette ratio being based on border/interior means, not total rim energy;
- band occupancy's actual limitations;
- diagnostic failure labels using broad saliency/AF, rather than the blended subject;
- overstated test coverage: the pinned suite has no direct tests of conservative subject blending, candidate selection, cubic fallback, silhouette multiplier, or subject-size bonus;
- relative UI labels and a photographic evaluation plan.

## Verification

Ran the package's existing `SharpnessMetricsTests`, `SharpnessConfigurationTests`,
`SharpnessAnalysisDescriptorTests`, and `PhotoAnalyzerTests`: **23 tests passed**,
including parameterized cases. A sandboxed run passed numeric tests but failed all
three graphics facade tests with nil output. All three passed when rerun with
macOS graphics-service access. This was an environment limitation, not a confirmed
package defect. RawCull's full application suite was not run; application input,
normalization, and persistence policies were checked in source.

A temporary diagnostic invoked the real internal `computeSharpnessBreakdown`
with a 512 px synthetic checkerboard, identical pixels and deliberately empty
saliency candidates. This bypasses Vision to isolate evidence availability:

| Preset | AF supplied | Global score | Final score | Broad AF score | AF-local score |
| --- | --- | ---: | ---: | ---: | ---: |
| Wildlife | No | 0.882388 | 0.002978 | unavailable | unavailable |
| Wildlife | Yes | 0.882388 | 0.896165 | 0.893722 | 0.913220 |
| Landscape | No | 2.044100 | 0.561361 | unavailable | unavailable |
| Landscape | Yes | 2.044100 | 1.990986 | unavailable | 1.892346 |

This proves sensitivity to evidence availability; it does not measure Vision
failure frequency or photographic ranking accuracy. Public robust-tail probes
also returned 0, 0.05, 0.1, and 1 for 1%, 5%, 10%, and 20% unit-valued samples
among zeros. For 1000 distinct evenly spaced samples, the percentile band had
71 samples and the density multiplier was 1. These demonstrate why texture and
contrast influence the score independently of focus.

## Before changing production scoring

Build a held-out set of expert-ranked burst pairs covering sharp/soft subjects,
sharp backgrounds, small birds, low contrast, motion blur, silhouettes, and
high ISO. Compare current versus candidate fallback and Landscape policies using
pairwise accuracy, top-choice agreement, and severe subject/background mistakes.
Stratify by source, image size, quality, ISO, and aperture. Add deterministic
regressions for measured failures. Only then tune remaining coefficients or
introduce another metric, update package algorithm/policy versions, update the
RawCull pin, invalidate cached scores, and synchronize the two technical pages.

No production Swift code or dependency version was changed by this review.
