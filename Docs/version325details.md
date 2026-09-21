# RawCull 3.2.5 detailed implementation plan

This document expands the implementation sequence from `Docs/version325.md`. It is a plan only: it does not record or authorize source-code changes.

## Recommended 3.2.5 implementation order

The order below is intentionally incremental. Every numbered commit is a complete, reviewable update. Finish the code, update or add its tests, run the listed verification, and commit it before starting the next update. Do not combine adjacent commits merely because they touch the same feature. If a commit cannot pass its gate independently, split or reorder the work rather than leaving the branch temporarily broken.

General rules for every update:

- Preserve user-visible behavior unless a step explicitly corrects behavior.
- Keep mechanical moves and renames separate from behavior changes.
- Add characterization tests before extracting logic whose behavior is not already covered.
- Keep compatibility shims for one commit when they materially reduce review risk; remove them in the next dedicated commit.
- Run the narrowest relevant tests while developing, then run the complete `RawCullTests` target at the end of each top-level section.
- Record the intent and verification in each commit message. A useful format is an imperative summary followed by the tests run.
- Begin the next commit only from a clean working tree after the previous commit and its verification are complete.

### 1. **Release blocker — completed:** the AI model catalogue, manifest, bundled-licence expectations, and smoke tests are aligned.

This item is already resolved. The prepared and production catalogue consists of DataComp CLIP, SAM 3, and Qwen. OpenAI CLIP and EfficientSAM remain reference-only where applicable. No further restructuring should be mixed into this completed release-blocker work.

#### Completed scope

- Removed the stale OpenAI CLIP production-descriptor expectation.
- Replaced source-text counting of optional archive hashes with assertions against typed catalogue values.
- Removed EfficientSAM from the application-bundled licence expectation while retaining its reference notice under `ModelAssets`.
- Required provenance descriptors for enabled models rather than for every model enum case.
- Kept the catalogue, manifest destinations, bundled resources, provenance information, and tests consistent.

#### Baseline verification before new work

Before beginning item 2, rerun the release-integrity tests and save the passing result as the baseline for the remaining work:

```text
xcodebuild test -project RawCull.xcodeproj -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  -only-testing:RawCullTests/ReleaseMetadataTests \
  -only-testing:RawCullTests/SmokeManifestIntegrityTests
```

Also run any repository provenance-verification command documented alongside `ModelAssets`. If this baseline fails, repair the release metadata as its own commit before continuing; do not fold that repair into correctness or architecture work.

#### Exit criteria

- The prepared catalogue and production manifest describe the same enabled models and destinations.
- Every enabled model has complete provenance and required licence metadata.
- Reference-only models are not required as production downloads or application-bundled licences.
- All release-integrity tests pass.

### 2. **Correctness hardening:** fix the rsync parse fallback and remove or tightly scope the blanket `KeyPath` unchecked `Sendable` conformance.

Complete the rsync correction first because it is a contained runtime defect. Address the concurrency escape hatch second, with a typed replacement rather than another application-wide unchecked conformance.

#### Commit 2.1 — Fix and test failed rsync-stat parsing

Add a regression test in `RawCullTests/ItemizedOutputTests.swift` or a new focused `RemoteDataNumbersTests.swift` that forces `getstats()` to fail. Assert every fallback value, with an explicit assertion that `datatosynchronize` is `false`.

In the same commit, update `RawCull/Model/ParametersRsync/RemoteDataNumbers.swift` so the failure path cannot fall through into assignments from an invalid parser. Prefer either:

- an immediate return after applying fallback values; or
- parsing into a temporary result and assigning all stored properties only after a complete successful parse.

The second form is preferable if it makes partial assignment impossible. Do not rename the existing properties in this commit; naming is handled in item 5.

Verification:

```text
xcodebuild test -project RawCull.xcodeproj -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/ItemizedOutputTests
```

