# RawCull's Modular AI Plan — A High-Level Guide

This document explains the plan in `Docs/modularai.md` for a developer who is new
to RawCull and may have limited Swift or SwiftUI experience. It describes the same
direction and all of the planned phases, but leaves out most implementation-level
checklists and test names.

**Current status:** the plan is active on the `version-3.2.0` development branch.
Phases 0–8 and 10 were implemented on August 28–30, 2026. Phase 11 records the
decision to keep the boundary application-local. Phase 12 compatibility removal
and exact import enforcement are implemented; its final automated and manual gate
evidence is tracked in `Docs/modularai.md`.

## The short version

RawCull is a macOS app for reviewing and selecting photos. Some of its most
important features use image-analysis models:

- **CLIP** compares images and enables text searches such as “a dog running.”
- **Apple Vision feature prints** provide a fallback for visual similarity when a
  selected CLIP model is unavailable.
- **SAM 3 and EfficientSAM** are optional models used by Deep Review to understand
  the main subject in a photo.

These features already work. The project is not replacing them or changing how
they behave. The problem is that responsibility for them is spread across the app.
The main application model, settings code, views, background tasks, model setup,
and cache code know too much about one another.

The plan reorganizes that code behind small, clear feature boundaries. A screen
should be able to ask “start a semantic search” or display “12 of 20 images
indexed” without knowing which model, cache format, or storage object does the
work. This should make the code easier to understand, test, and change without
altering the user experience.

## A few Swift and SwiftUI terms

- A **view** is SwiftUI code that describes part of the interface. SwiftUI can
  recreate view values frequently, so long-lived feature objects must not be
  created inside a view's `body`.
- An **observable model** is an object whose changing values automatically update
  the interface.
- `@State` gives a SwiftUI owner stable storage for a value. In this plan, the app
  root uses it to retain one intelligence runtime for the whole app session.
- `@MainActor` means code runs on the main application thread, where interface
  state is safe to update.
- A **protocol** is a small contract describing what a service can do. Callers can
  depend on that contract rather than on one concrete CLIP or Vision
  implementation.
- An **actor** protects mutable data used by concurrent work. RawCull uses actors
  for disk-backed caches and artifact storage.
- A **composition root** is the one place where concrete implementations are
  created and connected.
- A **generation token** is a version number for asynchronous work. If newer work
  starts, an older result is rejected instead of appearing in the interface.

## What motivated the plan?

RawCull already has useful lower-level separation. `PhotoAIKit` provides reusable
AI contracts, workflows, storage, and backends. RawCull also has protocols for
similarity, semantic search, Deep Review, model downloads, and focus scoring.

When the plan began, the weak point was the application layer above them:

- `RawCullApp` creates several intelligence objects and connects them with
  callbacks.
- `RawCullViewModel`, the large central application model, also owns similarity,
  Deep Review, AI tasks, burst-analysis state, cache operations, and backend
  switching.
- Burst grouping currently combines cache loading, old-cache migration, image
  scoring, indexing, grouping, ranking, saving, Deep Review preparation, and user
  actions in one area.
- Some SwiftUI views reach through the main view model into low-level similarity
  or Deep Review state.
- Some presentation and persistence code exposes types belonging to PhotoAIKit.

This makes changes risky. For example, switching a backend involves settings,
task cancellation, cache compatibility, view-model state, and UI updates. It is
easy to accidentally publish an old result, rebuild a valid cache, or create a
second observable model with conflicting state.

## The target design

Dependencies should flow in one direction:

```text
SwiftUI screens
    -> small RawCull presentation models and actions
    -> RawCull feature coordinators
    -> RawCull service and repository protocols
    -> PhotoAIKit workflows and storage
    -> concrete CLIP, Vision, SAM, and EfficientSAM implementations
```

A lower layer must never depend on a higher one. In particular, a SwiftUI view
must not construct or inspect a concrete AI provider.

At the app root, RawCull creates exactly one
`RawCullIntelligenceRuntime`. The runtime is a lifetime container and coordination
point. It owns stable references to focused parts such as:

- similarity and semantic search;
- Deep Review;
- AI settings and model downloads;
- burst analysis;
- artifact and derived-analysis repositories;
- the integration object that knows the concrete backends.

The runtime must not become a second giant view model. It should not copy every
piece of child state or offer hundreds of forwarding properties. Each view gets
only the small model or action surface it needs. General app concerns—catalog
navigation, ratings, selection, and user culling actions—remain with the main
application layer.

The boundary distinguishes three kinds of data:

1. **Product data:** RawCull concepts such as semantic matches, similarity state,
   burst-analysis requests, and Deep Review results.
