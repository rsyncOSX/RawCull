# Instruments Trace Analysis
Trace: `/tmp/rawcull-54058fce-fresh-load.trace`  •  27.1 (27A9275)  •  Time Profiler
Recording duration: 60.33s

## Time Profiler — 12,341 samples, 12341ms CPU time
Processes: RawCull

Top offenders:
1. `mach_msg2_trap` — 6.5% (797ms, 797 samples, main)
2. `read` — 5.0% (618ms, 618 samples, tid 0x1374a)
3. `_platform_memmove` — 3.6% (445ms, 445 samples, tid 0x13247)
4. `<deduplicated_symbol>` — 3.4% (424ms, 424 samples, main)
5. `_xzm_xzone_malloc_tiny` — 3.3% (411ms, 411 samples, main)
6. `objc_msgSend` — 3.1% (380ms, 380 samples, main)
7. `_xzm_free_main` — 2.3% (281ms, 281 samples, main)
8. `void resample_horizontal<unsigned char, int, 4, false>(resample_filter const*, unsigned i…` — 2.1% (265ms, 265 samples, tid 0x139e4)
9. `__CFStringHash` — 2.1% (258ms, 258 samples, main)
10. `void resample_vertical<int, unsigned char, 4, (AlphaStyle)1>(resample_filter const*, unsi…` — 2.0% (251ms, 251 samples, tid 0x1396d)
11. `__CF_IS_OBJC` — 1.6% (199ms, 199 samples, main)
12. `__CFStringEqual` — 1.1% (130ms, 130 samples, main)

## Hangs — 0 hangs, 0ms total, worst 0ms
Severity: <250ms=0, 250ms–1s=0, >1s=0


## Animation Hitches — skipped — Animation hitches not present in trace.

## SwiftUI — skipped — SwiftUI lane not in trace (Xcode 26+ SwiftUI template required).

## SwiftUI Cause Graph — skipped — SwiftUI causes data not present (requires SwiftUI template on a real device).