- Run the new failure-path test.
- Run all rsync/copy result tests, including `ItemizedOutputTests`, `CopyCompletionTests`, and `ExecuteCopyFilesStartupTests`.

#### Commit 2.2 — Introduce a sendable sort description

Add a small `Sendable` value that represents the supported file sort choices. An enum such as `FileItemSortField`, combined with direction in a `FileItemSortDescriptor`, should cover only real application cases. Give it an explicit comparator or immutable sortable projection; do not store or transport a `KeyPath`.

Add focused tests for every supported field, ascending and descending order, tie behavior, and empty/single-item input. Use stable tie-breaking where the current UI depends on stable ordering.

Likely touch points include:

- `RawCull/Main/RawCullMainView.swift`;
- the scan/sort workflow under `RawCull/Actors` and `RawCull/Model/ViewModels`; and
- `RawCullTests/ScanFilesSortAndFormatTests.swift`.

This commit may introduce the typed API alongside the existing call path, but should not yet remove the old conformance.

#### Commit 2.3 — Replace key-path transport and remove the blanket conformance

Migrate the caller and worker to the typed sort description. Then delete:

```swift
extension KeyPath: @unchecked @retroactive Sendable where Root == FileItem {}
```

Do not replace it with a similarly broad conformance. If a narrow unchecked wrapper proves unavoidable, keep it private to the concrete sorting implementation, constrain its value type, document why it is safe, and add an actor-boundary test.

Verification:

- Run `ScanFilesSortAndFormatTests` and relevant concurrency tests.
- Build with Swift concurrency diagnostics enabled by the project configuration.
- Run the complete `RawCullTests` target before starting item 3.

#### Exit criteria

- Failed rsync-stat parsing leaves all documented safe defaults intact.
- No global retroactive `KeyPath` `Sendable` conformance remains.
- Sort behavior is represented by a finite, testable, sendable domain type.
- The complete test target passes.

### 3. **First modular extraction:** introduce a session model for one image-review path (preferably `ComparisonGridView`, whose task-generation logic is already cohesive and tested), then reuse the extracted policies in Loupe and burst review.

Use `ComparisonGridView` as the first vertical slice. The objective is not to create one universal image-review view. It is to separate testable state and policy from rendering, then share only the policies genuinely common to comparison, Loupe, zoom, and burst review.

#### Commit 3.1 — Freeze Comparison Grid behavior with characterization tests

Extend the existing focused suites before moving ownership:

- `ComparisonGridDisplayStateTests.swift` for derived presentation state;
- `ComparisonGridNavigationTests.swift` for next/previous and boundary behavior;
- `ComparisonImageAnalysisSourceTests.swift` for source selection;
- coordinator tests for cancellation, stale generation rejection, and reload behavior.

Cover rapid selection changes and out-of-order async completion. No production types move in this commit.

#### Commit 3.2 — Add the `ComparisonSessionModel` shell

Create a `@MainActor @Observable` session owned privately by `ComparisonGridView` through `@State`. Inject its loader, cache, and other services through its initializer. Initially move only construction, dependency storage, and lifecycle entry points; keep rendering unchanged.

The session must expose narrow intents such as `select`, `reload`, `moveSelection`, and `cancel`, rather than exposing mutable task dictionaries. Keep hover, disclosure, and other purely visual state in the view.

#### Commit 3.3 — Move per-file load state and generation ownership

Move per-file image state, viewport state where applicable, task handles, and generation tokens from `ComparisonGridView` into `ComparisonSessionModel`. Preserve the rule that stale work cannot overwrite a newer selection or generation.

Update tests to drive the session directly with deterministic fake loaders. Commit only when cancellation and stale-result tests pass without rendering a SwiftUI view.

#### Commit 3.4 — Move navigation and display-state mapping

Have the session produce immutable presentation values for the view and own navigation policy. Reuse the existing `ComparisonGridNavigation` and `ComparisonGridDisplayState` types where they remain good boundaries; do not duplicate their rules inside the new session.

