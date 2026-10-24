# Phase 2 — progress publication experiment

Status: candidate in the worktree, not accepted or committed as a completed phase.

The historical trace showed repeated ProgressCount/Sidebar body updates and
animation work. The first experiment changes only publication cadence, leaving
the ring and parent animations unchanged so that effects can be evaluated
separately. No frame-smoothness improvement is claimed.

## Candidate

- Each metadata scan and thumbnail preload owns an independent MainActor
  `CatalogProgressCoalescer`. Initial/total/terminal values publish immediately;
  intermediate values share one cancellable 100 ms tick. Duplicate snapshots do
  not publish. Internal pipeline counters, readiness gates, decode concurrency,
  image delivery and disk-save ownership are unchanged.
- Catalog cancellation invalidates both publishers before resetting tasks/state.
  Late callbacks cannot revive an invalidated publisher, even after reopening
  the same URL. Timer callbacks use a generation token; the task holds a weak
  reference to the publisher and UI publication captures the view model weakly.
- Queued completion counters cannot move the UI backwards. On drain, the view
  model asks the preload actor for exact completed/total accounting, flushes
  those values and ETA=0, then closes the publisher. This avoids relying on
  delivery order of the pipeline's fire-and-forget UI callbacks.
- Memory-pressure and extraction-needed callbacks remain immediate and check
  publisher identity. JPG export and separate JPG-cache workflows are unchanged.
- Metadata progress and thumbnail progress stay separate. No speculative view
  extraction or observation-model rewrite has been introduced.

Only observable writes are coalesced. Per-file MainActor callbacks still occur;
this experiment does not claim to eliminate their scheduling overhead.

## Correctness validation

Controlled scheduling tests exercise bursts, exact final state/ETA, completion
before the tick, cancellation, replacement, stale timer callbacks and publisher
lifetime. An 809-event burst within one controlled window publishes initial and
latest values only; this verifies the algorithm, not the cadence of a real decode
or a measured reduction in SwiftUI render work. No timing assertions depend on
machine speed and the tests use no sleeps.

Selected existing preload save-ownership/cancellation and catalog lifecycle tests
are included in the Xcode check. Release test compilation exposed existing tests
that require DEBUG hooks and a save callback ambiguously bound to the measurement
parameter. The latter test now labels `saveToDisk:` explicitly. Test execution
uses Debug; optimized app compilation is checked separately.

Focused Debug run passed: 11 tests across three suites, including six new
coalescer tests and the existing parameterized cancellation/save-ownership checks.
All 18 Python catalog checks also pass. SwiftLint reports no source errors;
existing style warnings and catalog-view-model length/complexity warnings remain.
`git diff --check` passes.

Logs: `/tmp/rawcull-phase2-tests.log` (initial Release attempts),
`/tmp/rawcull-phase2-debug-tests.log` (focused Debug run),
`/tmp/rawcull-phase2-release-build.log` (successful optimized app build).
The final helper extraction/timer-isolation revisions also pass the optimized
build (`/tmp/rawcull-phase2-release-final.log`) and all 11 focused Debug tests
(`/tmp/rawcull-phase2-debug-final.log`). An additional ownership test assertion
checks that the actor's exact completed/total snapshot matches expected accounting
on success and cancellation; log `/tmp/rawcull-phase2-counts-tests.log`.

## Remaining acceptance work

- Manually check small/full catalogs, ETA, cancellation and repeated same-URL
  switching, including exact final counts and immediate overlay dismissal.
- Measure actual publication frequency and phase-scoped main-thread work under
  a comparable setup. Existing phase 1 CPU/signpost recordings are historical
  context, not an after-result.
- Resolve the SwiftUI/Deferred collection limitation or establish a documented
  comparable alternative before claiming reduced SwiftUI fan-out/hitches.
- Evaluate animation simplification as a separate intervention, including Reduce
  Motion, after publication-only evidence is available.
- Retain/commit a completed phase only after the plan's correctness and measured
  benefit criteria are met. No performance baseline or raw trace is overwritten.

Focused test command (uses the existing pinned package cache):

```sh
xcodebuild test -project RawCull.xcodeproj -scheme RawCull -testPlan Smoke \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -only-testing:RawCullTests/CatalogProgressCoalescerTests \
  -only-testing:RawCullTests/ThumbnailPreloadSaveOwnershipTests \
  -only-testing:RawCullTests/CatalogLifecycleCoordinatorTests \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  -clonedSourcePackagesDirPath /Users/thomas/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/SourcePackages \
  ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS=
```

Optimized build uses `xcodebuild build` with scheme RawCull, configuration Release,
macOS arm64 destination and the same pinned-package/cache arguments, without the
Debug test overrides. Full executed commands and diagnostics are in the logs.
