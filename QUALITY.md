# QA Audit Checklist — RawCull

> **Audit date:** 2026-02-21  
> **Audited by:** GitHub Copilot  
> **Repository:** https://github.com/rsyncOSX/RawCull  
> **Primary language:** Swift (macOS, SwiftUI + AppKit)

This document is a **checklist-style QA / code-quality audit**. Each item is marked as:
- **PASS** (meets expectation)
- **WARN** (acceptable but should improve)
- **FAIL** (needs change)
- **N/A** (not applicable / not observed)

---

## 0. Scope & Evidence

- **Scope:** repository state on `main` as of 2026-02-21.
- **Evidence:** Links point to representative files/sections. This is not an exhaustive static analysis run.

---

## 1. Architecture & Design (MVVM boundaries)

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| ARCH-001 | MVVM separation is clear (Views thin, ViewModels own state, background work isolated) | PASS | `RawCull/Model/ViewModels/RawCullViewModel.swift`, `RawCull/Views/...` | Overall structure is consistent. |
| ARCH-002 | ViewModels that mutate UI state are `@MainActor` or otherwise main-thread safe | PASS | `ExecuteCopyFiles` is `@Observable @MainActor` | Ensure other UI-mutating models remain main-actor bound. |
| ARCH-003 | Dependency injection used for progress/reporting rather than tight coupling | PASS | `FileHandlers` pattern used by actors | Good testability pattern. |
| ARCH-004 | Singleton usage is minimal and justified | WARN | `SettingsViewModel.shared`, `SharedMemoryCache.shared` | Acceptable for app-wide config/cache; document invariants. |

---

## 2. Concurrency Model (actors, isolation, cancellation)

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| CONC-001 | Heavy I/O and CPU work isolated from UI thread | PASS | actors in `RawCull/Actors/` | Good separation overall. |
| CONC-002 | Actor isolation not violated from detached tasks (no `self` capture of actor-isolated state) | ~~FAIL~~ (fixed) | `RawCull/Actors/DiscoverFiles.swift` uses `Task.detached` and references `self.supported` | Fix by copying `supported` into a local `let` before the detached closure. |
| CONC-003 | Cancellation checks exist in long-running work | PASS | `ScanAndCreateThumbnails.processSingleFile` checks `Task.isCancelled` | Continue to propagate cancellation in loops/groups. |
| CONC-004 | Detached tasks capture only what they need (avoid retaining whole actor) | PASS | `ScanAndCreateThumbnails` captures `dcache` | Good pattern; keep it consistent. |
| CONC-005 | `nonisolated(unsafe)` usage is justified and documented | WARN | `SharedMemoryCache`/NSCache pattern implied by usage | Ensure comments explain thread-safety assumptions where used. |

---

## 3. Thumbnail Pipeline & Caching (RAM + disk + extraction)

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| CACHE-001 | RAM cache checked first, then disk, then extract (clear layered design) | PASS | `RawCull/Actors/RequestThumbnail.swift` | Correct lookup order. |
| CACHE-002 | Disk cache keys stable and collision-resistant for this use | PASS | `RawCull/Actors/DiskCacheManager.swift` uses MD5 of standardized path | MD5 ok for non-security caching. Keep comment. |
| CACHE-003 | Cache invalidation strategy exists when source file changes | FAIL | No check for file modification date vs cached entry | Add invalidation (mtime-based) or versioned keys. |
| CACHE-004 | Disk cache pruning/eviction exists to prevent unbounded growth | FAIL | No pruning observed | Add LRU/time-based cleanup job. |
| CACHE-005 | Thumbnail extraction runs off-actor thread to avoid serialization stalls | PASS | `SonyThumbnailExtractor.extractSonyThumbnail` dispatches to global queue | Good note in code. |
| CACHE-006 | NSImage normalization before disk write is consistent | PASS | `ScanAndCreateThumbnails` normalizes to JPEG-backed NSImage | Be explicit about quality tradeoffs. |

---

