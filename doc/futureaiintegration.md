# Future AI Integration for RawCull

## Progress update — 2026-07-18

### Quality-first delivery policy

The recommended clean-port approach is now underway on the `RawCullAI` branch in the canonical RawCull repository. AI work should continue in small, independently verifiable slices. Correctness on representative photos, explainable decisions, deterministic cache identity, cancellation, memory behavior, and explicit fallback/error reporting take priority over feature velocity.

A provider or UI control being present does not make a phase complete. A phase is complete only after its application boundary, persisted data, cancellation behavior, failure states, performance, and real-photo output quality have been verified.

### Current phase status

| Phase | Status | Progress so far | Still intentionally deferred |
| --- | --- | --- | --- |
| 1. Platform and composition boundary | Implemented baseline; verified | The app and test targets now require macOS 27 and use Swift 6. PhotoAIKit is pinned and its CLIP, SAM 3, contracts, storage, workflows, and Vision products are linked. RawCull has a single `RawCullAIIntegration` composition root, canonical RawCull-owned paths, actor-owned model-resource managers, typed capability state, mask memory/disk stores, a repository, segmentation service, selector, and a narrow `RawCullAISettingsModel`. Model validation and provider construction are deferred from launch, run outside the main actor, and reuse a metadata-keyed cached result. | The source-controlled mask worker and model-download flow do not exist. The Settings download and saved-data deletion controls are placeholders. Cold-launch and refresh profiling with real installed SAM 3 and CLIP bundles remains required. |
| 2. Similarity | CLIP activation implemented; synthetic coverage verified | CLIP is selected after asynchronous model validation and is enabled by default through a persisted Settings preference. PhotoAIKit performs bounded CLIP artifact generation and whole-batch Vision fallback. RawCull preserves homogeneous batches, dispatches distance semantics to the artifact backend, validates both exact backend descriptors, resets in-memory analysis when selection changes, and persists the selected and fallback descriptors in schema-7 cache signatures. Existing ranking, cancellation, progress, source decoding, and the small subject-label penalty remain intact. | Real installed-model smoke tests, representative Sony ARW quality comparisons, CLIP latency/memory profiling, and threshold calibration remain required. A fallback batch is deliberately reused until explicit reindexing or another cache invalidation. |
| 3. SAM storage and overlays | Storage/repository scaffold only | RawCull configures PhotoAIKit memory and disk mask stores under the canonical cache path and constructs the repository, segmentation service, and selector. Capability reporting distinguishes model, storage, and worker readiness. | There is no supported mask-generation entry point, worker target, inventory/quality flow, RawCull mask source adapter, or cached overlay provider connected to the UI. |
| 4. Subject-aware focus evidence | Not started | The existing Vision/AF focus pipeline remains unchanged by the AI port. | No SAM-specific focus scorer or subject-detail evidence integration has been ported. |
| 5. Deep AI review | Not started | No deep-review behavior has been added to the central view model. | Candidate policy, mask acquisition/evaluation, explainable recommendation output, and user-confirmed application remain future work. |

### Xcode 27 and test verification

This progress snapshot was checked with Xcode 27.0 build `27A5218g`, the macOS 27.0 SDK, and Apple Swift 6.4:

- `make test-smoke` succeeds, including the new model-validation cache, Settings cancellation, and ranking-helper cancellation checks, plus the existing PhotoAIKit artifact, ranking-policy, and cache-migration coverage.
- `RawCullAIIntegrationTests` succeeds for canonical paths, the complete Phase 1 capability surface, persisted Vision evidence scanning, model-cache reuse/invalidation, Settings cancellation, persisted CLIP preference behavior, and the no-op safety of saved-data deletion.
- The app and tests compile with the SDK 27 `@State` macro. The explicit `RawCullApp` state initialization does not currently match a known SDK 27 incompatibility.
- The Settings migration already uses the modern `Tab` API. No current AI view matches the SDK 27 `@ContentBuilder` ambiguity patterns for direct `overlay`/`background`, shadowed SwiftUI types, explicit `TupleView`, or empty builders.

