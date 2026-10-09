# Combined Review phase 1 input-contract decision

Date: 9 October 2026

Status: phase 1 complete; installed-model input verification and application checks passed.

## Scope and decision

The phase 1 input geometry gate passes for the three installed bundles recorded in
[the machine-readable report](CombinedReviewInputFixtures/input-contract.json),
using Core AI `1953c4f90ba0214c1abc7bebcb9be5107e329a46` and PhotoAIKit
`7f9adfcd69661c6bae4a640c16a4056dfc7393df`. Source/crop implementation may proceed
for these contracts. Other models, alternate tensor shapes, and changed
preprocessing are not qualified by this decision.

Implementation and source-contract review: Codex, acting as the implementation
engineer and subsequent source/crop implementer. This is a recorded engineering
self-review, not an independent photographic evaluation or an external human
approval. Review checked the pinned engine's preprocessor dispatch and tensor
binding against the probe calls and compiled descriptors. Phase 7 still requires
the independent reviewers described in the evaluation specification.

The application exposes declared capabilities and keeps `encoderGeometryVerified`
false: validation of an arbitrary installed provider does not inherit this report's
measured verification. Future run admission must match model content and runtime
compatibility before relying on the recorded geometry. A model name, metadata
hash, or an earlier successful report alone is insufficient.

## Observed contracts

| Model | Encoder dimensions | Bound tensor | Geometry |
| --- | --- | --- | --- |
| Qwen | 448 × 448 | `float32` / NCHW RGB | Stretch; full frame retained |
| CLIP-OpenAI | 224 × 224 | `float16` / NCHW RGB | Shortest-side resize; central square retained |
| CLIP-DataComp | 256 × 256 | `float16` / NCHW RGB | Shortest-side resize; central square retained |

Qwen metadata, the compiled vision descriptor, the executed `ImagePreprocessor`,
and actual engine encoding agree. Its projected embedding shape is
`[1, 196, 2048]`. The metadata specifies RGB mean/std `[0.5, 0.5, 0.5]`,
rescale factor 1, patch size 16, and stretch. The app's request contains one
`CGImage`; the pinned adapter consumes the first image attachment. No native
multi-image comparison capability is advertised.

Both CLIP bundles expose a 77-token Int32 text input and 512-dimensional
L2-normalized embeddings. Their actual preprocessor uses sRGB RGB data,
shortest-side resize, integer center crop, Pillow-compatible bicubic sampling,
and the metadata's mean/std. The preprocessor produces Float32 CHW data; the
provider converts it to Float16 before binding these installed encoders.
The report records separate preprocessed and bound-tensor hashes. Layout and
normalization were checked with colored markers and finite, repeated embeddings;
maximum absolute repeat difference was zero for every tested overview.
Source-space square detail crops also produced finite compatible embeddings.

The CLIP center crop removes peripheral evidence. For a normalized 900 × 600
source, both bundles retain the central 600 × 600 area, starting at x=150.
Qwen retains the full frame but stretches its proportions. Source preparation
must record these consequences rather than treating an encoder as seeing every
original pixel at its original geometry.

## Fixtures and evidence

The hostless Debug probe exercises the exact pinned preprocessors without
editing dependencies. Eleven fixtures cover landscape, portrait, square,
10:1 extreme aspect ratio, and all eight EXIF orientations. Each uses four
colored corner markers, a regular grid, and a cyan circle. ImageIO normalizes
orientation with the same transformed-thumbnail options used by the app.

For every model and fixture, the report records encoded/normalized/prepared
sizes, source crop and retained rectangles, resize/crop geometry, effective
scale, padding, tensor hashes, and preview filenames. Qwen runs the actual vision
engine for overview and source-space detail crops. CLIP runs overview and crop
embeddings and checks repeatability and finite normalized values. Geometry
assertions check corner identity, edge removal, and circle stretching/preservation.
The crop is extracted from the normalized fixture source before model resizing.

All source and model-input PNG previews referenced by the report are retained in
`CombinedReviewInputFixtures/`. PNGs are denormalized viewing aids; they do not
preserve every floating-point tensor value. Re-run the deterministic probe to
reproduce numeric inputs and compare the recorded scalar hashes. This fixture set
is separate from the consented photographic evaluation dataset.

## Context and response boundaries

The Qwen bundle's context capacity is 4096 tokens. The single-image probe used
212 expanded input tokens, including 196
image tokens and 16 instruction/template tokens,
and returned 16 tokens under a 16-token response allowance.
The app allows requested response limits only in 1...4096; this does not mean
4096 output tokens fit alongside an arbitrary prompt.

