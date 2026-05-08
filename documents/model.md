# Model Layer Review

Date: 2026-05-08

Scope: `RawCull/Model`, `RawCull/Actors`, `RawCull/Enum`, and model-supporting extensions. SwiftUI view components under `RawCull/Views` were excluded. This review focuses on model behavior, concurrency, actor isolation, sendability, cancellation, persistence, and cache ownership.

Build settings observed in `RawCull.xcodeproj/project.pbxproj`:

- `SWIFT_VERSION = 6.0`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `SWIFT_UPCOMING_FEATURE_DISABLE_OUTWARD_ACTOR_ISOLATION = YES`
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = NO` for app configurations

The default isolation setting is the dominant architectural constraint: types are implicitly MainActor-isolated unless they explicitly opt out with `actor`, `nonisolated`, `@concurrent`, or detached work.

## Executive Summary

The model layer has a generally coherent actor-per-concern design. UI-owned state is mostly kept in `@Observable @MainActor` view models, while scanning, thumbnail extraction, disk caches, and persistence have dedicated actors or detached work for blocking I/O. The code also shows good intent around Swift 6 boundaries: many helpers are explicitly `nonisolated`, settings are snapshotted into `SavedSettings`, and non-Sendable image objects are often encoded to `Data` before crossing actor/task boundaries.

Latest commit update: the image export path was partially refactored after the initial review. `@preconcurrency` imports were removed from the touched image extraction/saving files, and sidecar JPEG export now encodes `CGImage` to `Data` before calling the save actor.

The remaining risks are concentrated in four areas:

1. Some continuation/GCD bridges do not propagate cancellation and can continue heavy ImageIO work after caller cancellation.
2. The cache layer uses `nonisolated(unsafe)` and `@unchecked Sendable` in ways that are defensible for `NSCache`, but the invariants are not enforced consistently enough to make future edits safe.
3. Several long-lived or fire-and-forget tasks are unstructured, making ownership, cancellation, and completion ordering harder to reason about.
4. Some synchronous file I/O still runs on MainActor-isolated paths.

## Findings

### Resolved: image export no longer relies on `@preconcurrency` or cross-actor `CGImage` saves

Files:

- `RawCull/Actors/SaveJPGImage.swift:9`
- `RawCull/Enum/JPGSonyARWExtractor.swift:8`
- `RawCull/Enum/JPGNikonNEFExtractor.swift:12`

The repository instructions explicitly say not to introduce `@preconcurrency` imports or silence concurrency errors without understanding the isolation model. `@preconcurrency import` tells Swift to treat declarations from that module as if they came from an older, concurrency-unannotated world. That can be useful as a temporary migration bridge for third-party code, but in this project it weakens the main safety mechanism Swift 6 is supposed to provide: the compiler can no longer fully warn when non-Sendable framework objects are moved through async, actor, or task boundaries.

That matters most in image model code because ImageIO/CoreGraphics objects are large, reference-backed framework values whose thread-safety and lifetime rules are not expressed as simple Swift `Sendable` guarantees. The safer design is to keep `CGImage` local to the task or actor that decoded it, convert it into immutable `Data`, and send that `Data` across actor/task boundaries for persistence or caching. `Data` is the stable value boundary; `CGImage` is the local decode/rendering product.

Current state:

- `SaveJPGImage` now uses regular `import ImageIO` and exposes `save(_ jpegData:originalURL:)`, so the actor receives `Data` instead of `CGImage`.
- `SaveJPGImage.jpegData(from:)` is a `nonisolated static` helper intended to run before crossing into the save actor.
- `ExtractAndSaveJPGs.processSingleExtraction(_:)` now extracts the `CGImage`, checks cancellation, encodes to `Data`, and then calls `SaveJPGImage().save(...)`.
- `JPGSonyARWExtractor` and `JPGNikonNEFExtractor` now import `CoreGraphics` instead of `@preconcurrency import AppKit`.

Residual note: `SaveJPGImage.jpegData(from:)` still uses ImageIO with a local `CGImage`, which is acceptable only because the caller keeps encoding in the same task that received the decoded image. Avoid reintroducing an async actor/task boundary that accepts `CGImage` directly.

### High: Continuation-based extractors ignore cancellation

Files:

- `RawCull/Enum/SonyThumbnailExtractor.swift:27`
- `RawCull/Enum/NikonThumbnailExtractor.swift:27`
- `RawCull/Enum/JPGSonyARWExtractor.swift:20`
- `RawCull/Enum/JPGNikonNEFExtractor.swift:24`

These functions bridge async APIs to `DispatchQueue.global` with checked continuations. Once dispatched, the ImageIO work runs to completion even if the parent task is cancelled. Callers often check `Task.isCancelled` before and after extraction, but cancellation does not stop work already running inside the GCD closure.

This matters because thumbnail/full-JPEG extraction can be expensive and memory-heavy. Cancelling a catalog load or zoom request can still leave multiple raw decode jobs consuming CPU and memory.

Recommendation:

- Prefer `Task.detached` for these bridges so cancellation is at least observable through `Task.isCancelled` inside the work body.
- Add cancellation checks before creating `CGImageSource`, before decoding thumbnails/images, and before binary fallback.
- For GCD-only APIs, wrap the bridge in `withTaskCancellationHandler` and make the closure check a cancellation token before expensive phases.
- Keep returning `CGImage` only when the caller immediately consumes it in the same task; otherwise return encoded `Data` or a value wrapper with a documented invariant.

### High: `ThumbnailLoader.acquireSlot()` can over-count active tasks on cancellation

File: `RawCull/Actors/ThumbnailLoader.swift:29`

`acquireSlot()` parks waiters in `pendingContinuations` and increments `activeTasks` after the continuation resumes. On cancellation, `removeAndResumePendingContinuation(id:)` resumes the continuation too, after which the cancelled task still executes `activeTasks += 1` at `RawCull/Actors/ThumbnailLoader.swift:40`. The caller then hits `guard !Task.isCancelled else { return nil }`, runs `defer { releaseSlot() }`, and usually balances the count.

That balance depends on all callers using the exact `await acquireSlot(); defer releaseSlot()` pattern. More importantly, cancellation resumes the waiter as if a slot were granted. If many cancellations happen while the loader is saturated, active slot accounting can briefly exceed `maxConcurrent`, and future edits could easily turn this into a stuck or over-admitted loader.

Recommendation:

- Make slot acquisition return `Bool`: `false` for cancelled waiters that were removed before receiving a real slot.
- Only increment `activeTasks` when a slot is actually granted.
- Keep continuation entries in a small struct with an explicit state, or replace the custom limiter with an actor-owned async semaphore that has tested cancellation semantics.

### High: `SharedMemoryCache.currentPressureLevel` is a non-atomic unsafe cross-thread property

File: `RawCull/Actors/SharedMemoryCache.swift:106`

`currentPressureLevel` is `private(set) nonisolated(unsafe)` and written from the memory pressure handler while read synchronously from `MemoryViewModel` and diagnostics. The comment says it is only written from the `DispatchSource` event handler, but the handler hops back into the actor through `Task { await self.handleMemoryPressureEvent() }`; reads can still occur concurrently from nonisolated callers. Unlike the cache counters, this property is not protected by `OSAllocatedUnfairLock`.

The value is small, but Swift's data-race model does not make unsynchronized cross-thread enum reads/writes safe just because the property is simple.

Recommendation:

- Store pressure level in an `OSAllocatedUnfairLock<MemoryPressureLevel>` like the other diagnostics counters, or make reads async and actor-isolated.
- If synchronous reads are required for UI sampling, expose `nonisolated func getCurrentPressureLevel()` backed by a lock.

### Medium: Cache count/cost accounting can drift from `NSCache`

Files:

- `RawCull/Actors/SharedMemoryCache.swift:370`
- `RawCull/Actors/SharedMemoryCache.swift:399`
- `RawCull/Model/Cache/CacheDelegate.swift`

Manual counters are incremented on every `setObject`/`setGridObject`, but `NSCache.setObject(_:forKey:cost:)` replaces existing keys without telling the caller whether an existing object was overwritten. Some call sites guard against duplicates first, but the invariant is distributed across callers. A future direct `setObject` call can over-count cost and item count.

Recommendation:

- Move duplicate handling into `SharedMemoryCache.setObject` and `setGridObject`: check for an existing wrapper under the same key and decrement its known cost before inserting.
- Consider making these methods the only write surface and keeping the raw `NSCache` properties less visible.
- Add thread-safety tests for replacement, eviction, `removeAll`, warning pressure, and critical pressure.

### Medium: `@unchecked Sendable` wrappers need tighter invariants

Files:

- `RawCull/Model/Cache/CachedThumbnail.swift:21`
- `RawCull/Model/Cache/CacheDelegate.swift:14`
- `RawCull/Model/ViewModels/FocusMaskModel.swift:180`

`CacheDelegate` is backed by locks and appears reasonable. `CachedThumbnail` wraps `NSImage`, which is not generally Sendable; it is stored in thread-safe `NSCache` and read from multiple contexts. `FocusMaskModel` is `@Observable` and `@unchecked Sendable`, with `config` mutable and MainActor-facing methods plus nonisolated scoring APIs.

The current code often snapshots `config` before detached work, which is good. The risk is future use of `FocusMaskModel` from detached tasks accessing observable mutable state directly, because `@unchecked Sendable` tells the compiler to trust the type.

Recommendation:

- Add a short invariant comment to each `@unchecked Sendable` declaration.
- For `FocusMaskModel`, consider splitting into a MainActor observable controller and a pure `FocusMaskEngine` value/static type that owns the nonisolated scoring pipeline.
- For `CachedThumbnail`, prefer storing immutable `CGImage` or encoded data where possible, or document that `NSImage` instances are created fully before caching and never mutated after insertion.

### Medium: Fire-and-forget tasks obscure completion ordering

Files:

- `RawCull/Actors/ScanAndCreateThumbnails.swift:195`
- `RawCull/Actors/ScanAndCreateThumbnails.swift:209`
- `RawCull/Actors/ScanAndCreateThumbnails.swift:214`
- `RawCull/Actors/ScanAndCreateThumbnails.swift:234`
- `RawCull/Actors/RequestThumbnail.swift:106`
- `RawCull/Actors/ScanAndExtractJPGs.swift:121`
- `RawCull/Actors/ScanAndExtractJPGs.swift:138`
- `RawCull/Actors/SharedMemoryCache.swift:320`
- `RawCull/Actors/SharedMemoryCache.swift:332`
- `RawCull/Actors/SharedMemoryCache.swift:351`

The pattern is understandable for UI progress callbacks and background cache writes, but there is no retained handle and no cancellation relationship to the owning operation. For example, disk cache saves launched from thumbnail extraction may complete after the catalog load has been cancelled. UI callback tasks can also arrive after state has moved on, unless the handler closure checks generation/catalog state.

Recommendation:

- Keep fire-and-forget UI progress callbacks only where handlers are idempotent and generation-checked.
- For cache writes, prefer a dedicated disk-cache actor method that queues work and can be awaited or cancelled at operation boundaries.
- For memory pressure callbacks, avoid nested unstructured tasks where actor-isolated code can call the MainActor handler directly from the existing async context.

### Medium: Synchronous persistence still runs on MainActor paths

Files:

- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:19`
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:27`
- `RawCull/Model/ViewModels/CullingModel.swift:29`
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:34`
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:47`

`ReadSavedFilesJSON` is explicitly `@MainActor` and performs synchronous JSON file reading/decoding. `CullingModel.loadSavedFiles()` calls it synchronously. Writes are behind an actor, but encoding and `Data.write` still run on that actor's executor without detaching blocking disk I/O.

Recommendation:

- Convert read to async and perform file I/O off MainActor.
- Snapshot `SavedFiles` on MainActor, then encode/write in `Task.detached` or inside a persistence actor that performs blocking work off the main executor.
- Keep `CullingModel` as the MainActor owner of selection state, but make persistence a separate service.

### Resolved: sidecar full-JPEG export now matches the data boundary used by disk caches

Files:

- `RawCull/Actors/ExtractAndSaveJPGs.swift:86`
- `RawCull/Actors/SaveJPGImage.swift:18`
- `RawCull/Actors/ScanAndExtractJPGs.swift:105`
- `RawCull/Actors/FullSizeJPGDiskCache.swift:58`

`ScanAndExtractJPGs` uses the safer path: extract `CGImage`, encode to `Data`, then save via `FullSizeJPGDiskCache`. The latest commits bring `ExtractAndSaveJPGs` into the same shape for sidecar exports: it now extracts `CGImage`, encodes to `Data` before crossing to the save actor, then writes the sidecar JPEG from that `Data`.

Remaining cleanup:

- Consider sharing one JPEG encoding helper between `SaveJPGImage` and `FullSizeJPGDiskCache` so export and disk-cache quality/options cannot drift.
- Keep `SaveJPGImage` data-oriented; do not add back a `save(image:originalURL:)` overload.

### Medium: MainActor tasks sometimes do background waiting before UI mutation

Files:

- `RawCull/Model/ViewModels/CullingModel.swift:128`
- `RawCull/Model/ViewModels/MemoryDiagnosticsViewModel.swift:86`
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:21`

