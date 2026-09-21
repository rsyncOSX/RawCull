# RawCull 3.2.5 source-code review

Review date: 21 September 2026

## Scope and severity

This review focuses on modularity, naming conventions, separation of SwiftUI views from model and workflow code, and other correctness or maintainability issues found while reading the application and test sources. The review also includes a clean `xcodebuild test` run of the `RawCullTests` target.

- **Critical** means the issue should block a 3.2.5 release because it breaks release validation or can invalidate an important safety guarantee.
- **Non-critical** means the current implementation can ship, but the issue raises maintenance cost, weakens testability, or creates a plausible future correctness/performance problem.

## Overall assessment

The high-level architecture is substantially better separated than the size of the application might initially suggest. Reusable parsing, analysis, AI inference, persistence contracts, and rsync behavior are delegated to packages or focused services. The application has a clear composition root (`RawCullApplicationState`), uses `@Observable` with main-actor isolation consistently, contains dedicated actors for expensive work, and has unusually broad automated coverage. Feature-specific types such as `RawCullSimilarityFeature`, `DeepAIReviewController`, `BurstAnalysisCoordinator`, and `RawCullAISettingsModel` are good examples of narrow boundaries.

The main weakness is that this separation is not yet consistent at the presentation boundary. Several large SwiftUI views still act as view, controller, task owner, cache owner, keyboard-event coordinator, and presentation mapper simultaneously. `RawCullViewModel` is also still the shared mutable surface for most workflows. This does not make the application structurally unsound, but it makes otherwise well-separated services harder to reason about and change independently.

No confirmed user-data-loss or crashing runtime defect was found in the reviewed code. There is, however, one critical release-validation issue and several non-critical correctness and design issues.

## Critical issue (resolved during this review)

### C1. The smoke/release test suite is not aligned with the current model catalogue

**Evidence**

Running:

```text
xcodebuild test -project RawCull.xcodeproj -scheme RawCull \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/RawCullReviewDerivedData \
  -only-testing:RawCullTests
```

compiled the application and executed 413 tests. The result was 410 passed and 3 failed:

1. `RawCullAIModelDownloadsTests.Production catalog includes only configured models`
2. `ReleaseMetadataTests.model manifest catalog and destinations agree`
3. `ReleaseMetadataTests.model provenance status and notice hashes are complete`

The failures have three related causes:

- `RawCullAIModelDownloadCatalog.prepared` currently contains DataComp CLIP, SAM 3, and Qwen only (`RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift:141-249`), while the test still requires an OpenAI CLIP descriptor (`RawCullTests/RawCullAIModelDownloadsTests.swift:13-19`).
- Every current prepared descriptor has a non-optional archive hash, while the release test still expects exactly one `expectedArchiveSHA256: nil` entry (`RawCullTests/ReleaseMetadataTests.swift:139`).
- The provenance test expects `RawCull/Resources/ModelLicences/EfficientSAM-Apache-2.0.txt`, but that resource is not present (`RawCullTests/ReleaseMetadataTests.swift:214-223`). EfficientSAM now appears to be retained only as reference material under `ModelAssets/Notices/EfficientSAM`.

**Why this is critical**

These are smoke-tagged release-integrity tests. A failing release suite means the repository cannot establish that shipped model metadata, licence resources, and the download catalogue agree. Even if the runtime implementation is correct, releasing while these checks fail removes an important safeguard around third-party model distribution.

**Recommended update for 3.2.5**

Choose one source of truth and update all derived expectations atomically. Based on the current catalogue and `ModelAssets/README.md`, the likely intended production/prepared set is DataComp CLIP, SAM 3, and Qwen, with OpenAI CLIP and EfficientSAM kept as reference-only assets. If that is correct:

- remove the stale OpenAI CLIP expectations from `RawCullAIModelDownloadsTests`;
- replace the source-text count assertion for `expectedArchiveSHA256: nil` with assertions against typed catalogue values;
- remove EfficientSAM from the list of licences expected in the application bundle, while retaining validation of its notice/provenance files under `ModelAssets` if desired; and
- keep the catalogue, manifest, resources, project file, provenance data, and tests in one change.

