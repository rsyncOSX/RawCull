# Phase 6 — UI hitches (in progress)

24 October 2026. **Not complete.** Recording setup and failure investigation are
complete for this step; an annotated interactive capture is pending. No
application optimization has been made or validated. Phase 7 has not started.

## Prepared build and current recording state

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

## Recording failure investigation

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

## Next user capture — interactive diagnostic baseline

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

## Evidence retained locally

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
