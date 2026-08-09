# CLIP Semantic Search and Image Similarity Evaluation

**Project:** RawCullFB / RawCull  
**Test date:** 9 August 2026  
**Report generated:** 9 August 2026  
**Catalog:** `/Users/thomas/Downloads/testphotos`  
**Test status:** All three runs completed successfully

## Executive summary

Three vision-language models were evaluated on the same catalog and test workload:

1. custom OpenCLIP `open_clip_model.safetensors` (ViT-B/32, 256 input),
2. Google SigLIP2 Base Patch16 256, and
3. OpenAI CLIP ViT-B/32.

Each run contains 77 text-to-image queries with 50 results per query and image-to-image similarity results for 453 anchor images with 10 neighbors per anchor. The files prove that the pipeline executes to completion, but they do **not** demonstrate acceptable retrieval quality.

The main conclusion is that **none of the three configurations should be released as the production semantic/similarity model in its present form**. All three exhibit implausible retrieval behavior:

- The custom OpenCLIP model returns the same unrelated microscope/museum image as the first result for 57 of 77 text queries (74.0%).
- SigLIP2 returns only two unrelated images as the first result for 75 of 77 queries (97.4%), and unrelated queries share, on average, 8.45 of their top 10 results.
- OpenAI CLIP is materially more diverse, but its dominant top result is still an unrelated ruined stone structure for 13 queries, and manually inspected image-similarity false positives score as high as 0.99765.
- Every model assigns approximately 0.996–0.998 similarity to at least one visually unrelated image pair. A global similarity cutoff therefore cannot make the current output safe or useful.
- The models almost never agree on semantic results: OpenCLIP and SigLIP2 agree on 0 of 77 first results; SigLIP2 and OpenAI CLIP also agree on 0; OpenCLIP and OpenAI CLIP agree on only 4.

The pattern is more consistent with a model-integration problem—preprocessing, tokenization, exported output selection, pooling, normalization, or distance computation—than with an ordinary difference in model quality. OpenAI CLIP ViT-B/32 is the best **diagnostic baseline** because it produces the most diverse semantic results and competitive steady-state latency, but it still fails the current quality checks.

## Scope and source data

| Model label in this report | Source result file | Model fingerprint family |
|---|---|---|
| OpenCLIP custom | `open_clip_model.safetensors-semantic-test-results.txt` | `clip:ViT-B-32-256...mlfoundations/open_clip...` |
| SigLIP2 | `SigLIP2-Base-Patch16-256-semantic-test-results.txt` | `siglip2:siglip2-base-patch16-256...google/siglip2...` |
| OpenAI CLIP | `ViT-B-32-semantic-test-results.txt` | `clip:clip-vit-base-patch32...openai/clip-vit-base-patch32...` |

All runs used:

- 77 completed text queries out of 77;
- a result limit of 50 per text query;
- 453 image anchors;
- 10 image-similarity neighbors per anchor; and
- a completed semantic and similarity status.

This gives 3,850 semantic ranking rows and 4,530 similarity rows per model, or 25,140 ranked rows across the three runs.

The query set covers basic objects and scenes, colors and attributes, actions and relations, photographic quality/style, composition, counts, spatial relations, negation, and five groups of paraphrased prompts. This is good qualitative coverage, but the data contains no relevance labels. Consequently, formal Precision@K, Recall@K, mean reciprocal rank (MRR), and normalized discounted cumulative gain (nDCG) cannot be computed from these files alone.

## Evaluation method

The report computes the following directly from the result files:

- latency distribution for the 77 semantic queries;
- first-result score and first-to-second score margin;
- number and frequency of distinct first-result images;
- overlap of top-10 semantic results across all query pairs;
- overlap within the five paraphrase groups at queries 63–77;
- image-similarity top-1 distribution and first-to-second margin;
- reciprocal nearest-neighbor behavior;
- cross-model first-result agreement and top-10 overlap; and
- a limited manual visual inspection of dominant semantic results and selected extreme similarity pairs.

### Important score caveat

Raw semantic scores and raw image-similarity scores are **not directly comparable across model families**. Different objectives, logit scales, exported heads, and calibration produce different numeric ranges. A higher average score does not mean a better model. Ranking behavior and visual correctness are more meaningful here.

The similarity files satisfy `similarity = 1 - distance` to rounding precision. This describes how RawCull reports the value, not whether the underlying embedding or metric is correct.

