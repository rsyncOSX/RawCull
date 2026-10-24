# Phase 2 — progress publication experiment

Status: progress coalescing retained after correctness checks and two after-captures; animation simplification is retained on sampled-work and manual evidence, with full UI/hitch acceptance still unavailable. Implementation recorded in `0cccc19c` and `649cea17`. The full original phase 2 UI/animation acceptance scope is not claimed complete.

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
- Confirm loading-time variation and accessibility behavior in later controlled
  UI validation; the separate animation experiment is documented below.
- The coalescing substep is retained as described below. Complete the remaining
  UI/animation scope before marking the full phase complete. No baseline is overwritten.

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

## Manual check feedback

On 24 October the user reported: "Run is done and seems OK" after instructions
to check normal progress, Actions > Abort task (Command-K), and catalog switching.
This is positive manual feedback, not a recorded assertion of every edge case or
measured performance. No Instruments after-capture has been supplied yet.
Next capture: same Immediate Time Profiler + os_signpost setup, standard sampling,
1616 pixels and original 809-file catalog, initially empty thumbnail cache with
backup preserved. Compare with archived phase 1 cold capture as descriptive data;
CPU/signposts cannot establish phase-scoped SwiftUI or hitch improvements.

## First instrumented after-capture — 24 October, 15:01 Oslo

User saved `~/Downloads/rawcull-phase2-cold-cpu-signposts.trace` after following
cold-thumbnail-cache instructions. Cache state, original catalog and action
sequence are user-reported; signposts independently confirm prepared=809 and
pixels=1616. TOC confirms Immediate, standard sampling, Xcode/Instruments 27.1,
macOS 27.0.1, duration 41.774771 s. All catalog events pair; preload runs from
14.187956416 to 33.326143875 s. Complete default export has nine valid independent
XML documents at `/tmp/rawcull-phase2-cold-reviewed-export`, with explicit
missing-SwiftUI/hitch/wait-table warnings. Profiler contains 37,707 samples.
RawCull binary UUID in CPU XML matches the current Release executable:
E51C75B8-62A5-3AEB-9096-15D3C35A2BF2.

Compared with the archived phase 1 cold CPU/signpost capture, independently
resolved XML sample timestamps are restricted to each run's own matching raw
signpost intervals (not total recording length). All included weights are the
recorded 1,000,000 ns. Sample weights are approximate profiler estimates, without
independent thread-running validation in this instrument subset.

| Measurement | Phase 1 before | Phase 2 candidate | Change |
| --- | ---: | ---: | ---: |
| Catalog-open wall time | 25.179 s | 23.785 s | -5.5% |
| Metadata wall time | 4.068 s | 4.066 s | -0.03% |
| Thumbnail-preload wall time | 20.577 s | 19.138 s | -7.0% |
| Preload all-thread sampled weight | 34.545 s | 31.853 s | -7.8% |
| Preload main-thread sampled weight | 4.575 s | 3.303 s | -27.8% |
| Main-thread share of preload sampled weight | 13.24% | 10.37% | -2.87 percentage points |

Inclusive main-thread samples containing ProgressCount.body.getter decline from
21 to 4; SidebarARWCatalogFileView.body.getter from 16 to 4 within preload.
These are small **CPU sample counts**, not SwiftUI body invocation counts, and
must not be reported as an 81% reduction in view updates. Coalescer symbols are
present in the after sample stacks, corroborating execution of the candidate.

Interpretation: encouraging preliminary evidence for lower main-thread work,
with successful readiness and no observed preload slowdown. One before/after
pair cannot establish repeatability, attribution, statistical significance,
actual publication frequency, peak memory, or smoother frames. Different total
recording lengths are why only matching catalog phases were compared. No UI/hitch
improvement or completed-phase acceptance is claimed. Animations remain unchanged.

