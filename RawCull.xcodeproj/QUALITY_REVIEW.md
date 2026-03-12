# RawCull SwiftUI-Pro QA Review

Date: 2026-03-12

## Summary
Overall quality is strong and trending in the right direction. The UI architecture is mostly clean, and recent refactors improved maintainability. The remaining issues are mostly consistency with modern SwiftUI APIs and a few accessibility/formatting details.

## Findings By File

### RawCull/Views/FocusPeek/FocusDetectorControlsView.swift

**Line 58: Avoid `String(format:)` for user-visible values.**
Use `FormatStyle` for numeric display.

```swift
// Before
Text(String(format: "%.2f", value))

// After
Text(value, format: .number.precision(.fractionLength(2)))
```

**Line 65: Avoid `.caption2` for accessibility.**
`.caption2` is very small and often fails Dynamic Type expectations.

```swift
// Before
Text(hint).font(.caption2)

// After
Text(hint).font(.caption)
```

### RawCull/Views/RawCullSidebarMainView/extension+RawCullView.swift

**Line 36: Avoid `String(format:)` for user-visible values.**
Use `FormatStyle` for percent formatting.

```swift
// Before
Text("Reset \(String(format: \"%.0f%%\", viewModel.scale * 100))")

// After
Text("Reset \(viewModel.scale * 100, format: .number.precision(.fractionLength(0)))%")
```

### RawCull/Views/Settings/CacheSettingsTab.swift

**Line 242: Avoid `String(format:)` for user-visible formatting.**
Prefer `ByteCountFormatStyle` for bytes.

```swift
// Before
return String(format: "%.1f %@", size, units[min(unitIndex, units.count - 1)])

// After
return ByteCountFormatStyle(style: .memory).format(Int64(bytes))
```

### RawCull/Extensions/extension+Thread+Logger.swift

**Line 55: Avoid `Task.sleep(nanoseconds:)`.**
Use `Task.sleep(for:)` instead.

```swift
// Before
try await Task.sleep(nanoseconds: duration)

// After
try await Task.sleep(for: .nanoseconds(duration))
```

## Notes
- Many earlier SwiftUI API issues (legacy `onChange`, `cornerRadius`, etc.) were already addressed in the recent refactor.
- If you want, I can sweep the remaining view files for fixed font sizes and other accessibility improvements, but that will produce a longer change list.