With default MainActor isolation, plain `Task { ... }` created inside MainActor types starts on the MainActor. Some tasks mostly sleep, wait, or immediately call async actor work. This is usually not a correctness bug, but it makes intent less clear and can pin the synchronous prefix to MainActor unnecessarily.

Recommendation:

- For delayed saves and polling loops, use `Task { @concurrent in ... }` where the synchronous prefix does not need MainActor access, then hop back with `MainActor.run` only for state mutations.
- Keep plain `Task {}` when the synchronous prefix intentionally mutates MainActor state.

### Low: `SettingsViewModel` is effectively MainActor-isolated but not annotated at type level

File: `RawCull/Model/ViewModels/SettingsViewModel.swift:14`

The singleton is declared `@MainActor static let shared`, and default actor isolation makes the type MainActor-isolated in this project. However, the type declaration itself is just `@Observable final class SettingsViewModel`, unlike other view models that state `@Observable @MainActor`.

Recommendation:

- Annotate the type as `@Observable @MainActor final class SettingsViewModel` for readability and to preserve intent if build settings change.
- Keep `asyncgetsettings()` as the nonisolated snapshot API.

### Low: `MemoryViewModel` relies on implicit MainActor isolation

File: `RawCull/Model/ViewModels/MemoryViewModel.swift:12`