## Performance results

### Semantic query latency

| Model | Total query time | Mean | Median | P95 | Minimum | Maximum | First query | Mean excluding first |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| OpenCLIP custom | 5,170 ms | 67.1 ms | 65 ms | 72.2 ms | 61 ms | 141 ms | 141 ms | 66.2 ms |
| SigLIP2 | 6,925 ms | 89.9 ms | 88 ms | 96.4 ms | 83 ms | 174 ms | 174 ms | 88.8 ms |
| OpenAI CLIP | 6,037 ms | 78.4 ms | 65 ms | 69.2 ms | 61 ms | 1,029 ms | 1,029 ms | 65.9 ms |

Interpretation:

- OpenCLIP and OpenAI CLIP have essentially identical steady-state latency: 66.2 ms versus 65.9 ms.
- SigLIP2 is about 35% slower than the two CLIP variants in steady state.
- OpenAI CLIP has a very large one-time startup cost: its first query is 15.6 times slower than its subsequent-query average. This strongly suggests model loading, graph compilation, allocation, or another warm-up effect.
- Benchmark reporting should separate cold-start and warmed latency. A dedicated unmeasured warm-up pass is needed before steady-state comparisons.
- The durations above cover the semantic queries recorded in the files. No per-anchor similarity latency is present, so similarity throughput cannot be compared.

### Semantic score and ranking behavior

| Model | Mean top-1 score | Median top-1 | Mean top-1 margin | Distinct top-1 images | Most common top-1 | Frequency |
|---|---:|---:|---:|---:|---|---:|
| OpenCLIP custom | 0.27973 | 0.27580 | 0.03569 | 17 / 77 | `0009_20160702_154921_383.jpg` | 57 / 77 (74.0%) |
| SigLIP2 | 0.14485 | 0.14336 | 0.01190 | 4 / 77 | `8689490321_944c9.jpg` | 39 / 77 (50.6%) |
| OpenAI CLIP | 0.27039 | 0.26992 | 0.00674 | 42 / 77 | `927380470.jpg` | 13 / 77 (16.9%) |

The large OpenCLIP margin must not be interpreted as confidence: its top result is a visually unrelated hub for most prompts. Similarly, SigLIP2's narrow score range and repeated ranking indicate embedding/ranking collapse rather than stable confidence.

### Semantic result diversity and prompt sensitivity

| Model | Mean shared results in top 10 across all query pairs | Mean shared results in top 10 for paraphrases | Unique images appearing anywhere in 77 × top 50 |
|---|---:|---:|---:|
| OpenCLIP custom | 2.27 / 10 | 5.27 / 10 | 303 |
| SigLIP2 | 8.45 / 10 | 8.33 / 10 | 161 |
| OpenAI CLIP | 0.92 / 10 | 3.60 / 10 | 373 |

Expected behavior is higher overlap for paraphrases than for unrelated queries. OpenCLIP and OpenAI CLIP show that direction, although correctness remains unproven. SigLIP2 does not: unrelated queries overlap slightly **more** than paraphrases because nearly all prompts retrieve the same small result pool. This is a strong collapse signal.

The five paraphrase groups are dog-on-beach, city-street-at-night, sharp portrait, blurry photograph, and beautiful landscape. The paraphrase measurement consists of the three pairwise comparisons within each group (15 comparisons total).

### Cross-model agreement on semantic search

| Model pair | Same first result | Mean common images in top 10 | Mean top-10 Jaccard similarity |
|---|---:|---:|---:|
| OpenCLIP custom vs. SigLIP2 | 0 / 77 | 0.04 / 10 | 0.0021 |
| OpenCLIP custom vs. OpenAI CLIP | 4 / 77 | 1.10 / 10 | 0.0655 |
| SigLIP2 vs. OpenAI CLIP | 0 / 77 | 0.06 / 10 | 0.0035 |

Near-zero agreement is not proof that every model is wrong, but it rules out treating the outputs as interchangeable. Together with the manual audit and hub behavior, it is strong evidence that at least two—and likely all three—pipelines are not producing trustworthy embeddings.

## Image similarity results

### Distribution and neighborhood behavior

