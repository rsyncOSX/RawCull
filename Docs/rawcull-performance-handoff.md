# RawCull performance measurement handoff — 2026-10-22

Paused at the user's request to preserve remaining AI usage. No source edits or commits in this measurement phase. Checkout remains ff3230fb.

## Reproduction
- Catalog: /Volumes/MacMini4/Orrfugl_lom_osv_mai_2026/DCIM/100MSDCF
- 1,198 ARW files; 68,527,349,760 bytes (about 63.8 GiB).
- Optimized Release build from ff3230fb, with coverage disabled, built by targeting RawCull directly. The scheme enabled coverage; target-level build avoided it without repository edits.
- Profiling app: /tmp/rawcull-profile-ff3230fb/Build/Products/Release/RawCull.app
- Build UUID: BA5078E6-7850-3B99-8166-F2EBB34DF41F (arm64).
- Installed /Applications copy predates the changes and was closed. Profiling copy may still be open.
- Existing caches were not purged. Do not call this a cold-cache benchmark.

## Recorded workload
UI automation returned stale menu elements for the profiling copy. The user manually loaded the catalog and exercised the requested browsing/review sequence, then reported "done and seems normal". Exact per-action timing and source-mode coverage are unavailable. Cancellation was not confirmed; a controlled warm reload was not recorded.

## Measurements
- Process sampling: about 160 seconds, one sample per second via proc_pid_rusage.
- Physical footprint: initial 165.9 MiB, peak 1428.4 MiB, final 621.0 MiB. The decline from peak is observed; this does not establish long-term memory stability or absence of leaks.
- Process disk I/O delta: 5405.0 MiB read, 321.7 MiB written.
- Time Profiler recording: 154.73 seconds, 112,394 samples; two recorded microhangs, 367 ms and 328 ms; none recorded over one second.
- Preload call paths: 49,617 ms inclusive sampled CPU weight / 112,394 ms total, about 44.1%.
- DiskCacheManager JPEG encoding call paths: 21,412 ms inclusive sampled CPU weight, about 19.1%, substantially overlapping preload. Do not add these percentages.
- selectedFile getter: 332 ms inclusive sampled main-thread weight; getFocusPoints: 289 ms, potentially overlapping. These are lower-priority than preload.
- Both SwiftUI and Time Profiler recording commands reported a corrupt/incomplete logging data stream. CPU samples and hang records exported successfully. No usable SwiftUI cause graph or animation-hitch measurements. Keep conclusions qualified.

## Artifacts
- /tmp/rawcull-ff3230fb-workload.trace
- /tmp/rawcull-trace-analysis.json
- /tmp/rawcull-trace-analysis.md
- /tmp/rawcull-workload-metrics.jsonl
- /tmp/rawcull-profile-summary.json
- /tmp/rawcull-stacks.json
- /tmp/rawcull-paths.json
- /tmp/rawcull-user-markers.jsonl
- /tmp/rawcull-profile-build.log

These are temporary files: verify they still exist next time. Tracing and metric sampling have stopped.

## Next work — approval gates remain
Finish the measurement assessment and prioritize candidates; do not implement automatically.
The strongest bounded follow-up candidate is ownership/backpressure for preload-originated disk writes: ScanAndCreateThumbnails currently detaches each save, and DiskCacheManager.save detaches the actual write. Decode concurrency therefore does not bound outstanding writes or retained encoded data. The recording demonstrates preload/encoding CPU cost, but does NOT demonstrate a disk backlog causing foreground stalls.

A possible future plan is to await preload-originated saves within the bounded worker group, releasing each thumbnail gate before awaiting the disk save so visible images are not delayed. Preserve JPEG size/quality, cache identity, UI-driven cache admission, security-scope lifetime, and cancellation. Inspect further and present exact files, responsibilities, tests, risks, and completion criteria for explicit implementation approval first. Interactive RequestThumbnail save behavior would be excluded unless separately approved.

Other candidates remain: first-content publication waits for artifact hydration; visible misses follow preload discovery order; native cancelled reads may keep running; comparison presentation rebuilds a full-catalog lookup; session image memory lies outside thumbnail-cache limits. Their practical cost was not isolated in this recording.

Before proceeding next session, check remaining usage. The user reported 18% remaining and asked to stop before exhaustion. No additional work is authorized by this handoff itself beyond the existing measurement scope.

## Follow-up — 2026-10-23

