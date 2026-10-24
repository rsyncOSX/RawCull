# Phase 5 — Source-load latency investigation

24 October 2026. **Investigation closed with opt-in diagnostics retained and the
production optimization deferred.** Long-tail latency is localized to the parser
API round trip. Its internal scheduling, actor/limiter wait, I/O and decoding
remain unresolved; this is not a finding that a native decode itself takes three
seconds. No concurrency-limit, priority, cache or dependency implementation change
is justified by this evidence. No application speedup is claimed.

## Retained diagnostic changes

`RawParserKitImageLoader` accepts an optional async reporting callback, nil in
normal application use. Only the diagnostic branch times thumbnail preload,
source thumbnail requests and preview loads. Existing normal branches remain in
place. Metadata and embedded-JPEG byte reads are not instrumented by this option.

`RawSourceLoadDiagnostic` preserves a UUID, source URL, operation, requested
pixels, success/cancellation at delivery, and five monotonic timestamps:

| Timestamp interval | What it measures | Limits |
| --- | --- | --- |
| submitted → accessReady | Signpost setup and catalog-access acquisition | Includes the MainActor hop; not exclusively security-scope work |
| accessReady → taskStarted | Adapter read-task scheduling | Not the preload admission queue or a parser limiter |
| taskStarted → parserReturned | RawParserKit API round trip | Includes private actor/limiter waits, scheduling, native I/O and decode |
| parserReturned → delivered | Read-task completion and adapter resumption | Not view publication or first painted pixels |

The read task retains catalog access until its native call finishes, preserving
the existing ownership behavior. Cancellation is sampled at delivery, then
rechecked after reporting before returning an image. Reporting occurs after all
five timestamps, so the reporting actor cannot inflate these stage durations.
The existing outer benchmark timer remains unchanged and can include reporting
and resumption waits. A containing-interval join quantifies the difference.

The opt-in branch emits `RawSourceLoad` signpost intervals in subsystem
`no.blogspot.RawCull`, category `SourceLoadDiagnostics`, with correlation UUID and
filename. These are prepared for a future same-run recording; their presence in
an Instruments recording was **not** validated in this phase.

`CatalogPerformanceJournal` writes separate `source-load` JSONL events containing
the original timing and journal clock origin. These do not become ordinary
performance metrics or required phases. Cancellation uses its own journal.
`AnalyzeSourceLoadDiagnostics.py` validates monotonic/finite timestamps and unique
IDs, then matches by operation, filename and containing time interval. Missing or
ambiguous joins remain explicit. It separates cancelled records from ordinary
failures/outliers and retains all records for file-by-file comparisons.

`RunCatalogPerformance.py --source-diagnostics` enables the callback in the test
loader and marks the run settings. The runner explicitly disables inherited
flags for normal runs. Diagnostic/normal comparisons are rejected by the existing
settings compatibility check. The changed harness fingerprint also prevents
silently comparing these captures against the historical harness. Benchmark
version 2 and normal readiness semantics remain unchanged.

## Workload and provenance

Restored pinned packages into `/tmp/rawcull-phase5-packages` because the previous
DerivedData package cache no longer existed. Used the resolved revisions,
including RawParserKit 1.3.2, without editing dependency checkouts. Initial sandbox
network/hardware-query attempts failed; approved runs used normal Xcode services.

Ran the original nonrecursive 809 ARWs, 50,126,917,632 bytes, 1616-pixel previews,
100 browsing steps, Release, arm64, Xcode 27.1 (27A9275). Workload fingerprint:
`be62561f3e8de6cd31775afc3df0c282586f0c6803ed2fe3697f559faef549ce`.
Three repetitions with diagnostics were followed by three normal-mode controls;
each repetition began with its own empty thumbnail cache. Repetitions share a
process. OS/parser caches were not flushed. Display, power and unrelated
background activity were not independently verified. No Instruments recording
ran concurrently.

