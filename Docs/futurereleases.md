# RawCull future releases

Planning baseline: September 30, 2026; source declares **3.2.8, build 398**.
This is a proposed product roadmap based on the checked-in application and test
code, not a release commitment or an assertion about current App Store status.
No app tests or performance benchmarks were run for this document. Priorities
are engineering/product judgments; release numbers and dates should be assigned
only after scope and validation are agreed.

## Recommendation

Make the next releases strengthen the photographer's complete workflow:
**review quickly, trust every decision, recover work, and carry selections into
an editor**. RawCull already has substantial local AI functionality. Improving
handoff and everyday reliability should come before adding larger models or
more assessment modes.

For RawCull's intended professional use, the essential requirements are fast
keyboard review, dependable ratings and rejection, reversible bulk actions,
accurate detail comparison, durable decisions, predictable export, and a tested
camera support matrix. AI should supply evidence while the photographer retains
control. Cloud sync, image editing, and automatic deletion are not prerequisites
for that culling workflow.

## What the current code already provides

| Capability | Code evidence | Implication for the roadmap |
|---|---|---|
| RAW discovery and preview pipelines | `RawCull/Actors/DiscoverFiles.swift`, `RawCull/Model/RawImageLoading.swift`, `RawCull/Actors/ThumbnailLoader.swift` | Discovery uses `RawFormatRegistry.allExtensions`; validate actual format/camera behavior rather than claiming discovery is ARW-only. |
| Ratings, tagging, saved decisions and recovery | `RawCull/Model/ViewModels/CullingModel.swift`, `RawCull/Model/JSON/WriteSavedFilesJSON.swift`, `RawCull/Main/RawCullApp.swift` | Debounced saves, atomic JSON writes, a backup, retry/flush, and quit recovery already exist. Extend portability and recovery rather than rebuilding persistence from scratch. |
| Burst recommendations and manual control | `RawCull/Intelligence/BurstAnalysis`, `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift` | Confidence, cautions, winner overrides, review states, and last-burst-action undo already exist. Broader undo and group correction remain useful extensions. |
| Comparison and detail review | `RawCull/Views/ComparisonGridView`, `RawCull/Model/ViewModels/ZoomSessionModel.swift`, `RawCull/Model/ViewModels/LoupeSessionModel.swift` | Improve consistent controls and validate source/zoom accuracy across existing surfaces. |
| Sharpness, AF and subject detail | `RawCull/Model/ViewModels/FocusandSharpness`, `RawCull/Intelligence/DeepReview` | Head/face presets and subject masks already exist; objective eye-quality validation is a separate capability. |
| Search, segmentation, photo/object assessments | `RawCull/Intelligence/Similarity`, `SemanticSearch`, `Qwen`, `ObjectAnalysis` | The app already has CLIP, SAM 3, Qwen, and structured eye-state output. Do not label generic face or eye analysis as entirely missing. |
| Optional managed model downloads | `RawCull/Intelligence/ModelManagement`, `RawCullModelDownloader` | Focus on update compatibility, understandable download states, and recovery. See [asset maintenance](assets.md). |
| Copy and JPEG export | `RawCull/Model/ParametersRsync`, `RawCull/Actors/ExtractAndSaveJPGs.swift` | Extend interoperability and completion verification around existing workflows. |
| Tests and accessibility presentation | `RawCullTests`, `RawCullReleaseTests`, `RawCull/Model/Accessibility` | Build on existing coverage; unit tests alone cannot establish real-model quality or professional workflow speed. |

The inspected application does not expose an XMP handoff implementation or a
general multi-step undo/redo system. Some behavior lives in pinned external
packages, so package changes should be investigated before assigning an
implementation to RawCull itself.

## Proposed release sequence

| Stage | Theme | Priority | Exit condition |
|---|---|---|---|
| Next maintenance release | Release evidence, model update safety, workflow regressions | P0 | A reproducible App Store candidate with documented app/pack compatibility and recovery results. |
| Following workflow release | XMP handoff, consistent batch decisions, general undo/redo | P1 | A complete keyboard cull can be safely reversed and imported into a chosen editor. |
| Following reliability/performance release | Portable catalog decisions, relinking, large-shoot budgets, format qualification | P1 | A large catalog survives interruption and relocation while meeting measured review targets. |
| Following intelligence release | Calibrated ranking, portrait review, user corrections to groups | P2 | Evaluations demonstrate useful gains without increasing confident wrong recommendations. |

P0 protects shipping reliability; P1 is central to the professional workflow;
P2 improves assistance after those foundations are proven. Keep each stage small
enough to release independently, and pull a discovered data-loss or incorrect
export issue into P0 immediately.

