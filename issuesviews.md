# RawCull Catalog Views — Code Review

**Reviewed files:** All views under `RawCull/Views/`, `RawCull/Main/RawCullApp.swift`, and the ViewModels they depend on.
**Date:** 2026-03-22

---

## Critical Bugs (wrong runtime behavior)

### 1. `TaggedPhotoItemView` — wrong URL in `isTagged` and `setbackground()`

**File:** `Views/ThumbnailComponents/TaggedPhotoItemView.swift:71–93`

`photoURL` is the **file** URL (e.g. `.../catalog/DSC0001.ARW`).
Both `isTagged` and `setbackground()` pass it to `CullingModel` methods that expect the **catalog/directory** URL.

```swift
// isTagged — passes file URL where catalog URL is required
cullingModel.isTagged(photo: photo, in: photoURL)     // ← wrong

// setbackground — same mistake
cullingModel.savedFiles.first(where: { $0.catalog == photoURL }) // ← never matches
```

`CullingModel.isTagged(photo:in:)` and `.savedFiles` store catalog (directory) URLs, so both properties always return `false`, meaning tagged images in this view never show their tagged state.

**Root cause also in `TaggedPhotoHorisontalGridView.swift:23`:** The outer parameter `photoURL` (catalog URL) is shadowed by a local `let photoURL = files.first(...)?.url` (file URL) inside the `ForEach`. The shadowed value is then passed to `TaggedPhotoItemView`, propagating the bug.

**Fix:** Use `photoURL.deletingLastPathComponent()` when calling into `CullingModel`, or pass the catalog URL separately from the file URL.

---

### 2. `FileTableRowView` — `onChange` self-assigns `selectedFileID`, risking an update loop

**File:** `Views/ThumbnailComponents/FileTableRowView.swift:80–99`

```swift
.onChange(of: viewModel.selectedFileID) { _, _ in
    if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
        viewModel.selectedFileID = viewModel.files[index].id   // ← assigns ID to itself
        viewModel.selectedFile   = viewModel.files[index]
    }
}
```

`viewModel.files[index].id` equals `viewModel.selectedFileID` by construction of the `firstIndex` lookup. The reassignment is a no-op but it mutates the `@Observable` property, which triggers another observation notification and can cause a redundant re-render cycle. Remove the self-assignment line.

---

### 3. Security-scoped resource is started but never stopped

**File:** `Views/RawCullSidebarMainView/extension+RawCullView.swift:111–119`

```swift
func handlePickerResult(_ result: Result<URL, Error>) {
    if case let .success(url) = result {
        if url.startAccessingSecurityScopedResource() {
            // ... appended to sources, but stop is never called
        }
    }
}
```

`stopAccessingSecurityScopedResource()` is never called. Over multiple catalog additions this leaks security-scoped kernel resources. Call `stop` when the catalog is removed or the app terminates.

---

## Concurrency Issues

### 4. Nested `Task {}` inside outer `Task {}` in `GridThumbnailSelectionView`

**File:** `Views/GridView/GridThumbnailSelectionView.swift:52–59`

```swift
onSelected: {
    Task {
        viewModel.selectFile(file)
        Task {               // ← inner unstructured Task
            await viewModel.toggleTag(for: file)
        }
    }
},
```

The inner `Task {}` is unstructured; it will not be cancelled if the outer task is cancelled. Structured concurrency is lost. Merge into one `Task`.

---

### 5. Fire-and-forget `Task {}` in `@MainActor` functions hides errors and makes completion unobservable

**Files:**
- `Model/ViewModels/CullingModel.swift:15–23` — `resetSavedFiles(in:)`
- `Model/ViewModels/RawCullViewModel.swift:243–252` — `updateRating(for:rating:)`

Both functions create a `Task {}` internally and return immediately. The JSON write `WriteSavedFilesJSON` is async, so if it fails (disk full, permission error) the caller has no way to observe it. Since both functions are already on `@MainActor`, marking them `async` and letting the caller `await` them is the correct fix.

```swift
// Current (fire-and-forget, errors silently lost)
func resetSavedFiles(in catalog: URL) {
    Task {
        ...
        await WriteSavedFilesJSON(savedFiles)
    }
}

// Preferred
func resetSavedFiles(in catalog: URL) async {
    ...
    await WriteSavedFilesJSON(savedFiles)
}
```

---

### 6. `Task(priority: .background)` does not move work off the MainActor

**File:** `Views/RawCullSidebarMainView/RawCullMainView.swift:171–177, 178–182, 183–187`

```swift
.task(id: viewModel.selectedSource) {
    ...
    Task(priority: .background) {
        await viewModel.handleSourceChange(url: url)   // still runs on MainActor
    }
}
```