Both batches passed with no harness failures and matching pre/post source,
workload and toolchain checks. Captured source SHA-256:
`a57935427a5575996c8d79cc1bbca6ff4e41a1ec3fc07141fa972f1f65a9070b`.
Harness SHA-256:
`0f37c719553f7a05fa8a152553b8af9487915afd660544d7368f5828bdd46203`.
Capture parent commit was `0f56ecb5`, with the diagnostic changes uncommitted.

## Results

| Batch/run | Cold preload | Warm preload | Process CPU delta | Sampled peak footprint | Preload loads ≥1 s | Maximum outer preload load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Diagnostic 1 | 8.756 s | 3.220 s | 29.248 s | 301.9 MiB | 3 | 2.800 s |
| Diagnostic 2 | 8.562 s | 3.076 s | 28.541 s | 210.0 MiB | 6 | 3.192 s |
| Diagnostic 3 | 8.682 s | 3.235 s | 27.989 s | 228.2 MiB | 6 | 2.182 s |
| Normal control 1 | 8.596 s | 3.421 s | 29.558 s | 254.0 MiB | 5 | 1.933 s |
| Normal control 2 | 9.199 s | 3.136 s | 29.530 s | 218.8 MiB | 5 | 2.456 s |
| Normal control 3 | 8.809 s | 3.275 s | 28.478 s | 216.5 MiB | 8 | 1.887 s |

This is an observational diagnostic/control sequence, not a randomized overhead
experiment or an optimization comparison. Extra clocks, UUIDs, signposts,
reporting and scheduling can perturb diagnostics. The pooled outer preload
median is 14.729 ms diagnostic versus 14.410 ms normal; neither that difference
nor the phase/resource differences establish a causal overhead estimate or an
application gain/regression.

Each diagnostic repetition contains 829 ordinary source records: 809 cold
preload calls, ten separate source-thumbnail samples and ten preview samples.
All 2,487 ordinary source records succeeded and matched exactly one outer metric.
There are nine additional cancellation records, three per repetition, all flagged
cancelled, with no ordinary failure misclassification and no ambiguous joins.
Normal control journals contain no source-load events, confirming opt-in isolation.
All 809 ordinary preload decodes/saves per repetition succeeded in both batches;
warm preparation, prepared browsing/no-source-fallback, bounded saves,
cancellation/drain and recovery checks passed.

All 15 diagnostic preload calls ≥1 second have **at least 99.995% of adapter
duration inside the parser round trip**. For these outliers, combined adapter
work outside that span is at most 0.068 ms; the outer timer adds at most 0.074 ms.
Thus access acquisition, the adapter task's initial scheduling, result delivery
and reporting waits do not explain these particular multi-second delays.
This does not establish their cost in every app workload.

The 15 outliers name 15 different files. In the other two repetitions, those
same files take 11.496–36.819 ms at the adapter boundary. Examples:

| File | Diagnostic 1 adapter | Diagnostic 2 adapter | Diagnostic 3 adapter |
| --- | ---: | ---: | ---: |
| `_DSC4800.ARW` | 2799.459 ms | 24.945 ms | 13.769 ms |
| `_DSC5034.ARW` | 14.232 ms | 3191.819 ms | 36.819 ms |

The phase 3 baseline similarly names nine different ≥1-second files; their other
repetitions take approximately 11–24 ms. These observations argue against a
consistently slow file on this workload. They do not exclude intermittent storage,
parser state, executor scheduling or contention. The controls also reproduce
outliers, showing that the phenomenon is not confined to diagnostic mode.

## Interpretation and unresolved limits

The evidence localizes the long tail to the parser **call**, not to a particular
internal component. RawParserKit has private actor state and a six-slot thumbnail
limiter; application preload is independently bounded to four workers. Neither
limit is changed. Source inspection alone cannot prove limiter occupancy or
whether a slow call is running, waiting on I/O, or queued behind another job.