| Model | Mean nearest similarity | Median | P10 | P90 | Mean top-1/top-2 gap | Mutual top-1 anchors | Top-1 reciprocal within top 10 |
|---|---:|---:|---:|---:|---:|---:|---:|
| OpenCLIP custom | 0.70481 | 0.72146 | 0.50673 | 0.90873 | 0.08385 | 238 / 453 (52.5%) | 406 / 453 (89.6%) |
| SigLIP2 | 0.79375 | 0.85256 | 0.56074 | 0.98448 | 0.03411 | 176 / 453 (38.9%) | 338 / 453 (74.6%) |
| OpenAI CLIP | 0.88558 | 0.95556 | 0.70489 | 0.99258 | 0.05802 | 290 / 453 (64.0%) | 409 / 453 (90.3%) |

The higher OpenAI CLIP and SigLIP2 similarity distributions do not establish higher quality. They may instead indicate a narrower or more clustered embedding distribution. This concern is supported by the visually false high-score pairs below.

### Count of anchors whose nearest neighbor exceeds a threshold

| Model | ≥ 0.50 | ≥ 0.70 | ≥ 0.80 | ≥ 0.90 | ≥ 0.95 | ≥ 0.99 |
|---|---:|---:|---:|---:|---:|---:|
| OpenCLIP custom | 414 | 245 | 131 | 51 | 22 | 5 |
| SigLIP2 | 413 | 351 | 265 | 180 | 120 | 23 |
| OpenAI CLIP | 443 | 411 | 346 | 287 | 237 | 66 |

These counts show why a threshold copied between models would be invalid. More importantly, a threshold as high as 0.99 still admits clear false matches in the present runs.

### Cross-model agreement on image neighborhoods

| Model pair | Same nearest neighbor | Mean common images in top 10 | Mean top-10 Jaccard similarity |
|---|---:|---:|---:|
| OpenCLIP custom vs. SigLIP2 | 13 / 453 (2.9%) | 0.66 / 10 | 0.0389 |
| OpenCLIP custom vs. OpenAI CLIP | 91 / 453 (20.1%) | 1.76 / 10 | 0.1187 |
| SigLIP2 vs. OpenAI CLIP | 12 / 453 (2.6%) | 0.54 / 10 | 0.0305 |

OpenCLIP and OpenAI CLIP are closer to each other than either is to SigLIP2, as expected from their related CLIP architecture, but even their agreement is low.

## Manual visual audit

This was a targeted spot-check, not a complete human relevance annotation. It is sufficient to identify production-blocking failures.

### Dominant semantic results

| Model | Dominant file | What the image contains | Finding |
|---|---|---|---|
| OpenCLIP custom | `0009_20160702_154921_383.jpg` | A museum display containing a large microscope/comparator machine | Returned first for 57 prompts, including “a dog,” “a bird,” “a bicycle,” and “a car”; clearly irrelevant to these examples |
| SigLIP2 | `8689490321_944c9.jpg` | Soldiers standing near a military vehicle | Returned first for 39 prompts; not a valid universal result |
| SigLIP2 | `4107809185_1736e.jpg` | A motion-blurred child bending in grass | Returned first for 36 prompts; relevant to blur/motion prompts at best, but not to most of the test suite |
| OpenAI CLIP | `927380470.jpg` | A ruined stone wall/tower against the sky | Returned first for 13 prompts; the first result for “a bird” is visibly wrong |

### Extreme image-similarity examples

| Model | Image A | Image B | Reported similarity | Visual judgment |
|---|---|---|---:|---|
| OpenCLIP custom | `2723280782.jpg`: person in front of a red wooden building | `2734034460.jpg`: macro photograph of a beetle | 0.99540 | Clear false positive; scenes and subjects are unrelated |
| SigLIP2 | `3621861224_5c872.jpg`: crowded food/community event | `5489343036_b39cf.jpg`: empty modern kitchen/dining room | 0.99595 | Some broad food/dining context, but far too dissimilar for near-duplicate-level similarity |
| OpenAI CLIP | `12223016903_011bb.jpg` and `12223016903_eed02.jpg`: same people and scene with different color rendering | same scene | 0.99801 | Correct near-duplicate match |
| OpenAI CLIP | `85152804.jpg`: blue flags | `2317822884.jpg`: yellow sunflower close-up | 0.99765 | Clear false positive despite an almost maximal score |

The OpenAI model can identify a genuine near duplicate, but a clearly unrelated pair receives almost the same score. This means its current score is not calibrated enough to distinguish duplicates from unrelated images.

