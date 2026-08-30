# RawCull macOS 26 Vision-only edition

Status: design and implementation plan only. This document does not authorize or
contain production code changes.

## Executive decision

An updated RawCull that runs on macOS 26 and uses only Apple's built-in Vision
feature prints is feasible.

The recommended implementation is a dedicated Vision-only release target or
release branch based on the current RawCull code, not a collection of runtime
`if #available` checks scattered through the application. The Vision edition
should keep the current non-model culling workflow and current modular similarity
orchestration, but remove CLIP, semantic text search, SAM/EfficientSAM Deep Review,
AI model discovery and downloads, Managed Background Assets, and the model-specific
package products and resources.

Swift compiler and availability directives can help a shared source tree support
both editions, but they do not by themselves make the present macOS 27 target
buildable for macOS 26. Dependencies, linked products, extension targets, and
deployment targets must also be separated at build time.

## Meaning of "Vision-only"

Vision feature prints are produced by an Apple framework and are themselves based
on machine-learning technology. In this plan, "remove AI-based code" therefore
means removing RawCull's separately supplied model stack and its product features:

- DataComp and OpenAI CLIP models and inference;
- CLIP text-to-image semantic search;
- SAM 3 and EfficientSAM segmentation;
- Deep Review and subject-mask generation/storage;
- model validation, selection, licensing, download, and deletion;
- Managed Background Assets model delivery;
- `coreai-models`, tokenizer/transformer, and other dependencies present only for
  those model backends.

The following Apple-provided analysis remains in scope:

- Vision feature prints for image-to-image similarity and burst grouping;
- Vision saliency/classification already used by `PhotoAnalysisKit` for focus and
  sharpness analysis;
- normal ImageIO, Core Image, Metal, AppKit, and SwiftUI image processing.

If "no machine learning of any kind" is the actual requirement, Vision feature
prints and Vision saliency would also have to be removed. That would be a different
product and would require a non-Vision similarity algorithm.

## Current repository baseline

The current `version-3.2.0` branch has these relevant properties:

- The RawCull app and tests have `MACOSX_DEPLOYMENT_TARGET = 27.0`.
- The app links seven `PhotoAIKit` products:
  `CoreAICLIPBackend`, `CoreAISAM3Backend`, `CoreAIEfficientSAMBackend`,
  `PhotoAIContracts`, `PhotoAIStorage`, `PhotoAIWorkflows`, and
  `VisionFeaturePrintBackend`.
- `RawCullAIIntegration` constructs both the Vision fallback and all external
  model providers.
- `RawCullIntelligenceRuntime` owns similarity, semantic search, Deep Review,
  model management, and AI settings as one application lifetime.
- The app embeds the `RawCullModelDownloader` extension, which links
  `BackgroundAssets.framework` and targets macOS 27.
- The repository contains model manifests and third-party model licence notices.
- The earlier `version-2.3.4` branch already targets macOS 26.2 and implements
  similarity with `PhotoAnalysisKit.VisionFeaturePrintBackend`, without
  `PhotoAIKit`, the model downloader extension, CLIP, or SAM.

This means the work is not speculative: the older branch proves the platform and
Vision pipeline, while the current branch provides the newer application and
orchestration improvements that should be retained where compatible.

## Target product behavior

### Retain

- Sony ARW discovery and embedded-preview extraction;
- thumbnail, full-size preview, and memory/disk caching;
- focus-point extraction, focus masks, and sharpness scoring;
- catalog, ratings, filters, keyboard navigation, compare, and export workflows;
- image-to-image similarity sorting using Vision feature prints;
- Vision-based burst grouping, candidate ranking, review queues, and manual winner
  overrides;
- compatible cache-first analysis, cancellation, generation-token, and stale-result
  protections from the current architecture;
- the current non-AI UI improvements that compile and behave correctly on macOS 26.

### Remove

- semantic search controls, state, services, accessibility strings, and tests;
- Deep Review buttons, sheets, controllers, services, subject-mask scoring, and
  tests;
- CLIP backend selection and fallback policy—the Vision backend becomes the only
  backend;
- the entire AI/model settings tab and model download sheet;
- model resource managers, capability scans, download catalogs, licence acceptance,
  download/delete flows, and their tests;
- `RawCullModelDownloader`, its extension target, Info.plist, entitlements, target
  dependency, and embedded-extension build phase;
- `BackgroundAssets.framework` from the project;
- model assets, manifests, and licence resources that no shipped feature consumes;
- concrete CLIP, SAM 3, and EfficientSAM package products and all unused transitive
  dependencies;