The full Thread Sanitizer suite, the performance target, installed CLIP/SAM resources, real Sony ARW catalogs, memory pressure, and output-quality comparisons were not exercised for this documentation update. The existing synthetic Vision benchmark is useful as a regression guard but is not a substitute for those checks.

### Current quality status before the next feature slice

1. **Move repeated model validation off the main actor or cache it — implemented; real-model profiling remains.** The synchronous composition-root initializer now creates only lightweight placeholder capability/provider state. Actor-owned resource managers perform validation and provider construction during asynchronous Settings refresh, cache the result behind a candidate-tree metadata snapshot, and invalidate it when bundle metadata changes. Settings begins with a typed `checking` state. Cold-launch and repeated-refresh profiling with installed SAM 3 and CLIP bundles is still required before activating either backend.
2. **Finish cancellation propagation for background helpers — implemented and tested.** Saved-evidence scanning is now a directly awaited `@concurrent` operation with cancellation checks around directory, file, decode, and embedding-loop boundaries. Similarity ranking uses an explicitly owned task because it needs supersession; replacement and reset cancel it, a cancellation handler forwards caller cancellation, and a generation check prevents stale state commits.
3. **Do not let remaining placeholder controls look production-ready.** The CLIP toggle is now connected and persisted. The SAM download button and saved-data deletion button remain intentionally inert; keep that limitation unmistakable until each action has typed progress, structured errors, cancellation, and tests.
4. **Make the AI Settings surface localization- and accessibility-ready before activation.** The project has no String Catalog, and the new view builds several user-facing messages as runtime `String` values or concatenated fragments, so SwiftUI cannot extract them for localization. It also relies heavily on fixed point-size fonts. Move user-facing state to `LocalizedStringResource` or localizable SwiftUI literals, add translator context for dynamic messages, and prefer semantic text styles as the UI stabilizes.
5. **Revisit test serialization.** `PhotoAIKitSimilarityMigrationTests` is marked `.serialized` even though its file fixtures use unique temporary roots. Confirm that Vision or another dependency truly requires serialization; otherwise remove it so Swift Testing can retain parallel execution. If it is required, document the invariant beside the trait.
6. **Keep SwiftUI sections as real view boundaries.** The Settings implementation already extracts its major cards into separate `View` types. As controls gain real state, also extract state-driven helper fragments such as the delete control instead of growing computed `some View` properties on the parent.

#### What each quality item means and what remains

These are quality gates for activating the next AI features, not six known user-data failures. Items 1 and 2 were implemented in the 2026-07-17 update and have focused automated coverage. Their remaining device/resource measurements, and the eventual code changes for items 3–6, must still be tested and profiled with the macOS 27/Xcode 27 toolchain used by this branch.

1. **Move repeated model validation off the main actor or cache it.**

   **Previous risk:** `RawCullApp.init()` created `RawCullAIIntegration` synchronously and provider setup could locate, fingerprint, and validate SAM 3 and CLIP bundles on the main actor. Capability refresh then repeated that work. A manifest cryptographic fingerprint can hash the full model asset, so large installed models could stall cold launch or “Check Again.”

   **Implemented change:** `RawCullAIModelResourceManager` is now an actor. Its `load()` operation captures a deterministic metadata snapshot of each candidate tree, reuses the cached capability and provider while that snapshot is unchanged, and asks PhotoAIKit to validate again only after a change. `RawCullAIIntegration` starts with an unavailable SAM provider and typed `checking` states, then concurrently awaits the SAM 3 and CLIP managers from `refreshCapabilities()`. The returned providers and capability snapshot are installed on the main actor only after validation completes. `RawCullAISettingsModel.refresh()` runs capability refresh and evidence scanning as structured child operations and publishes their results together.

   **Verification and remaining work:** `RawCullAIIntegrationTests` verifies the initial `checking` state, asynchronous missing-resource resolution, cache reuse by provider identity, and invalidation after the asset metadata changes. The full smoke suite and a clean app build pass with Xcode 27. PhotoAIKit's current CLIP/SAM provider initializers can still validate a newly discovered bundle once more during first provider construction; that work is also on the resource-manager actor and is cached for later refreshes. Measure cold launch, first refresh, repeated unchanged refresh, and changed-bundle refresh with real SAM 3 and CLIP assets in Instruments before declaring the performance gate complete or deciding whether PhotoAIKit should accept a prevalidated `ModelResource` without revalidation.

