# Refactor Review (SwiftUI + Concurrency)

Scope: project-wide scan for duplicate UI patterns, repeated async workflows, and concurrency smells. Findings are grouped by file with suggested refactors and short before/after sketches.

## Findings

### RawCull/RawCull/Views/ThumbnailComponents/TaggedPhotoItemView.swift (lines ~72–93)
**Rule: Avoid `Task {}` inside `onAppear` for async work; prefer `.task` for automatic cancellation.**

```swift
// Before
.onAppear {
    guard let url = photoURL else { return }
    isLoading = true
    Task {
        let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
        let thumbnailSizePreview = settingsmanager.thumbnailSizePreview
        let cgThumb = await RequestThumbnail().requestThumbnail(
            for: url,
            targetSize: thumbnailSizePreview
        )
        ...
        isLoading = false
    }
}

// After
.task(id: photoURL) {
    guard let url = photoURL else { return }
    isLoading = true
    let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
    let thumbnailSizePreview = settingsmanager.thumbnailSizePreview
    let cgThumb = await RequestThumbnail().requestThumbnail(
        for: url,
        targetSize: thumbnailSizePreview
    )
    ...
    isLoading = false
}
```

### RawCull/RawCull/Views/RawCullSidebarMainView/RawCullMainView.swift (lines ~159–168)
**Rule: Avoid nesting `Task {}` inside `.task`; use `.task(priority:id:)` directly.**

```swift
// Before
.task(id: viewModel.selectedSource) {
    guard viewModel.currentselectedSource != viewModel.selectedSource else { return }
    viewModel.currentselectedSource = viewModel.selectedSource

    Task(priority: .background) {
        if let url = viewModel.selectedSource?.url {
            viewModel.scanning.toggle()
            await viewModel.handleSourceChange(url: url)
        }
    }
}

// After
.task(priority: .background, id: viewModel.selectedSource) {
    guard viewModel.currentselectedSource != viewModel.selectedSource else { return }
    viewModel.currentselectedSource = viewModel.selectedSource

    if let url = viewModel.selectedSource?.url {
        viewModel.scanning.toggle()
        await viewModel.handleSourceChange(url: url)
    }
}
```

### RawCull/RawCull/Views/ThumbnailComponents/ImageItemView.swift (lines ~113–125)
### RawCull/RawCull/Views/ThumbnailComponents/TaggedPhotoItemView.swift (lines ~108–123)
**Duplicate component: Tag button UI appears in multiple views with near-identical styles.**

Extract a reusable `TagButtonView(isTagged:isHovered:action:)` or a `ViewModifier` so the tag UI is consistent and centralized.

```swift
// Before (two places)
Image(systemName: isTagged ? "checkmark.circle.fill" : "circle")
    .font(.system(size: isHovered ? 14 : 10))
    .foregroundStyle(isTagged ? Color.green : Color.white.opacity(0.8))
    .shadow(color: .black.opacity(0.5), radius: 2)
    .padding(5)
    .background(.ultraThinMaterial)
    .clipShape(Circle())
    .padding(5)

// After
TagButtonView(isTagged: isTagged, isHovered: isHovered, action: onToggle)
```

### RawCull/RawCull/Views/ThumbnailComponents/ImageItemView.swift
### RawCull/RawCull/Views/ThumbnailComponents/TaggedPhotoItemView.swift
### RawCull/RawCull/Views/ThumbnailComponents/MainCachedThumbnailView.swift
**Duplicate component: Thumbnail loading + placeholder logic is repeated using different code paths.**

Suggestion: extract a single `ThumbnailImageView` that accepts `fileURL`, `targetSize`, and `style` (grid vs. list). It can internally choose `ThumbnailLoader` or `RequestThumbnail` and expose consistent placeholders and shimmer.

```swift
// Before (multiple views)
.task { thumbnailImage = await ThumbnailLoader.shared.thumbnailLoader(file: file) }
// ...and elsewhere
let cgThumb = await RequestThumbnail().requestThumbnail(for: url, targetSize: size)

// After
ThumbnailImageView(fileURL: file.url, targetSize: size, style: .grid)
```

### RawCull/RawCull/Views/GridView/GridThumbnailSelectionView.swift (lines ~82–85)
### RawCull/RawCull/Views/ThumbnailComponents/FileTableImageView.swift (lines ~76–79)
### RawCull/RawCull/Views/ThumbnailComponents/ImageTableVerticalView.swift (lines ~48–59)
**Duplicate logic: Selection and tagging actions repeat across views.**

Unify into `RawCullViewModel` helpers, e.g. `selectFile(_:)` and `toggleTag(for:)`.

```swift
// Before
viewModel.selectedFileID = file.id
viewModel.selectedFile = file
Task { await cullingModel.toggleSelectionSavedFiles(in: file.url, toggledfilename: file.name) }

// After
viewModel.selectFile(file)
await viewModel.toggleTag(for: file)
```

### RawCull/RawCull/Views/GridView/GridThumbnailSelectionView.swift (line ~72)
### RawCull/RawCull/Views/ThumbnailComponents/FileTableImageView.swift (line ~66)
### RawCull/RawCull/Views/ThumbnailComponents/ImageTableVerticalView.swift (line ~167)
### RawCull/RawCull/Views/TaggingGridView/TaggedPhotoHorisontalGridView.swift (line ~43)
### RawCull/RawCull/Views/ThumbnailComponents/TaggedPhotoItemView.swift (lines ~79 and ~104)
**Duplicate async settings fetch: `SettingsViewModel.shared.asyncgetsettings()` appears in many views.**

Consider a shared `@Environment(SettingsViewModel.self)` or a higher-level `SavedSettings` injection to avoid repeated tasks and state churn. This also simplifies previews and reduces background tasks.

```swift
// Before
@State private var savedSettings: SavedSettings?
.task { savedSettings = await SettingsViewModel.shared.asyncgetsettings() }

// After
@Environment(SettingsViewModel.self) private var settings
let savedSettings = settings.savedSettings
```

### RawCull/RawCull/Views/ThumbnailComponents/TaggedPhotoItemView.swift (lines ~119–136)
### RawCull/RawCull/Views/ThumbnailComponents/ImageItemView.swift (lines ~160–166)
**Duplicate state queries: Tag status is computed directly from `savedFiles` in multiple views.**

Extract into a single model method (e.g. `cullingModel.isTagged(in:fileName:)`) and use it everywhere to prevent drift and to centralize the data source.

```swift
// Before
cullingModel.savedFiles[index].filerecords?.contains { $0.fileName == photo } ?? false

// After
cullingModel.isTagged(in: photoURL, fileName: photo)
```

## Priority Summary
1. **High:** Replace `Task` inside `onAppear` with `.task` to avoid uncancelled work (TaggedPhotoItemView).
2. **High:** Remove nested `Task` inside `.task` in RawCullMainView by using `.task(priority:id:)`.
3. **Medium:** Extract a shared `ThumbnailImageView` to reduce duplicate loading/placeholder logic.
4. **Medium:** Centralize `SavedSettings` access to reduce repeated async tasks in views.
5. **Low:** Unify selection/tagging handlers into `RawCullViewModel` helpers for consistency.
6. **Low:** Consolidate tag button UI and tag-status query logic into shared components/model methods.
