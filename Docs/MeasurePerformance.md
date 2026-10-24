# Measure catalog performance: Python benchmark and Instruments

Use this workflow to measure the same catalog through the production component benchmark and the complete macOS app. Run the Python benchmark first, then record the app opening that catalog in Xcode Instruments. Save the recording as **`~/Downloads/opencatalog.trace`** and export it with the helper below.

The benchmark measures image readiness and component throughput. Instruments adds UI layout, rendering, frame hitches, scheduling and filesystem evidence. Their elapsed times are not interchangeable; use both to explain where the work goes.

## 1. Prepare a comparable workload

Run these commands from the repository root:

```sh
cd /Users/thomas/GitHub/RawCull/RawCull
xcodebuild -version
xcrun xctrace version
```

Use the same physical catalog path, files, computer, display setup and power mode for both runs. Close heavy background work. Do not edit source, change settings or move files between benchmark and recording. Keep the original `.trace` and its matching Release build/dSYM for symbolication.

The commands below use the catalog from the previous successful run. Change `CATALOG` if measuring a different folder. A fresh output directory is required each time:

```sh
CATALOG="/Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF"
BENCHMARK="/tmp/rawcull-performance-v2-before"
```

The benchmark scans this folder nonrecursively and expects valid ARWs. It reads source files without editing them.

### Thumbnail size and cache state

Check RawCull's preview thumbnail size in Settings and pass that exact size to `--pixels`. The app source default is 1616; the benchmark CLI default is 1600. The examples below explicitly use **1616** for both. If your saved app setting differs, change it or change `--pixels` accordingly. Record your choice in the notes.

The benchmark uses three independent, initially empty thumbnail disk caches inside its output folder. Each repetition measures cold thumbnail creation, then reads its populated cache with thumbnail RAM cleared. The normal application's thumbnail cache is separate.

For the app recording, decide whether you want:

- **Cold thumbnail cache:** with RawCull closed, preserve the existing `Thumbnails` folder by moving it aside, then launch RawCull. Only move the thumbnail cache, not application support, catalogs or saved culling data. The usual cache root is `~/Library/Caches/no.blogspot.RawCull/Thumbnails`; a sandboxed build may use `~/Library/Containers/no.blogspot.RawCull/Data/Library/Caches/no.blogspot.RawCull/Thumbnails`. Locate the cache used by the actual build before moving anything. Keep the backup until the investigation is finished.
- **Warm thumbnail cache:** leave the app's populated thumbnail cache in place and quit/relaunch the app to avoid simply measuring RAM hits.

Do not describe a run as fully cold storage: the OS and parser caches are not flushed. Running the benchmark first can warm source filesystem data for the app. Repeat the same ordering for future comparisons.

## 2. Run the Python benchmark

Optional manifest-only check:

```sh
python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" --validate-only
```

Run all three repetitions:

```sh
python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" \
  --output "$BENCHMARK" \
  --runs 3 --steps 100 --pixels 1616 \
  --notes "External volume; AC power; preview 1616px; record display setup and power mode here"
```

Wait for `PASSED`. Open the report:

```sh
open "$BENCHMARK/report.md"
```

The output includes `results.json`, `report.md`, `run-configuration.json`, `xcodebuild.log`, `tests.xcresult`, and each `run-N` directory's raw JSON/events and benchmark JPEG caches.

Version 2 reporting includes:

| Measurement | Meaning |
|---|---|
| `catalog.discovery`, `catalog.metadata` | File discovery and metadata scan |
| `preload.emptyDiskCache` | Entire cold preload, including extraction, grid creation, JPEG encoding and awaited saves |
| `preload.warmDiskCache` | Entire preload using the previously generated disk thumbnails |
| `decode.preload` | Source-thumbnail loading through the parser adapter, including scheduling/adapter overhead |
| `jpeg.encode` | Per-file thumbnail JPEG encoding, before the disk save |
| `grid.preloadResize` | Actual grid thumbnail creation throughout preload; skips existing grid hits |
| `cache.save` | Saving already encoded JPEG data and checking that the file exists |
| `grid.resize` | Separate small image sample, not the full-catalog grid workload |
| `browse.*`, `zoom.previewReady` | Image-ready latency, not first painted pixels |
| Individual repetitions | Cold/warm wall timings and encoding/grid operation sums for each run |
| Resources | Sampled process footprint, corrected CPU seconds, disk counters, concurrency counts |