Like `SettingsViewModel`, `MemoryViewModel` is `@Observable` without explicit `@MainActor`. Under current build settings this is MainActor-isolated, but the code is easier to audit if UI-facing observable models are explicit.

Recommendation:

- Annotate `MemoryViewModel` as `@Observable @MainActor`.
- Keep Mach helper methods `nonisolated`, but avoid capturing `self` in detached work where a small static helper or local `pressureThresholdFactor` capture would do.

## Positive Patterns To Preserve

- `RawCullViewModel`, `SharpnessScoringModel`, `SimilarityScoringModel`, `CullingModel`, and diagnostics models keep UI-owned state on MainActor.
- `SavedSettings` gives actors a Sendable-style value snapshot instead of reading mutable settings directly.
- `DiskCacheManager`, `FullSizeJPGDiskCache`, and `SaveJPGImage` accept `Data`, avoiding non-Sendable image transfer for saves.
- The latest image-save refactor removed `@preconcurrency` imports from the touched ImageIO/AppKit paths and replaced the sidecar export save boundary with `Data`.
- `ScanFiles.sortFiles` uses `@concurrent nonisolated`, which is appropriate for CPU-bound sorting/filtering under default MainActor isolation.
- `SimilarityScoringModel` snapshots dictionaries before detached work and archives Vision observations to `Data`, reducing non-Sendable lifetime issues.
- `FocusMaskModel.computeSharpnessScore` snapshots `CIContext` and config before detached processing.
- The catalog-load path uses `activeCatalogLoadURL` checks to avoid applying stale scan results.

