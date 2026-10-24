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
