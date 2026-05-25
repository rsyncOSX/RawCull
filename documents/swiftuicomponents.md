# SwiftUI Reusable Component Analysis — RawCull

> Deep analysis across **69 Swift view files** in `RawCull/Views/` plus `Main/`, `Extensions/`, and `Model/`.  
> The goal is to identify patterns that repeat across multiple call-sites and are strong candidates for extraction into dedicated, parameterised components.

---

## 1. Already-Extracted Components (Good baseline)

These components exist and do the right thing. Listed for completeness and to avoid duplicating them.

| Component | File | What it does |
|---|---|---|
| `RefinedGlassButtonStyle` | `Views/Modifiers/ButtonStyles.swift` | Glass-material button with spring press animation |
| `ConditionalGlassButton` | `Views/Modifiers/ButtonStyles.swift` | Icon+label button with `.softCapsule` material pill style |
| `ToggleViewDefault` | `Views/Modifiers/Viewmodifiers.swift` | Toggle + coloured label helper |
| `ThumbnailKeyNavigationModifier` | `Views/ThumbnailComponents/ThumbnailKeyNavigationModifier.swift` | Keyboard arrow-key navigation modifier with `View.thumbnailKeyNavigation(…)` helper |
| `RatingFilterButtons` | `Views/ThumbnailComponents/RatingFilterButtons.swift` | Colour-dot + keeper pill + clear filter row |
| `CurrentRatingBadgeView` | `Views/ThumbnailComponents/RatingControlsView.swift` | Capsule rating indicator (icon + label) |
| `RatingActionBarView` | `Views/ThumbnailComponents/RatingControlsView.swift` | Material-capsule row of circular rating buttons |
| `ThumbnailImageView` | `Views/ThumbnailComponents/ThumbnailImageView.swift` | Async thumbnail loader with shimmer/placeholder states |
| `ImageOverlayControlsView` | `Views/ThumbnailComponents/ImageOverlayControlsView.swift` | Bottom control bar (focus mask, focus points, zoom pill) |
| `SettingsCard` | `Views/Settings/SettingsCard.swift` | Generic `@ViewBuilder` container with control-background fill + corner radius |
| `SettingsSliderRow` | `Views/Settings/SettingsSliderRow.swift` | `Label + value + Slider + description` form row |
| `LabeledSlider` | `Views/FocusPeek/LabeledSlider.swift` | Compact `caption + Slider + hint` (similar to `SettingsSliderRow` — see §4.1) |
| `SettingsResetSaveButtons` | `Views/Settings/SettingsResetSaveButtons.swift` | Reset + optional middle + Save button pair with confirmation dialogs |
| `CommandButton` | `Views/Tools/MenuCommands.swift` | Menu command button wrapper with optional keyboard shortcut |
| `ProgressCount` | `Views/Progress/ProgressCount.swift` | Circular progress ring + status text + ETA label |

---

## 2. High-Value Candidates — Extract Now

These patterns appear **3 or more times** with near-identical code and clear, stable interfaces.

---

### 2.1 `StatusChipView` — tiny monospaced text badge

**Pattern:** `Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 2).background(color.opacity(…), in: RoundedRectangle(cornerRadius: 3))`

This exact shape appears **7 times** across four files — as separate structs and as local private functions. They are structurally identical apart from the string and colour.

