# Plan: Make Vision calls safe to run concurrently

Status: draft · 2026-11-21 · branch `version-3.4.9`

## Summary

RawCull can hang when too many Vision requests run at the same time. The hang was seen in the `RawCull` test plan on 2026-11-21. The app runs the same code paths at the same concurrency, so it can hang too.

The cause: `VNImageRequestHandler.perform(_:)` blocks the thread it runs on while Vision does its work. Vision itself needs a free thread from Swift concurrency's shared (cooperative) thread pool to finish that work. The pool has one thread per CPU core. When every pool thread is blocked inside Vision, or blocked waiting to start a Vision call, no request can finish and the process stops making progress. It never recovers.

The fix has two parts, and both are needed:

1. Run Vision requests one at a time across the process.
2. While a caller waits its turn, it must suspend, not block a pool thread. The Vision work itself must run off the pool.

Part 1 alone is not enough. A lock-based version was tried and hung the same way (see [Evidence](#evidence)).

This plan is split so the first phase is a small app-only change. The full fix lives in the packages and can wait for a quieter release.

## Evidence

### The hang in the RawCull test plan

`xcodebuild test -testPlan RawCull` on a 10-core Mac stopped making progress after 809 passed tests and 0 failures. Nothing was printed for more than 7 minutes, and the test host used 0.1% CPU. `sample` of the test host showed:

- The main thread waiting in `XCTWaiter` for async tests to finish.
- **11 threads blocked in `-[VNControlledCapacityTasksQueue dispatchGroupWait:error:]`**, called from `VNImageRequestHandler.performRequests`.
- 10 cooperative-pool threads in total, matching `hw.ncpu = 10`. Every one of them was among the blocked threads.

The blocked calls were:

| Call | Threads | Reached from |
|---|---|---|
| `VisionFeaturePrintBackend.artifact(for:source:)` (PhotoAIKit, `VisionFeaturePrintBackend.swift:36`) | 7 | `SimilarityArtifactIndexer.run` (`SimilarityArtifactIndexer.swift:118`) → `RawCullParallelVisionArtifactProvider` (`RawCullVisionSimilarityService.swift:516`) |
| `FocusMaskEngine.detectSaliencyAndClassify` (PhotoAnalysisKit, `FocusMaskEngine+Scoring.swift:78` and `:107`) | 4 | `computeSharpnessScore` and `generateFocusMaskWithBreakdown`, inside `FocusMaskEngine.runCancellableWorker` (`FocusMaskEngine.swift:52`) |

None of these files changed in the view-model refactor (steps 1–18). The problem was already there.

### Serializing with a lock is not enough

A first fix routed every Vision `perform` in PhotoAnalysisKit through a process-wide `NSRecursiveLock`. With it in place, `swift test` in PhotoAnalysisKit hung the same way. A sample showed:

- **1 thread** holding the lock, blocked in `VNControlledCapacityTasksQueue dispatchGroupWait`.
- **10 threads** blocked in `NSRecursiveLock lock` (`_pthread_mutex_firstfit_lock_wait`), waiting for their turn.

Only one Vision request was running, but it could not finish: every pool thread was busy waiting for the lock, so Vision had no free thread to complete its work. This shows that waiting callers must suspend, not block a thread. The lock change was reverted.

### RawCull defeats the one place that does serialize

`VisionFeaturePrintBackend` is an actor, so calls on one instance run one at a time. RawCull works around that on purpose. [RawCullVisionSimilarityService.swift](../RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift), `RawCullParallelVisionArtifactProvider` (about line 496), creates a new backend for every image. Its comment says the goal is to avoid "serializing all generation through one actor instance".

`BurstDetectedFacesView.analyzeFaces` does the same with `FaceEvidenceAnalyzer`: "A fresh analyzer per call … a shared instance would serialize every Vision pass on one actor."

### How much Vision work the app can run at once

| Work | Concurrency | Where |
|---|---|---|
| Similarity indexing (feature prints) | 4 (`RawCullVisionSimilarityService.defaultConcurrencyLimit`) | `RawCullVisionSimilarityService.swift:85` |
| Sharpness scoring (saliency, classification) | 6 fast / 4 balanced / 3 high precision; at most 2 for RAW demosaic | `SharpnessScoringOptions.swift:70`, `SharpnessScoringModel.swift:113` |
| Face evidence | one per call, new analyzer each time | `BurstDetectedFacesView.swift:126` |
| Animal close-ups | synchronous call in a `@concurrent` function | `BurstDetectedFacesView.swift:131` |

At the "fast" setting, sharpness scoring and similarity indexing together can run 10 Vision requests at once. That is the whole pool on a 10-core Mac, and more than the whole pool on an 8-core Mac. The test plan has `"parallelizable": true`, so suites that use Vision also run at the same time.

## Every Vision call site

| Repo | File | Call |
|---|---|---|
| PhotoAnalysisKit | `FocusMaskEngine+Scoring.swift:78` | saliency `handler.perform([saliencyRequest])` |
| PhotoAnalysisKit | `FocusMaskEngine+Scoring.swift:107` | classification `handler.perform([classifyRequest])` |
| PhotoAnalysisKit | `VisionFeaturePrintBackend.swift:51` | feature print |
| PhotoAnalysisKit | `FaceEvidenceAnalyzer.swift:38` and `:83` | face rectangles (full image, then up to 4 tiles) |
| PhotoAnalysisKit | `AnimalCloseUpDetector.swift:20` | animal body pose |
| PhotoAIKit | `Sources/VisionFeaturePrintBackend/VisionFeaturePrintBackend.swift:36` | feature print (the one RawCull's similarity indexing uses) |
| RawCull | `Scripts/PeopleAssessmentPilot.swift` | script only, not part of the app |

RawCull's app target makes no Vision requests itself. All of them happen inside the two packages.

## Plan

### Phase 1: Lower the risk in RawCull only (small, no package release)

This phase does not guarantee the hang is gone, but it keeps the number of concurrent Vision requests well below the pool size. Each step is one small commit.

1. **Use one feature-print backend.** In `RawCullVisionSimilarityService.swift`, delete `RawCullParallelVisionArtifactProvider` and pass a single shared `VisionFeaturePrintBackend` to the indexer. The actor then runs one feature print at a time. The comment above the provider goes too. Expect similarity indexing to slow down, since decoding still runs 4 at a time but feature prints run 1 at a time. Measure it on a real catalog.
2. **Use one face analyzer.** In `BurstDetectedFacesView.swift`, replace `FaceEvidenceAnalyzer()` per call with one shared instance, and update the comment.
3. **Cap sharpness scoring below the pool size.** In `SharpnessScoringModel.effectiveMaxConcurrentScoringTasks`, cap the result at `max(1, ProcessInfo.processInfo.activeProcessorCount / 2)`. On a 10-core Mac, "fast" goes from 6 to 5. On an 8-core Mac it goes to 4.
4. **Check.** Run the `RawCull` test plan three times in a row, and it must finish each time. Then run sharpness scoring and similarity indexing at the same time on a catalog of a few hundred images.

Worst case after phase 1: 1 feature print + 1 face pass + up to (cores ÷ 2) saliency passes + animal detection. That still leaves pool threads free.

### Phase 2: Fix it in PhotoAnalysisKit (next package release)

1. **Add `VisionRequestGate`.** It is a process-wide gate with one private serial `DispatchQueue` and one method:

   ```swift
   public func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
   ```

   It enqueues `body` on the queue and resumes the caller through a continuation. Waiting callers suspend instead of holding a thread, and the Vision work runs on the queue's thread, outside the pool. If the caller is cancelled before its turn, it throws `CancellationError`. Once `body` has started, it runs to the end. Vision requests and handlers are not `Sendable`, so `body` builds them itself and returns only `Sendable` values (such as `Data`, `[CGRect]` or `SaliencyDetection`). Never call `run` from inside a body: it would wait for itself.
2. **Route every call site through it**, and make the synchronous ones `async`:
   - `VisionFeaturePrintBackend.featurePrint(for:)` is already `async`. The body returns the archived payload.
   - `FaceEvidenceAnalyzer.analyze(_:)` becomes `async throws`. External callers already `await` it because it is an actor method. One gate body runs the full-image pass and the tile passes and returns the boxes. `measureDetail` stays outside the gate.
   - `AnimalCloseUpDetector.regions(in:)` becomes `async throws`. **This breaks source compatibility**: RawCull's `BurstDetectedFacesView.swift:131` and `Scripts/PhotoAnalysisCatalog.swift:190` need `await`.
   - `FocusMaskEngine.detectSaliencyAndClassify` becomes `async`. It is called inside the synchronous closures of `runCancellableWorker`, so `computeSharpnessScore`, `generateFocusMask` and `generateFocusMaskWithBreakdown` each split into three steps: worker (normalize), then `await` saliency, then worker (breakdown and mask). Results must be byte-identical. Run `FocusMaskAccuracyTests` and the release sharpness test to confirm.
3. **Tests:**
   - Concurrent callers never overlap: record the peak number of bodies in flight and expect 1.
   - Cancellation before the turn throws `CancellationError`.
   - Regression test for the hang: start `activeProcessorCount × 3` concurrent feature prints and face analyses with `.timeLimit(.minutes(1))`. It must finish.
4. Release PhotoAnalysisKit 1.3.10, or 1.4.0 given the API change.

### Phase 3: PhotoAIKit and RawCull (after phase 2)

PhotoAIKit does not depend on PhotoAnalysisKit, and it should stay that way.

1. **In PhotoAIKit**, add a small protocol with the same shape as the gate:

   ```swift
   public protocol VisionWorkSerializing: Sendable {
       func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
   }
   ```

   Add a default serial-queue implementation. `VisionFeaturePrintBackend.init` takes `serializer: any VisionWorkSerializing = <default>.shared`, and `artifact(for:source:)` runs its Vision work through it. Release PhotoAIKit.
2. **In RawCull**, add a 10-line adapter that implements `VisionWorkSerializing` by calling `VisionRequestGate.shared.run`. Pass it to every `VisionFeaturePrintBackend` (`RawCullVisionSimilarityService.swift:93`, `RawCullAIModelRuntime.swift:79`). The whole app then shares one gate.
3. Bump both package pins in `RawCull.xcodeproj`, add `await` at the two `AnimalCloseUpDetector.regions` call sites, and revert the phase 1 cap on sharpness scoring if measurements allow.
4. Run the `RawCull` test plan three times in a row, the release sharpness test, and one end-to-end burst analysis on a real catalog.

## Risks and what to measure

- **Throughput.** Vision work becomes strictly sequential. Saliency is a small part of each sharpness score (Core Image dominates), so the impact should be small. Similarity indexing will slow down more. Time a 500-image catalog before and after each phase.
- **Cancellation latency.** A request that has started runs to the end, so cancelling a scan can wait for one Vision request. That is the same as today.
- **Other code that blocks pool threads.** `runCancellableWorker` runs Core Image rendering synchronously on the pool. This plan does not change that, but it is the same class of problem if it ever needs a pool thread to complete.
- **Testing the packages before release.** RawCull pins exact package versions. To build RawCull against unreleased package changes, create a throwaway workspace (outside the repo) that contains `RawCull.xcodeproj` and the local `PhotoAnalysisKit` and `PhotoAIKit` folders. Local packages override the pinned remote ones with the same name, and the project file stays unchanged.

## Not in scope

- The view-model refactor findings (`CatalogController` size, slice encapsulation, slice tests). They are tracked separately.
- `Scripts/PeopleAssessmentPilot.swift`. It is a script, not part of the app.
