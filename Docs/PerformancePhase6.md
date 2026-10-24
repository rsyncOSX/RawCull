# Phase 6 — UI hitches (in progress)

24 October 2026. **Interactive investigation complete; production optimization
deferred.** No application change or smoother-frame claim is justified by this
capture. Full acceptance remains limited by missing phase markers, workload/source
provenance and unverified interaction coverage. Phase 7 has not started.

## User capture findings

Preserved recording: `~/Downloads/rawcull-phase6-ui-before.trace` (approximately
1.3 GB). Run **1**, 50.798646 seconds, 24 October 2026 at 20:55:48–20:56:39 Oslo
time; Xcode/Instruments 27.1, Deferred, standard Time Profiler sampling, SwiftUI
layout updates off, Hangs threshold 250 ms. The user replied “no” to the question
about errors/visible pauses and supplied no action timestamps.

This was an Xcode-launched process, PID 12167, not the prepared attach PID 7499.
The exported main-image identity is:
`D64E676D-90C4-3746-B932-088CBCA1D738`, at
`/Users/thomas/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/Build/Products/Release/RawCull.app/Contents/MacOS/RawCull`.
That binary/dSYM is no longer at the recorded path after cleanup. Do not label
prepared UUID `5691876A-7C8A-3D18-BCF3-A24BA8991DBD` as matching this recording.
The trace's embedded symbol data is retained. Exact capture source hash, cache
state, pixels/prepared count, workload manifest, display/power conditions and
complete action coverage were not independently established for this run.

| Finding | Result |
| --- | ---: |
| Non-system hitches | 31 |
| Total recorded hitch duration | 1800.119 ms |
| Worst hitch | 516.701 ms |
| Detected hangs at 250 ms threshold | 0 |
| Independent main-thread running time | 3.202 s |
| Main-thread sampled weight | 3.205 s |
| CPU samples | 47,152, each recorded at 1 ms |

The independent main running total corroborates the selected single profiler
view's approximate sample weights. No duplicate conflicting view was found.
Blocked intervals include normal idle time and must not be called stalled work.
Inclusive stack weights overlap and are not additive elapsed time.

| Hitch start | Duration | Main running | Evidence-backed context |
| --- | ---: | ---: | --- |
| 0.695 s | 316.687 ms | 249.856 ms (78.9%) | Initial-window creation, SwiftUI/AppKit layout |
| 2.846 s | 516.701 ms | 32.674 ms (6.3%) | Native picker presentation, NSSavePanel/FileImportExportBridge stacks; predominantly waiting |
| 7.779 s | 83.339 ms | 66.347 ms (79.6%) | Native picker/sheet dismissal |
| 8.029 s | 83.339 ms | 64.241 ms (77.1%) | Main-thread update/render work |
| 12.663 s | 200.013 ms | 144.881 ms (72.4%) | Initial content/layout and thumbnail presentation |
| 42.048 s | 66.671 ms | 31.315 ms (47.0%) | Mixed main-thread/render/wait work; action not independently labelled |

After 13 seconds there are 24 hitches, worst 66.671 ms, mostly approximately
one frame. Neither these counts nor zero detected hangs prove smoothness.
The native picker wait does not justify moving unrelated RAW work or replacing
the picker. Startup's grain renderer accounts for approximately 8 ms of inclusive
main sampled work inside the 316.687 ms hitch. This is not its dominant cause.
Other named application callers contribute only a few sampled milliseconds to
the 200 ms event; framework graph/layout work dominates the inclusive stacks.
Reject a speculative grain, observation, picker or view-hierarchy rewrite here.

SwiftUI export: 290,560 primary updates (281,629 Other, 8,628 View Body,
303 Representable), 827,719 separate update groups and 179,258 cause edges.
Groups and primary events are distinct measures and must not be added together.
Selected body events across the whole trace:

| View | Body event count | Sum of body event durations |
| --- | ---: | ---: |
| RawCullMainView | 10 | 4.505 ms |
| FileDetailView | 16 | 15.454 ms |
| SidebarARWCatalogFileView | 220 | 16.292 ms |
| ProgressCount | 202 | 10.601 ms |

