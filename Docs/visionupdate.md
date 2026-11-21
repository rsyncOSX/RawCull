# Plan: Make Vision calls safe to run concurrently

Status: phases 1–3 done (PhotoAnalysisKit 1.4.0, PhotoAIKit 3.1.0); real-catalog checks passed · open: phase 1 cap decision, end-to-end burst run · 2026-11-21 · branch `version-3.4.9`

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

#### Phase 1 result (2026-11-21)

What changed:

| Step | Change | File |
|---|---|---|
| 1 | `RawCullParallelVisionArtifactProvider` is deleted. The indexer uses the service's own `VisionFeaturePrintBackend`, the single instance `RawCullAIModelRuntime` creates, so feature prints run one at a time. Decoding still runs 4 at a time. | `RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift` |
| 2 | `BurstDetectedFaceLoader` uses one shared `FaceEvidenceAnalyzer`, so face passes run one at a time. | `RawCull/Views/ComparisonGridView/BurstDetectedFacesView.swift` |
| 3 | `effectiveMaxConcurrentScoringTasks` is capped at `visionSafeScoringTaskLimit`, which is `max(1, activeProcessorCount / 2)`. On a 10-core Mac, "fast" goes from 6 to 5. On an 8-core Mac, "fast" goes to 4 and "balanced" stays at 4. | `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift` |

Plan corrections:

- Faces and animal close-ups were already limited: `BurstEvidenceWorkLimiter.shared` allows 2 of them at a time in total. Step 2 makes face passes go one at a time within that limit. Animal detection is unchanged.
- Worst case on a 10-core Mac is now 1 feature print + 2 face or animal passes + 5 saliency passes = 8 Vision requests, with 10 pool threads. On an 8-core Mac it is 1 + 2 + 4 = 7, with 8 pool threads. That leaves little margin on smaller machines, which is why phase 2 is still needed.
- Test suites that build their own backends or scoring models still run in parallel, so the test plan can still exceed these numbers. Phase 1 only lowers that risk.

Checks:

- The `RawCull` test plan ran three times in a row with `xcodebuild test-without-building` on a 10-core Mac. Every run finished, with 955 passed, 0 failed and 6 skipped (the real-model tests). The runs took 30, 15 and 15 seconds. Before phase 1, the same plan hung after 809 tests and never finished.
- `Scripts/VerifyAIImportBoundary.sh` passes.
- The manual check of sharpness scoring and similarity indexing running at the same time on a real catalog has not been done. Do it during TestFlight testing.

Not measured here: the indexing speed of a real catalog before and after step 1. Time a 500-image catalog during TestFlight testing and record the result in this section.

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

#### Phase 2 result (2026-11-21)

Released as PhotoAnalysisKit **1.4.0** (tag `v1.4.0`, commit `e4f974d`).

What changed:

| Change | File |
|---|---|
| New `VisionRequestGate`, a `Sendable` final class with `static let shared`. A private serial `DispatchQueue` (`.userInitiated`, autorelease pool per work item) runs the bodies. Each caller gets a ticket guarded by a `Mutex`. Whoever moves the ticket out of "waiting" resumes the continuation: either the queue starting the body, or cancellation. So a cancelled caller is resumed exactly once and its body is skipped. The initializer is internal, so tests can make private gates. | `VisionRequestGate.swift` |
| `featurePrint(for:)` runs request, perform and archiving in one gate body, and returns `Data`. | `VisionFeaturePrintBackend.swift` |
| `analyze(_:)` is now `async throws`. A new `detectFaces(in:)` runs the full-image pass and the tile passes as one gate body. `measureDetail` runs outside the gate. | `FaceEvidenceAnalyzer.swift` |
| `regions(in:)` is now `async throws`. The request and the conversion to `[Region]` run in one gate body, because Vision observations are not `Sendable`. | `AnimalCloseUpDetector.swift` |
| `detectSaliencyAndClassify` is now `async`. The Vision work moved to `performSaliencyAndClassify`, which runs saliency and the optional classification in one gate body. `computeSharpnessScore` is now: worker (normalize), then await saliency, then worker (breakdown). `generateFocusMask` and `generateFocusMaskWithBreakdown` are now: await saliency, then worker. They do not normalize, so they have two steps, not three. | `FocusMaskEngine+Scoring.swift`, `FocusMaskEngine+MaskGeneration.swift` |
| New section "Vision request gate". The animal example now uses `await`. | `README.md` |

Plan corrections:

- A gate body runs outside any task, so `Task.isCancelled` is always `false` inside it. The cancellation checks inside the old Vision code were moved to just before and after the `run` call. The saliency and classification error logs no longer check for cancellation.
- `FaceEvidenceAnalyzer.analyze` and `AnimalCloseUpDetector.regions` pass a `CancellationError` from the gate on to the caller. `detectSaliencyAndClassify` returns an empty detection on cancellation, as before.