## 4. File Scanning & EXIF Metadata

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| SCAN-001 | Security-scoped resources used for sandbox file access | PASS | `RawCull/Actors/ScanFiles.swift` | Uses `startAccessingSecurityScopedResource()` and `defer stop...`. |
| SCAN-002 | Directory enumeration avoids hidden files and limits work | PASS | `ScanFiles.scanFiles` uses `.skipsHiddenFiles` | Consider recursion option if needed. |
| SCAN-003 | EXIF extraction failure handled explicitly/logged | WARN | `extractExifData` returns nil without logging | Consider logging at debug level for diagnostics. |

---

## 5. Error Handling & Logging

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| ERR-001 | Uses typed errors for core flows | PASS | `ThumbnailError` in `RequestThumbnail.swift` | Good user-facing descriptions. |
| ERR-002 | Avoid silent `try?` for important I/O | ~~FAIL~~ (fixed) | `DiskCacheManager` uses `try? createDirectory(...)` | Prefer `do/catch` + log warnings. |
| ERR-003 | Background task failures are observable | WARN | Some warnings logged, but not all writes | Ensure disk write failures are logged. |

---

## 6. SwiftUI View Layer

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| UI-001 | Uses idiomatic navigation/layout for macOS | PASS | `RawCullView` uses `NavigationSplitView` | Good. |
| UI-002 | Settings propagation is reactive (Environment) rather than per-view async fetch | WARN | `RawCullView` uses `SettingsViewModel.shared.asyncgetsettings()` in `.task` | Prefer `@Environment(SettingsViewModel.self)` in subviews for reactivity. |
| UI-003 | Avoids `AnyView` when possible | WARN | `FileContentView` takes `AnyView` | Consider generics or `@ViewBuilder`. |

---

## 7. Testing

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| TEST-001 | Uses Swift Testing framework consistently | PASS | `RawCullTests/*` imports `Testing` | Modern approach. |
| TEST-002 | Tests contain real assertions (not placeholders) | FAIL | Several tests have `#expect(true)` placeholder comments | Replace with real assertions or disable with tracking issue. |
| TEST-003 | Coverage includes scanning, persistence, rsync integration | FAIL | Tests focus mainly on thumbnail/cache layer | Add tests for `ScanFiles`, `CullingModel`, `SettingsViewModel`, `ExecuteCopyFiles`. |

---

## 8. Tooling & Quality Gates

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| TOOL-001 | Repeatable build/test/lint automation exists | PASS | `Makefile` present | Consider CI integration later. |
| TOOL-002 | Formatting/linting configured | PASS | `.swiftlint.yml`, `.swiftformat`, `.periphery.yml` mentioned in prior doc | Verify rules are enforced in CI. |

---

## 9. Naming & API Design

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| NAME-001 | Type names follow UpperCamelCase | PASS | `SonyThumbnailExtractor`, `EmbeddedPreviewExtractor` | Previously-fixed issues appear addressed. |
| NAME-002 | Function/variable names follow lowerCamelCase | WARN | Some legacy patterns may remain; re-run search to confirm | Keep consistent across repo. |

---

## 10. Security & Privacy

| ID | Check | Status | Evidence | Notes / Action |
|---|---|---|---|---|
| SEC-001 | Sandbox entitlements/privacy manifest present | PASS | repo includes `.entitlements` + `PrivacyInfo.xcprivacy` (per prior analysis) | Keep updated as APIs change. |
| SEC-002 | Security-scoped resource lifetimes are handled correctly | PASS | `ScanFiles` uses `defer stop...` | Ensure all importer flows do the same. |

---

## 11. Summary

### Critical FAIL items to address first
1. **CONC-002:** Fix actor-isolation violation in `DiscoverFiles` (`Task.detached` + `self.supported`).
2. **CACHE-003/CACHE-004:** Add cache invalidation + disk pruning.
3. **ERR-002:** Replace silent `try?` for important disk operations with logging.
4. **TEST-002/TEST-003:** Replace placeholder tests and expand coverage beyond caching.

### Overall status (subjective)
- **Architecture / concurrency fundamentals:** strong
- **Operational robustness (cache lifecycle, error observability, test depth):** needs work