Reduce `ComparisonGridView` to rendering those values and forwarding actions. Extract substantial visual regions into real `View` structs with narrow inputs where doing so reduces invalidation scope. Do not move files or rename unrelated symbols in this commit.

#### Commit 3.5 — Extract shared image-review policies

From the proven comparison implementation, extract small independent policies for the behavior duplicated across image-review surfaces:

- source-selection and RAW failure presentation inputs;
- viewport/zoom math and limits;
- keyboard input to semantic action resolution;
- focus-mask and subject-outline request identity, cancellation, and stale-result rejection; and
- rating presentation and actions.

Each policy should be value-based or protocol-backed, `Sendable` where it crosses actor boundaries, and tested without SwiftUI. Avoid a single `ImageReviewManager` with broad mutable state.

#### Commit 3.6 — Adopt shared policy in the Loupe path

Introduce `LoupeSessionModel` for `MainThumbnailImageView`. Move source loading, preview ownership, mask/outline work, and task cancellation into it one concern at a time. Keep layout-specific controls and visual state in the view.

If the move is larger than one reviewable diff, split it into these commits, each passing its narrow tests:

1. source and preview loading;
2. mask and outline task ownership;
3. viewport and keyboard/rating actions; and
4. view simplification and extraction of visual subviews.

#### Commit 3.7 — Adopt shared policy in Zoom Overlay

Introduce `ZoomSessionModel` for zoom navigation, viewport state, async image-review work, and keyboard actions. Preserve overlay-specific layout and dismissal behavior in `ZoomOverlayView`. Keep the gesture API modernization for item 6 so this commit remains an ownership change only.

Verify `ZoomOverlayKeyActionTests.swift`, `ZoomCullingMetadataTests.swift`, and the relevant image-loading tests after each slice.

#### Commit 3.8 — Adopt shared policy in burst review

Introduce `BurstWorkspaceSessionModel` for the sliding image window, cache ownership, preloading, focus analysis, masks/outlines, and cancellation. Keep burst-specific comparison layout in `BurstCullingWorkspaceView`.

Split this work if necessary into separate commits for window/cache ownership, analysis ownership, and view simplification. Verify `BurstAnalysisCoordinatorTests`, `BurstAnalysisPipelineValuesTests`, burst presentation tests, and image-source tests.

#### Commit 3.9 — Narrow feature dependencies

Define the smallest interfaces needed by the extracted sessions—for example, focused catalog selection, rating, and culling actions—instead of passing all of `RawCullViewModel`. Wire live implementations at `RawCullApplicationState`. This is the first incremental reduction of the broad application façade described in the review; it is not a request to rewrite the entire view model.

#### Exit criteria

- Comparison, Loupe, Zoom, and burst views primarily render immutable presentation values and forward user intents.
- Async task ownership and stale-result protection live in testable session models or policies.
- Each feature root observes a focused session; leaf views receive values, bindings only where necessary, and action closures.
- Shared behavior is factored into small policies, not a monolithic shared view or manager.
- The complete `RawCullTests` target passes before item 4 starts.

### 4. **Copy boundary:** replace the `RawCullViewModel` dependency in `ExecuteCopyFiles` with an immutable request and move bookmark persistence out of `OpencatalogView`.

The target flow is: the view gathers choices, constructs an immutable request, asks a coordinator to start, and renders coordinator state. Security-scoped bookmark creation/restoration belongs to a dedicated store.

#### Commit 4.1 — Define and test `CopyRequest`

Add an immutable, `Sendable` request containing only the data required to execute a copy:

- source URL or resolved source access;
- destination URL or bookmark reference;
- selected filenames;
- rating/tag selection mode;
- dry-run mode; and
- any explicit rsync options required by execution.

Validate impossible combinations at construction time where practical. Add equality/validation tests and fixtures for empty selections, tagged selections, and dry runs. Do not connect the request to the UI yet.

#### Commit 4.2 — Add a narrow selection adapter