Checks:

- 4 new tests in `VisionRequestGateTests`: the peak number of bodies in flight is 1 (32 callers), body errors reach the caller, cancellation before the turn throws `CancellationError` and skips the body (also when the task was cancelled before calling `run`), and 3 × `activeProcessorCount` concurrent feature prints, face analyses, saliency passes and animal detections finish within `.timeLimit(.minutes(1))`. On a 10-core Mac the last one takes about 0.4 seconds.
- `swift test` ran three times in a row: 63 tests passed each time.
- Byte-identical results: a temporary probe recorded scores, breakdowns, saliency summaries, mask SHA-256 hashes, feature-print sizes and face results for 3 synthetic images × 3 AF points (none, center, corner), with classification on. The output before and after the change was identical. The probe was not committed.
- The release sharpness test is in RawCull and is part of phase 3.

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

#### Phase 3 progress (2026-11-21)

RawCull now uses PhotoAnalysisKit 1.4.0 (pin bumped in `RawCull.xcodeproj`, resolved to `e4f974d`).

Done:

| Change | File |
|---|---|
| `await` added at `AnimalCloseUpDetector.regions`, and the comment on the shared face analyzer now points to the gate | `RawCull/Views/ComparisonGridView/BurstDetectedFacesView.swift` |
| `await` added at `AnimalCloseUpDetector.regions` | `Scripts/PhotoAnalysisCatalog.swift` |
| The package table lists `photoanalysiskit` at `1.4.0`. `ReleaseMetadataTests` checks this. | `README.md` |

Checks:

- The `RawCull` test plan ran three times in a row with `xcodebuild test-without-building` on a 10-core Mac. Every run finished, with 955 passed, 0 failed and 6 skipped (the real-model tests).
- `Scripts/VerifyAIImportBoundary.sh` passes.

#### Phase 3 steps 1–2 result (2026-11-21)

PhotoAIKit **3.1.0** (tag `v3.1.0`, merge commit `26647c6` of `0a59366`):

- New `VisionWorkSerializing` protocol and a default `SerialVisionWorkQueue` (the same ticket design as `VisionRequestGate`), both in the `VisionFeaturePrintBackend` target. PhotoAIKit still does not depend on PhotoAnalysisKit.
- `VisionFeaturePrintBackend.init(revision:serializer:)`, where `serializer` defaults to `SerialVisionWorkQueue.shared`. `artifact(for:source:)` runs request, perform and archiving in one body. Existing `init(revision:)` calls still compile.
- 6 new tests: no overlap, error propagation, cancellation before the turn (two cases), the injected serializer is used, and 3 × cores concurrent feature prints finish within one minute. `swift test` passed 56 tests three times in a row.

RawCull:

| Change | File |
|---|---|
| New `RawCullVisionWorkSerializer`, which forwards to `VisionRequestGate.shared.run`. It uses a scoped `import class PhotoAnalysisKit.VisionRequestGate`, because PhotoAnalysisKit also declares a `VisionFeaturePrintBackend` type. Keeping it in this file means the import-boundary policy did not change. The default backend of `RawCullVisionSimilarityService` uses it. | `RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift` |
| The runtime's single `VisionFeaturePrintBackend` uses it | `RawCull/Intelligence/Composition/RawCullAIModelRuntime.swift` |
| Test: a body passed through the adapter runs only after an earlier `VisionRequestGate.shared` body finished | `RawCullTests/RawCullVisionWorkSerializerTests.swift` |
| PhotoAIKit pin `3.1.0`. `Package.resolved` had to be resolved again with `xcodebuild -resolvePackageDependencies`: after the pin was bumped in the project file, it still pointed to 1.0.0. The package table lists `photoaikit` at `3.1.0`. | `RawCull.xcodeproj`, `README.md` |

Every Vision request in the app now goes through one queue: `VisionRequestGate.shared`.

Checks:

- The `RawCull` test plan ran three times in a row with `xcodebuild test-without-building` on a 10-core Mac. Every run finished, with 956 passed, 0 failed and 6 skipped (the real-model tests).
- `Scripts/VerifyAIImportBoundary.sh` passes.

#### Real-catalog checks (2026-11-21)

Catalog: 275 Sony ARW files (27 GB) from `JagerborgDyrehave/DCIM/100MSDCF`, on a 10-core Mac. The release sharpness test ran on a local copy, `~/RawCullCatalogs/100MSDCF`. See the note on volume access below.

**PhotoAnalysisKit 1.3.9 against 1.4.0** (`Scripts/RunPhotoAnalysisCatalog.py --phase before --revision v1.3.9`, then `--phase after --revision v1.4.0`):