## 1. Release confidence and safe model updates — P0

**Motivation.** Downloaded model weights can change independently of the app.
`RawCullAIModelDownloadService.swift` requests the latest available pack during
availability checks. An old app must not unexpectedly receive an incompatible
tokenizer, tensor interface, or model layout. Existing provenance validation is
valuable, but packaging correctness does not establish inference correctness.

**Recommended work.** Record tested app/pack pairs and compatible older app
versions; test updates from installed version 1 as well as clean installations.
Audit artifact compatibility in `PerFileAnalysisArtifactStore`,
`BurstAnalysisCache`, and similarity signatures so an upstream model change
invalidates only affected analysis. Preserve ratings, tags, and manual winners.
Use a distinct pack ID for replacements that cannot serve released clients.
Make model errors actionable: distinguish missing files, validation failure,
insufficient space, interrupted transfer, and activation failure.

Correct release documentation drift: the root README's Release section still
uses the Developer ID/DMG workflow, while `Docs/assets.md` records the App Store
path. `ModelAssets/README.md` retains historical review-pending wording. Reconcile
these against actual App Store Connect evidence without inferring review from
successful processing.

**Done when.** Each affected model passes real inference, install/update,
cancel/retry, remove/reinstall, relaunch, and offline-use checks through
TestFlight. Cache invalidation is demonstrated with changed model inputs. The
release record identifies the previous known-good app and packs. Reuse
`RawCullAIModelDownloadsTests`, `TypedAIPersistenceMatrixTests`, and the release
integration harnesses for relevant checks.

## 2. Editor handoff through XMP and an export manifest — P1

**Motivation.** Ratings stored in RawCull's `savedfiles.json` and copying selected
RAW files are useful, but a professional workflow continues into an editor.
Decisions should travel with photographs without requiring the user to repeat
the cull. No XMP writer was found in the inspected application source.

**Recommended work.** Introduce an explicit sidecar export service independent
of the view layer. Start with star ratings and clearly defined pick/reject
mapping, then color labels and keywords. Keep unreviewed distinct from rejected.
Offer a preview of changed files, destination selection, collision handling, and
an export manifest listing decisions and failures. Preserve unknown metadata in
existing sidecars; never overwrite a RAW file to transfer ratings. Define
conflict handling when editor and RawCull decisions disagree.

Editor-specific flags and labels must be mapped and tested against the chosen
editor's documented behavior; do not promise universal pick/reject compatibility.
Start with one supported handoff, then add others from real user demand.

**Done when.** A fixture shoot imports into the chosen editor with the expected
ratings and supported flags, existing metadata survives a round trip, repeated
exports are idempotent, and unwritable/colliding sidecars produce an itemized
report. Copied RAWs retain associated sidecars where requested.

## 3. Consistent decisions and general undo/redo — P1

**Motivation.** The code has `lastBurstUndoEntry` and an undo action for bursts.
That is narrower than reversing a session of ratings, tags, rejections, and
batch edits across grid, loupe, and comparison views. Fast review encourages
mistakes; recovery should be equally fast.

**Recommended work.** Route decision mutations through shared commands with
before/after values, use a bounded multi-step history, and connect standard
Undo/Redo menu actions. Treat each bulk operation as one undoable change.
Preserve file identity and selection when filters hide a newly rejected frame.
Standardize keyboard actions and visible shortcut help across review surfaces.
If color labels are added, give them text and symbols as well as color.

**Done when.** Rate/tag/reject a multi-selection, undo and redo across views,
change filters, and confirm persistence after relaunch. Verify focus handling
while a text field is active and VoiceOver announcements after decisions.
Undo must reverse user decisions without discarding reusable image analysis.

## 4. Portable catalogs, relinking, and durable recovery — P1

**Motivation.** Current saved decisions use catalog URLs and file names;
`BurstAnalysisCoordinator+CacheCompatibility.swift` remaps cached files by path.
Atomic writes and a backup already protect ordinary saves, but a moved shoot or
renamed volume needs an explicit identity and relinking policy.

**Recommended work.** Add export/import of a versioned catalog decision file,
relative paths, source identity evidence, and a relink workflow for relocated
folders. Keep user decisions separate from disposable analysis caches. Detect
ambiguous matches rather than matching duplicate names silently. Offer visible
backup restore, migration diagnostics, and a recoverable last reviewed position.
Evaluate whether whole-store JSON persistence meets measured catalog-size
requirements before choosing SQLite or another storage replacement.