Prefer typed assertions over searching Swift source text. Text-count assertions are brittle and failed here even though the underlying typed production catalogue and manifest destinations were consistent.

**Resolution**

The release tests now treat DataComp CLIP, SAM 3, and Qwen as the prepared and production download catalogue. Stale OpenAI CLIP descriptor expectations were removed, the source-text hash count was replaced with typed completeness checks, and EfficientSAM was removed from the application-bundled licence expectation while its reference notice remains under `ModelAssets/Notices/EfficientSAM`. The provenance verifier now requires a descriptor for every enabled model instead of every enum case, allowing reference-only model IDs without weakening validation of production models. The targeted release tests, the provenance verifier and its rejection fixtures, and the complete `RawCullTests` target pass after these changes.

## Non-critical issues and recommended updates

### N1. Large feature views own too much workflow state and asynchronous coordination

**Evidence**

- `ZoomOverlayView` is 912 lines and owns zoom state, image-source state, task cancellation, focus-mask generation, subject-outline loading, navigation, keyboard monitoring, rating actions, and rendering (`RawCull/Views/ZoomViews/ZoomOverlayView.swift:129-912`).
- `BurstCullingWorkspaceView` is 851 lines and owns an image cache, window preloading, focus analysis, subject-mask loading, navigation, keyboard monitoring, rating actions, and presentation (`RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift:36-851`).
- `ComparisonGridView` owns per-file image and viewport dictionaries, several task/generation registries, bulk loading, focus regeneration, keyboard handling, and presentation (`RawCull/Views/ComparisonGridView/ComparisonGridView.swift:5-554`).
- `MainThumbnailImageView` has the same broad responsibilities for the Loupe workflow (`RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:49-683`).
- `CullingGridView` owns derived render caches and workflow mutations in addition to composing the grid (`RawCull/Views/CullingGrid/CullingGridView.swift:196-739`).

**Why it matters**

SwiftUI recreates view values frequently. `@State` preserves the stored values, but lifecycle correctness is spread across `.task`, `.onChange`, `.onAppear`, `.onDisappear`, manual `Task` properties, UUID generations, and AppKit event monitors. This makes cancellation and stale-result behavior harder to audit and requires view-level tests to exercise logic that could otherwise be tested as ordinary model behavior. Large bodies and computed subviews also share broad invalidation boundaries.

**Recommended update**

Introduce small `@MainActor @Observable` feature-session models, owned by the corresponding view with private `@State`. Suitable boundaries would be:

- `LoupeSessionModel` for source selection, loaded previews, masks, subject outlines, and task ownership;
- `ZoomSessionModel` for zoom navigation, viewport state, and keyboard actions;
- `ComparisonSessionModel` for per-file image/viewport state and reload generations; and
- `BurstWorkspaceSessionModel` for the sliding image window, focus analysis, and cache ownership.

The views should primarily render immutable presentation values and forward user intents. Keep small, purely visual state such as hover and disclosure state in the view. Extract substantial sections into real `View` structs with narrow inputs rather than only computed `some View` properties, because separate view types also create useful SwiftUI invalidation boundaries.

### N2. `RawCullViewModel` remains a broad application façade

**Evidence**

The base declaration exposes catalog selection, scanning, progress, sheets, alerts, copy state, zoom state, culling state, sharpness state, similarity state, Deep Review state, persistence, security-scoped access, caches, and task handles (`RawCull/Model/ViewModels/RawCullViewModel.swift:70-238`). Its extensions add catalog loading/filtering, thumbnails, similarity, sharpness, culling, AI analysis, and nearly 1,000 lines of burst-group behavior.

Views consequently receive and mutate the complete view model even when they need only a few values. For example, `ComparisonGridView` can initiate image loading, rating, burst actions, zoom, and selection through the same object (`RawCull/Views/ComparisonGridView/ComparisonGridView.swift:5-517`).

**Why it matters**

The observation framework limits many unnecessary redraws at property granularity, so this is primarily a modularity and testability issue rather than proof of a performance bug. The broad mutable interface nevertheless makes dependencies implicit and lets any view alter unrelated workflow state. It also makes feature removal and parallel development more conflict-prone.

**Recommended update**