The native iterator clamps output to
`min(requested, max(0, context - expandedPromptTokens))`. Tests verify one token
remaining, exactly exhausted context, and an over-context prompt. An actual
over-context adapter request generated no tokens and processed no prompt tokens;
on macOS 27.0.1 the session reports “Session ended without producing a response.”
This is a stage failure, not a photographic finding. Phase 3 must budget image,
instruction/template, evidence, and output together before inference. The probe
also verifies RawCull's zero/4097 response-limit rejection.

CLIP's installed BPE tokenizers prefix-truncate oversized text to 77 tokens and
place the end token in the last slot. The probe compares the retained prefix
against an untruncated tokenization, checks start/end IDs, and runs a finite
long-text embedding. OpenAI and DataComp padding IDs remain distinct and are
recorded with their respective configurations.

## Identity and reproducibility

Bundle content fingerprints use `bundle-tree-sha256-v1`: sorted non-hidden
regular file paths, each followed by NUL, that file's SHA256 hex, and LF, hashed
as one stream. This includes metadata, tokenizer, and model assets. It differs
from CLIP's declared main-asset fingerprint and Qwen's metadata SHA256; all have
their separate roles recorded in the JSON.

- Qwen: `8b575d2b2a499c2ea697deb7f878eee7afdc79818c95d9e304eb7809242d19f7`
- CLIP-OpenAI: `ac42a2db447f60cd0d0e3e8a31e6dec2ca29f85e6637e84f8fee44bf19ce91d1`
- CLIP-DataComp: `796848121936bde228b1cc14471baae1ba7c12d1beaee30cff7bf1bae847c6a5`

The run used Xcode 27.0 (27A266a), macOS 27.0.1 (26A434), arm64,
11 logical processors, and 18 GiB physical memory.
The complete dependency pins and hardware/OS fields are retained in the JSON.

Reviewed implementation source SHA256 values:

- `RawCull/Intelligence/Qwen/QwenInputCapabilities.swift`: `a525965a0cd1e080ba373020e00a166816b94a7af9f691a122fd98720f3dd832`
- `RawCull/Intelligence/Qwen/QwenInferenceRuntime.swift`: `f8198919fcb433fdb7ad8b1ae495cfb4e269d07c16570ea6058dbe1d79acfb94`
- `RawCull/Intelligence/Composition/CLIPInputCapabilities.swift`: `cc323f928dc93700ff63dad932b1f9d448288dcdfd6132783c1aa0b20f302971`
- `RawCull/Intelligence/Composition/RawCullAIModelRuntime.swift`: `761cc4f53080764602d5f63049be14000aa5298531efdc04c3b497ed18c30a2b`
- `RawCullReleaseTests/CombinedReviewInputFixtures.swift`: `4dd8abc1fc2524e6535e1823dac8c0d65092ba7c100b273b668cfc72f024d28d`
- `RawCullReleaseTests/CombinedReviewInputProbe.swift`: `515937a78f2637853b76672349f0a8fa119d6eca3ebe3a9b2b588d78a5042b9e`

Reproduce from the repository root:

```sh
make combinedinputstest \
  INPUT_PROBE_MODELS="$HOME/ModelAssets/Release/Models" \
  INPUT_PROBE_OUTPUT="/tmp/rawcull-combined-input-probe"
```

## Validation and remaining unknowns

- Installed-model input probes: passed, both tests, no skips; all three models
  and all 33 model/fixture combinations plus their detail crops were inspected.
- `make test-smoke`: passed; 258 unique identifiers enumerated, 257 passed,
  zero failed, one expected opt-in real-photo Qwen test skipped. The synthetic
  installed-model probes above ran separately with no skips.
- Targeted Qwen/CLIP runtime contracts: passed, including concrete/protocol Qwen
  dispatch, metadata defaults/invalid geometry, and provider removal.
- Hostless Release contracts: passed; shared Qwen/CLIP capability sources compile
  in Release, with two deterministic AI Objects contracts passed and the opt-in
  real-photo analysis skipped.
- AI import boundary and whitespace checks: passed.

Smoke verification also corrected a stale enumeration baseline and aligned the
README's four outdated dependency rows with the already-resolved pins. No package
revision was changed. The capability implementation uses an explicit async Qwen
method signature so both protocol and concrete runtime callers receive the
validated snapshot rather than the default unsupported-provider response.

Compression is absent from the Qwen metadata and remains unknown. CLIP vision
patch/token counts are not exposed by its provider. Alternate encoder shapes,
larger-input bundles, and native multi-image attachment handling remain
unqualified. Required geometry is known for the tested assets; no CLIP degraded
mode is needed. This milestone verifies input contracts, not photographic
accuracy, calibrated quality scores, latency targets, or memory admission limits.
