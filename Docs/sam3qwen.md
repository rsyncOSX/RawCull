# SAM 3 → Qwen Object Analysis Workplan

Status: proposal, reevaluated against RawCull and the adjacent PhotoAIKit
checkout on September 23, 2026. RawCull still has two AI Analysis modes;
PhotoAIKit still exposes one union mask. A four-photo muskox spike now confirms
that the tested Core AI runtime also returns separate instance segments, but
release-quality instance handling remains unproven. The CLIP, SAM 3, and Qwen Apple-hosted packs are uploaded,
processed, and ready for internal testing. A signed App Store build and
clean-install TestFlight validation remain pending in `appleassets.md`.

## Recommendation for the next update

**Next release gate:** finish the signed App Store build and clean-install
TestFlight checks for the existing three models. This validates the exact
download, activation, removal, and relaunch path on which any new AI feature
depends. The prerequisite is release validation, not more asset-pack code.

**Next feature update:** add an optional, resumable **Catalog AI Triage** pass
using the Qwen model RawCull already distributes. Run it after the normal scan
and CLIP indexing, first on a bounded, representative subset of images. Show
review cues and reasons in the grid or burst review without changing ratings
or selections. Section 17 defines the coverage and measurement gate. This has
broader culling value than requiring photographers to select images before
Qwen can help, and it reuses an installed model. It must never delay initial
catalog browsing or compete with interactive analysis.

**Following feature update:** continue this document's **Objects** mode through
the additive PhotoAIKit instance contract and a larger validation set. The
four-photo Phase 0 spike supports that work: it separated six touching muskox
in one image, while also showing why low-score fragments must be filtered. The
current union-mask API cannot yet expose those instances to RawCull. The
Objects work can proceed while Catalog AI Triage is being designed.

These priorities are product recommendations, not evidence that Qwen batch
throughput or SAM 3 instance output already meets release quality. Record the
benchmarks and user-visible value before promoting either feature.

## 1. Objective

Add a third mode to RawCull's existing **AI Analysis** view that discovers
objects in each selected photograph, preserves the individual SAM 3 masks, and
uses Qwen to produce structured, object-aware photographic analysis.

The user-facing modes should become:

1. **SAM 3 + CLIP** — current burst/deep-review ranking.
2. **Qwen Vision** — current whole-image assessment.
3. **Objects** — new SAM 3 → Qwen object analysis.

This is an additional mode inside the existing AI Analysis view, not a new
top-level application tab. It uses the same **Selected** and **Tagged** image
sources and the same local-only privacy model as the existing AI features.

The desired pipeline is:

```text
selected photo
    ↓
Qwen concept discovery, or user-supplied concepts
    ↓
SAM 3 returns every matching instance for each concept
    ↓
filter and deduplicate instance masks
    ↓
render original + numbered object crops/overlays into a review board
    ↓
Qwen returns structured per-object and whole-image findings
    ↓
RawCull presents sortable results and object details
```

## 2. Product definition

### 2.1 What “discover objects” means

SAM 3 performs exhaustive segmentation for a supplied open-vocabulary concept:
for example, `bird` should return every matching bird. It does not, by itself,
produce a complete vocabulary of every meaningful concept in an image.

For automatic object analysis, RawCull should therefore use Qwen for a small
first-pass concept-discovery request, use those concepts with SAM 3, and then
use Qwen again for the detailed analysis. A manual concept mode must also be
available so the user can bypass discovery and request concepts such as
`bird`, `person`, `car`, or `bird head` directly.

References:

- [Meta SAM 3 overview](https://ai.meta.com/research/sam3/)
- [Official SAM 3 repository](https://github.com/facebookresearch/sam3)

### 2.2 First Objects release user experience

The first Objects release should support:

- automatic concept discovery, limited to a small number of concrete visible
  object categories;
- a manual comma-separated concept override;
- all matching SAM 3 instances for every accepted concept;
- an original-image overview plus numbered object crops;
- structured object descriptions, visibility, focus/detail, expression when
  applicable, obstructions, strengths, problems, and confidence;
- whole-image summary and relationships between visible objects;
- batch processing of the currently selected or tagged images;
- cancellation, progress, partial failures, and retry;
- entirely local processing;
- reuse of cached object masks when the source, model, concept, and processing
  parameters still match.

### 2.3 Non-goals for the first release

- Replacing the existing SAM 3 + CLIP Deep Review workflow.
- Changing the existing single/union-mask contract used by Deep Review.
- Automatically applying star ratings, selections, keywords, or metadata.
- Tracking objects between different still photographs.
- Training or fine-tuning SAM 3 or Qwen.
- Claiming that every real-world object was found.
- Treating disconnected regions from a union probability map as guaranteed
  object instances.
- Sending photographs, masks, prompts, or results to a network service.

## 3. Current implementation and constraints

### 3.1 PhotoAIKit currently returns one union mask

The package at `../PhotoAIKit` currently exposes:

- `SubjectSegmentationPrompt`, a fixed enum of known prompts;
- `SubjectSegmentationResult`, containing one `CGImage` mask and one score;
- `SubjectSegmenting.segment(_:)`, returning one result;
- `SegmentationService`, which caches and resizes that one result;
- `SubjectMaskDiskStore`, which stores one PNG plus JSON metadata.

`CoreAISAM3Provider` configures the Core AI engine with `maxSegments: 5`.
`SegmentationResponse.segments` can contain individual masks, boxes, and scores,
but `CoreAISAM3Provider.makeMaskImage` currently unions every segment. When a
semantic probability map is present, the provider turns that exhaustive map
into one mask as well. Existing tests explicitly verify this union behavior.

This behavior is correct for Deep Review and must remain unchanged.

### 3.2 RawCull's Qwen path is whole-image only

`RawCullQwenAnalysisFeature` currently:

- decodes one thumbnail per file at a maximum side of 2,048 pixels;
- passes one image and a text criterion to `QwenInferenceRuntime.assess`;
- processes selected files sequentially;
- accepts either the existing structured photo schema or free-form text.

`QwenInferenceServing` exposes only the photo-assessment operation. The new
workflow needs a lower-level structured-response operation that can support
both concept discovery and object-board analysis without duplicating model
loading or creating a second Qwen provider.

### 3.3 Runtime ownership

`RawCullApplicationState` creates one `RawCullAIModelRuntime`, which owns the
single `QwenInferenceRuntime` alongside the CLIP and SAM 3 resource managers. It
also creates one `RawCullQwenAnalysisFeature` using that manager. The
object-analysis feature must be created in the same composition root and share
those validated model resources. Views must receive the feature; views must not
create model providers or perform inference directly.

### 3.4 Managed model release validation is a prerequisite

The three packs, managed Qwen location propagation, and app-side activation
path are implemented. Before shipping either new AI feature, finish the remaining
`appleassets.md` release checks: signed App Store upload, clean-install
TestFlight download/use/relaunch/remove/reinstall, and removal during active
inference. Treat a passed automated build as insufficient evidence for the
Apple-hosted end-to-end path.

Object Analysis should not add another model-location or download mechanism.

## 4. Required architectural decisions

The implementation should use the following decisions unless the discovery
spike proves one of them impossible.

1. Keep the existing `SubjectSegmenting` API and union-mask caches intact.
2. Add a separate, additive multi-instance segmentation contract.
3. Support arbitrary validated short noun-phrase concepts in the new contract;
   do not expand the fixed `SubjectSegmentationPrompt` enum for every query.
4. Preserve the individual masks from `SegmentationResponse.segments`.
5. Do not represent a union probability map as multiple definite instances.
6. Use one shared Qwen provider/model manager for Qwen and Object modes.
7. Serialize Qwen inference so two UI modes cannot run model sessions at the
   same time.
8. Render one deterministic review-board image per source photograph because
   the current Qwen boundary accepts one image attachment.
9. Keep object-analysis state in a dedicated `@Observable @MainActor` feature.
10. Cache segmentation output, but initially regenerate Qwen prose so changes
    to prompts and schemas do not silently reuse stale language-model results.

## 5. Phase 0 — capability spike and go/no-go gate

Do this before changing public APIs.

**Diagnostic completed on four muskox photographs:** The local PhotoAIKit
checkout includes the opt-in `SAM3InstanceCapabilityTests` and its run guide
at `../PhotoAIKit/Documentation/SAM3InstanceSpike.md`. It records individual
instance masks and overlays without changing the existing union-mask API.
The result is summarized in §5.4.

### 5.1 Add a diagnostic test or executable in PhotoAIKit

Run the exact SAM 3 model that RawCull will distribute against representative
images containing:

- several separated objects of the same concept;
- touching or overlapping objects of the same concept;
- one large foreground object and small background objects;
- no instances of the requested concept;
- repeated concepts such as `bird`, `person`, `car`, and `face`.

Record, without checking model artifacts into source control:

- whether `SegmentationResponse.segments` is populated;
- the number of returned segments;
- each segment score and box;
- whether the probability map is also present;
- coordinate system and normalization of `Segment.box`;
- ordering stability across repeated identical runs;
- behavior of `maxSegments` at 5, 8, 12, and 16;
- peak memory and latency at RawCull's current 4,320-pixel input cap.

### 5.2 Gate criteria

Proceed with true instance analysis only if the production Core AI runtime
returns usable individual `segments` for the shipped SAM 3 model.

If it returns only a union probability map:

- stop the main implementation;
- retain the union mask for the existing workflow;
- document the Core AI limitation;
- optionally prototype connected-component extraction under a clearly named
  **regions** workflow;
- do not label connected components as reliable object instances, because
  touching objects cannot be separated and one object may have disconnected
  visible parts.

### 5.3 Deliverable

Add a short result section to this document containing the tested model
fingerprint, runtime revision, images used, observed output fields, chosen
instance cap, and the go/no-go decision.

### 5.4 Four-photo muskox spike result — September 23, 2026

The release-build diagnostic completed 56 runs using the local release bundle
at `~/ModelAssets/Release/Models/SAM3`, PhotoAIKit's pinned
`coreai-models` revision `475c585fdb0fe82a83c8f777f259e9414bd44c98`,
and macOS 27.0 (26A428). The bundle reports `sam3_float16.aimodel` and this
artifact identity:

```text
coreai-sam3-local:sam3_float16:sam3_float16.aimodel:file-metadata-v1:1663921567:1783701311.5240934
```

That identity uses file metadata because this bundle has no cryptographic
fingerprint manifest. Confirm that the Apple-hosted pack has the same model
artifact before treating these measurements as release validation.

| Photo | Visible muskox | Strong separate instance masks at cap 8 |
|---|---:|---:|
| `_DSC7268_DxO.jpg` | 2 | 2 |
| `_DSC7470_DxO.jpg` | 2, overlapping | 2 |
| `_DSC7605_DxO.jpg` | 1 | 1 |
| `_DSC7625_DxO.jpg` | About 6, touching/partly occluded | 6 |

Both `musk ox` and `muskox` produced the same strong counts on the two photos
tested with both spellings. The `car` negative control on the single-muskox
photo returned only scores at or below 0.016. The runtime returned individual
`segments` **and** a semantic probability map on every run. Segment mask
fingerprints and ordering were identical across both repetitions for every
photo, concept, and cap (28 paired comparisons). Strong boxes were within the
input-image pixel bounds and used the macOS bottom-left coordinate convention;
some low-score boxes extended slightly beyond an edge, so production code must
validate or recompute them.

The raw response always filled the requested cap, including false masks. On
this sample, a provisional score floor of 0.5 and minimum mask area of 0.1%
of the image removed extra fragments while retaining the visible animals.
The separated-pair photo had a 0.676-score mask covering only 0.02% of the
image, demonstrating why score alone is insufficient. The herd needed six
instances, so cap 5 truncated a real animal; caps 8, 12, and 16 yielded the
same six strong animals. **Choose engine cap 8 for the next prototype**, then
retune filters and cap on a wider set with smaller and more diverse subjects.

The first call took 17.7 seconds including model load; the median subsequent
provider call took 2.13 seconds. The test process reached a 6.33 GiB resident
memory high-water mark, including diagnostic image output. These are single-Mac
measurements, not release performance targets. The complete report, individual
masks, and overlays are under `../images/sam3-results/`; the input manifest is
`../images/sam3-muskox-cases.json`.

**Decision: conditional go for additive multi-instance prototyping.** These
photos demonstrate useful separation, including overlapping animals. The
four-photo set does not establish broad recall, prompt discovery quality, or
Qwen object-board value. Validate the hosted pack identity and test more
subjects, tiny distant objects, and negative controls before a release gate.

## 6. Phase 1 — PhotoAIKit multi-instance contracts

Make these changes in the separate `PhotoAIKit` repository first. They must be
additive so existing RawCull Deep Review call sites keep compiling.

### 6.1 New concept type

Add an open-vocabulary value type in
`Sources/PhotoAIContracts/ObjectSegmentation.swift`:

```swift
public struct SegmentationConcept: Codable, Hashable, Sendable {
    public let query: String
    public let cacheIdentifier: String
}
```

The initializer should:

- trim leading/trailing whitespace;
- collapse repeated internal whitespace;
- reject empty input;
- enforce a conservative UTF-8 or character limit;
- reject control characters and line breaks;
- derive a locale-independent normalized cache identifier;
- preserve the user's display spelling separately only if the UI needs it.

Provide conveniences for converting existing `SubjectSegmentationPrompt`
values to `SegmentationConcept`, but do not make the new type depend on a fixed
list of concepts.

### 6.2 New request/result types

Add types similar to:

```swift
public struct ObjectSegmentationRequest: Sendable {
    public let requestID: UUID
    public let sourceID: UUID
    public let concept: SegmentationConcept
    public let image: CGImage
    public let inputSize: CGSize
    public let outputSize: CGSize
    public let maxSide: Int
    public let maximumInstanceCount: Int
}

public struct ObjectMaskInstance: Identifiable, Sendable {
    public let id: String
    public let index: Int
    public let mask: CGImage
    public let score: Float
    public let normalizedBoundingBox: CGRect
}

public struct ObjectSegmentationResult: Sendable {
    public let sourceID: UUID
    public let requestID: UUID
    public let concept: SegmentationConcept
    public let instances: [ObjectMaskInstance]
    public let modelIdentity: ModelIdentity
    public let inputSize: CGSize
    public let outputSize: CGSize
    public let timing: SubjectSegmentationTiming
}

public protocol ObjectInstanceSegmenting: Sendable {
    var modelIdentity: ModelIdentity { get }
    func segmentInstances(
        _ request: ObjectSegmentationRequest
    ) async throws -> ObjectSegmentationResult
}
```

Final naming may follow PhotoAIKit conventions, but the concepts must remain
separate from the existing single subject-mask API.

Instance identity must be deterministic for one cached result. Sort instances
using documented stable criteria, for example descending score followed by
normalized box coordinates, then assign the stable result-local index. Do not
use a fresh `UUID()` as a SwiftUI row identity.

### 6.3 CoreAISAM3Provider implementation

Make `CoreAISAM3Provider` conform to both `SubjectSegmenting` and
`ObjectInstanceSegmenting`.

Refactor inference so both public operations share one internal method and do
not load or run the model twice. The multi-instance path should:

1. tokenize `SegmentationConcept.query`;
2. request a configurable, bounded number of segments;
3. decode each `Segment.mask` separately;
4. retain its score and verified bounding box;
5. calculate the box from the decoded mask when the runtime box is missing or
   invalid;
6. resize every mask to the requested output size;
7. remove empty masks;
8. return an empty `instances` array when no object matches;
9. check cancellation before inference, after inference, and during expensive
   per-mask conversion.

The existing `segment(_:)` behavior should continue returning the exhaustive
union mask expected by Deep Review and existing cache tests.

Do not silently use `SemanticSegmentationMap` as an instance list. It may still
be used by the existing union-mask operation.

### 6.4 Configurable instance limit

Replace the hard-coded `maxSegments: 5` with a configuration value whose
production default is selected from the Phase 0 measurements. The application
request should also have a lower or equal cap. Recommended starting limits:

- engine cap: 12;
- per-concept retained cap: 8;
- total objects sent to Qwen per photograph: 8.

These are starting values, not acceptance thresholds. Lower them if memory or
latency is unacceptable on supported hardware.

### 6.5 PhotoAIKit workflow service

Add `ObjectSegmentationService` in `PhotoAIWorkflows`. It should own:

- image downscaling;
- source/model/concept cache lookup;
- provider invocation;
- output-mask resizing;
- memory and disk persistence;
- cancellation;
- batch-friendly progress primitives where useful.

Do not overload `SegmentationService.segment` with a flag that changes the
shape and meaning of its return value.

### 6.6 PhotoAIKit tests

Add focused Swift Testing coverage for:

- concept normalization and invalid input;
- zero, one, and multiple returned segments;
- individual masks are not unioned;
- stable sorting and IDs;
- score and bounding-box preservation;
- invalid runtime boxes fall back to measured mask bounds;
- empty masks are discarded;
- instance cap enforcement;
- cancellation;
- existing union-mask behavior remains unchanged;
- EfficientSAM and existing `SubjectSegmenting` conformers remain unaffected.

Commit and push PhotoAIKit, then update RawCull's pinned PhotoAIKit revision.
Do not point RawCull at an uncommitted local package path for the final change.

## 7. Phase 2 — multi-instance cache

### 7.1 Separate cache contract

Add a separate store rather than changing `SubjectMaskStoring`:

```swift
public struct ObjectMaskSetStorageKey: Codable, Hashable, Sendable

public protocol ObjectMaskSetStoring: Sendable {
    func load(for key: ObjectMaskSetStorageKey) async -> ObjectSegmentationResult?
    func contains(_ key: ObjectMaskSetStorageKey) async -> Bool
    func save(
        _ result: ObjectSegmentationResult,
        for key: ObjectMaskSetStorageKey
    ) async throws
}
```

The cache key must include:

- standardized source path;
- source file size and modification date;
- normalized concept identifier;
- complete model artifact identity/fingerprint;
- input maximum side;
- maximum instance count if it changes output;
- object-result schema/cache version.

### 7.2 Disk representation

Use one atomic cache entry per source/concept/model combination:

```text
SAM3ObjectMasks/
    <cache-key>/
        manifest.json
        instance-000.png
        instance-001.png
        ...
```

The manifest should contain the concept, stable ordering, scores, normalized
boxes, dimensions, source identity, model identity, and schema version.

Write to a temporary sibling directory and atomically replace the completed
entry so cancellation or process termination cannot leave an apparently valid
partial entry. A missing PNG, malformed manifest, mismatched fingerprint, or
invalid dimensions must be treated as a cache miss.

Keep the existing `SAM3Masks` cache and its `v2-multi-subject-mask` entries
unchanged. Add a separate `objectMaskDirectory` to `RawCullAIPaths`, such as:

```text
~/Library/Caches/no.blogspot.RawCull/SAM3ObjectMasks
```

### 7.3 Cache lifecycle tests

Test:

- complete round-trip of several masks;
- source modification invalidation;
- model fingerprint invalidation;
- concept normalization maps equivalent queries to one entry;
- corrupt/missing instance files cause a miss;
- cancelled writes do not create valid entries;
- prune and remove-all behavior;
- the existing single-mask cache is neither read nor deleted accidentally.

## 8. Phase 3 — Qwen general-purpose response boundary

### 8.1 Extend without duplicating the provider

Extend the RawCull-owned Qwen protocol with a general vision response method:

```swift
nonisolated struct QwenVisionRequest: Sendable {
    let instruction: String
    let image: CGImage
    let maximumResponseTokens: Int
}

nonisolated protocol QwenInferenceServing: Sendable {
    func validate(url: URL) async -> QwenModelStatus
    func respond(to request: QwenVisionRequest) async throws -> String
    func assess(criteria: String, image: CGImage) async throws -> QwenModelResponse
    func clear() async
}
```

Implement `assess` using the same lower-level response path so the current Qwen
mode keeps its exact schema and behavior.

### 8.2 Serialize inference

Actor isolation alone does not guarantee that a method remains non-reentrant
while awaiting model generation. Ensure that only one Qwen generation runs at
a time across the Qwen and Objects modes. Use a small actor-owned inference
gate or another explicit serialization mechanism with cancellation support.

Required behavior:

- starting one AI mode cancels or waits for the previous mode according to the
  UI action;
- removing or switching the active Qwen model cancels current work before the
  provider is cleared;
- a stale response cannot overwrite a newer run;
- the model is loaded once and reused where safe;
- cancellation does not discard the validated model unnecessarily.

### 8.3 Qwen tests

Add test doubles and tests proving:

- the current `assess` prompt/schema is unchanged;
- general responses receive the requested token cap;
- two attempted generations are not executed concurrently;
- cancellation unblocks a queued request;
- clearing or replacing the model prevents stale results from publishing.

## 9. Phase 4 — object-analysis models and pipeline

Create a focused folder:

```text
RawCull/Intelligence/ObjectAnalysis/
    ObjectAnalysisModels.swift
    ObjectAnalysisResponseDecoder.swift
    ObjectConceptDiscovery.swift
    ObjectInstanceDeduplicator.swift
    ObjectReviewBoardRenderer.swift
    RawCullObjectAnalysisFeature.swift
```

Names may be adjusted to match project conventions, but keep model decoding,
image rendering, inference orchestration, and SwiftUI presentation separate.

### 9.1 Feature state

Use an injected `@Observable @MainActor` feature. Suggested public state:

```swift
@Observable @MainActor
final class RawCullObjectAnalysisFeature {
    var discoveryMode: ObjectDiscoveryMode
    var manualConceptText: String
    var criteria: String

    private(set) var availability: ObjectAnalysisAvailability
    private(set) var phase: ObjectAnalysisPhase
    private(set) var results: [ObjectPhotoAnalysisResult]
    private(set) var failureMessage: String?

    var canRun: Bool { get }
    func analyze(_ files: [FileItem]) async
    func cancel()
    func retryFailed(_ files: [FileItem]) async
    func clearResults()
}
```

All state enums and result structs should be `Equatable` and `Sendable` where
their contents permit it. Store expensive `CGImage` values outside frequently
observed row models, or behind a narrow cache/loader, so progress changes do not
invalidate every image view.

### 9.2 Availability

Object Analysis requires both:

- a validated SAM 3 provider with multi-instance support; and
- a validated Qwen vision model.

Represent combined availability explicitly. The UI must distinguish:

- both models ready;
- SAM 3 missing/invalid;
- Qwen missing/invalid;
- both missing;
- model validation in progress;
- model removed or changed during analysis.

EfficientSAM must not satisfy this feature unless it later gains a separately
verified open-vocabulary multi-instance contract.

### 9.3 Progress phases

Use semantic progress rather than one ambiguous spinner:

```swift
enum ObjectAnalysisStage: Equatable, Sendable {
    case loadingImage
    case discoveringConcepts
    case segmenting(concept: String, conceptIndex: Int, conceptCount: Int)
    case preparingObjectBoard
    case analyzingObjects
    case completed
}
```

Progress should include current filename, completed image count, total image
count, and the current stage. A failure in one photograph should produce a
per-file failed result and continue with the remaining files unless the error
invalidates a required model.

Use the same generation-token pattern as `RawCullQwenAnalysisFeature` so stale
work cannot publish after cancellation or a new run.

### 9.4 Concept discovery

For automatic mode, send the full image to Qwen with a strict schema such as:

```json
{
  "concepts": [
    {
      "query": "bird",
      "displayName": "Bird",
      "reason": "Primary visible subject"
    }
  ]
}
```

Prompt requirements:

- return zero to six concrete visible object categories;
- use short singular noun phrases that SAM 3 can ground;
- prefer photographically meaningful subjects;
- avoid scene adjectives, actions, relationships, and abstract concepts;
- avoid redundant parent/child concepts in the first release, for example
  returning both `bird` and `animal` for the same obvious subject;
- do not infer unseen objects;
- return JSON only.

Decode and validate the JSON strictly. Normalize and deduplicate queries. If
discovery fails, show the failure and allow the user to enter manual concepts;
do not silently invent a default list.

For manual mode, parse comma-separated concepts through
`SegmentationConcept` validation and show invalid entries before starting.

### 9.5 Instance filtering and cross-concept deduplication

After segmentation:

1. discard empty masks;
2. reject scores below a configurable threshold chosen from real-model tests;
3. reject unusably tiny regions while retaining legitimate small subjects;
4. reject masks covering almost the entire image unless the concept and result
   are expected to represent the main subject;
5. prefilter comparisons using bounding-box intersection;
6. compare overlapping masks using mask IoU and containment;
7. merge near-identical instances discovered under synonymous or parent/child
   concepts;
8. retain the higher-scoring mask and preserve the discarded concept names as
   aliases;
9. sort deterministically;
10. cap the board to the strongest eight instances.

Suggested initial duplicate rules for validation, not hard-coded product truth:

- IoU at least 0.85; or
- intersection divided by the smaller mask area at least 0.90.

Add fixtures for nested concepts (`bird`/`animal`), two touching objects, two
separate similar objects, and legitimately nested objects (`person`/`face`) so
the deduplicator does not erase a useful part. The first release should prefer
whole-object concepts during automatic discovery to reduce this ambiguity.

### 9.6 Review-board rendering

`ObjectReviewBoardRenderer` should create one deterministic `CGImage` that
Qwen can interpret with the existing single-attachment runtime.

Recommended board:

- a full-image overview occupying the top or left portion;
- numbered, tightly cropped object panels with 10–15% context padding;
- the original pixels visible inside each crop;
- a high-contrast mask outline rather than a fully transparent background;
- an unambiguous number rendered inside each panel;
- consistent reading order matching result IDs;
- enough surrounding context to recognize occlusion and relationships;
- a neutral background and no decorative effects.

Do not send only masked cutouts. Qwen needs both the original scene and local
detail. Do not use SwiftUI view rendering for this pipeline; use Core Graphics
and, if needed, Core Text so rendering is deterministic, testable, and
independent of view lifecycle.

Bound the final board to the Qwen model's useful image size. Start with a
2,048-pixel maximum side and verify whether the packaged Qwen vision encoder
internally reduces it further. If small objects become unreadable, prefer
fewer/larger panels over a denser board.

### 9.7 Object-analysis response schema

Request one JSON object and no Markdown. Suggested model:

```swift
nonisolated struct ObjectPhotoAssessment: Codable, Equatable, Sendable {
    let imageSummary: String
    let objects: [ObjectAssessment]
    let relationships: [String]
    let strengths: [String]
    let problems: [String]
    let preferredObjectIDs: [String]
    let confidence: Float
}

nonisolated struct ObjectAssessment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let concept: String
    let description: String
    let visibility: ObjectVisibility
    let focusQuality: ObjectFocusQuality
    let expression: String?
    let obstructions: [String]
    let strengths: [String]
    let problems: [String]
    let confidence: Float
}
```

The final schema should use bounded enums where Qwen can follow them reliably.
Validate:

- confidence is within `0 ... 1`;
- every object ID exists on the rendered board;
- duplicate IDs are rejected;
- unknown IDs in `preferredObjectIDs` are removed or fail validation;
- list lengths are capped;
- strings are nonempty after trimming;
- responses cannot create object records for regions not supplied to Qwen.

Preserve the raw model response for diagnostics only when the structured
response is invalid. The UI may show it as a clearly marked free-form response,
matching the existing Qwen behavior, but it must not be treated as structured
object data.

### 9.8 Per-photo result

Each result should retain:

- file ID and filename;
- concepts requested and their source (automatic/manual);
- retained instance descriptors and aliases;
- structured assessment or free-form fallback;
- stage-specific failure information;
- model identities for SAM 3 and Qwen;
- timestamp;
- enough mapping information to reload cached masks for overlays.

Avoid retaining all full-resolution masks and rendered boards indefinitely in
the observable feature. Keep only current-detail images in a bounded memory
cache and reload masks from the object-mask store when necessary.

## 10. Phase 5 — composition and model lifecycle

### 10.1 RawCullAIModelRuntime

Extend `RawCullAIModelRuntime` to own:

- object-mask memory and disk stores;
- `ObjectSegmentationService` when the active provider supports
  `ObjectInstanceSegmenting`;
- a narrow installation/update callback for the object-analysis feature;
- object-analysis availability derived specifically from SAM 3.

The existing selected segmentation model may be EfficientSAM. Decide explicitly
whether Object Analysis always targets installed SAM 3 independently or becomes
unavailable while EfficientSAM is selected. Recommended behavior: Object
Analysis always requires SAM 3 and should not silently use EfficientSAM, while
Deep Review continues honoring the user's selected segmentation backend.

### 10.2 RawCullIntelligenceRuntime

Create exactly one `RawCullObjectAnalysisFeature` in
`RawCullApplicationState.make`, inject the shared Qwen manager and SAM 3 object
service, retain it in `RawCullIntelligenceRuntime`, and pass it down to
`RawCullMainView` and `AIAnalysisView`.

Add identity assertions similar to the current Qwen and Deep Review assertions
so tests catch accidentally duplicated feature/model instances.

### 10.3 Model changes during work

When SAM 3 or Qwen is removed, updated, or switched:

- cancel Object Analysis;
- invalidate the current generation;
- release runtime references backed by the removed asset pack;
- update combined availability;
- retain compatible disk caches, because model fingerprinting prevents their
  accidental reuse;
- show a stable unavailable state instead of publishing a late result.

## 11. Phase 6 — AI Analysis UI

### 11.1 Existing header

Update `AIAnalysisTool` in `RawCull/Views/AIAnalysis/AIAnalysisView.swift`:

```swift
private enum AIAnalysisTool: String, CaseIterable, Identifiable {
    case samCLIP
    case qwen
    case objects
}
```

Use the user-facing title **Objects**. Increase the segmented control width or
allow the header to adapt so all three choices remain legible. Do not add a new
sidebar destination or top-level `TabView` tab.

Cancel irrelevant work when either the image source or selected tool changes.
Switching away from a running mode must not leave its inference active.

### 11.2 ObjectAnalysisView structure

Create a dedicated `ObjectAnalysisView` and separate state-sensitive subviews.
Do not place the whole implementation into `AIAnalysisView.swift`.

Suggested structure:

```text
ObjectAnalysisView
├── ObjectAnalysisControls
├── ObjectAnalysisAvailabilityView
├── ObjectAnalysisProgressView
└── HSplitView
    ├── ObjectPhotoResultsTable
    └── ObjectPhotoDetailView
        ├── ObjectOverviewImage
        ├── ObjectInstanceList
        └── ObjectAssessmentDetail
```

Use `@Bindable` only where a child needs bindings into the injected observable
feature. Use `let` for read-only values. Keep view-owned selection state
`@State private`. Give every `ForEach` and table row a stable model ID.

### 11.3 Controls

Provide:

- **Automatic** / **Specific Concepts** mode control;
- concept text input when manual mode is selected;
- additional analysis criteria;
- **Analyze N Images**;
- **Cancel** while running;
- **Retry Failed** after partial failure;
- **Clear Results** when idle.

Disable controls that would mutate a running request. Snapshot concepts and
criteria at the beginning of a run so editing UI state cannot alter in-flight
work.

### 11.4 Result presentation

The table should show at least:

- filename;
- retained object count;
- discovered/requested concepts;
- confidence;
- status.

The detail view should show:

- original image with numbered mask outlines;
- selectable object rows;
- crop for the selected object;
- concept and aliases;
- visibility and focus/detail assessment;
- expression when applicable;
- obstructions, strengths, problems, and confidence;
- whole-image relationships and summary;
- a clear “No matching objects” state distinct from failure.

Keep RawCull's shared selected-image thumbnail strip below the tool content.

### 11.5 Accessibility

Add dedicated accessibility labels, values, and hints for:

- analysis-mode selection;
- automatic/manual concept mode;
- each object row and its number;
- confidence and status;
- the original image overlay;
- run, cancel, retry, and clear actions.

Do not rely on color alone for mask/object identity. Pair outline colors with
visible numbers and spoken labels. Ensure keyboard selection works in the
results table and object list.

### 11.6 Empty and unavailable states

Provide distinct `ContentUnavailableView` states for:

- no selected/tagged images;
- SAM 3 not installed;
- Qwen not installed;
- invalid model;
- no concepts discovered;
- no matching objects;
- no analysis results yet;
- analysis failure.

When managed downloads are complete, unavailable messaging should point to
**Settings › AI › Download AI Models**, not instruct normal users to locate a
model folder manually.

## 12. Phase 7 — tests

### 12.1 PhotoAIKit tests

- Individual SAM 3 segments survive decoding.
- Union-mask compatibility remains exact.
- Instance ordering and IDs are deterministic.
- Object service resizes all masks consistently.
- Object cache round-trips and invalidates correctly.
- Cancellation prevents partial valid cache writes.
- Arbitrary concepts validate and tokenize correctly.

### 12.2 RawCull unit tests

Add `RawCullTests/ObjectAnalysisFeatureTests.swift` covering:

- automatic concept response decoding;
- manual concept parsing and normalization;
- concept discovery failure;
- zero matching objects;
- multiple concepts and instances;
- cross-concept deduplication;
- object-board ID mapping;
- structured response validation;
- unknown/duplicate object IDs;
- free-form fallback;
- sequential batch progress;
- partial per-file failure;
- cancellation at every stage;
- stale-generation suppression;
- retry of failed files;
- combined SAM/Qwen availability;
- model removal during segmentation and Qwen generation.

Add renderer tests using deterministic small fixtures:

- expected board dimensions;
- crop padding and clamping at image edges;
- mask outline alignment;
- number-to-instance mapping;
- stable output hash where platform rendering is deterministic, otherwise
  pixel/sample assertions.

### 12.3 Composition tests

Extend `RawCullIntelligenceRuntimeTests` and integration tests to prove:

- one shared Qwen manager is used;
- one object-analysis feature is retained;
- SAM 3 installation activates multi-instance analysis;
- EfficientSAM cannot accidentally activate Objects mode;
- managed model replacement cancels stale work;
- object cache paths stay inside RawCull's cache namespace.

### 12.4 UI and accessibility tests

Extend current presentation/accessibility coverage for:

- the third **Objects** analysis selector;
- all unavailable states;
- progress-stage text;
- stable table selection as progress publishes new results;
- numbered object accessibility labels;
- no-object versus failed states;
- keyboard navigation;
- switching analysis modes cancels the previous operation.

### 12.5 Manual validation matrix

Test at least:

| Image type | Expected validation |
|---|---|
| One obvious subject | One stable object and useful detail analysis |
| Several same-category subjects | Every strong match is separately numbered |
| Mixed categories | Automatic discovery yields useful nonredundant concepts |
| Touching/overlapping objects | No false claim when instances cannot be separated |
| Tiny distant subjects | Conservative filtering and clear confidence |
| No requested concept | Successful “No matching objects” result |
| Partially occluded subject | Obstruction is described without inventing hidden detail |
| RAW and JPEG versions | Correct orientation, crop, and mask alignment |
| Model removed mid-run | Cancellation and stable unavailable state |
| Large tagged batch | Bounded memory and correct sequential progress |

## 13. Phase 8 — performance and resource controls

Measure with release builds on supported hardware:

- SAM 3 load time;
- per-concept segmentation latency;
- Qwen concept-discovery latency;
- object-board rendering time;
- Qwen object-analysis latency;
- peak resident memory;
- mask-cache disk growth;
- cancellation latency;
- UI responsiveness while publishing progress.

Initial safeguards:

- process photographs sequentially;
- process concepts sequentially unless profiling proves bounded parallelism is
  safe and materially faster;
- cap automatic concepts at six;
- cap retained objects at eight;
- cap mask inference input using the existing 4,320-pixel policy;
- cap the Qwen board at 2,048 pixels initially;
- keep only one current detail board in memory;
- release temporary crops promptly;
- avoid decoding the same source image separately for each concept;
- check cancellation between every pipeline stage.

Do not add concurrency simply to improve benchmark throughput. Both model
runtimes are large, and predictable memory use is more important than parallel
batch completion.

## 14. Logging and diagnostics

Add privacy-conscious structured logging for:

- run ID and generation;
- filename only where existing logging policy permits it;
- stage transitions and durations;
- number of discovered concepts;
- number of raw and retained SAM instances;
- deduplication counts;
- cache hit/miss;
- response decode success/failure;
- cancellation and model changes.

Never log image pixels, full user prompts, full Qwen responses, or security-
scoped/model URLs at public privacy. Diagnostics exposed in the UI should be
actionable but should not reveal internal paths unnecessarily.

## 15. Documentation and release notes

Update:

- `README.md` AI feature description;
- AI Settings explanatory text;
- privacy wording stating that Object Analysis runs locally;
- App Review notes explaining how to download both models and reach Objects
  mode;
- model/cache documentation if object masks affect “clear cache” behavior;
- release notes with the distinction between “all matches for requested
  concepts” and “guaranteed discovery of every object.”

Do not market the feature as flawless object inventory. Preferred wording:

> RawCull uses Qwen to identify photographically relevant concepts, SAM 3 to
> segment matching visible instances, and Qwen to analyze those numbered
> subjects locally on your Mac.

## 16. Implementation sequence and release order

The release order is: complete Apple-hosted validation; deliver Catalog AI
Triage only if its Section 17 pilot improves review outcomes within the measured
resource budget; then deliver Objects only if Phase 0 passes. The Triage and
Objects features share Qwen, so the generic response and inference
serialization work in Phase 3 should be designed once and reused.

For the Objects feature, apply the work in reviewable changes:

1. **Capability spike** — verify real multi-instance Core AI output, before
   committing to the Objects feature.
2. **PhotoAIKit contracts** — add concept and instance result APIs.
3. **SAM 3 backend** — preserve individual segments while retaining union API.
4. **PhotoAIKit cache/service** — add object-set storage and orchestration.
5. **PhotoAIKit release/pin** — commit, test, publish, and update RawCull pin.
6. **Qwen general response** — add structured generic response and serialization.
7. **RawCull object pipeline** — discovery, deduplication, board rendering, schema.
8. **Runtime composition** — shared services, availability, model lifecycle.
9. **AI Analysis UI** — third mode, controls, progress, table, detail.
10. **Test hardening** — unit, integration, UI/accessibility, cancellation.
11. **Performance pass** — select final caps and thresholds from measurements.
12. **Documentation and manual QA** — privacy, App Review, clean-install test.

Do not combine the PhotoAIKit API change, RawCull pipeline, and UI into one
large commit. The additive package API and compatibility tests should land
first so downstream failures are easier to isolate.

## 17. Catalog AI coverage beyond CLIP and future models

### 17.1 Can AI run on all or most scanned images?

**Yes, technically, but coverage must be a separate post-scan job.** The scan
in `RawCull/Actors/ScanFiles.swift` discovers RAW files and metadata. CLIP
artifacts are generated and reused by `SimilarityScoringModel`; the existing
Qwen feature decodes up to a 2,048-pixel thumbnail and analyzes selected or
tagged files sequentially. Qwen currently has no catalog-wide scheduler,
persistent per-image assessment cache, or measured throughput budget. SAM 3
requires prompted concepts and is substantially more specialized than a
whole-image screening pass. Therefore, simply invoking the existing Qwen or
SAM 3 action for every discovered file would make scan time, memory use, and
failure behavior unpredictable.

The valuable new job is **review triage**: identify frames that merit attention
because of visible subject obstruction, closed eyes where applicable, weak
composition, or a potentially exceptional moment. These are advisory cues;
RawCull's focus/sharpness and burst evidence remain the source for technical
comparison, and the photographer makes the culling decision. CLIP already
covers semantic retrieval; repeating that task with another model offers less
value than adding visual judgments CLIP does not supply.

### 17.2 Proposed coverage ladder for the next feature update

1. **All catalog files:** continue normal metadata, preview, and CLIP artifact
   processing. Build only inexpensive scheduling inputs from existing catalog,
   burst, focus, and sharpness evidence. No Qwen inference on this critical
   browsing path.
2. **Representative majority when useful:** group near-duplicates/bursts and
   queue one or a few representative frames per group, plus unique images.
   Prioritize uncertain groups and frames likely to affect a keep/reject
   decision. This can cover the major *visual variety* of a catalog without
   processing every near-duplicate. Show both image coverage and group
   coverage; do not describe group coverage as per-image analysis.
3. **Optional exhaustive pass:** allow a user to request Qwen screening of all
   eligible images after seeing an estimated time and disk impact based on
   measured local throughput. Resume from durable results and skip matching
   image/model/prompt versions. Make this opt-in until large-catalog tests show
   that it finishes acceptably on supported Macs.
4. **Targeted detail:** run SAM 3 and Objects on images the user opens or marks
   for close comparison. This retains the expensive segmentation where masks
   make a visible difference to culling.

The coverage unit must be explicit: scanned RAW files, successfully decoded
images, Qwen-processed images, and represented burst groups are different
counts. If decoding fails or the model is unavailable, retain the file in the
catalog and report an unprocessed state.

### 17.3 Catalog AI Triage pilot and acceptance gate

Use the already packaged Qwen3-VL-2B model for a narrow pilot with a short,
bounded response schema: visible issue categories, one sentence of evidence,
uncertainty, and whether the cue is relevant to culling. Keep the full-image
thumbnail; do not ask Qwen for precise pixel-level sharpness or face identity.
Run at utility priority with one active inference, pause for foreground Qwen or
Objects work, honor cancellation/model removal, and cap memory. Persist results
with source size/date (or stronger content identity), model fingerprint,
prompt/schema version, and image preprocessing version. Display provenance and
allow retry, clear, and reanalysis.

Benchmark several catalog sizes and photographic subjects on the minimum
supported Mac and a faster Mac. Record decode and inference time per image,
peak resident memory, energy/thermal behavior, cache size, interruption and
resume, and browsing responsiveness. Compare triage cues with photographer
judgments on a held-out set that includes bursts, wildlife, portraits, low
light, and challenging RAW previews. Track useful surfaced frames, missed
keepers, false issue flags, and time saved in review. A new cue must be more
useful than existing focus/sharpness/burst evidence alone. Set numeric release
thresholds from this pilot before enabling broad default coverage; no latency
or accuracy threshold is currently established in the repository.

If the pilot fails on speed or value, ship only selected/tagged Qwen analysis
and revisit lighter specialized models. A background pass should never auto
reject, auto rate, or hide an image based on a generative assessment.

The next feature update can be split into four reviewable changes: (1) a
reproducible Qwen throughput/quality pilot and release thresholds; (2) a
versioned assessment record plus resumable post-scan queue; (3) advisory grid
and burst cues with progress, pause, and clear controls; and (4) large-catalog,
model-removal, and clean-install verification. Ship broad coverage only after
the pilot passes. The user should see which images were actually assessed,
which were represented by another frame, and which remain pending.

### 17.4 Should future versions add other models?

Add a model only for a measured gap in culling quality or speed, with local
inference, redistribution rights, reproducible conversion, managed delivery,
and a clear fallback. Candidate directions, in priority order:

| Candidate | Potential RawCull gain | Decision test |
|---|---|---|
| Small task-specific image-quality or eye-state model | Fast per-image issue detection that could make broad coverage practical | Compare against current sharpness/focus evidence and Qwen pilot on real RAW previews; reject if it adds false rejects or weak coverage. |
| Alternative compact vision-language model | Faster or more reliable structured critique than current Qwen | Same prompts, images, hardware, memory, and review labels; adopt only with a clear gain. |
| DINOv2-style visual feature model | Better grouping of visually similar frames or subject details | Compare burst grouping and nearest-neighbor quality against existing CLIP and Vision features; avoid a second catalog embedding without benefit. |
| SigLIP 2-style image/text encoder | Better multilingual or fine-grained semantic search | Compare retrieval quality and indexing cost against shipped CLIP; this is a possible replacement or optional backend, not a reason to compute two embeddings for every image by default. |

The [official DINOv2 model card](https://github.com/facebookresearch/dinov2/blob/main/MODEL_CARD.md)
describes visual features; the [official SigLIP 2 project](https://github.com/google-research/big_vision/blob/main/big_vision/configs/proj/image_text/README_siglip2.md)
describes image/text retrieval capabilities. Neither source establishes a
RawCull-specific gain. SAM 3 itself is documented as concept-prompted
segmentation by [Meta](https://github.com/facebookresearch/sam3); its value
for this plan still depends on the shipped Core AI runtime returning usable
instances. Future candidates must pass the same product benchmark and asset
provenance checks as existing models. Do not add a model merely because it is
newer or more capable on general benchmarks.

## 18. Completion checklist

### Prerequisites

- [x] CLIP, SAM 3, and Qwen packs are uploaded and ready for internal testing.
- [ ] Signed App Store build and clean-install TestFlight validation complete.
- [ ] Managed SAM 3 and Qwen install, validate, activate, remove, and reinstall.
- [ ] Managed Qwen activation, removal, and cancellation are tested.

### Capability

- [ ] Production SAM 3 returns separable instance masks.
- [ ] Instance box coordinates and ordering are understood.
- [ ] Final instance/concept caps are recorded from measurements.

### PhotoAIKit

- [ ] Open-vocabulary concept contract exists.
- [ ] Additive multi-instance provider contract exists.
- [ ] SAM 3 preserves individual masks, scores, and boxes.
- [ ] Existing union-mask API remains compatible.
- [ ] Object segmentation service and cache are implemented.
- [ ] PhotoAIKit tests pass.
- [ ] RawCull pins the released PhotoAIKit revision.

### RawCull pipeline

- [ ] General Qwen response API exists.
- [ ] Qwen inference is serialized across analysis modes.
- [ ] Automatic and manual concept modes work.
- [ ] Filtering and deduplication are deterministic.
- [ ] Review boards preserve overview, detail, and ID mapping.
- [ ] Structured object responses validate strictly.
- [ ] Cancellation and stale-result suppression work at every stage.
- [ ] Model removal/switching cannot publish stale results.

### UI

- [ ] **Objects** is the third AI Analysis mode.
- [ ] Selected and Tagged sources both work.
- [ ] Availability and empty states are specific and actionable.
- [ ] Progress reports the current semantic stage.
- [ ] Results table and object detail remain responsive.
- [ ] Object numbers do not rely on color alone.
- [ ] Keyboard and accessibility behavior are verified.

### Verification

- [ ] PhotoAIKit focused tests pass.
- [ ] RawCull object-analysis tests pass.
- [ ] Existing Qwen and Deep Review tests pass unchanged.
- [ ] Runtime/composition identity tests pass.
- [ ] Accessibility tests pass.
- [ ] Release build is profiled for memory and cancellation latency.
- [ ] Clean-install manual validation succeeds with Apple-hosted model packs.
- [ ] Documentation and App Review notes are updated.

## 19. Definition of done

The feature is done when a clean-install user can download SAM 3 and Qwen,
select or tag photographs, choose **AI Analysis › Objects**, automatically
discover or manually enter concepts, and receive local structured analysis for
separately numbered SAM 3 instances. Existing SAM 3 + CLIP and Qwen modes must
continue to behave as before, cached data must be model-safe, cancellation must
be reliable, and removing either model during work must leave the application
in a stable, understandable state.