Continue the pattern already established by the focused intelligence features. Incrementally extract or expose narrow feature interfaces such as `CatalogSession`, `CullingSession`, `LoupePresentation`, and `CopySelectionProviding`. Pass those focused models to feature roots, and pass immutable values/bindings/actions to leaf views. Do not attempt a single large rewrite; move one workflow at a time and preserve the existing composition root.

### N3. The copy workflow crosses the view-model boundary in both directions

**Evidence**

`ExecuteCopyFiles`, a model/workflow type, stores a weak reference to `RawCullViewModel` and asks it for filenames during startup (`RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:82-137`). `CopyFilesView` constructs and controls that execution object directly and translates its completion into other model objects (`RawCull/Views/CopyFiles/CopyFilesView.swift:137-191`). `OpencatalogView` also performs security-scoped access and writes bookmark data directly to `UserDefaults` (`RawCull/Views/CopyFiles/OpencatalogView.swift:24-57`).

**Why it matters**

The execution layer cannot be reused or tested without the application-wide view model, and the view owns persistence/security behavior. The weak reference prevents a retain cycle but does not create a meaningful abstraction. String bookmark keys such as `"destBookmark"` are also easy to mistype.

**Recommended update**

Create an immutable `CopyRequest` containing source URL, destination URL or bookmark, selected filenames, rating/tag mode, and dry-run mode. Have a `CopyFilesCoordinator` or service accept that request and publish progress/result state. Move bookmark creation and restoration into a dedicated security-scoped bookmark store with typed keys. The view should select options, call `start(request:)`, and render coordinator state.

### N4. Folder boundaries do not consistently match type responsibilities

**Evidence**

- `RawCull/Model/ParametersRsync/ItemizedOutput.swift` imports SwiftUI, maps change kinds to `Color`, and declares `ItemizedOutputRow` alongside the parser (`lines 6-35` and `95-124`).
- `HistogramLoader` and `HistogramPresentationModel` live in `Views/Histogram/HistogramView.swift` (`lines 13-107`).
- `Views/ComparisonGridView` contains loaders, cache policy, navigation policy, display-state mapping, coordinators, and image state in addition to views.
- `Views/CullingGrid` contains selection coordination and render-cache policy.

**Why it matters**

Code location communicates architectural ownership. Mixed files make it harder to enforce one-way dependencies and tempt domain/model code to import SwiftUI. They also obscure which code can be unit-tested without rendering UI.

**Recommended update**

Organize each feature into explicit layers, for example `Features/Comparison/Model`, `Features/Comparison/Presentation`, and `Features/Comparison/Views`, or retain the existing root folders but move non-view types to `Model/Presentation` and `Model/Coordinators`. Split `ItemizedOutputRecord` parsing from `ItemizedOutputRow`; keep `Color` and SF Symbol mapping in the presentation layer.

### N5. Naming conventions are inconsistent and sometimes hide intent

**Evidence**

Examples include:

- `gridthumbnailviewmodel` (`RawCull/Main/RawCullApp.swift:108`, `RawCull/Main/RawCullMainView.swift:9`);
- `currentselectedSource`, `issorting`, `creatingthumbnails`, `focusaborttask`, `showcopyARWFilesView`, and `remotedatanumbers` (`RawCull/Model/ViewModels/RawCullViewModel.swift:74-116`);
- `startcopyfiles`, `copytaggedfiles`, `itemizeparameter`, and the misspelled `updateparamter` (`RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:89-162`);
- `selecteditem`, `uutype`, `sourcecatalog`, and `destinationcatalog` in copy views;
- `filestransferred`, `totaltransferredfilessize`, `datatosynchronize`, and `defaultvalues` (`RawCull/Model/ParametersRsync/RemoteDataNumbers.swift:16-56`);
- `sshkeypathandidentityfile`, `snapdayoffweek`, and generic fields such as `parameter4` through `parameter14` (`RawCull/Model/ParametersRsync/SynchronizeConfiguration.swift:17-35`); and
- type/file names such as `OpencatalogView`, `Viewmodifiers.swift`, `extension+RawCullView.swift`, and `FocusandSharpness`.

**Why it matters**