| Location | What it represents |
|---|---|
| `Views/ThumbnailComponents/ImageItemView.swift:80–99` | `SharpnessBadgeView` (Sharp / Good / Check / Soft) |
| `Views/ThumbnailComponents/ImageItemView.swift:103–122` | `SaliencyBadgeView` (subject label) |
| `Views/ThumbnailComponents/ImageItemView.swift:126–135` | `NoSubjectBadgeView` ("~") |
| `Views/ThumbnailComponents/ImageItemView.swift:139–148` | `PickedBadgeView` ("P") |
| `Views/ThumbnailComponents/ImageItemView.swift:180–211` | `rankBadge(_:)` and `statusBadge(_:color:)` private helpers inside `BurstCandidateBadgeView` |
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:207–231` | `sharpnessBadge(for:)` — monospaced text chip with delta parts |
| `Views/RawCullSidebarMainView/RAWCatalogSidebarView.swift` | `.badge(…)` on list items |

**Draft interface:**

```swift
struct StatusChipView: View {
    let text: String
    let color: Color
    var opacity: Double = 0.80
    var cornerRadius: CGFloat = 3
}
```

The five badge view structs (`SharpnessBadgeView`, `SaliencyBadgeView`, `NoSubjectBadgeView`, `PickedBadgeView`, and the two private helpers) could all be reduced to wrappers that call `StatusChipView`.

---

### 2.2 `ThumbnailSelectionOverlay` — selection border + glow shadow

**Pattern:**
```
.overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0))
.shadow(color: isSelected ? Color.accentColor.opacity(0.65) : .clear, radius: isSelected ? 8 : 0)
.clipShape(RoundedRectangle(cornerRadius: 4))
```

Appears **5 times** across thumbnail and grid views. The values (corner radius 4, line width 3, opacity 0.65, shadow radius 8) are consistent. The only variation is whether `isMultiSelected` adds a teal border at a different width.

| Location | Context |
|---|---|
| `Views/ThumbnailComponents/ImageItemView.swift:337–346` | Grid thumbnail inner image frame |
| `Views/ThumbnailComponents/ImageItemView.swift:364–369` | Grid thumbnail outer card border |
| `Views/ThumbnailComponents/RatedImageItemView.swift:61–69` | Rated-grid card inner frame |
| `Views/ThumbnailComponents/RatedImageItemView.swift:83–90` | Rated-grid card outer border |
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:59–67` | Comparison pane frame |

**Draft interface:**

```swift
// As a ViewModifier
struct ThumbnailSelectionModifier: ViewModifier {
    let isSelected: Bool
    let isMultiSelected: Bool
    var cornerRadius: CGFloat = 4
}

extension View {
    func thumbnailSelection(isSelected: Bool, isMultiSelected: Bool = false, cornerRadius: CGFloat = 4) -> some View
}
```

---

### 2.3 `MultiSelectCheckmark` — top-corner checkmark badge overlay

**Pattern:** `.overlay(alignment: .topTrailing) { if isMultiSelected { Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white, Color.teal).padding(5).shadow(radius: 2) } }`

Code is **character-for-character identical** in two files, and would logically appear in any future third grid view.

| Location |
|---|
| `Views/ThumbnailComponents/ImageItemView.swift:304–313` |
| `Views/ThumbnailComponents/RatedImageItemView.swift:52–60` |

**Draft interface:**

```swift
struct MultiSelectCheckmark: View {
    let isVisible: Bool          // renders nothing when false
}
// Used as: .overlay(alignment: .topTrailing) { MultiSelectCheckmark(isVisible: isMultiSelected) }
```

---

### 2.4 `RatingColorStrip` — rating colour bar at bottom of card

**Pattern:** `if let color = ratingColor { color.frame(height: 4) }` where `ratingColor` maps `-1→.red, 2→.yellow, 3→.green, 4→.blue, 5→.purple`.

The same integer→colour mapping and 4 pt height appear **twice** with duplicated `ratingColor` computed property logic.

| Location |
|---|
| `Views/ThumbnailComponents/ImageItemView.swift:359–362` + private `ratingColor` property |
| `Views/ThumbnailComponents/RatedImageItemView.swift:76–79` + private `ratingColor` property |

**Draft interface:**

```swift
struct RatingColorStrip: View {
    let rating: Int       // -1, 0, 2–5; nil-safe (shows nothing for unrated/0)
    var height: CGFloat = 4
}
```

The colour mapping logic should live once inside this view, removing the duplicated private properties.