2. **Finish cancellation propagation for background helpers.**

   **Previous risk:** The main similarity-indexing operation already owned its task and cooperatively stopped work, but Settings evidence scanning and similarity ranking created inner unstructured concurrent tasks. Cancelling the caller prevented some final state commits without automatically cancelling those helpers, so disk or CPU work could continue after its result became irrelevant.

   **Implemented change:** `RawCullSavedBurstEvidenceScanner.scan()` is now an async throwing `@concurrent` function awaited directly by the Settings refresh operation. Cancellation throws through the structured call path, and the Settings model's generation-aware `defer` clears the loading flag only for the current refresh. Ranking retains an independent task because a newer anchor must supersede older computation; `SimilarityScoringModel` stores that task, cancels it on replacement/reset, forwards caller cancellation with `withTaskCancellationHandler`, checks cancellation within the distance loop, and guards the final commit with both task and generation state. The parent `findSimilarToSelected()` also avoids re-sorting after cancellation.

   **Verification:** Focused Swift Testing coverage uses deterministic probes to verify that cancelling Settings refresh reaches the evidence helper and clears `isScanningSavedBurstData`, and that cancelling ranking reaches the owned distance helper without replacing the previous anchor or distances. The existing indexing cancellation and supersession tests remain in the smoke selection.

3. **Do not let placeholder controls look production-ready.**

   **What is happening now:** The Settings CLIP switch persists its preference and updates the similarity feature model after capability refresh. It selects validated CLIP resources when available and Vision otherwise. The SAM 3 download button still displays an informational alert, and saved-data deletion remains a deliberate no-op. Those two controls still resemble working product actions.

   **What the fix involves:** Until implementation begins, hide or clearly disable the remaining placeholders with nearby text such as “Not available in this build.” Model download needs a defined trusted source, destination and disk-space checks, progress, cancellation, temporary staging, integrity validation, atomic installation, cleanup, and actionable errors. Saved-data deletion needs an exact inventory of what is in scope, protection for original photos and unrelated caches, progress/cancellation, partial-failure reporting, and a capability/evidence refresh afterward. Each operation should expose a typed state such as idle, running with progress, succeeded, cancelled, or failed instead of inferring behavior from display strings.

4. **Make the AI Settings surface localization- and accessibility-ready before activation.**

   **What is happening now:** `AISettingsTab.swift` contains many user-facing values as runtime `String` properties and assembles several sentences with `+`. SwiftUI and a String Catalog cannot reliably extract or reorder those fragments for translation. Count labels also create English plurals by appending `s`. The view uses many fixed `.system(size:)` fonts, which makes it harder for the interface to adapt consistently to accessibility text-size preferences. Some status rows are grouped for assistive technology, but the full behavior of progress, disabled placeholders, changing status, and destructive actions has not yet been audited.

   **What the fix involves:** Add the project's first String Catalog and establish a naming convention. Keep fixed UI literals directly in localizable SwiftUI initializers, and carry model-provided user-facing text as `LocalizedStringResource` rather than plain `String`. Replace concatenated sentences with single interpolated resources so translators can reorder placeholders, use catalog plural variations for counts, and add translator comments for terms such as “burst,” “embedding,” “Vision,” and “model.” Replace fixed point sizes with semantic styles such as `.headline`, `.body`, `.callout`, and `.caption` where possible; use scalable metrics only where a custom size is truly necessary. Audit VoiceOver labels, values and hints, keyboard navigation, focus order, disabled-state explanations, progress announcements, color-independent status cues, and the destructive confirmation flow. Completion requires pseudolocalization or deliberately long translations, right-to-left layout checks where applicable, larger accessibility text, VoiceOver and keyboard-only use, and tests or previews for each typed operation state.