These names slow scanning, make acronym policy unpredictable, and allow typographical mistakes to look normal. Generic numbered parameters conceal domain meaning and make invalid combinations representable.

**Recommended update**

Adopt standard lower camel case and one acronym policy: `gridThumbnailViewModel`, `currentSelectedSource`, `isSorting`, `isCreatingThumbnails`, `focusAbortTask`, `showCopyARWFilesView`, `remoteDataNumbers`, `startCopyFiles`, `copyTaggedFiles`, `selectedItem`, and `uiType` (or preferably `allowedContentType`). Rename types to `OpenCatalogView`, directories to `FocusAndSharpness`, and extension files to `RawCullView+...swift` or the extended type plus responsibility.

Perform this as mechanical, behavior-preserving batches. For `SynchronizeConfiguration`, replace numbered parameters with a typed options structure rather than merely renaming them.

### N6. Image review behavior is duplicated across three presentation paths

**Evidence**

Loupe, zoom overlay, and burst workspace independently implement image-source changes, zoom/pan, rating display, focus points, focus-mask generation, subject-outline loading, keyboard monitors, RAW failure messages, and task cancellation. Representative implementations are in:

- `RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:420-678`;
- `RawCull/Views/ZoomViews/ZoomOverlayView.swift:407-906`; and
- `RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift:441-684`.

**Why it matters**

The implementations already differ in details—for example, one path uses `MagnifyGesture`, another still uses `MagnificationGesture`; zoom limits and lifecycle handling are repeated. Fixes made to one surface can easily miss the others.

**Recommended update**

Share a testable image-review state/policy layer and small reusable controls, while allowing each screen to keep a distinct layout. Centralize source loading, mask/outline task ownership, viewport math, keyboard-action resolution, and rating presentation. Avoid forcing all three screens into one oversized reusable view.

### N7. A blanket unchecked `Sendable` conformance suppresses concurrency checking

**Evidence**

`RawCull/Main/RawCullMainView.swift:5` declares:

```swift
extension KeyPath: @unchecked @retroactive Sendable where Root == FileItem {}
```

The constraint does not restrict `Value`, and the retroactive conformance applies application-wide to every `KeyPath` rooted at `FileItem`.

**Why it matters**

`@unchecked Sendable` tells the compiler to trust a guarantee it cannot verify. The current sort key path (`\FileItem.name`) is likely safe, but the conformance also blesses future key paths with non-sendable values and can hide a real actor-boundary mistake. Retroactive conformances can additionally conflict with later SDK/library conformances.

**Recommended update**

Replace key-path transport across concurrency boundaries with a small `Sendable` sort descriptor/enum, or perform the key-path sort on the owning actor and pass an immutable sortable projection to background work. If an unchecked wrapper is unavoidable, scope it to the one concrete operation and document the invariant instead of conforming `KeyPath` globally.

### N8. Failed rsync-stat parsing can overwrite its own safe defaults

**Evidence**

When `getstats()` throws, `RemoteDataNumbers` calls `defaultvalues()` (`RawCull/Model/ParametersRsync/RemoteDataNumbers.swift:103-110`). Execution then continues and overwrites those values from the parser (`lines 112-126`). In particular, `defaultvalues()` sets `datatosynchronize = false`, while the later assignment uses `... ?? true`.

**Why it matters**

A malformed or unsupported rsync summary can be reported as containing data to synchronize even though parsing failed. This appears to affect result presentation rather than the already completed copy operation, so it is non-critical, but it is a concrete correctness defect.

**Recommended update**

Return immediately after `defaultvalues()`, or parse into a temporary value and assign the complete result only after all required parsing succeeds. Add a test that forces `getstats()` to fail and verifies every fallback field, especially `datatosynchronize`.

### N9. Presentation text and navigation state leak into the central model

**Evidence**

`AlertType`, `ActiveSheet`, `OperationFailurePresentation`, `alertTitle`, and `alertMessage` are declared on or beside `RawCullViewModel` (`RawCull/Model/ViewModels/RawCullViewModel.swift:7-68` and `273-289`). The strings are then interpreted by `RawCullMainView` as SwiftUI alerts/sheets.

**Why it matters**