Raw derived comparison: `/tmp/rawcull-phase2-comparison.json`; procedure:
`/tmp/compare_rawcull_phase2.py`; pairing report:
`/tmp/rawcull-phase2-cold-pairing.json`. Retain these alongside the trace/exports
and matching binary/dSYM before cleanup. A repeat under the same cache/setup is
needed before treating the apparent work reduction as repeatable.

## Repeated cold after-capture — 24 October, 15:09 Oslo

`~/Downloads/rawcull-phase2-cold-repeat.trace` validates: Immediate, standard
sampling, 40.999906 s, 36,509 CPU samples. All catalog intervals pair; completion
records prepared=809 pixels=1616. RawCull binary UUID matches the first candidate
capture (E51C75B8-62A5-3AEB-9096-15D3C35A2BF2). Preload runs from
10.949546291 to 29.155160000 s. All nine documents in the complete default export
parse independently with checked rows and explicit missing-instrument warnings.

| Measurement | Original cold | First after | Repeat after |
| --- | ---: | ---: | ---: |
| Metadata wall time | 4.068 s | 4.066 s | 4.093 s |
| Catalog-open wall time | 25.179 s | 23.785 s | 22.889 s |
| Preload wall time | 20.577 s | 19.138 s | 18.206 s |
| Preload all-thread sampled weight | 34.545 s | 31.853 s | 30.551 s |
| Preload main-thread sampled weight | 4.575 s | 3.303 s | 3.026 s |

Repeat versus original: preload wall time -11.5%, main-thread sampled weight
-33.9%. Both after-captures show lower phase-scoped sampled main-thread work
and successful preparation. Retain publication coalescing on this directional
work-reduction evidence, plus controlled correctness tests and positive manual
feedback. The source implementation is already committed as `0cccc19c`/`649cea17`.
No extra source change was made in response to the repeat.

Limits remain: a single before-run and two after-runs do not establish statistical
significance or isolate storage/scheduling variation. Recorded weights remain
approximate and lack independent thread-running confirmation. No frame-smoothness,
SwiftUI invocation-count or hitch improvement is claimed. Actual publication
frequency is constrained by the tested scheduler but was not independently
counted in the captured app. Animations remain unchanged; a separate animation
experiment and full phase-scoped UI validation remain deferred because the
combined Deferred instrument set fails collection. Do not treat this substep's
acceptance as completion of the original full phase 2 validation scope.

Derived comparison: `/tmp/rawcull-phase2-repeat-comparison.json`; script:
`/tmp/compare_rawcull_phase2_repeat.py`; pairing report:
`/tmp/rawcull-phase2-repeat-pairing.json`; full package:
`/tmp/rawcull-phase2-repeat-reviewed-export`. Durable repeat archive:
`/Volumes/MacMini4/TestRunPerformance/phase2-publication-repeat-2026-10-24`.
The first after-capture and its source/binary snapshot remain in
`/Volumes/MacMini4/TestRunPerformance/phase2-publication-candidate-2026-10-24`.

## Separate animation candidate (after the repeated coalescing comparison)

The repeat results are committed as `0a635a49`. The following experiment changes
only `ProgressCount.swift`: remove the parent-wide default animation and numeric
content transition; replace the 600 ms spring with a 100 ms linear animation
scoped to the ring, disabled when accessibilityReduceMotion is true. This aligns
the transition length with the progress publication cadence and avoids animating
frequently changing text. Publication code and decode/cache semantics are unchanged.

Hypothesis: simpler, narrower animation reduces remaining progress-related work
without impairing readable counts, completion or accessibility. This is an
unmeasured candidate, not part of the already captured before/after results.
SwiftLint and diff checks pass. The optimized Release build also passes; log:
`/tmp/rawcull-phase2-animation-build.log`. No mirror unit tests are added for these
view modifiers. Manual normal/Reduce Motion behavior and an otherwise comparable
cold CPU/signpost capture are required before retention. The SwiftUI/hitch
collection limitation still prevents direct frame-smoothness conclusions.