5. **Revisit test serialization.**

   **What is happening now:** Swift Testing normally runs independent tests in parallel, but the `.serialized` trait forces every test in `PhotoAIKitSimilarityMigrationTests` to run one at a time. The suite creates unique temporary directories and catalog paths, so its file fixtures do not obviously require ordering. Serialization may therefore be hiding an assumption that no longer exists and makes the suite slower. On the other hand, Vision initialization, process-wide provider state, resource pressure, or the performance benchmark could still make concurrent execution unsafe or too noisy; that must be demonstrated rather than guessed.

   **What the fix involves:** Temporarily remove `.serialized` on an investigation branch and run the suite repeatedly with randomized ordering, alongside other relevant suites, and under Thread Sanitizer. Look for shared static state, singleton mutation, common cache locations, framework requirements, and timing thresholds affected by concurrent Vision work. If failures appear, isolate the shared resource per test or move only the genuinely exclusive/performance case into a narrowly serialized suite or test plan. If the framework truly requires exclusive access, keep `.serialized` and document that invariant beside the trait, including what would allow its removal later. Completion means parallel runs are deterministic and clean, or there is a specific, reproducible reason for the smallest possible serialized boundary.

6. **Keep SwiftUI sections as real view boundaries.**

   **What is happening now:** The major AI cards are already separate `View` structs, which gives SwiftUI useful identity and invalidation boundaries. The delete control is still a computed `some View` property on `AISettingsTab`, and its confirmation state also lives on the parent. A computed view property organizes source code but is expanded as part of the parent's body; it is not an independently diffable view. As deletion gains progress, errors, cancellation, confirmation variants, and accessibility behavior, the parent would become responsible for an increasing amount of unrelated state and would re-evaluate that whole fragment whenever any parent-observed state changes.

   **What the fix involves:** Extract a dedicated control view when real deletion behavior is added. It should own presentation-only state such as whether the confirmation dialog is visible and receive the narrowest operation state and action it needs. Keep deletion policy and file-system work in `RawCullAISettingsModel` or a narrower service rather than moving business logic into the view, and do not let the child reach into `RawCullAIIntegration`. Apply the same rule to the downloader or other state-heavy fragments as they grow: simple static decoration may remain a helper, while independently changing or logically distinct UI becomes a `View` type. Completion means the parent remains mostly composition, each child has clear inputs and local presentation state, and operation-state tests or previews can exercise the child without constructing the whole Settings tab.

## Recommendation

Use a modified version of the clean-port approach:

**Keep RawCull as the canonical application and continue macOS 27 AI integration on the `RawCullAI` branch inside the RawCull repository. Do not create another permanent RawCullAI repository.**

Optionally, that branch can contain a `RawCullAI` target so RawCull and RawCullAI can be installed side by side during beta testing. Both targets should reference the same physical source files.

Use RawCullSAM3 as a reference implementation and source of selected AI components—not as the future application base and not as a tree that must be made identical to RawCull.

## Why this is the safest approach

The reusable AI architecture is now in good condition. PhotoAIKit has clean products for contracts, backends, storage, and workflows, with model fingerprints and actor-owned services. Its macOS 27 and Swift tools 6.4 requirements are explicit in its `Package.swift`.

The RawCullSAM3 application integration is promising, particularly its `RawCullAIContainer` composition root, but its application layer is not yet a cleaner replacement for RawCull.

The source comparison found:

| Measure | RawCull | RawCullSAM3 |
| --- | ---: | ---: |
| Application Swift files | 148 | 195 |
| Application Swift lines | 23,923 | 28,007 |
| Common Swift paths | 139 | 139 |
| Identical common paths | 77 | 77 |
| Different common paths | 62 | 62 |
| Swift Testing tests | 222 | 269 |

The 62 changed shared files look worse than they really are: 40 differ by no more than 25 lines. Many of the 56 RawCullSAM3-only paths are small type extractions or file moves rather than AI implementations.

The important differences are concentrated in risky places:

- Deep-review orchestration remains inside the roughly 1,300-line `RawCullViewModel+BurstGrouping.swift`.
- Subject-aware scoring has expanded `FocusMaskEngine+Scoring.swift` to roughly 1,370 lines.
- Some views access `aiContainer` directly, coupling UI code to the application's composition root.
- Helper state is inferred from exact status strings instead of a typed state model.
- The referenced `RawCullSAM3MaskBuilder` executable has no source-controlled target or implementation.
- Several `try?` paths hide whether degradation came from a missing model, invalid resources, decoding, inference, or cache failure.