This makes the central model aware of concrete presentation concepts and stores user-facing text as plain `String`, weakening localization and making alternate presentation surfaces harder to add.

**Recommended update**

Keep workflow failures typed in the feature model and map them to `LocalizedStringResource`, titles, messages, and actions in a presentation mapper near the view. A small main-window router can own sheet/navigation destinations without putting them in the catalog/culling model.

### N10. A few SwiftUI-specific cleanup items remain

**Evidence and recommendations**

- `RawCullMainView.columnVisibility` is the only non-private `@State` property (`RawCull/Main/RawCullMainView.swift:19`). Make it private so it cannot be mistaken for an input.
- `RawCullMainView` uses the older `alert(item:)` overload that returns `Alert` (`RawCull/Main/RawCullMainView.swift:116-121`). Migrate to the modern title/actions/message overload.
- `ZoomOverlayView` uses `MagnificationGesture` (`RawCull/Views/ZoomViews/ZoomOverlayView.swift:761-780`) while other code uses `MagnifyGesture`. Standardize on `MagnifyGesture` for the macOS 27 target.
- `CandidateInspectorView` identifies dynamic patch rows by their enumerated offset (`RawCull/Views/ComparisonGridView/CandidateInspectorView.swift:112-114`). Give the patch model stable identity, or use a stable property as the ID, to preserve correct SwiftUI row identity if ranking changes.
- A few files retain older spelling-only APIs such as `foregroundColor` and `cornerRadius`. These are low-risk cleanup items; modernize them only in focused edits.

**Why it matters**

None of these currently demonstrates a major runtime failure, but addressing them keeps the code aligned with the deployment target, clarifies state ownership, and avoids subtle identity problems during live updates.

### N11. Global singletons make dependencies less explicit

**Evidence**

Examples include `SettingsViewModel.shared`, `ThumbnailLoader.shared`, `SharedMemoryCache.shared`, and the direct `UserDefaults.standard` access in presentation code.

**Why it matters**

Actors make these globals concurrency-safe, and the test suite already supplies several useful overrides. The remaining globals nevertheless couple features to process-wide state and make isolated tests more complicated than necessary.

**Recommended update**

Inject protocol-typed services at the application composition root and pass them into the focused feature/session models. Keep shared live instances in `RawCullApplicationState.live()`, not at the call sites. This preserves runtime behavior while making dependencies visible.

## Recommended 3.2.5 implementation order

1. **Release blocker — completed:** the AI model catalogue, manifest, bundled-licence expectations, and smoke tests are aligned.
2. **Correctness hardening:** fix the rsync parse fallback and remove or tightly scope the blanket `KeyPath` unchecked `Sendable` conformance.
3. **First modular extraction:** introduce a session model for one image-review path (preferably `ComparisonGridView`, whose task-generation logic is already cohesive and tested), then reuse the extracted policies in Loupe and burst review.
4. **Copy boundary:** replace the `RawCullViewModel` dependency in `ExecuteCopyFiles` with an immutable request and move bookmark persistence out of `OpencatalogView`.
5. **Naming pass:** mechanically normalize the highest-traffic view-model and copy-workflow names; replace numbered synchronization parameters with typed options.
6. **Presentation cleanup:** move parser/view mixtures and presentation-only alert/sheet mapping to their proper layers, then modernize the small SwiftUI API issues.

## Suggested architectural direction

A practical target is a feature-oriented presentation layer rather than a large architecture rewrite:

```text
RawCullApplicationState (composition root)
    ├── CatalogSession
    ├── CullingSession
    ├── CopyFilesCoordinator
    ├── Similarity / Semantic Search features
    ├── Deep Review / Qwen features
    └── View-specific session models
            ├── LoupeSessionModel
            ├── ZoomSessionModel
            ├── ComparisonSessionModel
            └── BurstWorkspaceSessionModel

SwiftUI feature roots observe one focused session/feature.
Leaf views receive immutable presentation data, bindings only when they mutate parent state,
and action closures for user intents.
```

This direction preserves the strong existing service/package boundaries while moving lifecycle and workflow code out of SwiftUI value types. It also allows the 3.2.5 work to proceed incrementally, with tests added around each extracted session before the corresponding view is simplified.
