# Instruments Trace Analysis
Trace: `/tmp/rawcull-54058fce-timeprofiler.trace`  •  27.1 (27A9275)  •  Time Profiler
Recording duration: 45.33s

## Time Profiler — 3,127 samples, 3127ms CPU time
Processes: RawCull

Top offenders:
1. `read` — 4.9% (153ms, 153 samples, tid 0x12803)
2. `objc_msgSend` — 4.2% (131ms, 131 samples, main)
3. `<deduplicated_symbol>` — 3.8% (120ms, 120 samples, main)
4. `_xzm_xzone_malloc_tiny` — 3.2% (101ms, 101 samples, main)
5. `__CFStringHash` — 2.5% (78ms, 78 samples, main)
6. `_xzm_free_main` — 2.4% (75ms, 75 samples, main)
7. `__CF_IS_OBJC` — 1.6% (49ms, 49 samples, main)
8. `__CFStringEqual` — 1.5% (48ms, 48 samples, main)
9. `_platform_memmove` — 1.4% (44ms, 44 samples, main)
10. `mach_msg2_trap` — 1.3% (42ms, 42 samples, main)
11. `start_wqthread` — 1.2% (37ms, 37 samples, tid 0x120ee)
12. `AG::Graph::UpdateStack::update()` — 1.1% (33ms, 33 samples, main)

## Hangs — 0 hangs, 0ms total, worst 0ms
Severity: <250ms=0, 250ms–1s=0, >1s=0


## Animation Hitches — skipped — Animation hitches not present in trace.

## SwiftUI — skipped — SwiftUI lane not in trace (Xcode 26+ SwiftUI template required).

## SwiftUI Cause Graph — skipped — SwiftUI causes data not present (requires SwiftUI template on a real device).