These issues are fixable, but they make a whole-tree consolidation into RawCullSAM3 unnecessarily risky.

The two repositories also have no common Git commit ancestry. Synchronizing them is therefore manual reconciliation rather than an ordinary Git merge. Creating a third permanent repository would reproduce this problem.

## Code-quality assessment

### PhotoAIKit

PhotoAIKit is the correct reusable boundary. It now owns:

- SAM 3 and CLIP providers.
- Vision feature-print fallback.
- Model capabilities, resource resolution, and fingerprints.
- Similarity artifacts, persistence codecs, and fallback indexing.
- Subject-mask storage, catalogs, quality analysis, and selection.
- Segmentation batching and transport events.

Its use of separate contracts, backends, workflows, and storage products is a strong architectural choice. Generic AI behavior should continue to move there when it is genuinely reusable.

RawCull-specific focus algorithms, culling policy, file models, security-scoped access, application paths, and UI behavior should remain outside PhotoAIKit.

### RawCullSAM3

RawCullSAM3 is a credible reference integration. Its strongest application-level decisions are:

- A central AI composition root.
- Narrow protocols between RawCull file models and PhotoAIKit services.
- Package-owned inference and cache implementations.
- Explicit CLIP-to-Vision fallback.
- Model-aware artifact invalidation.
- Additional AI-specific Swift Testing coverage.

Its weakest area is feature isolation above the composition root. AI state and orchestration still leak into the central view model and several large UI and focus-scoring files.

### RawCull

RawCull should remain the canonical base because it contains the current non-AI product development and has the smaller application tree. At the time of the original recommendation, its smoke test suite succeeded under Xcode 26.6. The current `RawCullAI` integration branch is now separately verified on Xcode 27 as recorded in the progress update above.

The suggested test-target migration has been completed on `RawCullAI`: the test target now uses Swift 6, complete strict-concurrency checking, and a macOS 27 deployment target. This should remain an explicit integration-branch requirement rather than silently changing the production branch's support policy.

## Remaining work from the original pre-integration checklist

The macOS 27 toolchain is now in use on `RawCullAI`, so the earlier “until the toolchain is ready” guidance is superseded. The still-relevant repository controls are:

- Continue normal production development on RawCull's production branch and AI integration on `RawCullAI`.
- Treat RawCullSAM3 only as a reference/donor; do not resume whole-tree synchronization.
- Continue reusable inference, storage, cache, identity, and workflow work in PhotoAIKit.
- Do not spend time making every non-AI RawCullSAM3 file match RawCull.
- Do not add additional AI orchestration directly to `RawCullViewModel`.
- Decide whether SAM mask generation will use a source-controlled helper executable or an in-process pipeline.
- Measure memory use before choosing in-process SAM execution for production.

The missing helper decision is a hard prerequisite. If retaining the external worker design, it needs:

- A source-controlled executable target and entry point.
- Request decoding and security-scoped resource lifetime management.
- Raw decoding and segmentation-pipeline execution.
- Progress, failure, cancellation, partial-result, and exit-code handling.
- Build and packaging verification.

## Suggested repository and branch arrangement

During the beta period, use one Git history:

```text
RawCull repository
├── main                         macOS 26 production
└── RawCullAI branch             macOS 27 AI integration
    ├── shared RawCull sources
    ├── RawCullAIIntegration
    ├── optional RawCullAI target (not added)
    └── PhotoAIKit dependency
```

Regular RawCull development can be merged into the AI branch using normal Git history. The branch diff should then contain only intentional AI integration and macOS 27 changes.

If side-by-side beta testing is useful, add a second application target on the AI branch with a separate bundle identifier. Do not duplicate the shared Swift source tree for that target.

After macOS 27 becomes the RawCull minimum deployment target, merge the integration branch into the canonical application and retire the temporary target if one was added. If RawCull must continue supporting macOS 26, retain a separate target or investigate availability-gated backends once Xcode 27 behavior can be tested properly.

