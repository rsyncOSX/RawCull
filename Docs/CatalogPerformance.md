# Real ARW catalog performance benchmark

## Purpose and implementation plan

Provide a repeatable Release integration test against a user-supplied, nonrecursive ARW catalog. Exercise production discovery, metadata scanning, thumbnail preparation, disk loading, interactive thumbnail requests, zoom preview decoding, grid resizing, navigation presentation, and cancellation. Capture enough provenance and raw measurements to compare a later source revision without Instruments.

Implementation:

1. Validate the input and record the catalog manifest, source identity, machine, toolchain, and fixed workload settings.
2. Compile the application and a dedicated `RawCullPerformanceTests` target in Release, with testability enabled. Disable code coverage, sanitizers, and parallel testing. Disable App Sandbox only for this benchmark build so a command-line catalog path can be read without a picker-issued security bookmark; normal application build settings are unchanged. Select only the opt-in catalog suite. Use a separate `build/CatalogPerformance` derived-data directory to isolate test products from normal app builds.
3. Use fresh thumbnail disk caches under each run's output directory. Forward metadata/image operations to the real production parser through a measuring adapter. Use the existing production task-group save path with a measuring saver.
4. Run the phases below, recording per-operation monotonic timing, success/failure, counters, and process resource samples. Persist JSONL throughout execution and a full JSON snapshot after each repetition, including failed runs.
5. Aggregate a Markdown report and self-contained JSON. Optionally compare against a compatible previous JSON report and apply an explicitly requested timing threshold.

## Run

From the repository root, with Xcode installed and the pinned package dependencies available:

```sh
python3 -B Scripts/RunCatalogPerformance.py "/Volumes/Photos/My ARW Catalog" \
  --output /tmp/rawcull-before
```

Or:

```sh
make catalog-performance CATALOG="/Volumes/Photos/My ARW Catalog" \
  PERF_ARGS='--output /tmp/rawcull-before'
```

The folder is required; no personal catalog path is embedded in the test. The output directory must be new and outside both the source catalog and repository. If omitted, a unique private temporary directory is created. Keep or copy the output directory to durable storage if using `/tmp`.

The source catalog is read only. Subdirectories are not traversed. Use an ARW-only catalog; the benchmark rejects other RAW formats discovered by production scanning. Invalid/undecodable files fail the run. Sidecar metadata is not edited. Thumbnail disk caches used by the measured pipeline are separate from the normal application thumbnail cache. The app-hosted test still initializes ordinary application services and reads application settings, as other app-hosted tests do.

Validate input without building:

```sh
python3 -B Scripts/RunCatalogPerformance.py "/Volumes/Photos/My ARW Catalog" --validate-only
```

Default workload: three repetitions in one process, 100 navigation actions, up to 100 evenly spaced distinct thumbnail requests per browsing phase, up to 10 evenly spaced zoom-preview and resize samples, and 1600-pixel thumbnails. Override with `--runs`, `--steps`, and `--pixels`. `--timeout` bounds the complete build/test subprocess (default 3600 seconds). Each repetition uses new benchmark disk caches; RAM thumbnail caches are cleared at documented phase boundaries. Preview RAM is capped at 256 MiB and grid RAM at 128 MiB; pressure handling may still evict entries.

## Executed phases

| Phase | Actual production work and checks |
| --- | --- |
| Discovery | Discover the folder's supported RAW files; require nonempty ARW-only input. |
| Metadata | Scan all files through ScanFiles/RawParserKit, sort by localized filename, require matching URL membership and successful metadata reads. |
| Empty thumbnail disk cache | Preload all files, including real source extraction, grid resizing, JPEG encoding and awaited disk saves. Require every cached JPEG to exist. |
| Warm thumbnail disk cache | Clear thumbnail RAM and preload again. Require every file to succeed with no additional source decodes or saves. |
| Disk-backed browsing | Clear thumbnail RAM and request evenly spaced prepared thumbnails through RequestThumbnail. Record each request-to-image-ready latency. |
| Revisit browsing | Request those images in reverse order without clearing RAM. This is a mixed RAM/disk workload if the working set exceeds cache limits. Require no source-decoding fallback. |
| Browsing during preparation | Clear thumbnail RAM and run warm preload alongside real interactive thumbnail requests. Scheduling overlap is workload-dependent; this does not simulate human input timing. |
| Grid resizing | Decode representative source thumbnails, then separately time GridThumbnailResizer. Check valid output dimensions capped at 200 pixels. |
| Navigation/controls | Use real scanned FileItems in the application view model. Time ordering and selection/control queries. Require ordering reuse across selection changes and correct filter/context/catalog invalidation. Uses isolated test persistence and does not load AI models. |
| Zoom preview | Decode production full embedded previews for representative files. Measure image readiness; does not exercise window rendering or full RAW demosaic. |
| Cancellation | Start real source extraction with a separate empty cache, request cancellation after a source decode starts, then wait for preload to drain. Save partial decode logs separately. Native reads already running may continue until completion. Very small catalogs may finish before cancellation is delivered. |
| Recovery | Complete a new warm preload after cancellation and require every file to succeed. |

The measuring saver records outstanding saves and encoded bytes. The test checks that observed outstanding preload saves do not exceed the production preload worker limit. This is an observation of this storage workload; the existing controlled stalled-save ownership tests provide stronger deterministic backpressure coverage.

## Complete output