- user-facing text that calls Vision indexing "CLIP" or directs the user to AI
  Settings.

### Rework rather than delete

- Rename application-owned `AI` types only where they would otherwise misdescribe
  the Vision-only product. A mechanical repository-wide rename is not required for
  functionality and should be a separate, reviewable cleanup.
- Keep `SimilarityScoringModel`, `RawCullSimilarityFeature`, burst coordinators, and
  artifact persistence, but narrow their contracts to one Vision artifact type and
  one fixed backend identity.
- Replace `RawCullAIIntegration` with a small Vision composition root, or make a
  Vision-only composition root conform to a shared application composition
  protocol.
- Reduce `RawCullIntelligenceRuntime` to the similarity/burst features the edition
  actually owns. It must no longer construct semantic-search, Deep Review, settings,
  or model-management state.
- Replace `RawCullAISettingsModel` with no model settings at all. If a user-facing
  Vision cache/status control is still useful, place it in Cache or Culling
  settings under a RawCull-owned type.
- Retain cache compatibility intentionally. The Vision edition should load current
  Vision artifacts, reject CLIP artifacts, and never mistake one backend's payload
  for the other.

## Dependency strategy

There are two viable ways to supply Vision feature prints.

### Preferred: use `PhotoAnalysisKit` directly

The `version-2.3.4` implementation already uses
`PhotoAnalysisKit.VisionFeaturePrintBackend`. Reusing that route gives the cleanest
meaning to "remove all AI-based code" because the Vision edition can remove the
entire `PhotoAIKit` package reference, not merely its CLIP and SAM products.

The current RawCull similarity service and artifact-store behaviors should be
adapted to RawCull-owned Vision contracts. The old branch is a behavior reference,
not a file-level replacement: copying its complete similarity model back over the
current modular code would discard newer cancellation, partial-failure, cache,
orchestration, and test improvements.

Before committing to this route, verify that the pinned `PhotoAnalysisKit` version:

- supports a macOS 26 deployment target;
- exposes feature-print generation, payload validation/revision, and distance
  calculation needed by the current pipeline;
- does not bring model-only dependencies into the Vision edition.

### Alternative: retain only the Vision slice of `PhotoAIKit`

This is acceptable only if `PhotoAIContracts`, `PhotoAIWorkflows`,
`PhotoAIStorage`, and `VisionFeaturePrintBackend` all declare macOS 26 support and
their dependency graph does not pull in Core AI, CLIP, SAM, tokenizer, or model
conversion products.

Xcode linking only the Vision products is not enough proof. Swift Package Manager
must resolve and build a macOS 26-compatible product graph. If the package itself
declares macOS 27 as its minimum, or a retained product depends on a macOS 27-only
target, compiler guards in RawCull cannot lower that requirement. In that case,
split a standalone Vision package/product or use `PhotoAnalysisKit` directly.

## Can macOS compiler directives be added?

Yes, but they solve different problems and must be used deliberately.

### Runtime API availability

Use `if #available(macOS 27, *)` when one binary has a macOS 26 deployment target
and a small execution path optionally calls a macOS 27 API. Every path must still
provide a macOS 26 implementation.

Use `@available(macOS 27, *)` to mark an entire declaration that references a
macOS 27-only API. Callers must then perform an availability check.

These checks do not remove a package dependency or an embedded extension from the
build. They only protect execution and type checking for OS APIs that are present
in the SDK used to compile the target.

### Compile-time edition selection

For a genuinely shared source tree, define an Active Compilation Condition such as
`RAWCULL_MODEL_AI` only on the macOS 27 AI target. Model-only imports, declarations,
and UI entry points can then be enclosed in `#if RAWCULL_MODEL_AI` blocks. The
Vision target compiles the other branch.

This is more reliable than testing the host OS:

- `#if os(macOS)` identifies the platform, not the macOS version;
- `#if compiler(...)` identifies the Swift compiler version, not the deployment
  target or runtime OS;
- `#if canImport(BackgroundAssets)` reports whether the compile SDK contains a
  module. With Xcode 27 it can be true even while building an app intended for
  macOS 26;
- `if #available` is runtime selection and cannot prevent SwiftPM from resolving an
  incompatible dependency.

### What directives cannot fix

Compiler or availability conditions cannot safely compensate for:

- a package or package product whose declared minimum platform is macOS 27;
- an unconditional package product in the target's link dependencies;
- an embedded app-extension target that requires macOS 27;
- resources and entitlements that should not ship in the Vision edition;
- shared types whose stored properties require model-only types in all
  initializers;
- a deployment target left at macOS 27.