The user approved implementing bounded preload saves. The working-tree change is based on bfd8fa62 (the only change since ff3230fb was this handoff).

- `ScanAndCreateThumbnails.processSingleFile` returns an optional encoded save payload. Each task-group worker releases its file's preload gate, then awaits the save before returning its worker slot. Pending preload writes and encoded payloads are therefore bounded by the existing per-group preload limit.
- Cancellation is checked after waiting for a worker slot and before encoding/saving. The catalog-access grant remains retained until the worker group finishes. An atomic disk write that has already begun is still awaited; it is not interrupted mid-write.
- `DiskCacheManager.save` already awaits its detached atomic writer, so no shared cache change was necessary. Interactive `RequestThumbnail` saves, JPEG quality/size, cache identity, and cache admission remain unchanged.
- A narrow injected saver supports controlled stalled-write tests. Both normal completion and cancellation verify the worker bound, gate release before save completion, no scan admission to preview RAM, and save ownership through preload completion. Normal completion also verifies disk-backed warm reload without further decoding or saving. Cancellation verifies that waiting saves do not create disk entries after cancellation and later files are not decoded.
- Focused Debug validation: 36 tests in 8 suites passed, including disk-cache/orientation regressions, scan admission, preload gates, interactive requests, image-loading integration, and the new parameterized ownership test. Log: `/tmp/rawcull-preload-final-tests.log`.
- The test host emitted `MDB_MAP_FULL` startup messages; all selected tests passed. These messages were not investigated as part of the preload change.

A fresh real-catalog performance recording is still needed before claiming improved browsing latency or memory use. The controlled warm-reload/cancellation tests use generated catalog fixtures, not the 1,198-file catalog above. The original recording's limitations still apply.

Release validation also passed: direct `RawCull` target build, Release configuration, coverage disabled. App: `/tmp/rawcull-preload-release/Products/Release/RawCull.app`; build log: `/tmp/rawcull-preload-release.log`. This is a build check, not a new workload measurement. The final focused test rerun after moving the new suite into `RawCullTests/ThumbnailPreloadSaveOwnershipTests.swift` passed all 36 tests. SwiftLint reported no source findings in the changed Swift files (only existing analyzer-rule configuration warnings). No commit was created.

## Real-catalog remeasurement — 2026-10-23

Completed at the user's request using the same 1,198-file catalog and Release build (arm64 UUID `60782AD2-A618-385A-A5BA-3BD3A30B07A9`), source checkout `54058fce`. Full report and durable measurements: [Performance/2026-10-23/report.md](Performance/2026-10-23/report.md).

- Longer browsing/source-switch/reload session: about 285 seconds; footprint initial 531.2 MiB, peak 4,836.9 MiB during full-size source exercise, final 692.9 MiB; read/write deltas 14,782.4/261.3 MiB. Different workload from yesterday; no direct memory/speed comparison is justified.
- Warm reload: still scanning at 5.586 seconds, 1,198 files and preview observed by 8.358 seconds (automation observation bounds). Early-load abort returned to an empty state; subsequent recovery loaded all files. Cancellation during thumbnail writes remains unverified.
- Separate fresh-process preload: footprint peak/final about 990 MiB, read delta 5,131.2 MiB, zero process disk writes. Recoverable 60.33-second CPU trace: 12,341 symbolicated samples, preload inclusive weight 3,072 ms (24.9%), downscaling 2,803 ms (overlapping), no sampled JPEG encoding, no recorded hangs. This cache-preserved workload did not stress the disk-write backlog and cannot establish the bounded-save performance benefit.
- Primary SwiftUI trace failed to finalize and was unusable. Both shorter Time Profiler traces reported corrupt/incomplete logging streams but exported CPU and hang tables. No reliable SwiftUI cause graph or hitch metrics. Keep conclusions qualified.
- Intermittent zero-file states occurred during same-folder reopening, with retry recovery; restored picker locations sometimes required selecting the catalog from its parent to enable Open. Cause and regression status are unestablished. Reproduce separately; do not silently attribute this to the preload change.

No further source changes or cache purge. Recording and metric sampling stopped; profiling app remains open with catalog loaded. Raw traces remain under `/tmp/rawcull-54058fce-*`; summaries and resource samples are saved in Docs. Next candidates are the reopening correctness issue and cached-preload grid downscaling, subject to separate investigation/implementation scope.