## Animation capture and retention decision — 24 October, 15:22 Oslo

User reported the visual check "seems OK", then recorded
`~/Downloads/rawcull-phase2-animation-cold.trace`. TOC confirms Immediate,
standard sampling, 43.761723 s; 37,022 CPU samples. Pairing validation passes
all three catalog intervals; preload runs 11.857836958–32.075632000 s and
completion records prepared=809 pixels=1616. Metadata duration 4.069469 s;
catalog-open duration 24.854256 s. All nine exported documents parse independently
and the manifest retains explicit missing-SwiftUI/hitch/wait-table warnings.
The recorded RawCull UUID matches the current Release app and dSYM:
3DC3A324-5FDC-362C-8493-BE1AEAB76988.

| Preload measurement | Original | Coalescing 1 | Coalescing 2 | Coalescing + animation |
| --- | ---: | ---: | ---: | ---: |
| Wall time | 20.577 s | 19.138 s | 18.206 s | 20.218 s |
| All-thread sampled weight | 34.545 s | 31.853 s | 30.551 s | 31.094 s |
| Main-thread sampled weight | 4.575 s | 3.303 s | 3.026 s | 1.261 s |

Interpretation: main-thread sampled weight is 58–62% below the two
coalescing-only captures and 72% below the original capture. Total sampled
weight is within the coalescing-only range. Preload wall time is **5.6–11.1%
longer than coalescing-only**, and 1.7% below the original. This is not evidence
of faster loading, and the longer readiness time relative to the intermediate
captures must remain visible. The available tables cannot attribute that
variation to storage, scheduling, animation or other causes. Metadata is similar
in all captures. One animation capture is descriptive, not a repeatable latency
or statistical conclusion.

Decision: retain the narrowly scoped animation simplification for the observed
main-thread work reduction and positive manual feedback, with the wall-time
uncertainty explicitly recorded for phase 7 comparison. The final phase 2 code
contains coalescing plus the ring-only 100 ms animation, immediate numeric text
and Reduce Motion support. No pipeline/decode/cache semantics changed in the
animation experiment. No smoother-frame, hitch or body-invocation-count claim
is made. The user feedback did not separately enumerate every accessibility
setting; Reduce Motion behavior is implemented by using nil animation when the
system environment reports it.

The implementation and CPU-based work experiment are retained, but the original
full phase-scoped SwiftUI/hitch acceptance remains **incomplete** because that
instrument set fails Deferred signpost collection. This is an explicitly deferred
measurement requirement, not an assertion that all original exit criteria passed.
No more identical CPU-only captures are requested now; they would not resolve
that missing UI evidence. Do not start phase 3 silently on the basis of this
partial acceptance.

Release build passed (`/tmp/rawcull-phase2-animation-build.log`), changed-view
SwiftLint has no source violations (existing analyzer configuration warnings),
18 Python catalog tests pass and diff checks pass. The previously passing
11 focused Swift tests cover the unchanged publication/pipeline behavior.
No mirror test was added for these simple view modifiers.

Comparison procedure: `/tmp/compare_rawcull_phase2_animation.py`; result:
`/tmp/rawcull-phase2-animation-comparison.json`; event pairing:
`/tmp/rawcull-phase2-animation-pairing.json`; full independent export package:
`/tmp/rawcull-phase2-animation-reviewed-export`. Durable archive:
`/Volumes/MacMini4/TestRunPerformance/phase2-animation-2026-10-24`, including
trace, exports, comparison, view source, report, matching binary/dSYM and verified
SHA-256 inventories. Historical source/trace archives remain unchanged.

Animation implementation commit: `de0dbef8` (`perf: simplify progress animation
and respect reduced motion`). Report/ledger update follows separately so this
source hash can be recorded without a self-reference. The archive snapshot was
verified before adding this Git provenance annotation; original artifacts were
not changed.