The `.task` modifier body runs on `@MainActor`. `Task(priority:)` inherits that isolation, so the work still executes on the main actor — `.background` only adjusts scheduling priority. The naming creates a false impression the work is off-thread. If background-thread execution is desired, use `Task.detached(priority: .background)` with explicit isolation annotations; if not, drop the misleading priority.

The same pattern appears for `handleSortOrderChange` and `handleSearchTextChange` in `onChange` handlers.

---

### 7. Redundant `await MainActor.run {}` inside `.task` bodies

**Files:**
- `Views/ThumbnailComponents/ThumbnailImageView.swift:48–51`
- `Views/ThumbnailComponents/MainThumbnailImageView.swift:162, 180`

SwiftUI's `.task` modifier already resumes on the `@MainActor` for view structs. The `await MainActor.run { }` wrappers are no-ops — they don't add safety and mislead readers into thinking the preceding work ran off the main actor.

---

### 8. `scanning.toggle()` before `handleSourceChange` is redundant

**File:** `Views/RawCullSidebarMainView/RawCullMainView.swift:172–176`

```swift
Task(priority: .background) {
    if let url = viewModel.selectedSource?.url {
        viewModel.scanning.toggle()              // ← toggles to true
        await viewModel.handleSourceChange(url: url)  // immediately sets scanning = true again
    }
}
```

`handleSourceChange` sets `scanning = true` on its first line. The `toggle()` before it is superfluous and confusing. Remove the toggle.

---

## SwiftUI Best Practices

### 9. `@State` properties are not `private`

**Files (non-exhaustive):**
- `Views/RawCullSidebarMainView/RawCullMainView.swift:22–23` — `showhorizontalthumbnailview`, `showGridThumbnail`
- `Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:20–21` — `counterScannedFiles`, `verticalimages`
- `Views/RawCullSidebarMainView/HorizontalMainThumbnailsListView.swift:23–24` — `showInspector`, `showGridThumbnail`
- `Views/CopyFiles/CopyFilesView.swift:20–26` — `sourcecatalog`, `destinationcatalog`, `dryrun`, `copytaggedfiles`, `copyratedfiles`

The SwiftUI correctness rule: `@State` properties must be `private`. Exposing them breaks the ownership contract (only the declaring view should write them) and disables the compile-time guarantee that parent views cannot mutate child state.

---

### 10. Invisible `Label("", …).onAppear { action() }` used as action triggers (anti-pattern)

**Files:**
- `Views/RawCullSidebarMainView/TagImageFocusView.swift`
- `Views/RawCullSidebarMainView/AbortTaskFocusView.swift`
- `Views/RawCullSidebarMainView/ExtractJPGsFocusView.swift`
- `Views/RawCullSidebarMainView/RawCullMainView.swift:50–62` — `labeltagimage`
- `Views/RawCullSidebarMainView/HorizontalMainThumbnailsListView.swift:84, 88–100`

Pattern:
```swift
Label("", systemImage: "play.fill")
    .onAppear {
        flag = false
        doAction()
    }
```

Problems:
- `onAppear` is not guaranteed to fire exactly once per flag change; SwiftUI can defer or batch view updates.
- A zero-text `Label` with no accessibility label is invisible to VoiceOver.
- The view takes layout space (even though visually zero-height).
- The correct tool is `.onChange(of: flag)` which fires precisely when the value changes, or calling the function directly from the keyboard handler that sets the flag.

---

### 11. `ImageTableHorizontalView` fetches settings async when environment already available

**File:** `Views/ThumbnailComponents/ImageTableHorizontalView.swift:88–90`

```swift
.task {
    savedSettings = await SettingsViewModel.shared.asyncgetsettings()
}
```

`SettingsViewModel` is injected into the environment and consumed in sibling views. The async fetch causes a `nil` → loaded flash (the scroll view is hidden until settings arrive). Use `@Environment(SettingsViewModel.self) private var settings` — already established in `GridThumbnailSelectionView` and `ImageTableVerticalView`.

---

### 12. Non-sortable `TableColumn` uses `\.id` as sort key

**File:** `Views/ThumbnailComponents/FileTableRowView.swift:31–39`

```swift
TableColumn("", value: \.id) { file in  // UUID sort on a checkbox column
    Button(...)
```

The checkbox/toggle column has no meaningful sort semantic. `UUID` sorts lexicographically, giving an arbitrary order. Use the non-sortable `TableColumn` initialiser (`TableColumn("") { file in ... }`) so the column header is not tappable as a sort trigger.

---

### 13. Inspector binding is semantically inverted

**File:** `Views/RawCullSidebarMainView/RawCullMainView.swift:159`