---

### 2.5 `MaterialPillGroup` — icon buttons wrapped in a material capsule

**Pattern:** `HStack { Button…; Button…; Button… }.buttonStyle(.plain).padding(.horizontal, X).padding(.vertical, Y).background(.regularMaterial).clipShape(Capsule() or .rect(cornerRadius: 20))`

| Location | Contents |
|---|---|
| `Views/ThumbnailComponents/ImageOverlayControlsView.swift:79–116` | Zoom out / Reset / Zoom in |
| `Views/ThumbnailComponents/ImageOverlayControlsView.swift:61–77` | Inspector toggle button |
| `Views/ThumbnailComponents/RatingControlsView.swift:103–125` | Rating action buttons (already uses `.regularMaterial` Capsule) |
| `Views/FocusPeek/FocusMaskControlsView.swift` | Focus-mask toggle pill |
| `Views/FocusPoints/FocusPointControllerView.swift` | Focus-points toggle pill |
| `Views/ZoomViews/ImageSourceToggleView.swift` | Source toggle pill |
| `Views/ThumbnailComponents/ImageTableVerticalView.swift:80+` | Navigation chevrons overlay pill |

The capsule styling (material background, 20 pt corner radius, 12/6 padding) repeats across all of these. A `@ViewBuilder`-based container could unify them.

**Draft interface:**

```swift
struct MaterialPillGroup<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 6
    @ViewBuilder let content: () -> Content
}
```

---

### 2.6 `SliderFormRow` — unified slider row (consolidate `SettingsSliderRow` + `LabeledSlider`)

`SettingsSliderRow` (settings tabs) and `LabeledSlider` (FocusPeek, ScoringParametersSheetView) implement essentially the same layout — a label row above a `Slider` above a description — but with slightly different font sizes and one using `Double`, the other `Float`. They exist in different files and are applied inconsistently: some ad-hoc slider rows in `ScoringParametersSheetView` don't use either.

| Uses `SettingsSliderRow` | Uses `LabeledSlider` | Ad-hoc inline |
|---|---|---|
| `Views/Settings/FocusSettingsTab.swift` | `Views/GridView/ScoringParametersSheetView.swift:79+` | `Views/GridView/ScoringParametersSheetView.swift:54–68` |
| `Views/Settings/ThumbnailSizesTab.swift` | `Views/FocusPeek/FocusMaskControlsView.swift` | `Views/Settings/CacheSettingsTab.swift` |
| `Views/GridView/SharpnessControlsView.swift` | | |

**Draft:** Merge into one generic row and retire `LabeledSlider`:

```swift
struct SliderFormRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    var systemImage: String = ""
    let description: String
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride? = nil
}
```

---

## 3. Medium-Value Candidates — Worth Extracting

These patterns appear **2 times** or have slightly more variability, but are still good extraction candidates.

---

### 3.1 `EmptyImagePlaceholder` — icon + caption for missing/unavailable images

**Pattern:** `Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)` + `Text("No preview available").font(.caption).foregroundStyle(.secondary)` inside a `VStack(spacing: 8)`.