- `run-configuration.json`: written before build/test; includes complete input manifest, settings, command, commit, worktree status, source fingerprint, hardware/OS, and Xcode version.
- `xcodebuild.log`: complete build and test output, including compiler and test failures.
- `tests.xcresult`: native Xcode test result bundle, when Xcode produces it.
- `run-N/events.jsonl`: incremental per-file operations, phase results, and 100 ms process-resource samples. Per-operation entries include phase, filename where relevant, elapsed duration, success, and relative completion timestamp. Raw data is retained, not just averages.
- `run-N/results.json`: full repetition snapshot: all operations, resource samples, counts and peak outstanding saves.
- `run-N/cancellation-events.jsonl` and `cancellation-results.json`: separate interrupted-operation evidence; a cancelled decode returning nil is expected and does not count as an ordinary decode failure.
- `run-N/thumbnail-cache` and `cancellation-cache`: generated benchmark JPEGs. These may be deleted after the run; the reports do not depend on retaining them.
- `results.json`: self-contained combined report with provenance, raw repetition snapshots, summary distributions, resource deltas, failures and optional baseline comparison.
- `report.md`: readable results with median, p95 and worst elapsed time for each measured operation/phase, resources, failures and optional comparison.

If Xcode fails, times out, skips the selected test, or returns no results, the runner fails and reports missing/incomplete phases. Partial JSONL and build logs remain available. An inability to read process resource counters is reported as unavailable, not zero. If source files or the catalog manifest change during execution, the run fails to prevent a misleading baseline.

## Compare after updating code

Keep the old output. Run the same command against the same folder with a new output directory:

```sh
python3 -B Scripts/RunCatalogPerformance.py "/Volumes/Photos/My ARW Catalog" \
  --output /tmp/rawcull-after \
  --baseline /tmp/rawcull-before \
  --notes "External SSD, AC power, normal power mode, other heavy apps closed"
```

`--baseline` accepts either the previous output directory or its `results.json`. Commit/source fingerprints are expected to differ. Catalog path and manifest, machine/OS, Xcode, workload settings, benchmark implementation fingerprint, and benchmark format version must match. The baseline must have passed. These checks cannot verify that storage, power, temperature, and competing workload are identical: record those in `--notes`.

The comparison records before/after median, p95 and worst time, with signed percentages, plus median resource changes across repetitions. Negative means less elapsed time. Comparison alone does not fail on timing changes. For an explicit regression gate:

```sh
python3 -B Scripts/RunCatalogPerformance.py "/Volumes/Photos/My ARW Catalog" \
  --output /tmp/rawcull-after --baseline /tmp/rawcull-before \
  --max-regression-percent 20
```

This fails when an operation's median increases by more than 20% **and** more than 5 ms. Tail changes remain visible without gating because few samples and occasional system interference make them noisy. For phases executed once per repetition, p95/worst across three repetitions are descriptive, not statistically strong tail estimates. Review each repetition's raw results as well as pooled summaries.

Exit codes: 0 passed; 1 execution/correctness/threshold failure; 2 invalid input, incompatible baseline, or runner error.

## Interpretation and limits

This is an optimized component integration benchmark, not an end-to-end UI automation test. It does not open a catalog through the picker, hydrate saved review artifacts, measure first painted grid content, synthesize real keyboard events, count dropped frames, or establish absence of leaks. Navigation uses scanned production data with isolated persistence. It does not exercise AI analysis.

“Empty disk cache” applies to the benchmark thumbnail cache. OS filesystem caches and internal parser caches are not flushed. Repetitions share a process, so later runs can benefit from warm-up. Keep repetition counts, order, storage and system conditions consistent.

The sampler uses process physical footprint, cumulative CPU time and disk-I/O counters. Values include the app test host, instrumentation, and ordinary service initialization. Memory is sampled every 100 ms and may miss brief peaks. Per-file timings include adapter, actor-hop, scheduling and logging overhead; phase timings include journal overhead. Per-file phases overlap within concurrent work, so their durations must not be added as total elapsed time.

The catalog fingerprint hashes sorted filenames, sizes and modification timestamps, not full ARW contents; this avoids reading tens of gigabytes before each test and changing cache conditions. The complete manifest and fingerprint method are saved. It is an identity check, not proof against deliberately modified contents with preserved metadata.

The Python runner tests validate manifest handling, complete-output requirements, failure retention, percentile calculation, compatibility checks, and regression gating without personal photographs:

```sh
python3 -B -m unittest discover -s Scripts -p 'TestRunCatalogPerformance.py' -v
```

For an existing Xcode package checkout cache, pass `--package-cache /absolute/path/to/SourcePackages`. Dependency versions remain pinned; the path is saved in the executed command. Without this option, the separate derived-data directory resolves its own package checkouts using the pinned resolution file.

## Implementation validation

- Optimized arm64 Release application and dedicated benchmark target compiled successfully.
- Two Swift reporting/navigation checks passed in the Release test host.
- Nine runner tests passed, including a complete simulated run followed by baseline comparison. All 26 repository Python script tests passed, with one existing optional-dependency skip.
- An actual invocation against a deliberately invalid nonempty ARW fixture returned failure and retained per-operation results, resource samples, JSON/Markdown reports, build/test output, and the native result bundle. This validates failure reporting, not image performance.
- `git diff --check` passed. SwiftLint reported no source errors; analyzer-rule configuration warnings and a whitespace style warning remained.
- The app test host emitted `MDB_MAP_FULL` startup messages, also seen in earlier repository validation. The two checks passed; those host messages were not investigated as a benchmark implementation issue.

No real ARW catalog was supplied during construction. Successful full-catalog decoding, measured performance, and before/after performance comparisons must be established by running the command with the user's catalog.