```swift
.inspector(isPresented: $viewModel.hideInspector)
```

The property is named `hideInspector`, but `.inspector(isPresented:)` shows the panel when the value is `true`. Rename to `showInspector` (or `inspectorVisible`) so the intent is self-documenting.

---

### 14. Deprecated `.foregroundColor` in `SidebarARWCatalogFileView`

**File:** `Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:145`

```swift
.foregroundColor(Color.green)
```

`foregroundColor(_:)` is deprecated. Replace with `.foregroundStyle(.green)`.

---

### 15. `TagButtonView.onToggle` closure is stored but never called

**File:** `Views/ThumbnailComponents/TagButtonView.swift`

```swift
var onToggle: () -> Void    // stored, never invoked inside the view
```

The view renders a circular icon that appears interactive but has no tap handler. The toggle logic is entirely deferred to parent views that don't always wire it up (e.g., `TaggedPhotoItemView` passes `onToggle: {}`). Either:
- Add `.onTapGesture { onToggle() }` inside `TagButtonView`, or
- Remove the closure parameter if parents own the tap handling.

---

## Performance Issues

### 16. `grainOverlay` regenerates random noise on every re-render

**File:** `Views/FileViews/FileDetailView.swift:85–100`

```swift
var grainOverlay: some View {
    Canvas { context, size in
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< Int(size.width * size.height * 0.015) {
            let x = CGFloat.random(in: 0 ..< size.width, using: &rng)
            ...
```

`grainOverlay` is a computed property recomputed on every SwiftUI diffing pass. Each evaluation re-generates thousands of random pixel positions, producing visible noise-pattern flickering on any parent state change. Use a fixed seed or generate the grain once into a cached image.

---

### 17. Duplicate `filteredFiles` / `sortedFiles` computed properties sort on every render

**Files:**
- `Views/ThumbnailComponents/ImageTableVerticalView.swift:185–195`
- `Views/ThumbnailComponents/ImageTableHorizontalView.swift:145–155`

Both views independently re-filter `viewModel.filteredFiles` by rating and re-sort by name on every render pass:

```swift
private var sortedFiles: [FileItem] {
    filteredFiles.sorted { lhs, rhs in
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
```

This runs `O(n log n)` on the main thread on every view update. The same rating filter and sort are already available through the ViewModel. Move the logic into the ViewModel where it can be updated lazily via `handleSortOrderChange`, caching the result.

---

## Code Quality / Maintainability

### 18. `showGridtaggedThumbnailWindow()` is duplicated verbatim in two extensions

**Files:**
- `Views/RawCullSidebarMainView/extension+RawCullView.swift:92–102`
- `Views/RawCullSidebarMainView/HorizontalMainThumbnailsListView.swift:190–200`

Identical private helper. Extract to a free function or a shared extension on `RawCullViewModel`.

---

### 19. Dead `focusPoints` computed property in `FileDetailView`

**File:** `Views/FileViews/FileDetailView.swift:102–104`

```swift
var focusPoints: [FocusPoint]? {
    viewModel.getFocusPoints()
}
```

This property is never referenced anywhere in `FileDetailView`'s body. Focus points are consumed in `MainThumbnailImageView`. Remove the dead property.

---

### 20. Variable shadowing in `TaggedPhotoHorisontalGridView` obscures catalog URL

**File:** `Views/TaggingGridView/TaggedPhotoHorisontalGridView.swift:19–26`

```swift
let photoURL: URL?     // outer — this is the CATALOG directory URL
...
ForEach(localfiles.sorted(), id: \.self) { photo in
    let photoURL = files.first(where: { $0.name == photo })?.url   // ← shadows with FILE url
    TaggedPhotoItemView(..., photoURL: photoURL, ...)               // passes file URL
```

The outer `photoURL` (catalog URL) is silently replaced by the inner `photoURL` (file URL). This is the root of the bug in issue #1. Rename the inner variable to `photoFileURL` to eliminate the shadow.

---

### 21. Zoom window state duplicated between `RawCullApp` and `RawCullViewModel`

**File:** `Main/RawCullApp.swift:24–25` vs `Model/ViewModels/RawCullViewModel.swift:48–49`

`RawCullApp` has `@State private var zoomCGImageWindowFocused` and `@State private var zoomNSImageWindowFocused`. `RawCullViewModel` also declares `var zoomCGImageWindowFocused` and `var zoomNSImageWindowFocused`. The two copies are never synchronised. The in-code comment `// ← pass viewModel instead` on line 62 of `RawCullApp.swift` acknowledges the design is incomplete. One source of truth should be chosen; the ViewModel copies appear unused.

---

*End of review. Issues are ordered by severity within each category.*
