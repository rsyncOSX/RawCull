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