## Model-by-model assessment

### OpenCLIP custom

**Strengths**

- Fast and stable steady-state semantic latency.
- Better paraphrase sensitivity than its average unrelated-query overlap suggests.
- Larger nearest-neighbor margin than the other models.

**Critical issues**

- Severe semantic hubness: one microscope image wins 74% of all queries.
- Only 17 distinct first results across 77 prompts.
- A visually unrelated red-building/beetle pair scores 0.99540 similarity.
- The high semantic score margin is misleading because the dominant result is wrong.

**Assessment:** Not usable until its preprocessing, text encoder, output tensor, and normalization are validated against the original OpenCLIP implementation.

### SigLIP2 Base Patch16 256

**Strengths**

- Lower cold-start penalty than OpenAI CLIP.
- High numerical image similarities, although these are not evidence of quality.

**Critical issues**

- Strongest semantic collapse of the three models: two images account for 75 of 77 first results.
- Unrelated query pairs share 8.45 of 10 results on average.
- Only 161 distinct images appear anywhere across 3,850 semantic results.
- Slowest warmed semantic latency.
- Weakest reciprocal image-neighborhood behavior.
- A loosely related event/kitchen pair scores 0.99595.

**Assessment:** Clearly unsuitable in the current integration. The results strongly suggest incorrect SigLIP2-specific preprocessing, text processing, output selection, or score handling.

### OpenAI CLIP ViT-B/32

**Strengths**

- Most diverse semantic rankings: 42 distinct first results and 373 distinct top-50 result images.
- Lowest unrelated-query top-10 overlap.
- Same steady-state latency as the custom OpenCLIP model.
- Best reciprocal image-neighborhood statistics.
- Correctly gives a very high score to an inspected near-duplicate pair.

**Critical issues**

- 1,029 ms first-query latency requires explicit warm-up or startup optimization.
- Semantic relevance is still visibly wrong in inspected examples.
- Very low first-to-second semantic margin.
- An unrelated blue-flags/sunflower pair scores 0.99765, almost the same as the valid near duplicate.

**Assessment:** Best of the three as a reference implementation and debugging baseline, but not production-ready.

## Likely failure modes to investigate

The report cannot identify a single root cause from result files alone. The following causes best match the observed collapse and should be checked in order.

1. **Text tokenizer mismatch**
   - Confirm exact vocabulary, merges/SentencePiece model, special tokens, padding token, context length, attention mask, truncation, and token IDs.
   - CLIP and SigLIP2 do not share interchangeable text preprocessing.
   - Compare token IDs generated by RawCull with the reference Hugging Face/OpenCLIP tokenizer for every test prompt.

2. **Image preprocessing mismatch**
   - Confirm RGB channel order, orientation handling, resize policy, center crop, interpolation, pixel range, and model-specific normalization mean/standard deviation.
   - Confirm the 256-pixel models receive the expected 256 × 256 input and ViT-B/32 receives its export's declared dimensions.

3. **Wrong exported tensor or pooling operation**
   - Verify that the final projected image/text embedding is used rather than patch tokens, a classifier output, a hidden state, or an incorrectly selected batch/token element.
   - Confirm CLS/EOS/pooled-token selection exactly matches the reference model.

4. **Incorrect L2 normalization or axis**
   - Normalize each complete embedding vector independently.
   - Record vector norms before and after normalization; post-normalization norms should be approximately 1.
   - Check for zero, constant, NaN, infinite, or low-variance dimensions.