- Every number in `analysis.json` was identical for all 275 photos, ignoring timing and revision fields. That covers scores, breakdowns, saliency, focus evidence, calibration, faces, animal regions and feature prints.
- All 1,650 rendered images (masks and close-up crops) were byte-identical.
- No burst winner changed. All 275 decodes, batch scores, combined scores and scalar scores succeeded in both runs.
- Batch scoring took 22.8 s with 1.3.9 and 21.6 s with 1.4.0, which is within noise.

**Sharpness scoring and similarity indexing running at the same time.** This used a temporary, opt-in test in the `RawCull` test host, which was not kept. Sharpness used the app defaults: Fast quality, 512 px, embedded preview, `RawCullPhotoAnalysisAdapter.analyzeBatch`. Similarity used `RawCullVisionSimilarityService.index` at 512 px with decode concurrency 4. The build was Debug, after one warm-up pass. Each row shows two rounds:

| Run | Sharpness | Similarity |
|---|---|---|
| Sharpness alone, 5 tasks (phase 1 cap) | 18.1 s / 18.0 s | — |
| Sharpness alone, 6 tasks (uncapped Fast) | 17.9 s / 17.6 s | — |
| Similarity alone | — | 1.0 s / 1.0 s |
| Both, 5 tasks | 18.6 s / 18.4 s wall | 1.6 s / 1.7 s |
| Both, 6 tasks | 18.1 s / 18.1 s wall | 1.9 s / 1.8 s |
| Both, 10 tasks (= cores), one run | 16.8 s wall | 8.1 s |

- All 275 photos were scored and indexed in every run, with 0 failures. Scores were identical in every run at every concurrency level.
- The 10-task stress run puts every pool thread on Vision-heavy work. That is the setup that hung before phase 1, and it now finishes.
- Sharpness time is dominated by Core Image, so Vision going one at a time costs little. The phase 1 cap costs about 1–2% compared with 6 tasks. Removing it is safe, but it gains little.

**Release sharpness test** (`make releasesharpnesstest RELEASE_CATALOG="$HOME/RawCullCatalogs/100MSDCF"`): **Passed.** All 3,025 comparisons (275 photos × 11 scenarios) finished with valid numbers and 0 failures, in 86 minutes. The report is `~/RawCullCatalogs/100MSDCF/RawCull-Sharpness-6788867F-78C4-4F9C-940A-9C3ACB54F4EF.md`. The test checks completion and valid output, not ranking accuracy: this catalog has no labels.

To run it, the `RawCullReleaseTests` target needed fixing first, in commit `7142f59b`. The target lists its files and packages explicitly, and it had fallen behind refactoring step 18, the extraction of PhotoAnalysisKit, and the move of two types into their own files.

Volume access: `RawCullReleaseTests` is a hostless test bundle, so it runs in Xcode's background `xctest` process. macOS refused that process access to the external drive (`Operation not permitted`), even when `make` was started from a shell that could read the drive. macOS never shows a prompt for it. Either give the `xctest` agent Full Disk Access, or copy the catalog to an unprotected folder in the home directory, as was done here.

Not done yet:

- Decide whether to remove the phase 1 cap on sharpness scoring (`SharpnessScoringModel.visionSafeScoringTaskLimit`). The measurements above allow it. The comment on the cap and the one in `RawCullVisionSimilarityService.index` still describe the phase 1 situation.
- An end-to-end burst analysis through the app (`Scripts/PrepareBursts.py` over MCP). It needs a build of this branch installed as the app, and it replaces the app's shared analysis result.

## Risks and what to measure

- **Throughput.** Vision work becomes strictly sequential. Saliency is a small part of each sharpness score (Core Image dominates), so the impact should be small. Similarity indexing will slow down more. Time a 500-image catalog before and after each phase.
- **Cancellation latency.** A request that has started runs to the end, so cancelling a scan can wait for one Vision request. That is the same as today.
- **Other code that blocks pool threads.** `runCancellableWorker` runs Core Image rendering synchronously on the pool. This plan does not change that, but it is the same class of problem if it ever needs a pool thread to complete.
- **Testing the packages before release.** RawCull pins exact package versions. To build RawCull against unreleased package changes, create a throwaway workspace (outside the repo) that contains `RawCull.xcodeproj` and the local `PhotoAnalysisKit` and `PhotoAIKit` folders. Local packages override the pinned remote ones with the same name, and the project file stays unchanged.

## Not in scope

- The view-model refactor findings (`CatalogController` size, slice encapsulation, slice tests). They are tracked separately.
- `Scripts/PeopleAssessmentPilot.swift`. It is a script, not part of the app.