No same-run thread-state, syscall or I/O trace was captured. Historical reads
(including `_DSC4506.ARW` in a different recording) must not be assigned to these
new outliers. Pure parser execution and its internal admission/actor waits remain
combined. There is no isolated dependency defect/reproduction warranting a patch.

The existing concurrent-browsing phase uses warm disk preparation and prepared
requests. Its success does **not** establish the latency of a cold interactive
source request queued alongside cold preload. The ten source-thumbnail samples
run after preload. Cold interactive contention and priority/fairness remain
unmeasured; there is no evidence-backed priority change here.

A further cause-level investigation needs a separate diagnostic run with the
same per-file UUIDs plus process-scoped thread-state and file-I/O data. Validate
RawSourceLoad signposts in a short smoke capture before interpreting a full trace,
and distinguish private queue wait from native execution. No recording is needed
from the user to accept this phase's diagnostic/defer decision. Phase 6's UI hitch
work still needs its own controlled action sequence and appropriate recording.

## Reproduction and validation

```sh
python3 -B Scripts/RunCatalogPerformance.py \
  /Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF \
  --output /tmp/rawcull-phase5-diagnostic --runs 3 --steps 100 --pixels 1616 \
  --source-diagnostics --package-cache /tmp/rawcull-phase5-packages \
  --notes 'Phase 5 adapter diagnostics; OS/parser caches not flushed; no trace; conditions not independently verified'
python3 -B Scripts/AnalyzeSourceLoadDiagnostics.py \
  /tmp/rawcull-phase5-diagnostic > /tmp/rawcull-phase5-source-analysis.json
```

The normal control uses the same invocation without `--source-diagnostics`, a
new output `/tmp/rawcull-phase5-control`, and notes recording its order/context.
Actual full commands/notes and source provenance are in each run configuration.
Do not reuse an existing output directory. Neither batch uses `--baseline`:
diagnostic settings and the changed harness are not compatible with old reports.

All 31 focused Python checks pass: 18 exporter/catalog, four signpost, four grid
analysis and five source-load analysis tests. Runner tests cover inherited flag
isolation and diagnostic/normal incompatibility. Source analysis tests cover
reporting overhead versus parser span, cancelled operations, repeated filenames,
ambiguous joins, invalid timestamps and missing outer metrics. Five focused Swift
report tests pass, including original-timestamp serialization independent of the
journal hop. Optimized app/test compilation and diff checks pass.

After capture, resolved new lint warnings through formatting/import ordering,
shortened signpost metadata to UUID and filename, and simplified a test type
check. Rebuilt the final Release sources and reran the five focused Swift tests
successfully. Six full catalog repetitions were not repeated for these changes.
The captured app/dSYM were copied before relinking (matching arm64 UUID
`75BEA41D-174A-38C6-B0B3-C919BB6C6348`). A complete captured-source snapshot,
including restoration of the two pre-cleanup files, was verified against the
capture's aggregate source SHA-256. Final sources are retained in Git.

SwiftLint reports only existing RawImageLoading complexity and the pre-existing
`x`/`y` identifier errors, verified against the parent version. It is **not** a
clean repository-wide lint result. No new violations remain in the changed code.
No SwiftUI/visual acceptance, new hitch result or performance improvement is claimed.

Diagnostic implementation commit: `0b1efff7`.
User-approved, checksum/inventory-verified evidence archive:
`/Volumes/MacMini4/TestRunPerformance/phase5-source-load-investigation-2026-10-24`.
It retains both complete benchmark outputs/caches/xcresults, source analysis,
historical file-repeat result, captured app/dSYM and verified captured-source
snapshot, final diagnostic source/report copies, focused-test xcresults/logs,
package-resolution provenance and lint/Python validation logs. The manifest lists
source/destination inventories, SHA-256 values and symlink targets. No historical
artifacts or temporary originals were removed. Phase 6 has not started.
