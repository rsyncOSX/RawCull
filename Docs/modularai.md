# Modular AI Refactoring

## Why this matters

CLIP-based similarity and semantic search are defining RawCull capabilities. As
these features grow, their implementation must remain understandable, testable,
and replaceable without weakening the current experience or turning AI into a
secondary, optional mode.

The modular AI architecture gives intelligence features clear ownership and keeps
backend details out of SwiftUI and general application code. This makes it safer to
upgrade models, add capabilities, diagnose failures, and evolve RawCull without
coupling every change to the central view model.

## Benefits

- One stable application-level owner for intelligence features and their lifetime.
- Narrow, testable APIs for similarity, semantic search, burst analysis, Deep
  Review, model management, and persistence.
- SwiftUI views depend on presentation state and actions, not concrete AI providers.
- CLIP providers can be upgraded or replaced without rewriting the interface.
- Cancellation, stale-result protection, cache compatibility, and fallback behavior
  remain explicit and independently testable.
- The central `RawCullViewModel` stays focused on application concerns such as
  selection, ratings, navigation, and review actions.
- New AI capabilities can follow the same dependency direction without creating
  another oversized facade.

## Current status

The refactor is active on the `version-3.2.0` development branch. Phases 0 through
8 and 10 through 12 are implemented. Phase 9 is intentionally deferred. Automated
validation is green; the remaining work is the manual acceptance matrix requiring
a representative catalog and installed licensed model resources.

CLIP remains the primary similarity implementation. Vision feature prints remain
the runtime fallback, while SAM 3 and EfficientSAM Deep Review remain optional
capabilities.

## Architecture at a glance

```text
SwiftUI views
    -> focused intelligence presentation state and actions
    -> intelligence feature coordinators
    -> RawCull-owned service and repository protocols
    -> PhotoAIKit workflows and backends
    -> core model implementations
```

`RawCullIntelligenceRuntime`, created once at the app root, owns stable references
to the focused feature models and coordinators. Concrete CLIP, Vision, SAM, and
EfficientSAM providers are restricted to composition and backend adapter code.

The architecture preserves existing preferences, cache formats, model licences,
fallback behavior, semantic ranking rules, burst review state, and Deep Review
validation. Persisted-format changes and product-policy changes are outside this
refactor.

## Phase highlights

### Phase 0 — Trustworthy baseline

Completed on 2026-08-28. Established the `version-3.1.1` baseline, recorded package
revisions, and verified smoke, full, performance, and Release-build gates. Added
characterization coverage for the important AI workflows before changing
production architecture.

### Phase 1 — Dependency boundary

Completed on 2026-08-28. Documented allowed AI imports and added
`make verify-ai-import-boundary`. Concrete backend modules became restricted to
approved composition and adapter files.

### Phase 2 — Stable intelligence runtime

Implemented on 2026-08-28. Added one app-owned `RawCullIntelligenceRuntime` and
shared exact model instances between the runtime and application. This established
stable ownership without moving feature behavior.

### Phase 3 — Typed configuration path

Implemented on 2026-08-29. Replaced separate settings callbacks with one ordered,
revisioned `RawCullIntelligenceConfiguration` path. Provider discovery stayed in
the composition layer, and stale configuration updates cannot restore older state.

### Phase 4 — Settings and model management

Implemented and verified on 2026-08-29. Split model download, licence, and managed-
location behavior into a focused model-management surface. The download path was
manually verified with both supported CLIP models.

### Phase 5 — Semantic search feature

Implemented on 2026-08-29. Moved semantic-search presentation and actions behind a
focused feature API while retaining application-owned filtering, catalog ordering,
selection, and navigation policy.

### Phase 6 — Similarity feature

Implemented on 2026-08-29. Consolidated similarity configuration, hydration,
indexing, ranking, progress, and cancellation behind one feature API. Similarity
and semantic search continue to share a single underlying model and source of truth.

### Phase 7 — Burst-analysis pipeline

Implemented and automatically verified on 2026-08-29 in four small steps:

- **7A:** introduced immutable, sendable request and result values.
- **7B:** extracted cache hydration, migration, and compatibility decisions.
- **7C:** moved scoring, indexing, grouping, ranking, progress, and cache-save
  orchestration into `BurstAnalysisCoordinator`.
- **7D:** reduced `RawCullViewModel` to application-facing state and commands while
  the coordinator owns task and generation lifecycles.

The interactive end-to-end burst qualification remains pending.

### Phase 8 — Optional Deep Review capability

Implemented and automatically verified on 2026-08-30. Added a stable
`DeepAIReviewController` owned by the runtime. The sheet consumes its narrow state
and action surface, while applying recommendations remains a culling-layer concern.

### Phase 9 — Persistence implementation boundary

Intentionally deferred. The future goal is to hide PhotoAIKit storage records and
codecs behind RawCull-owned repository operations while preserving the existing
on-disk encoding and migration behavior exactly.

### Phase 10 — Physical organization

Implemented and automatically verified on 2026-08-30. Moved intelligence code into
clear `Composition`, `Contracts`, `Similarity`, `SemanticSearch`, `BurstAnalysis`,
`DeepReview`, `ModelManagement`, `Persistence`, and `Presentation` directories.
This was a file-organization change only.

### Phase 11 — Package decision

Completed on 2026-08-30. The intelligence boundary remains app-local. A separate
Swift package would currently add adapters for application models, paths, resources,
and Background Assets wiring without improving dependency direction. The decision
can be revisited if the orchestration becomes reusable by another executable and
its inputs are independent of application types.

### Phase 12 — Final enforcement and cleanup

Completed on 2026-08-30. Removed compatibility initializers and forwarding APIs,
migrated remaining views to focused feature surfaces, replaced presentation-layer
backend types with RawCull-owned values, and tightened the import verifier to an
exact allowlist.

Smoke, full Thread Sanitizer, performance, Debug, Release, boundary, and unused-code
checks passed. Manual acceptance remains pending because its catalog and licensed
model resources were unavailable in the validation workspace.

## Required behavior

- Preserve the selected CLIP model and preference keys.
- Use Vision when the chosen CLIP provider is unavailable or invalid.
- Never cross-load DataComp, OpenAI CLIP, and Vision artifacts.
- Do not publish results from cancelled or superseded work.
- Keep semantic search cache-only; a query must not implicitly index images.
- Preserve burst cache-first behavior, review state, and manual winner overrides.
- Validate a Deep Review group signature before applying its recommendation.
- Keep model licence, download, deletion, and Background Assets behavior unchanged.
- Keep cache clearing scoped so it cannot remove ratings, settings, licences, or
  unrelated caches.

## Validation

The standard automated gates are:

```sh
make verify-ai-import-boundary
make test-smoke
make test-full
make test-performance
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -onlyUsePackageVersionsFromResolvedFile \
  build
```

The remaining manual pass should cover startup and settings, both CLIP models and
Vision fallback, semantic search, cached and fresh burst analysis, Deep Review,
cache clearing, model download/removal, and termination persistence.

For detailed dependency rules, see `Docs/ai-dependency-boundary.md`. Test ownership
and suite guidance are recorded in `RawCullTests/TEST_ARCHITECTURE.md`.