For those, use separate target membership, separate package products, separate
composition roots, or a dedicated branch.

## Recommended repository arrangement

For one maintained source tree, use two thin application targets over shared core
sources:

```text
Shared RawCull application and culling sources
    -> Vision similarity and burst contracts
        -> macOS 26 Vision composition target
            -> PhotoAnalysisKit + Apple Vision
        -> macOS 27 model-AI composition target
            -> PhotoAIKit Vision/CLIP/SAM products
            -> model settings and downloader extension
```

The macOS 26 target should have its own build settings, source membership,
entitlements if needed, test plan, and release scheme. The AI target alone should
embed the downloader extension and link model products. This makes accidental
macOS 27 dependencies visible as build failures rather than hidden runtime paths.

If maintaining two Xcode targets produces too much project complexity, use a
long-lived Vision release branch. Start from `version-3.2.0`, remove the model stack,
and keep the branch synchronized through small, selected non-AI changes. Starting
from `version-2.3.4` is the quickest way to ship a known Vision baseline, but
forward-porting all current UI, cache, concurrency, and workflow improvements onto
it will usually be harder to audit than removing the isolated model features from
the current modular branch.

Do not attempt to create one target in which every view and model contains edition
conditionals. Conditional logic should be concentrated at target membership,
composition, settings navigation, and the few model-only feature entry points.

## Implementation phases

### Phase 0: establish the build and behavior baseline

1. Create the Vision edition target/branch without altering production behavior.
2. Record clean current test results and a manual macOS 27 behavior snapshot.
3. Build `version-2.3.4` with Xcode 26 as a reference and record its Vision cache
   signature, grouping behavior, and deployment settings.
4. Write a feature matrix declaring the retained and removed behavior above.

Exit condition: both reference editions build and the expected Vision behavior is
captured in tests or fixtures before deletion begins.

### Phase 1: make Vision the unconditional similarity backend

1. Add a Vision-only composition root using the preferred dependency strategy.
2. Construct exactly one Vision similarity service at application startup.
3. Remove backend switching from similarity configuration and persisted settings.
4. Preserve indexing progress, cancellation, failure isolation, ranking, burst
   grouping, and current cache validation.
5. Add characterization tests proving that only the Vision backend identity is
   produced and accepted.

Exit condition: all similarity and burst workflows work with no CLIP model present,
and no production code can select a model backend.

### Phase 2: remove semantic search

1. Remove semantic-search feature/service/presentation objects from runtime and app
   composition.
2. Remove semantic-search controls and selection state from detail, grid, toolbar,
   filtering, accessibility, and burst-analysis scope.
3. Simplify filters and cache invalidation paths that currently react to semantic
   selection changes.
4. Remove semantic-search tests and replace any useful general selection coverage
   with non-semantic tests.

Exit condition: there are no `SemanticSearch` or text-embedding references in
production, tests, manifests, or user-facing strings.

### Phase 3: remove Deep Review and segmentation

1. Remove `DeepAIReviewController`, `DeepAIReviewFeature`,
   `SubjectMaskFocusScorer`, their sheet/UI presentation, and view-model commands.
2. Remove SAM 3/EfficientSAM capability types, prompts, repositories, mask stores,
   cache locations, and settings.
3. Keep ordinary focus masks from `PhotoAnalysisKit`; they are not SAM subject
   masks and remain part of the Vision analysis product.
4. Remove segmentation and Deep Review tests.

Exit condition: no CLIP/SAM/segmenter/provider/model-bundle type is reachable from
the app target.

### Phase 4: remove model management and macOS 27 delivery

1. Remove the AI settings tab and model download UI.
2. Remove model catalog, resource manager, licence acceptance, download service,
   model management model, and associated tests.
3. Remove the `RawCullModelDownloader` target and files, target dependency, embed
   phase, Background Assets framework reference, and extension entitlements.
4. Remove model manifests and model-only licence resources after confirming they
   are not required for previously distributed artifacts.
5. Decide whether old downloaded model directories are left untouched or offered
   as an explicit, user-confirmed cleanup. The Vision edition must not silently
   delete user data during first launch.

Exit condition: the built app contains no model downloader extension, Background
Assets linkage, model manifest, or model-only licence payload.

### Phase 5: prune packages and lower the platform

1. Remove all unused `PhotoAIKit` products. With the preferred strategy, remove the
   `PhotoAIKit` package reference entirely.
2. Regenerate `Package.resolved` and confirm model-only transitive packages are
   absent.
3. Set app and test deployment targets to the intended macOS 26 floor. Use macOS
   26.2 if parity with `version-2.3.4` is required; lower it only after testing the
   framework and SwiftUI API surface.