| Location | Text shown |
|---|---|
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:290–305` | "No preview available" / "Extracting image…" |
| `Views/ThumbnailComponents/RatedImageItemView.swift:42–49` | "No image available" (uses `Label`) |
| `Views/CullingGrid/CullingGridView.swift` | Empty catalog state |

**Draft interface:**

```swift
struct EmptyImagePlaceholder: View {
    var systemImage: String = "photo"
    var message: String = "No preview available"
    var isLoading: Bool = false          // shows ProgressView instead when true
    var loadingMessage: String = "Loading…"
}
```

---

### 3.2 `MaterialHeaderStrip` — material-background header/footer bar inside overlays

**Pattern:** `VStack/HStack { … }.padding(.horizontal, X).padding(.vertical, Y).background(.regularMaterial).clipShape(.rect(cornerRadius: 8))`

Used as both the top header overlay and the EXIF footer strip in the comparison pane, and similarly in `MainThumbnailImageView`.

| Location | Role |
|---|---|
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:137–173` | `headerOverlay` — filename + badges |
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:233–253` | `exifFooter` — exposure + gear text |
| `Views/ThumbnailComponents/MainThumbnailImageView.swift` | Metadata bar at bottom of loupe view |

**Draft interface:**

```swift
struct MaterialHeaderStrip<Content: View>: View {
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    @ViewBuilder let content: () -> Content
}
```

---

### 3.3 `ToolbarActionButton` — `Label + help + disabled` toolbar button

Every toolbar in the app uses a repeating construct:

```swift
Button { action() } label: { Label("Title", systemImage: "symbol") }
    .help("Tooltip")
    .disabled(someCondition)
```

This appears **~14 times** inside `SharedMainToolbarContent` alone and recurs in `CullingGridView`, `SimilarityGridSelectionView`, `SavedFilesView`, and `GridThumbnailSelectionView`. The `CommandButton` struct in `MenuCommands.swift` partially solves this for menu commands, but not for toolbar items.

| File | Approximate count of occurrences |
|---|---|
| `Views/RawCullSidebarMainView/SharedMainToolbarContent.swift` | ~10 |
| `Views/CullingGrid/CullingGridView.swift` | ~4 |
| `Views/SimilarityGridView/SimilarityGridSelectionView.swift` | ~3 |
| `Views/SavedFiles/SavedFilesView.swift` | ~2 |
| `Views/GridView/GridThumbnailSelectionView.swift` | ~2 |

**Draft interface:**

```swift
struct ToolbarActionButton: View {
    let title: String
    let systemImage: String
    let help: String
    var isDisabled: Bool = false
    let action: () -> Void
}
```

---

### 3.4 `SettingsToggleRow` — labelled toggle with description

Settings tabs create `Toggle` + `Text(description)` pairs ad-hoc several times. `ToggleViewDefault` exists but only does the icon-less inline case and isn't used consistently.

| Location |
|---|
| `Views/Settings/FocusSettingsTab.swift` (multiple toggles) |
| `Views/GridView/ScoringParametersSheetView.swift:72–76` |
| `Views/Settings/CacheSettingsTab.swift` |
| `Views/Settings/ThumbnailSizesTab.swift` |

**Draft interface:**

```swift
struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let description: String
    @Binding var isOn: Bool
}
```

---

### 3.5 `HoverScaleEffect` — subtle scale-on-hover for grid cells

**Pattern:** `.scaleEffect(isHovered ? 1.02 : 1.0).animation(.easeOut(duration: 0.15), value: isHovered)`

| Location |
|---|
| `Views/ThumbnailComponents/ImageItemView.swift:374–375` |
| `Views/GridView/GridThumbnailView.swift` |
| `Views/SimilarityGridView/SimilarityGridView.swift` |

**Draft interface (ViewModifier):**

```swift
struct HoverScaleModifier: ViewModifier {
    let isHovered: Bool
    var scale: CGFloat = 1.02
    var duration: Double = 0.15
}