Move filename derivation out of `ExecuteCopyFiles`. If the current selection logic must temporarily read `RawCullViewModel`, put that dependency behind a narrow `CopySelectionProviding` interface at the composition boundary. Produce the final filename list before constructing `CopyRequest`.

Add tests proving that request construction selects the same files as the current workflow. This adapter is allowed to be transitional; the execution layer must not know about `RawCullViewModel`.

#### Commit 4.3 — Make `ExecuteCopyFiles` request-driven

Change `ExecuteCopyFiles` to accept `CopyRequest` and remove its weak `RawCullViewModel` reference. Preserve argument generation and startup behavior. Update `ExecuteCopyFilesStartupTests.swift` to instantiate it without the application-wide model.

Do not introduce the coordinator or alter the view in this commit beyond the minimum call-site compatibility needed to compile.

#### Commit 4.4 — Introduce `CopyFilesCoordinator`

Add a focused coordinator/service that accepts `start(request:)`, owns execution/cancellation, and publishes typed progress and result state. Translate process output to domain results here, not in `CopyFilesView`.

Test success, failure, cancellation, repeated start, and stale completion. Keep irreversible work after validation and security-scoped access has succeeded.

#### Commit 4.5 — Add a typed security-scoped bookmark store

Create a dedicated store for bookmark creation, persistence, restoration, stale-bookmark renewal, and balanced access start/stop. Replace raw string keys such as `"destBookmark"` with typed keys or dedicated methods.

Inject the persistence backend so tests can use an isolated store instead of `UserDefaults.standard`. Add tests for missing, valid, stale, corrupt, and access-denied bookmarks.

#### Commit 4.6 — Simplify the copy views

Update `OpencatalogView` to ask the bookmark store to persist/restore access. Update `CopyFilesView` to construct a request, call the coordinator, and render its typed state. Remove direct execution control, result translation, bookmark encoding, and direct `UserDefaults.standard` access from presentation code.

Keep UI wording and layout unchanged in this commit. Run `ExecuteCopyFilesStartupTests`, `CopyCompletionTests`, security-scope tests, and the complete test target.

#### Exit criteria

- `ExecuteCopyFiles` has no reference to `RawCullViewModel` or SwiftUI presentation state.
- A complete copy operation is described by an immutable request.
- A focused coordinator owns execution and typed progress/results.
- Bookmark persistence and security-scoped access have a typed, injectable boundary.
- Copy views contain option selection, user intents, and rendering only.

### 5. **Naming pass:** mechanically normalize the highest-traffic view-model and copy-workflow names; replace numbered synchronization parameters with typed options.

Naming changes must be behavior-preserving and grouped into small, searchable batches. Do not mix renames with logic extraction. Prefer IDE/compiler-assisted symbol renames so call sites and tests move atomically.

#### Commit 5.1 — Normalize composition and central view-model names

Rename the highest-traffic symbols first, including:

- `gridthumbnailviewmodel` to `gridThumbnailViewModel`;
- `currentselectedSource` to `currentSelectedSource`;
- `issorting` to `isSorting`;
- `creatingthumbnails` to `isCreatingThumbnails`;
- `focusaborttask` to `focusAbortTask`;
- `showcopyARWFilesView` to `showCopyARWFilesView`; and
- `remotedatanumbers` to `remoteDataNumbers`.

Limit this commit to the composition root, `RawCullViewModel`, direct call sites, and tests. Build and run view-model tests before committing.

#### Commit 5.2 — Normalize copy-workflow names

Rename the copy symbols and labels in one contained batch, including:

- `startcopyfiles` to `startCopyFiles`;
- `copytaggedfiles` to `copyTaggedFiles`;
- `itemizeparameter` to `itemizedParameter` or a clearer domain name;
- `updateparamter` to `updateParameter` or a more specific action name;
- `selecteditem` to `selectedItem`;
- `uutype` to `allowedContentType`; and
- `sourcecatalog`/`destinationcatalog` to `sourceCatalog`/`destinationCatalog`.