2. **Backend data:** model providers, encoded AI artifacts, backend descriptions,
   and storage codecs. These stay inside the intelligence and persistence layers.
3. **Presentation data:** progress, errors, settings rows, availability, and cache
   summaries shown by the interface.

Existing PhotoAIKit values are not all replaced at once. Small adapters are added
only where they remove a real dependency.

## What must not change

This is a structural refactor, not a product redesign. Throughout the work:

- CLIP remains a core RawCull capability, and the default selected model does not
  change.
- Vision remains the fallback when CLIP cannot be used.
- Semantic search uses only compatible CLIP data already cached on disk. Searching
  must not silently index photos.
- DataComp CLIP, OpenAI CLIP, and Vision artifacts must never be mixed.
- Ranking, grouping, sharpness, subject penalties, result limits, and Deep Review
  policy remain the same.
- Changing models must cancel or supersede old work. Cancelled work must never
  publish stale results.
- Burst analysis keeps its current order: restore compatible data, migrate legacy
  data if needed, fill missing analysis, group, rank, and save.
- Burst review state and manual winner choices survive compatible regrouping and
  cache restoration.
- Deep Review applies a recommendation only to the exact burst it analyzed.
- Preference keys, cache paths, on-disk formats, licences, model download behavior,
  and migration support remain compatible.
- Clearing one cache must not delete ratings, settings, licences, downloaded
  models, or unrelated caches.
- App shutdown must still finish culling persistence and correctly release access
  to the user's files.

## The phased migration

Each phase must compile and pass its own checks. Temporary forwarding methods are
allowed so callers can move one at a time. Behavior edits, file moves, broad
renames, and storage-format changes must not be mixed with the architectural work.

### Phases 0–4: foundation and settings — completed

**Phase 0 established a reliable baseline.** The project recorded its starting
commit, dependency versions, Xcode version, and passing smoke, full, performance,
and Release-build results. Missing behavior tests were added before production
code moved.

**Phase 1 documented and enforced dependency direction.** A repository check now
prevents concrete AI backend imports outside approved composition and adapter
files. Remaining PhotoAIKit contract leakage is reported for gradual cleanup.

**Phase 2 introduced the intelligence runtime.** The app now creates one runtime
and shares the exact same similarity, settings, and Deep Review objects with the
existing app model. At this stage the runtime was deliberately only a stable
lifetime owner; behavior did not move.

**Phase 3 replaced separate settings callbacks with one typed configuration.** A
complete snapshot describes the selected similarity service, semantic-search
capability, and segmentation model. Snapshots have revisions, so an older refresh
cannot restore outdated settings. A repeated but unchanged configuration does not
restart work. Similarity changes are still applied before semantic changes, as in
the original app.

**Phase 4 separated model management from general AI settings.** Settings still
owns preferences and capability presentation, while a focused model-management
model owns the download catalog, licence acceptance, progress, cancellation,
retry, removal, and installed-model locations. Download screens see only that
focused model. Automated gates pass, and downloading both supported CLIP models
was manually verified. The wider manual regression list remains for later phases.

### Phase 5: semantic search

Create a focused semantic-search feature around the existing similarity model.
It will expose search state, progress, result counts, selected IDs, and per-photo
rank/score evidence without exposing providers or artifact dictionaries.

The feature will coordinate with the application through a very small, weak
contract. The app still decides which catalog photos are admitted by filename,
rating, and sharpness filters, and still owns selection, comparison mode, and
catalog ordering.

Search, show-all, change-result-count, clear, and cancel actions will move behind
one feature API. Query text and focus stay local to the view. Semantic search
remains cached-only, and cancelling one query before starting another must prevent
the first query's progress or results from reappearing.

### Phase 6: similarity indexing and image ranking

Create a focused similarity feature that shares the exact same underlying model as
semantic search. It will own top-level hydration tasks and backend-change handling,
while the existing model continues to perform the lower-level indexing and ranking
work.

Views will receive simple progress, completeness, backend name, active anchor, and
per-photo distance information. They will no longer inspect embeddings, backend
descriptors, repositories, or providers.

Catalog loading, explicit indexing, model replacement, and image-to-image ranking
will use typed requests. The main application model continues to own the selected
photo, catalog identity, filters, and final display ordering. This phase also
removes the temporary configuration bridge through `RawCullViewModel`.

Because this phase moves asynchronous and persistence-related ownership, it must
test cancellation during loading, generation, and saving; backend and catalog
switches; partial success; force re-indexing; cache compatibility; and ranking
with a changed anchor.

### Phase 7: burst analysis

This is the riskiest area and is intentionally split into smaller steps:

- **7A:** describe burst input and output with immutable RawCull-owned request and
  result values, without moving the work.