5. **Metric or ranking error**
   - Confirm semantic search uses cosine similarity (or the model's intended logit computation) with descending order.
   - Confirm image distance and similarity operate on the correct vectors and that a cached embedding from another model cannot be mixed in.
   - Verify model fingerprint changes force a complete, model-specific re-index.

6. **Core ML conversion/precision error**
   - Compare the float16 Core ML output against the original float32 and float16 framework outputs before evaluating retrieval.
   - Inspect whether flexible shapes, attention masks, gather operations, or normalization layers changed during conversion.

7. **Embedding collapse or anisotropy**
   - Compute per-dimension mean and variance, covariance/effective rank, mean random-pair cosine similarity, and nearest-neighbor score distribution.
   - Visualize embeddings with PCA/UMAP, colored by source folder and simple content labels.

## Recommended validation plan

### Phase 1: Establish reference parity

Create a small immutable fixture set containing at least:

- 10 images spanning people, animals, vehicles, landscapes, indoor scenes, text, blur, and macro photography;
- 10 text prompts with expected tokenizer outputs; and
- the exact reference embeddings produced by the source PyTorch/OpenCLIP/Hugging Face model.

For each converted model, compare:

- input pixels after preprocessing;
- token IDs and attention masks;
- raw output embedding;
- normalized output embedding;
- image-to-text cosine matrix; and
- ranking order.

Suggested parity gates:

- identical token IDs and masks;
- maximum preprocessed-pixel error appropriate to the chosen precision;
- cosine similarity between reference and converted embeddings ≥ 0.999 for float16 unless conversion analysis justifies another bound; and
- identical top-k ranking on the fixture set, allowing only documented near-ties.

### Phase 2: Add labeled retrieval evaluation

The current 77 prompts are useful, but each prompt needs relevance labels. At minimum:

- label every top-10 result from a pooled union of all models;
- use binary or graded relevance;
- report Precision@1, Precision@5, Precision@10, MRR, and nDCG@10;
- report metrics by category: object, attribute, relation, photographic quality, composition, count/spatial/negation, and paraphrase;
- include a random baseline and the source framework model as controls.

For image similarity, build explicit positive and negative pairs:

- exact duplicates;
- resized/re-encoded duplicates;
- color/exposure edits;
- burst/near-duplicate frames;
- same subject but different scene;
- semantically related but visually different images; and
- unrelated hard negatives.

Then report ROC-AUC, precision-recall AUC, false-positive rate at the selected recall, and threshold-specific confusion matrices.

### Phase 3: Benchmark operational behavior

- Measure cold load, first inference, and warmed inference separately.
- Run at least 30 warm-up iterations followed by enough measured iterations for stable P50/P95/P99 values.
- Record image-embedding throughput, text-embedding latency, similarity-search latency, memory peak, model size, energy impact, and hardware/OS version.
- Ensure every benchmark starts with a verified model-specific index.

## Release recommendation

**Current decision: no-go for production semantic search or automatic duplicate/similar-image decisions.**

Use OpenAI CLIP ViT-B/32 as the first parity/debugging target because its semantic output is least collapsed and its warm latency is competitive. Once Core ML/reference parity is demonstrated, rerun the identical catalog test and add labeled relevance metrics. Only then compare the custom OpenCLIP and SigLIP2 variants on quality, speed, memory, and energy.

Recommended minimum release gates:

1. Converted/reference embedding parity passes on all fixtures.
2. No universal semantic hub: no single image is first for more than a justified small fraction of unrelated queries.
3. Paraphrase overlap is materially higher than unrelated-query overlap.
4. A labeled semantic benchmark meets product-defined Precision@K and nDCG targets.
5. A labeled similarity benchmark meets a product-defined false-positive ceiling.
6. Inspected unrelated pairs cannot receive near-duplicate confidence.
7. Cold-start behavior is explicitly handled and warmed P95 meets the UI latency budget.

## Limitations

- No ground-truth relevance labels are included, so this report cannot produce formal retrieval accuracy.
- The manual image inspection is deliberately small and aimed at detecting obvious failures; it is not an unbiased accuracy sample.
- Raw score thresholds are model-specific and currently uncalibrated.
- The files do not record catalog size explicitly, per-anchor similarity latency, hardware, OS version, memory, energy, model load time, or index-build time.
- Filename relationships can hint at near duplicates but are not treated as ground truth.
- The results assess these specific exported models and RawCull integration, not the theoretical capability of OpenCLIP, SigLIP2, or OpenAI CLIP in their original frameworks.

## Reproducibility details

| Model | Started (UTC) | Updated (UTC) | Status |
|---|---|---|---|
| OpenCLIP custom | 2026-08-09 09:39:46 | 2026-08-09 09:39:53 | completed |
| OpenAI CLIP | 2026-08-09 09:40:17 | 2026-08-09 09:40:24 | completed |
| SigLIP2 | 2026-08-09 09:40:51 | 2026-08-09 09:40:59 | completed |

Model fingerprints, including directory-tree SHA-256 values, are preserved in the original result files and should be retained with any future comparison to ensure that the model and index are exactly identified.