Also normalize `RemoteDataNumbers` properties such as `filestransferred`, `totaltransferredfilessize`, `datatosynchronize`, and `defaultvalues`. Update serialized keys only if they are not compatibility-sensitive; otherwise retain explicit coding keys.

Run all copy and rsync tests before committing.

#### Commit 5.3 — Introduce typed synchronization options

Replace `parameter4` through `parameter14` and other generic configuration fields with a typed `SynchronizationOptions` value whose properties describe their domain meaning. Make invalid combinations unrepresentable where feasible and keep command-line serialization in one place.

First add mapping tests that freeze the current generated rsync arguments. Then introduce the typed value and migrate one construction path. Commit only after old and new output match for every fixture.

#### Commit 5.4 — Remove the numbered-parameter compatibility layer

Migrate remaining callers and delete the numbered properties/initializer. Run argument-generation, startup, and copy tests. Keep this separate from commit 5.3 so the typed mapping can be reviewed before the legacy surface is removed.

#### Commit 5.5 — Normalize type, directory, and extension-file names

Perform file-system-sensitive renames in small groups:

- `OpencatalogView` to `OpenCatalogView`;
- `FocusandSharpness` to `FocusAndSharpness`;
- `Viewmodifiers.swift` to a responsibility-specific file name; and
- `extension+RawCullView.swift` to `RawCullView+<Responsibility>.swift`.

Use a two-step temporary rename on case-insensitive file systems when needed. Update Xcode project references in the same commit as each file move. Prefer one commit per directory or project-file-sensitive rename.

#### Naming policy to apply

- Use standard lower camel case for properties, variables, functions, and parameters.
- Use upper camel case for types.
- Treat acronyms consistently: use established Swift forms such as `URL`, but prefer descriptive names over ambiguous abbreviations.
- Boolean names should read as assertions (`isSorting`, `hasDataToSynchronize`, `shouldCopyTaggedFiles`).
- Avoid generic numbered fields; use domain names and typed groupings.
- Preserve external formats with explicit coding keys or migration logic.

#### Exit criteria

- The listed high-traffic naming violations no longer appear in source searches.
- Generated rsync arguments remain unchanged except for separately approved correctness fixes.
- No serialized data or user preference silently changes key because of a Swift rename.
- Xcode project references resolve with the new file/directory names.
- The complete test target passes before item 6 starts.

### 6. **Presentation cleanup:** move parser/view mixtures and presentation-only alert/sheet mapping to their proper layers, then modernize the small SwiftUI API issues.

Finish with small separation, API, identity, and dependency-injection updates. Each concern below should remain its own commit so regressions can be located and reverted independently.

#### Commit 6.1 — Separate itemized-output parsing from its row view

Move the parsing record and parser from `RawCull/Model/ParametersRsync/ItemizedOutput.swift` into model-only files that do not import SwiftUI. Move `Color`, SF Symbol, and row rendering decisions into a presentation mapper and `ItemizedOutputRow` view under `RawCull/Views/OutputViews`.

Retain parser behavior exactly. Run `ItemizedOutputTests` and build the app before committing.

#### Commit 6.2 — Move histogram loading and presentation types

Move `HistogramLoader` and `HistogramPresentationModel` out of `RawCull/Views/Histogram/HistogramView.swift` into model/presentation files. Keep `HistogramView` focused on layout and drawing. Inject loading dependencies and run `HistogramLoadingTests`.

#### Commit 6.3 — Add typed workflow failures and presentation mapping

Replace plain alert title/message storage in the central model with typed feature failures. Add a presentation mapper near the main view that converts failures to `LocalizedStringResource`, actions, and accessibility-friendly messages.

Do this one workflow at a time if necessary. Keep existing English copy stable in the first commit, and add localization resources in a separate follow-up if required.

#### Commit 6.4 — Move sheet and navigation ownership to a main-window router