## Integration order

### Phase 1: Platform and composition boundary — baseline implemented

- Raise the integration branch to the required macOS and Swift toolchain baseline.
- Add the PhotoAIKit products.
- Preserve RawCull's bundle identifier, settings keys, cache directories, and Application Support paths.
- Port model-location adapters and a RawCull-owned AI composition root.
- Introduce structured capability state for CLIP, SAM 3, Vision, mask storage, and worker availability.

### Phase 2: Similarity — CLIP activation implemented; real-model verification pending

Port CLIP similarity first because it has the narrowest visible feature boundary and RawCull already has Vision-based similarity behavior.

- Port RawCull-aware image decoding.
- Store descriptor-complete PhotoAIKit similarity artifacts.
- Use whole-batch CLIP-to-Vision fallback. Implemented.
- Include model fingerprints and artifact versions in cache signatures.
- Validate complete descriptors for both disk and in-memory reuse.

### Phase 3: SAM storage and overlays — storage scaffold only

- Configure package memory and disk stores using RawCull-owned locations.
- Port `FileItem` and `AIImageSource` adapters.
- Port mask inventory and quality metadata.
- Implement the selected helper or in-process generation path.
- Expose cached overlays through a narrow provider rather than `aiContainer` traversal from views.

### Phase 4: Subject-aware focus evidence — not started

Keep focus policy in RawCull, but extract SAM-specific subject scoring from the large focus engine into a component such as `SubjectMaskFocusScorer`.

The component should accept decoded focus evidence and a subject mask, then return explainable subject-detail evidence. It should not mutate ratings or choose winners.

### Phase 5: Deep AI review — not started

Port deep review last and place its workflow in a RawCull-owned `DeepAIReviewFeature` or service.

The service should:

- Select candidate files and prompt policy.
- Ask PhotoAIKit to acquire and evaluate masks.
- Ask RawCull focus scoring for subject-detail evidence.
- Return a proposed winner, confidence, reasons, and cautions.

`RawCullViewModel` should only start or cancel the operation and apply user-confirmed actions.

## Required application-boundary improvements

During the port:

- Replace Boolean and string-based helper state with a typed enum such as `idle`, `preparing`, `running(progress)`, `completing`, `failed(error)`, and `completed`.
- Stop views from accessing the AI composition root directly.
- Keep the composition root hidden behind feature models and narrow protocols.
- Preserve structured operational errors instead of collapsing failures with `try?`.
- Separate deep-review orchestration from burst-management state.
- Separate SAM subject scoring from the general focus-scoring implementation.
- Keep AI-produced decisions explainable and reversible.

## Testing strategy

- Preserve all current RawCull tests during the port.
- Port AI-specific RawCullSAM3 tests individually rather than replacing complete test files.
- Keep generic provider, serialization, storage, fallback, identity, and concurrency tests in PhotoAIKit.
- Keep RawCull adapter, worker-lifecycle, focus-evidence, ranking, and UI-state tests in RawCull.
- Keep the migrated `RawCullAI` test target on Swift 6 with complete strict-concurrency checking.
- Keep tests parallel-safe and isolate file-system/cache state per test.
- Run a CI matrix for stable RawCull and the macOS 27 AI branch while both exist.
- Add representative real-photo validation for correctness, memory pressure, fallback rates, cancellation, and cache invalidation.

## Final decision

The best long-term result is **one RawCull codebase with optional AI capabilities**, not two synchronized application repositories.

Therefore:

- Do not use RawCullSAM3 as a whole-tree replacement for RawCull.
- Do not create a third permanent application repository.
- Keep RawCull as the canonical integration destination.
- Use RawCullSAM3 as a reference and donor for deliberate AI changes.
- Continue the clean AI port on the macOS 27 `RawCullAI` branch within the RawCull repository.
- Retire RawCullSAM3 after feature parity and deliberate data migration are complete.

This preserves the strong PhotoAIKit boundary, avoids importing unrelated fork drift, and gives RawCull a maintainable foundation for future local AI models.