The largest FileDetailView body event is 14.188 ms; Canvas has a 9.614 ms
non-body event. Counts are actual exported events, not CPU sample counts.
These whole-recording values are not phase-matched before/after evidence for
phase 2, and reduced totals versus historical captures cannot establish causality.
The cause graph includes native environment, animation and interaction work;
its generic aggregate names do not establish an application feedback loop.

All 13 selected export documents validated. RawCull catalog signposts and logs
are unavailable: the only exported signpost schema is for ConditionInducer and
has zero rows. No catalog phase interval or completion metadata is available.
Sampled occurrences of ScanFiles (~8.09–12.19 s) and ScanAndCreateThumbnails
(~12.91–40.15 s) are context clues, not precise phase durations. ZoomOverlayView
body events and zoom-named CPU frames are absent; ZoomMetadataPanel is also used
by Loupe, so its presence does not prove the zoom overlay was exercised. Grid,
rating/filter, reverse-navigation, cancellation and switching coverage are not
independently established. Carry these acceptance gaps into phase 7 rather than
claiming they passed. No optimization was retained, so there is no new after-run
or production performance improvement to report.

## Analysis, retention and disk-space limits

The first TOC attempts failed while the internal disk was effectively full.
After space was reclaimed, the same preserved trace exported successfully.
Only checksum-verified phase 5 temporary duplicates were removed (approximately
1.7 GB); their external archive and all source/new trace files were preserved.
No further deletion was performed during resumed analysis.

Selected UI/CPU/thread tables were exported with the repository exporter, using
an explicit schema subset to omit raw kernel/filesystem tables. XML references
in the analyses were resolved with disk-backed SQLite indexes; missing references
fail rather than silently becoming empty values. Main-thread running intervals
were merged before hitch intersections. Row/type totals were checked against
export counts; native recorded weights and independent running totals were
cross-checked. No application source changed and no build/tests were needed for
this documentation-only close-out.

Evidence paths:

- Original: `~/Downloads/rawcull-phase6-ui-before.trace` — preserve this bundle.
- `/tmp/rawcull-phase6-before-export/`: 13 XML tables, TOC and export manifest.
- `/tmp/rawcull-phase6-before-analysis-core.json`, `-analysis-causes.json`,
  `-analysis-updates.json`: derived detailed findings.
- `/tmp/rawcull-phase6-export-selected.py`, `-analyze.py`, `-analyze-ui.py`,
  `-analyze-updates.py`: the exact export/analysis procedures.
- Matching logs use `/tmp/rawcull-phase6-*.log`.

The procedure uses `Scripts/ExportCatalogTrace.py` with Run 1 and the archived
phase 5 normal benchmark as context only; it is not a same-run catalog benchmark.
Source/log/symbolication and uncollected lanes cannot be recovered by exporting.
A durable external archive of these new exports/analysis is still pending; do
not delete the temporary evidence before archiving. The original trace is kept
in Downloads. Earlier setup paths below are historical and may no longer exist
following reboot/cleanup. In particular, they do not describe the current UI or
running processes.



## Historical setup before the user capture

Built RawCull with project defaults, Release, arm64, pinned packages restored in
phase 5. The build succeeded:

```sh
xcodebuild build -project RawCull.xcodeproj -scheme RawCull \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  -clonedSourcePackagesDirPath /tmp/rawcull-phase5-packages \
  -derivedDataPath build/CatalogPerformance
```

No benchmark `ENABLE_APP_SANDBOX` or testability overrides were passed. The
project requests App Sandbox for this configuration; this is a build-setting
statement, not an independent runtime sandbox verification. The signing-inspection
command warned about an invalid entitlements blob, so do not infer runtime
sandbox status solely from that command. No signing/security setting was changed.