CPU seconds sum all process threads and can exceed wall time. Mach counters are converted using the host's timebase. Per-operation elapsed times can overlap; their sums are neither CPU time nor the enclosing phase's wall time. RAM/CPU sampling is every 100 ms and can miss brief peaks.

**Legacy baseline:** `/tmp/rawcull-before` was generated with version 1. Its CPU totals are about 41.67 times too small on this Mac (timebase 125/3), and it lacks the new encoding/grid phases. Preserve it as historical evidence. Make a new version 2 baseline for automated before/after comparisons; `--baseline` deliberately rejects incompatible versions/harnesses. Do not blindly apply 125/3 on a different machine.

## 3. Record `opencatalog.trace` in Xcode Instruments

1. Open `RawCull.xcodeproj` in Xcode and select the **RawCull app scheme**, destination **My Mac**. Use the same source checkout as the benchmark.
2. In **Product → Scheme → Edit Scheme → Profile**, verify **Release**. Disable coverage and sanitizers for the performance recording. Choose **Product → Profile** (Command-I).
3. Select the **SwiftUI** template. Verify that **Time Profiler**, **SwiftUI**, **Hangs** and **Hitches** are present. Include microhangs over 250 ms. Use the same Time Profiler sampling setting across recordings; Standard reduces overhead compared with High.
4. Add **os_signpost** (or Points of Interest displaying the app's signposts). The app emits subsystem `no.blogspot.RawCull`, category `CatalogPerformance`, with `CatalogOpen`, `CatalogMetadataScan`, `CatalogThumbnailPreload`, and the completion event `CatalogThumbnailPreloadComplete`. The preload interval includes the requested pixel size; the completion event includes prepared count and size.
5. To investigate the occasional long decode delays, add **Thread Activity**, **Filesystem Activity**, and **Disk I/O Latency**. Add **System Call Trace** if you need syscall attribution. These are the names available in the installed Instruments. They add overhead; keep this instrument set consistent, or make a separate diagnostic recording and label it accordingly. Grant Instruments any recording permissions macOS requests.
6. Record RawCull. Let the initial window settle, note the elapsed recording time, then use **File → Add Catalog…** to open exactly the folder used for Python. Avoid starting AI analysis or unrelated work.
7. Wait until thumbnail creation finishes. Note when the catalog first becomes visible and when progress completes. Browse some images and open a zoom preview. Note those actions and any visible pauses. Wait a few seconds, then press Stop.
8. Check that the signpost intervals, profiler stacks and filesystem/thread lanes actually contain data. If you attach after the catalog was already loaded, its opening cannot be reconstructed afterward.
9. Save with **File → Save** as **`opencatalog.trace` in Downloads**. Finish saving before exporting. If that name already exists, preserve the previous recording under another name first.

If the combined instrument set cannot be recorded on your system, keep the SwiftUI recording and make a separate wait/I/O recording, saved under another name. Export both with distinct output directories. Missing instruments cannot be added retroactively through XML export.

For a warm-cache comparison, quit/relaunch, open the same catalog again, and save a second trace as `opencatalog-warm.trace`. Keep the first cold trace intact.

## 4. Export the trace for comparison

Use the helper to export **each table as an independent XML document**, with its own schema and references. It reads the table of contents, exports the relevant tables that actually exist, validates their XML and counts rows. It also copies the benchmark report/results into the export folder and records the trace details, export queries, row counts and warnings in `export-manifest.json`.

The following command uses the exact Downloads filename and benchmark directory above:

```sh
python3 -B Scripts/ExportCatalogTrace.py "$HOME/Downloads/opencatalog.trace" \
  --benchmark /tmp/rawcull-performance-v2-before \
  --output /tmp/rawcull-opencatalog-export \
  --notes "Cold thumbnail cache; preview 1616px; opened same catalog; add action times and visible pauses here"
```

Use `Warm thumbnail cache` in the notes if that is what you recorded. The output directory must not already exist. Exports can take several minutes and substantial disk space. The script prints progress per table. It never launches or records the app.

By default it exports Time Profiler, primary SwiftUI updates and causes, hitches/hangs, process/thread/lifecycle metadata, and any detected signpost, log, scheduling/wait or filesystem/disk tables. Raw kernel sampling tables are large; for a complete export of **every table**, use a separate output directory and `--all-tables`:

```sh
python3 -B Scripts/ExportCatalogTrace.py "$HOME/Downloads/opencatalog.trace" \
  --benchmark /tmp/rawcull-performance-v2-before \
  --output /tmp/rawcull-opencatalog-export-all \
  --all-tables \
  --notes "Cold thumbnail cache; preview 1616px; same catalog; add recording actions here"
```

For a warm recording:

```sh
python3 -B Scripts/ExportCatalogTrace.py "$HOME/Downloads/opencatalog-warm.trace" \
  --benchmark /tmp/rawcull-performance-v2-before \
  --output /tmp/rawcull-opencatalog-warm-export \
  --notes "Warm thumbnail cache; fresh app launch; preview 1616px; same catalog"
```

If the `.trace` has multiple recordings, use `--run 2` (or the desired recording number shown in `trace-toc.xml`). Export success does not mean all instruments were recorded: read the manifest warnings. Empty hang/hitch tables may legitimately mean zero detected events; an empty CPU profile is treated as an export failure.

### Manual export commands

The helper is preferred because it includes every matching table and validates the result. To inspect or export specific lanes manually:

```sh
xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --toc --output /tmp/opencatalog-toc.xml

xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /tmp/opencatalog-cpu.xml

xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="swiftui-updates"]' \
  --output /tmp/opencatalog-swiftui.xml

xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="swiftui-causes"]' \
  --output /tmp/opencatalog-causes.xml

xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' \
  --output /tmp/opencatalog-hitches.xml

xcrun xctrace export --input "$HOME/Downloads/opencatalog.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' \
  --output /tmp/opencatalog-hangs.xml
```

Signpost and I/O schema names depend on the instruments used. Read the TOC rather than guessing their names, or let the helper choose the tables. A 65-byte `<trace-query-result>` with no nodes is an unmatched query, not a usable data export. Avoid one broad all-table XML query: it can share references and omit later schema definitions, making independent table analysis difficult.

## 5. Provide the results for analysis

Give Codex these paths:

```text
/tmp/rawcull-performance-v2-before
/tmp/rawcull-opencatalog-export
~/Downloads/opencatalog.trace
```

If you chose `--all-tables`, provide `/tmp/rawcull-opencatalog-export-all` instead. Keep the original recording available for Instruments inspection and symbolication. Include the cache state, actual thumbnail size, action timestamps, display setup and observed pause. Keep results somewhere durable if you need them after reboot: `/tmp` is temporary.

Ask: “Compare this benchmark with the catalog-opening trace. Use signposts to separate startup, metadata, thumbnail preparation and browsing; inspect JPEG/grid CPU costs, UI hitches, progress invalidations and wait/I/O evidence.”

The analysis should use actual profiler sample weights, not assume 1 ms/sample; the previous trace used 0.1 ms. Count primary SwiftUI updates separately from update groups. Do not equate zero hangs with zero hitches, sum overlapping stack costs as elapsed time, or attribute a benchmark file's slow decode to an unrelated event in another recording. The script packages evidence; it does not automatically diagnose every wait or prove equivalent cache/settings conditions.

## 6. Repeat after an optimization

Keep the instrumentation and workload unchanged between before/after runs:

```sh
python3 -B Scripts/RunCatalogPerformance.py "$CATALOG" \
  --output /tmp/rawcull-performance-v2-after \
  --runs 3 --steps 100 --pixels 1616 \
  --baseline /tmp/rawcull-performance-v2-before \
  --notes "Same storage, power mode, display and cache-order conditions"
```

An optional `--max-regression-percent 20` fails when a measured median increases by more than 20% and more than 5 ms. p95/worst remain diagnostic; three repetitions do not establish a strong tail distribution. Instrumentation/harness changes require a fresh baseline. Record the optimized app again with the same Instruments setup and export it to a different directory.

See [CatalogPerformance.md](CatalogPerformance.md) for detailed benchmark semantics and correctness checks.

## Phase 1 exporter diagnostics

Before a full recording, save a short Release smoke trace to a **new** path.
In the os_signpost instrument, enable the `no.blogspot.RawCull` subsystem and
`CatalogPerformance` category (check process and signpost filters). Open a small
catalog after recording starts. Verify `CatalogOpen`, `CatalogMetadataScan`,
`CatalogThumbnailPreload`, and `CatalogThumbnailPreloadComplete` in the timeline,
including `pixels` and `prepared` metadata. Repeat cancellation and catalog
replacement and check that each started interval ends under its own signpost ID.
If tables remain empty, inspect instrument configuration before changing emission.
Binary strings establish instrumentation presence, not successful collection.

The exporter now records `phase_alignment.signpost_status` as `missing_schema`,
`empty_data`, or `exported_nonempty`. An exported document can be valid while
phase alignment is unavailable. Nonempty rows may belong to unrelated signposts;
`ready` remains false until a separate recording review verifies catalog names,
interval pairing and completion metadata. Retain that review alongside the manifest.

Each profiler view retains all TOC attributes and its own XML document. A
streaming, disk-backed reference index computes ordered sample and weight
fingerprints without retaining the XML reference graph in memory. Identical
resolved sample sequences with differing weights produce a warning; views are
never merged or automatically selected. These fingerprints detect identical
ordered views, not partially overlapping samples. Forward or missing references
fail validation explicitly. XML fingerprints are diagnostics, not CPU estimates.
Use recorded weight values and units for analysis; validate any chosen view
against the recording's sampling configuration and independent thread running
intervals. Until resolved, report relative shares and qualify absolute CPU values.
The temporary reference database requires disk space proportional to unique IDs.

`swiftui-update-groups` is exported by default when present. Its row count counts
groups; `swiftui-updates` counts primary events, whose body-update subset must be
classified separately. Do not add these counts together.

For this baseline, preserved inputs are under
`/Volumes/MacMini4/TestRunPerformance/firstrun/tmp/` and the trace is under
`/Volumes/MacMini4/TestRunPerformance/firstrun/Downloads/`. Export to a fresh
location, never into that archive. The installed `/Applications/RawCull.app`
may lag the profiled build: check executable identity and instrumentation before
attaching. Prefer launching the explicit Release executable over attaching by name.

On Xcode 27.1, inspect `xcrun xctrace record --template MySwiftUI --show-recording-options`.
To enable collection, save its **complete** JSON, add `no.blogspot.RawCull` to
`os_signpost.dynamicTracingEnabledSubsystems`, and pass the file with
`--recording-options`. Partial objects can fail with a missing-data error. Save
those options with the new trace; an empty subsystem list alone does not prove
the historical cause. A recording with logging-stream errors is diagnostic
failure evidence and cannot satisfy the smoke-test exit criterion.

Validated smoke configuration (24 October): Xcode Profile of the DerivedData
Release app, Blank template plus os_signpost, Immediate mode, enabled subsystem
`no.blogspot.RawCull`. The completed smoke trace contains balanced catalog
intervals and `prepared=809 pixels=1616`. A yellow warning about backdated
intervals appearing only after Stop is distinct from the fatal log-archive error;
inspect the stopped trace before declaring missing intervals. Save this setup
and retain Immediate mode for subsequent correlated captures, recording the mode
as part of provenance. Cancellation and catalog-switch pairing still need checking.

The combined os_signpost/Hangs/Time Profiler/SwiftUI/Hitches setup disables
Immediate mode in the user's Instruments 27.1. A 40.7-second Deferred trial
reproduced the fatal logging archive error and exported zero signpost rows,
while CPU samples survived. Do not assume the successful Immediate-only smoke
configuration works with the full set. Check availability of Immediate mode in
a smaller instrument subset before further recording. Do not use phase timings
from separate recordings to align CPU/SwiftUI windows.

### Repeatable signpost pairing validation

The working combined subset is Time Profiler plus os_signpost in Immediate mode,
standard sampling, enabled subsystem `no.blogspot.RawCull`. Complete warm/cold
captures contain CPU samples and balanced catalog intervals. Raw event XML must
be exported independently for the selected table index from its TOC; indices vary
between traces. Do not use modeled intervals for the following check:

```sh
python3 -B Scripts/ValidateCatalogSignposts.py /absolute/path/raw-os-signpost.xml
```

The checker resolves references with a disk-backed index, filters the RawCull
catalog category, sorts its events by timestamp, pairs Begin/End by process,
scope, identifier and name, and checks completion pixels/prepared metadata.
Exit 0 means the exported events pair correctly; exit 1 reports missing,
truncated, duplicated or malformed data. It intentionally accepts partial prepared
counts after cancellation. It does not infer cancellation from such a count,
prove that UI callbacks are current, or label unrelated SwiftUI events by timing
from another recording. Use the dynamic-subsystem table containing RawCull events;
empty sibling os-signpost views may coexist in the same trace.

For cancellation/switch validation, record selecting a replacement catalog during
preparation with caches unchanged, allow all cancelled work to drain and the new
load to finish, then stop. Record the action sequence separately: the current
signposts do not carry catalog URL identity. A balanced normal load alone does
not establish this path was exercised. Do not quit the app to simulate cancellation;
process termination cannot execute deferred interval cleanup.

Phase 1 evidence archive: `/Volumes/MacMini4/TestRunPerformance/phase1-2026-10-24`.
It includes complete warm/cold/switch CPU-signpost traces/exports and the failing
Deferred trial, plus the matching Release binary/dSYM and checksum inventory.
The switch trace passes pairing for both overlapping catalog loads, including
completion metadata; the trace itself does not identify the catalog paths or
explicitly label cancellation. Keep the written action notes with it. This closes
the observed switching pairing check; it does not establish UI correctness or
remove the phase 2 SwiftUI/hitch measurement limitation.


## Optional source-load latency diagnostics (phase 5)

Use `Scripts/RunCatalogPerformance.py --source-diagnostics` with a new output
directory to capture adapter-stage timing and `RawSourceLoad` UUID/file
signposts. Normal app use does not enable this path. Diagnostic run settings
prevent comparison with normal baselines; the updated harness fingerprint also
requires a compatible new baseline. Preserve `events.jsonl` and the separate
cancellation journal, then analyze with:

```sh
python3 -B Scripts/AnalyzeSourceLoadDiagnostics.py /path/to/diagnostic-output
```

The parser roundtrip includes private actor/limiter waits, scheduling, native I/O
and decode. It is not decode CPU time. The journal preserves original monotonic
timestamps and its clock origin before reporting waits. The analyzer joins by
operation, filename and containing interval, keeping cancelled calls separate.
No source event is converted into an ordinary required benchmark phase.
The runner forces diagnostics off unless explicitly requested, including when an
opt-in flag is inherited from the shell. See [phase 5](PerformancePhase5.md) for
validated commands, measurements, source identities and unresolved limits.

For cause-level attribution, collect thread-state and file-I/O evidence in that
same diagnostic run and correlate UUID/file/time boundaries. Validate the new
signpost category in a smoke recording first; phase 5 compiled/emitted it but did
not validate an Instruments capture. A different recording's slow read cannot
explain the benchmark's named outlier. Prepared warm browsing does not measure
cold interactive-source contention alongside cold preload.
