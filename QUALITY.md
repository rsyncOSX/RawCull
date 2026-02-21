# QUALITY

## 3.3 Nonisolated Static Let Singletons

- **SettingsViewModel.shared** and **SharedMemoryCache.shared** have been updated as nonisolated static let singletons.
- Note: **SharedMemoryCache** spans memory and disk coordination.

## 3.4 Naming Conventions

- The naming has been standardized for **SonyThumbnailExtractor** and **EmbeddedPreviewExtractor**, which now use caseless enums as namespaces.

## 10 Naming Conventions

- Updated to remove the phrase 'most inconsistent aspect'.
- Changed 'Issues observed (all are fixed)' to 'Recent fixes and remaining items'.

### Current State
| Aspect                    | Status                       |
|---------------------------|------------------------------|
| Extractor Names           | Fixed                        |
| RequestThumbnail Rename    | Fixed                        |
| Remaining snake_case date functions | Note if still present   |
| SavedSettings Naming      | Fixed                        |
| Scorecard Row            | Updated (removed strikethrough) and adjusted notes accordingly. |