## Recommended Fix Order

1. Add cancellation-aware extraction wrappers for Sony/Nikon thumbnail and full-JPEG extraction.
2. Fix `ThumbnailLoader.acquireSlot()` cancellation semantics and add tests.
3. Replace `currentPressureLevel nonisolated(unsafe)` with a lock-backed getter or actor-isolated async getter.
4. Harden `SharedMemoryCache` counter accounting against replacement and add cache accounting tests.
5. Split `FocusMaskModel` into observable MainActor state plus a pure nonisolated engine, or document and constrain its unchecked-sendable invariant.
6. Move saved-files read/write file I/O off MainActor.
7. Make all observable model types explicitly `@MainActor` unless they are deliberately nonisolated.

## Suggested Tests

- `ThumbnailLoader` cancellation test: saturate all slots, enqueue waiters, cancel waiters, then assert later requests are not stuck and concurrency never exceeds the limit.
- `SharedMemoryCache` replacement accounting test: set the same key twice, evict/remove, and assert count/cost do not drift.
- Memory pressure test: simulate warning/critical handling if possible through an injectable pressure event method and assert pressure level, cost limits, counters, and callback behavior.
- Extractor cancellation test: start thumbnail/full-JPEG extraction on a large sample, cancel immediately, and assert no UI state is updated and bounded work remains.
- Persistence test: rapid culling changes should produce one debounced write with the latest snapshot, and `saveImmediately()` should cancel pending delayed writes.

## Bottom Line

The model layer is close to a solid Swift 6 concurrency design, and the latest commits resolved the most direct image-persistence escape hatch by removing `@preconcurrency` from the touched paths and standardizing sidecar saves around `Data`. The highest-value remaining cleanup is to make cancellation/accounting behavior explicit in the extraction, loader, and cache layers.