extension View {
    func hoverScale(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View
}
```

---

## 4. Low-Value / Opportunistic

These are smaller or more contextual patterns. Extraction is optional; worth tracking.

---

### 4.1 Consolidate `SettingsSliderRow` and `LabeledSlider` usage

Already covered in §2.6 above, but worth noting: `SettingsSliderRow` has `systemImage` and `description` fields while `LabeledSlider` does not. Neither is used consistently — some Form sections in `ScoringParametersSheetView` create the VStack+HStack+Slider pattern inline without using either. A single component would eliminate all three shapes.

---

### 4.2 `MemoryLegendDot` — coloured dot + label in memory stats

**Pattern:** `HStack(spacing: 4) { Circle().fill(Color.X).frame(width: 8, height: 8); Text("…").font(.system(size: 10)) }` 

Appears 2–3 times inside `Views/Settings/MemoryTab.swift` for the memory bar legend.

---

### 4.3 `SectionTitleBar` — sheet title row (label + dismiss/action buttons)

The title bar pattern `HStack { Label(title).font(.title3.bold()); Spacer(); Button("Reset"); Button("Done") }` is used in `ScoringParametersSheetView` and has close analogues in other sheet views. A generic title bar component would keep sheet chrome consistent.

---

### 4.4 `ExifMetadataRow` — monospaced exposure / gear text

**Pattern:** `Text(parts.joined(separator: " · ")).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)`

| Location |
|---|
| `Views/ComparisonGridView/ComparisonImagePaneView.swift:235–248` (two rows) |
| `Views/FileViews/FileDetailView.swift` |
| `Views/OutputViews/DetailsView.swift` |

---

## 5. Existing `ConditionalGlassButton` — Incomplete Implementation

`ButtonStyles.swift` defines `ConditionalGlassButton` with two style options: `.refinedGlass` and `.softCapsule`. However the `if style == .softCapsule { … }` block has no `else` branch, meaning the `.refinedGlass` path silently renders nothing. This is a latent bug, not just a reuse opportunity.

---

## 6. Summary Table

| # | Candidate | Files affected | Usage sites | Priority |
|---|---|---|---|---|
| 2.1 | `StatusChipView` | 3 | 7 | 🔴 High |
| 2.2 | `ThumbnailSelectionModifier` | 3 | 5 | 🔴 High |
| 2.3 | `MultiSelectCheckmark` | 2 | 2 | 🔴 High |
| 2.4 | `RatingColorStrip` | 2 | 2 | 🔴 High |
| 2.5 | `MaterialPillGroup` | 7 | 7+ | 🔴 High |
| 2.6 | `SliderFormRow` (merge) | 5 | 8+ | 🔴 High |
| 3.1 | `EmptyImagePlaceholder` | 3 | 3 | 🟡 Medium |
| 3.2 | `MaterialHeaderStrip` | 2 | 3 | 🟡 Medium |
| 3.3 | `ToolbarActionButton` | 5 | ~21 | 🟡 Medium |
| 3.4 | `SettingsToggleRow` | 4 | ~6 | 🟡 Medium |
| 3.5 | `HoverScaleModifier` | 3 | 3 | 🟡 Medium |
| 4.2 | `MemoryLegendDot` | 1 | 3 | 🟢 Low |
| 4.3 | `SectionTitleBar` | 2 | 2 | 🟢 Low |
| 4.4 | `ExifMetadataRow` | 3 | 4 | 🟢 Low |

---

## 7. Suggested Target Location

All new shared components should live in `Views/ThumbnailComponents/` (for thumbnail-specific ones) or a new `Views/SharedComponents/` folder for app-wide reusables, keeping the `Views/Modifiers/` folder for pure `ViewModifier` types.

```
Views/
  Modifiers/
    ButtonStyles.swift        ← existing
    Viewmodifiers.swift       ← existing
    ThumbnailSelectionModifier.swift   ← new (§2.2)
    HoverScaleModifier.swift           ← new (§3.5)
  SharedComponents/           ← new folder
    StatusChipView.swift               ← §2.1
    MultiSelectCheckmark.swift         ← §2.3
    RatingColorStrip.swift             ← §2.4
    MaterialPillGroup.swift            ← §2.5
    SliderFormRow.swift                ← §2.6 (replaces LabeledSlider)
    EmptyImagePlaceholder.swift        ← §3.1
    MaterialHeaderStrip.swift          ← §3.2
    ToolbarActionButton.swift          ← §3.3
    SettingsToggleRow.swift            ← §3.4
    ExifMetadataRow.swift              ← §4.4
```