- **7B:** extract cache restoration, compatibility checks, legacy migration, and
  artifact digest decisions.
- **7C:** extract the compute sequence: missing sharpness work, missing similarity
  indexing, grouping, ranking, and saving.
- **7D:** remove the extracted worker state from the central view model.

The application view model will still own ratings, navigation, selection, undo,
manual winners, and review commands. The result should be a burst pipeline that can
be tested without constructing the entire application model.

### Phase 8: Deep Review

Keep the existing focused Deep Review operation model, but add a controller for
request construction and availability. The Deep Review sheet will receive a narrow
state/action surface and will not check optional providers itself.

The application remains responsible for applying a recommendation, updating
ratings, recording a manual winner, and verifying that the result belongs to the
current burst. SAM 3 and EfficientSAM remain optional, with the same candidate
limit, prompt behavior, subject-mask scoring, and failure/cancellation states.

### Phase 9: persistence boundaries

Keep the existing disk-store actors and on-disk encodings, but hide PhotoAIKit
storage records and codecs behind RawCull repository operations. Views and the
central view model should use RawCull requests and summaries only.

Once this is complete, the import checker can enforce that PhotoAIKit contract
types appear only in approved intelligence and persistence files. This phase does
not introduce a new cache schema.

### Phase 10: physical file organization

Only after logical ownership is stable should files be moved into folders such as
Composition, Similarity, SemanticSearch, BurstAnalysis, DeepReview,
ModelManagement, Persistence, and Presentation. File moves are committed
separately from logic changes so history remains readable and accidental Xcode
target changes are easy to spot.

### Phase 11: decide whether to create a Swift package

A separate `RawCullIntelligence` package is optional. It is useful only if the
finished boundary no longer depends on SwiftUI, the full application model,
implicit app paths, or app-only resources. Otherwise, keeping it as a well-enforced
part of the app is the better result.

The project must record either decision and its reasons. If a package is chosen,
contracts, pure policy, repositories, and burst computation move in small steps,
with builds and tests after every target change.

RawCull chose to keep this boundary in the application target. It still uses
application-owned catalog values and callbacks, app paths and resources, and
Background Assets wiring. An additional package would therefore add adapters
without creating a cleaner compile-time graph. Exact source-level enforcement is
used instead.

### Phase 12: remove temporary compatibility code

Search the repository for old forwarding methods, compatibility initializers, and
backend imports. Remove unused shims feature by feature, tighten the dependency
checker, update architecture documentation, and run the complete automated and
manual validation suite.

The provider-constructing view-model initializers and runtime similarity-model
exposure are removed. Tests assemble isolated feature graphs through a test-only
factory, views use focused feature surfaces, and the checker now uses exact
file/module allowlists with no warning-only production imports. It also prevents
the removed constructors, forwarding methods, and direct view traversal from being
reintroduced.

## How the work is kept safe

The main risks are duplicate observable state, SwiftUI recreating feature objects,
late asynchronous results, cache incompatibility, an oversized runtime, and an
accidental product change. The plan addresses them by:

- creating feature objects once at the app root and testing their identity;
- moving a task together with its cancellation and generation state;
- checking cancellation, generation, catalog identity, and model identity before
  publishing results;
- retaining the existing backend descriptors, schemas, signatures, paths, and
  encoded payloads;
- giving views narrow feature models instead of the full runtime;
- adding behavior tests before moving poorly documented code;
- making each phase independently reviewable and reversible.

The standard automated gates are `make test-smoke`, `make test-full`, and, when
indexing, ranking, storage, or package boundaries change,
`make test-performance`. Changes to composition or build membership also require a
Release build using the exact versions in `Package.resolved`.

Manual checks cover startup and settings, model downloads, both CLIP models,
Vision fallback, semantic search, similarity indexing and ranking, burst cache
restoration and cancellation, Deep Review with both segmentation choices, cache
clearing, relaunch behavior, and safe app termination. Runs should record the app,
OS, Xcode, model, catalog, and cache versions so results can be reproduced.

## What success looks like

At the end, RawCull behaves as it did before, but the code has clearer ownership:

- screens work with small RawCull presentation models and actions;
- concrete AI backends are known only by composition and adapter code;
- similarity, semantic search, burst analysis, Deep Review, model management, and
  persistence can be tested independently;
- `RawCullViewModel` focuses on application concerns rather than AI providers,
  codecs, and worker tasks;
- caches and existing user data continue to work without migration;
- a CLIP provider can be upgraded or replaced without rewriting the interface.

The most useful first milestone is the end of Phase 6, where configuration,
semantic search, and similarity have coherent feature APIs. Phases 7–12 can then be
continued only if their complexity is justified by the measured improvement.