Build source commit: `195174b4aa4ba0a8340c7b0675f6c3a7f43ca281`.
Executable:
`/Users/thomas/GitHub/RawCull/RawCull/build/CatalogPerformance/Build/Products/Release/RawCull.app/Contents/MacOS/RawCull`.
App and dSYM arm64 UUID: `5691876A-7C8A-3D18-BCF3-A24BA8991DBD`.
Copied both complete bundles into `/tmp/rawcull-phase6-profile-build`, with a
build/identity manifest and executable/dSYM SHA-256 values. Build log:
`/tmp/rawcull-phase6-profile-build.log`.

Launched that explicit app with the native app tool and verified PID **7499**
using its executable path, not its display name. Its main window has no catalog
selected. Active settings were verified in the app UI: preview **1616 pixels**,
zoom sharpening **off**. Settings were not changed. The cache UI reported
259.2 MB of thumbnail disk cache and empty preview/grid RAM caches. No cache was
moved, cleared or reset; classify the next capture as **as-is cache state**.
A separate nonsandboxed settings file reported another preview size; it was not
used as evidence of the running app's settings.

Instruments currently has `/tmp/rawcull-phase6-gui-smoke.trace` open. **Next
Recording** is selected, attached to RawCull (7499), with:

- Hitches, Display, Time Profiler, Thread Activity, Thermal State and SwiftUI.
- Standard sampling (High Frequency Sampling off), SwiftUI layout tracing off.
- Deferred mode; Immediate is unavailable for this set.
- The automatic stop limit switched off; stop manually after the action sequence.

This configuration is prepared for a diagnostic interactive capture. Its full
collection is not established as clean. If the app is restarted, the PID changes;
verify the executable path again before recording. Do not select the older
`/Applications/RawCull.app` merely because it has the same name.

## Historical recording failure investigation

| Smoke | Target identity | Result |
| --- | --- | --- |
| CLI SwiftUI + Thread Activity, 12 s | Resolved to installed app, not intended workspace build | Fatal logging-archive error; some tables survive |
| CLI Animation Hitches + CPU/thread instruments, 12 s | Installed app | Same fatal error |
| CLI reduced hitch template with Hangs removed, 12 s | Installed app | Same fatal error; Immediate still unavailable |
| GUI reduced hitch template, approximately 18 s | Verified workspace build, PID 7499 | Same fatal error shown in Instruments; CPU/hitch/thread data survives |

The exact message is:

> Data stream: Fatal logging system error: The log archive is corrupt or incomplete and cannot be read

The three CLI calls supplied the workspace **.app** path, but inspection of the
exported main-image UUID/path and running processes showed resolution to
`/Applications/RawCull.app/Contents/MacOS/RawCull`, UUID
`895163D6-C305-3BD2-ABEE-8B38C07B0F2F`. They are **not current-code performance
measurements**. Do not repeat this launch shorthand. Prefer verified PID
attachment; any future launch command must pass and verify the explicit
`Contents/MacOS/RawCull` executable. A proposed launch spelling is not validated
until the trace's main-image path/UUID agrees.

The initial partial CLI export contains 33,496 SwiftUI update rows and 3,825
update-group rows, plus CPU/thread/hitch tables. Its two launch hitches total
350.023 ms; the larger is 333.355 ms, overlapping approximately 275.327 ms of
main-thread running (82.6%). Its sampled stacks include window restoration and
layout. This is **older installed-app, partial diagnostic evidence**, not a
current-code startup baseline or evidence for changing FileDetailView's grain
rendering. The grain renderer was inspected, but no causal sample finding or
production edit is claimed. Historical picker CPU/wait findings likewise do not
justify replacing the native picker without a new controlled measurement.

The GUI smoke deliberately contained no catalog, browsing or zoom actions.
Its displayed hitch counts must not be compared with the historical 25 hitches:
workload, attachment/startup coverage and instrument configuration differ.
SwiftUI was added only to **Next Recording**, after this GUI smoke.
The GUI reproduction establishes that the logging failure also occurs on the
current process and is not confined to the command-line launcher. It does not
identify the underlying logging-system defect.