**Done when.** A catalog can move to another volume and recover its decisions;
same-named files in nested folders remain distinct; ambiguous or modified files
require resolution. Interrupted saving, corrupt input, old-schema migration,
and failed relinking do not destroy the last valid decision record.

## 5. Measured speed and trustworthy comparison — P1

**Motivation.** RawCull already has caches, preload admission, memory monitoring,
and dedicated comparison/zoom models. Professional speed needs measurements on
real shoots, especially while AI and preview decoding compete for resources.

**Recommended work.** Establish reproducible 1,000-, 10,000-, and larger-file
fixtures on a baseline Apple Silicon Mac and a faster Mac. Measure cold/warm
scan, first visible thumbnail, key-to-next-frame latency, full-detail readiness,
peak memory, cache growth, and cancellation delay. Prioritize visible previews
and user input over background analysis. Verify synchronized comparison zoom
and pan, orientation, crop position, and the displayed preview/developed RAW
source; expose incomplete or lower-resolution detail clearly.

Suggested initial product targets, to validate before committing: warm
key-to-visible-preview p95 below 100 ms and cancellation feedback within one
second on the baseline machine. Set separate cold decode and full-detail budgets
from measured camera files. Publish fixture, hardware, OS, and source settings
with results; these numbers are targets, not current measurements.

**Done when.** Rapid navigation stays responsive during background work,
repeated runs stay within agreed memory/disk budgets, and comparison renders the
same subject location accurately. Use `make test-performance` plus manual
end-to-end measurement; cache unit tests do not substitute for UI latency.

## 6. Camera qualification and dependable export — P1

**Motivation.** Extension discovery through RawParserKit does not guarantee every
camera variant's orientation, focus points, embedded JPEG, or developed preview.
RAW support should be a tested promise. Copy completion should also give users
evidence they can safely proceed to the next stage.

**Recommended work.** Maintain a camera/format matrix with separate columns for
metadata, orientation, embedded preview, developed RAW, AF points, and known
limits. Qualify Sony and Nikon fixtures first, then expand by demand. Keep
unsupported AF evidence visibly unavailable. Extend the existing rsync copy
report with expected/copied/skipped/failed counts, sidecar association, filename
collision policy, and an optional checksum verification mode. Make interruption
and destination reconnection recoverable.

**Done when.** Supported fixtures pass each advertised capability; corrupt and
unsupported files are reported without aborting a whole shoot. Export tests
cover existing destination files, duplicate basenames, interruption, and
verification failure. A successful transfer report must account for every
selected file before it encourages the user to remove a source copy.

## 7. Calibrated AI, portrait checks, and editable groups — P2

**Motivation.** Burst scores already expose reasons/cautions, Deep Review has
head/face modes, and Qwen can return `eyesOpen`. These are useful starting points,
but structured output or numeric confidence alone does not prove photographic
accuracy. Group portraits need per-person evidence; sharp backgrounds and soft
eyes can confuse global detail scores.

**Recommended work.** Build a consented, versioned evaluation set covering
portraits, wildlife, motion blur, high ISO, intentional shallow depth of field,
occlusion, and exposure extremes. Record photographer preferences and measure
pairwise winner agreement, abstention, and confident wrong choices. Compare
changes against the current implementation and a sharpness-only baseline.

Add subject/face selection and consistent eye/head crops; distinguish measured
local detail from a Qwen opinion. For group portraits, associate eye/expression
findings with each visible person and support “unknown.” Keep intent-sensitive
criteria adjustable. Let users split/merge groups and choose alternate winners;
invalidate group recommendations while retaining reusable per-file analysis.
Do not silently reject photographs based solely on model output.

**Done when.** Evaluation shows useful quality or time improvements, failure
cases remain visible, uncertain results abstain, and all suggestions can be
overridden. Explain which preview and subject supplied the evidence. Preserve
manual corrections across rescans and model updates. A new model ships only
when quality, latency, memory, storage, licence, and compatibility evidence
justify its added cost.

## Release gates and scope discipline

Every release should exercise the complete open → review → decide → relaunch →
export workflow on a representative shoot. Run relevant focused tests during
implementation, then the required smoke/full checks for the candidate. Record
skips with reasons and run real-model release probes when inference changes.
Include keyboard-only and VoiceOver review, failed saves, disconnected volumes,
unsupported RAWs, and low-space download/export cases as applicable.

Keep the core culling flow available without optional models and without a
network connection once files are local. Preserve local-photo privacy. Defer a
full RAW editor, cloud collaboration, and a larger default model until workflow
feedback demonstrates a concrete need; each introduces maintenance or resource
cost without necessarily making a photographer's first cull faster.