Introduce a small presentation router for `ActiveSheet` and other main-window destinations. Remove concrete sheet/navigation concepts from `RawCullViewModel` after callers have migrated. This continues narrowing the central façade without combining it with catalog or culling extraction.

Add router transition tests and verify all existing presentation tests.

#### Commit 6.5 — Modernize `RawCullMainView` state and alerts

Make `columnVisibility` private. Replace the older `alert(item:)` returning `Alert` with the current title/actions/message form, using the typed presentation mapping from commit 6.3. Keep this a presentation-only change.

#### Commit 6.6 — Standardize the zoom gesture

Replace `MagnificationGesture` in `ZoomOverlayView` with `MagnifyGesture` for the macOS 27 target. Preserve anchor, scale limits, and end-of-gesture state. Add or update viewport-policy tests before changing the gesture wiring.

#### Commit 6.7 — Give candidate patches stable identity

Add stable identity to the patch presentation model and update `CandidateInspectorView` so rows are not identified by enumerated offsets. Test reordered rankings, insertions, and removals to ensure SwiftUI state remains attached to the correct patch.

#### Commit 6.8 — Apply focused spelling-only SwiftUI updates

Update `foregroundColor`, `cornerRadius`, and similar older spelling-only APIs only where the replacement is behaviorally equivalent. Keep this commit mechanical and do not reformat unrelated view bodies.

#### Commit 6.9 — Make remaining global dependencies explicit

Define protocol-typed dependencies for remaining direct uses of `SettingsViewModel.shared`, `ThumbnailLoader.shared`, `SharedMemoryCache.shared`, and `UserDefaults.standard`. Construct live instances in `RawCullApplicationState.live()` and inject them into the focused feature/session models.

Migrate one dependency per commit if call-site volume is significant. Supply isolated fakes or in-memory implementations to tests. Shared actors may remain the live implementation; the goal is to remove hidden call-site access, not to prohibit shared runtime resources.

#### Commit 6.10 — Align feature folders with responsibilities

After types have stable ownership, move non-view comparison and culling types to explicit model, presentation, or coordinator locations. Possible layouts include `Features/<Feature>/Model`, `Presentation`, and `Views`, or equivalent subfolders within the current structure.

Move one feature per commit and update Xcode project references atomically. Do not combine file moves with symbol changes. Confirm that model layers do not import SwiftUI unless they intentionally expose presentation types.

#### Final verification and documentation commit

After commits 6.1–6.10:

1. Run every focused suite named in this plan.
2. Run the complete `RawCullTests` target on macOS.
3. Review the build log for concurrency warnings and missing Xcode project references.
4. Search for the removed legacy names, numbered synchronization parameters, global `KeyPath` conformance, and direct presentation-layer `UserDefaults.standard` access.
5. Perform a manual smoke pass through catalog opening, sorting, Comparison Grid, Loupe, Zoom, burst review, rating, copy dry-run, and copy result presentation.
6. Update architecture documentation to show the actual final boundaries and record any intentionally deferred item. Make this documentation update its own final commit.

#### Exit criteria

- Parsers and workflow models do not contain SwiftUI views or presentation colors/icons.
- Histogram loading and mapping are testable without rendering the histogram view.
- Workflow failures remain typed until mapped near the presentation layer.
- A main-window router, rather than the catalog/culling model, owns sheets and navigation.
- Dynamic rows use stable domain identity.
- Live global services are supplied by the application composition root and replaceable in tests.
- Folder placement reflects type responsibility without mixing moves and behavior changes.
- The full automated suite and manual smoke pass succeed from a clean working tree.

## Completion definition

RawCull 3.2.5 implementation work described here is complete only when every top-level item has met its exit criteria, every small update exists as a separate verified commit, the complete `RawCullTests` target passes, and the working tree is clean. Deferred work must be written down explicitly with its reason and must not leave an incomplete migration, compatibility shim, failing test, or unchecked concurrency escape hatch in the release branch.