A logging error does not prove every other exported table is empty. Preserve
partial recordings and validate each surviving lane independently. Conversely,
valid XML or populated CPU/hitch tables do not establish intact log/signpost
collection, full recording completeness or catalog phase alignment. Acceptance
criteria remain open. No log-store reset, permission change or speculative
application workaround was performed.

## Historical recording handoff (superseded by the results above)

Leave the prepared RawCull and Instruments windows open; **do not quit RawCull**.
The currently prepared target is the verified running process, so this capture
covers interactions after launch. Startup still requires a separately verified
launch capture later.

1. In Instruments, select **Next Recording**, confirm RawCull (7499), then Record.
2. Wait about five seconds. In RawCull, press Command-O for **Add Catalog…**.
   Pause in the picker for about three seconds before confirming the folder:
   `/Volumes/MacMini4/Hornugle_24_jun_2025/100MSDCF`.
3. Wait for metadata and thumbnail progress to finish. Note elapsed trace times
   for picker opening, folder confirmation, first visible images and final
   progress completion. If separate metadata/thumbnail transitions are visible,
   note those too; do not guess boundaries afterward.
4. In Loupe, select the first image, move right 20 times at roughly two images
   per second, then left 20 times at the same rate.
5. Double-click the image to open zoom, wait three seconds, move right five times,
   then press Escape. Switch to Grid, scroll down two viewport lengths and back.
   Toggle a rating filter and return it to its original state. Do not alter saved
   ratings or start AI work in this baseline.
6. Wait about three seconds, then Stop in Instruments. Let analysis finish.
7. Use **File → Save As…** to save a new
   `~/Downloads/rawcull-phase6-ui-before.trace`. Preserve the existing smoke file.
   Since this document already contains smoke Run 1, the interactive capture
   should be **Run 2**; verify rather than assume the run number when exporting.
8. Report the saved path, action timestamps, visible pauses, display/refresh rate,
   power mode and any recording error. If the logging error recurs, save the trace
   anyway; it is diagnostic evidence to inspect, not automatically an accepted
   clean baseline. Do not overwrite the previous `opencatalog.trace`.

If a filter hides every file, clear it before keyboard/zoom work. A small catalog
or missing source volume is a different workload and must be reported explicitly.
The existing disk cache is left intact. A controlled cold run, cancellation/
catalog-switch checks and a repeat/after capture are later steps; this first
interactive recording is not a substitute for all phase 6 exit criteria.

## Historical setup evidence (paths may no longer exist)

- `/tmp/rawcull-phase6-ui-smoke.trace`, `-ui-smoke-record.log`,
  `-ui-smoke-export/`, `-ui-smoke-export.log`: first failed CLI trace/export.
- `/tmp/rawcull-phase6-hitches-smoke.trace`, `-hitches-smoke-record.log`:
  reduced built-in template failure.
- `/tmp/rawcull-phase6-nohangs.tracetemplate`, `-nohangs-smoke.trace`,
  `-nohangs-smoke-record.log`: native-created template and CLI failure.
- `/tmp/rawcull-phase6-gui-smoke.trace`, `-gui-smoke-export/`,
  `-gui-smoke-export.log`: verified current-process GUI failure.
- `/tmp/rawcull-phase6-*-options.json`: inspected complete recording options;
  `/tmp/rawcull-phase6-templates.txt`: installed template inventory.
- `/tmp/rawcull-phase6-smoke-analysis.py` and `.json`: small-trace-only ad hoc
  analysis of the first, older-app smoke. Not a general bounded-memory parser.
- `/tmp/rawcull-phase6-profile-build/`: prepared matching app/dSYM and manifest.

No external phase 6 archive has been created yet. Preserve these temporary
artifacts until the recording/analysis step is finished and archiving is approved.
The first export validated 16 independent tables but explicitly lacks catalog
phase alignment. The GUI export is a separate evidence set. Companion phase 5
benchmark copies provide context, not a directly comparable startup workload.
The build and documentation diff checks pass; no source tests were needed or
rerun for this documentation/setup-only step. No hitch or responsiveness
improvement is claimed.