4. Remove or back-deploy any remaining macOS 27-only SwiftUI or framework API.
5. Build with the oldest supported Xcode/SDK as well as the current Xcode. Building
   only with Xcode 27 and a lower deployment target does not prove Xcode 26 source
   compatibility.

Exit condition: dependency resolution, compilation, linking, tests, launch, and
core workflows succeed on an actual macOS 26 host.

### Phase 6: naming, persistence, and release cleanup

1. Rename remaining user-facing "AI" labels to Vision, similarity, or analysis.
2. Rename internal types only where this improves ownership; do not combine large
   symbol renames with behavior changes.
3. Update README feature/version tables, About text, release metadata tests, test
   manifests, cache descriptions, and build/version numbers.
4. Document how the Vision edition treats old CLIP, SAM, and mixed-backend caches.
5. Run a clean-install and upgrade test from both `version-2.3.4` and a RawCull 3
   installation.

Exit condition: the shipping binary, dependency graph, settings, documentation,
and persisted behavior all describe a Vision-only macOS 26 product consistently.

## Persistence and upgrade policy

The safest default is compatibility without destructive cleanup:

- continue reading valid Vision feature-print records when their source and
  pipeline signatures match;
- reject CLIP and mixed-backend artifacts as incompatible and rebuild Vision
  records lazily;
- preserve ratings, saved catalogs, review state, and other non-AI user data;
- ignore old model preference keys rather than repurposing them;
- leave downloaded models and licence-acceptance records in place unless the user
  explicitly chooses to remove them;
- version any changed Vision artifact schema so stale payloads cannot be decoded as
  current records.

Cache compatibility needs explicit tests because `version-2.3.4` stores
`PhotoAnalysisKit` payloads while RawCull 3 stores typed `PhotoAIKit` artifacts.
Even when both represent Vision feature prints, their envelopes and backend
descriptors may not be byte- or schema-compatible.

## Validation matrix

Automated checks should cover:

- a source/import scan showing no CLIP, SAM, Core AI, Background Assets, semantic
  search, model management, or model download references in the Vision target;
- dependency inspection showing no model-only SwiftPM products or transitive
  packages;
- clean Debug and Release builds for the macOS 26 destination;
- the full unit test suite plus focused Vision indexing, cache, ranking, burst,
  cancellation, and migration tests;
- archive inspection showing no downloader extension, model bundles, model
  manifests, or model-only licence resources;
- launch testing on macOS 26.2, not only a compile using a newer SDK;
- upgrade testing from `version-2.3.4` and RawCull 3 application data;
- manual ARW import, thumbnail generation, focus/sharpness, Vision indexing,
  similar-image sort, burst grouping/review, ratings, and export.

Useful final repository checks include searches for:

```text
CoreAICLIPBackend
CoreAISAM3Backend
CoreAIEfficientSAMBackend
PhotoAIKit
BackgroundAssets
RawCullModelDownloader
SemanticSearch
DeepAIReview
CLIP
SAM3
EfficientSAM
```

Each remaining match must be either historical documentation that is intentionally
retained or a test proving exclusion. It must not be linked production code or a
shipping resource.

## Principal risks

- The retained Vision product may inherit a macOS 27 minimum through its package
  manifest even though the Apple Vision API itself runs on macOS 26.
- Lowering `MACOSX_DEPLOYMENT_TARGET` can expose unrelated macOS 27 SwiftUI or SDK
  usage not currently visible through source searches.
- Removing semantic selection affects more than its view: filtering, selection,
  cache invalidation, burst scope, and accessibility all have integration points.
- Vision artifacts from RawCull 2 and RawCull 3 may use different envelopes or
  revisions and must not cross-load without a tested migration.
- A second target can drift if shared behavior is copied rather than shared behind
  narrow protocols and source membership.
- A branch can drift if fixes are merged wholesale instead of selectively ported
  with both editions' test gates.

## Recommended final choice

For the least long-term ambiguity, create a dedicated macOS 26 Vision app target
over shared RawCull sources and give it a Vision-only composition root. Use
`PhotoAnalysisKit` directly for feature prints if its pinned product supports the
chosen macOS 26 floor. Keep the current macOS 27 AI target separate and use one
target-level compilation condition only at the few edition boundaries.

If the immediate priority is shipping rather than maintaining both editions in one
project, create a Vision release branch from `version-3.2.0`, follow the phases
above, and use `version-2.3.4` as the known-good behavioral reference. In either
case, availability/compiler directives are supporting tools, not the primary
architecture.
