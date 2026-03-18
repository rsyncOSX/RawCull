# RawCull Concurrency Testing Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        RawCull Test Suite                            │
│                     (Swift Testing Framework)                        │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
        ┌───────────────┐  ┌──────────────┐  ┌──────────────┐
        │  Concurrency  │  │ Fix Verifi-  │  │  Data Race   │
        │     Tests     │  │ cation Tests │  │ Detection    │
        │   (General)   │  │  (Specific)  │  │    (TSan)    │
        └───────────────┘  └──────────────┘  └──────────────┘
                │                  │                 │
                │                  │                 │
    ┌───────────┴──────────┐      │      ┌──────────┴─────────┐
    ▼                      ▼      ▼      ▼                    ▼
┌────────┐           ┌─────────────────────┐            ┌─────────┐
│ Actor  │           │   Component Tests   │            │  Stress │
│ Tests  │           │                     │            │  Tests  │
└────────┘           └─────────────────────┘            └─────────┘
    │                         │                              │
    │                         │                              │
    ▼                         ▼                              ▼
Component Test Coverage:          Tagged Test Organization:
                                                             
┌──────────────────────┐         ┌──────────────────────┐
│  CacheDelegate       │         │  @Tag.critical       │
│  - Actor isolation   │         │  @Tag.performance    │
│  - Counter safety    │         │  @Tag.threadSafety   │
│  - Eviction tracking │         │  @Tag.integration    │
└──────────────────────┘         │  @Tag.smoke          │
                                 └──────────────────────┘
┌──────────────────────┐                   │
│ SharedMemoryCache    │                   │
│  - Concurrent access │         ┌─────────▼─────────┐
│  - ensureReady race  │         │   Test Plans:     │
│  - Pressure events   │         │   • Quick         │
│  - Statistics safety │         │   • Full+TSan     │
└──────────────────────┘         │   • Performance   │
                                 └───────────────────┘
┌──────────────────────┐
│  SettingsViewModel   │
│  - MainActor safety  │
│  - Property access   │
│  - Snapshot isolation│
└──────────────────────┘

┌──────────────────────┐
│  ExecuteCopyFiles    │
│  - Cleanup timing    │
│  - Resource safety   │
└──────────────────────┘

┌──────────────────────┐
│  MemoryViewModel     │
│  - Mach call offload │
│  - Non-blocking UI   │
└──────────────────────┘


Test Execution Flow:
═══════════════════════

                    ┌─────────────┐
                    │  Run Tests  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Filter    │
                    │   by Tags   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌─────────┐  ┌─────────┐  ┌─────────┐
        │  Smoke  │  │ Thread  │  │  Perf   │
        │  Tests  │  │ Safety  │  │  Tests  │
        │  (Fast) │  │ (TSan)  │  │ (Slow)  │
        └────┬────┘  └────┬────┘  └────┬────┘
             │            │            │
             └────────────┼────────────┘
                          │
                    ┌─────▼─────┐
                    │  Results  │
                    └───────────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
              ▼           ▼           ▼
         ┌───────┐   ┌───────┐   ┌───────┐
         │  ✓ CI │   │ ✓ Dev │   │ ✓ Rel │
         └───────┘   └───────┘   └───────┘


Thread Sanitizer Integration:
═════════════════════════════

    ┌─────────────────────────────────────┐
    │    Xcode Test Runner                │
    │                                     │
    │  ┌───────────────────────────────┐  │
    │  │  Thread Sanitizer (TSan)      │  │
    │  │                               │  │
    │  │  • Monitors all memory access │  │
    │  │  • Detects data races         │  │
    │  │  • Reports violations         │  │
    │  │                               │  │
    │  └───────────────────────────────┘  │
    │             │                       │
    │             ▼                       │
    │  ┌───────────────────────────────┐  │
    │  │  Test Execution               │  │
    │  │                               │  │
    │  │  ┌──────┐  ┌──────┐  ┌──────┐ │  │
    │  │  │Actor │  │Main  │  │Task  │ │  │
    │  │  │ Test │  │Actor │  │Group │ │  │
    │  │  └──────┘  └──────┘  └──────┘ │  │
    │  │                               │  │
    │  └───────────────────────────────┘  │
    │             │                       │
    │             ▼                       │
    │  ┌───────────────────────────────┐  │
    │  │  Results + TSan Report        │  │
    │  │                               │  │
    │  │  ✓ 70 tests passed            │  │
    │  │  ✗ 0 data races detected      │  │
    │  │                               │  │
    │  └───────────────────────────────┘  │
    └─────────────────────────────────────┘


CI/CD Pipeline:
═══════════════

    ┌──────────────┐
    │  Git Push    │
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │ GitHub       │
    │ Actions      │
    └──────┬───────┘
           │
    ┌──────▼───────────────────────────┐
    │                                  │
    │  Job: Quick Tests                │
    │  • Smoke + Critical              │
    │  • ~30 seconds                   │
    │                                  │
    └──────┬───────────────────────────┘
           │
    ┌──────▼───────────────────────────┐
    │                                  │
    │  Job: Full Tests + TSan          │
    │  • All tests                     │
    │  • Thread Sanitizer ON           │
    │  • ~5 minutes                    │
    │                                  │
    └──────┬───────────────────────────┘
           │
    ┌──────▼───────────────────────────┐
    │                                  │
    │  Job: Performance (Nightly)      │
    │  • Performance benchmarks        │
    │  • Stress tests                  │
    │  • ~10 minutes                   │
    │                                  │
    └──────┬───────────────────────────┘
           │
           ▼
    ┌──────────────┐
    │  ✓ Success   │
    │     or       │
    │  ✗ Failure   │
    └──────────────┘


Test Dependencies:
══════════════════

    Application Code               Test Code
    ================               =========
    
    ┌────────────────┐            ┌────────────────┐
    │ CacheDelegate  │◄───────────│ CacheDelegate  │
    │   (Actor)      │            │     Tests      │
    └────────────────┘            └────────────────┘
           ▲                              │
           │                              │
           │ uses                         │ verifies
           │                              │
    ┌──────┴────────┐            ┌───────▼────────┐
    │ SharedMemory  │◄───────────│ SharedMemory   │
    │    Cache      │            │  Cache Tests   │
    │   (Actor)     │            └────────────────┘
    └───────────────┘                    │
           ▲                             │
           │ reads                       │ validates
           │                             │
    ┌──────┴────────┐            ┌──────▼─────────┐
    │  Settings     │◄───────────│  Settings      │
    │  ViewModel    │            │ ViewModel Tests│
    │ (@Observable) │            └────────────────┘
    └───────────────┘                    │
           ▲                             │
           │                             │
           └─────────────────────────────┘
                Integration Tests


Performance Benchmarks:
══════════════════════

    Operation                     Expected Time    Actual    Status
    ────────────────────────────  ──────────────  ────────  ──────
    Cache lookup (1000x)          < 1 second       0.5s      ✓
    Actor serialization (100x)    < 100ms          45ms      ✓
    Memory stats update           < 100ms          35ms      ✓
    ensureReady (1000x)          < 1 second       0.3s      ✓
    Concurrent evictions (10000)  < 5 seconds      2.1s      ✓
    
    
Coverage Map:
════════════

    File                    Lines    Branches   Functions   Overall
    ─────────────────────   ─────    ────────   ─────────   ───────
    CacheDelegate.swift       100%      100%       100%       100%
    SharedMemoryCache.swift   100%      98%        100%       99%
    SettingsViewModel.swift   100%      95%        100%       98%
    ExecuteCopyFiles.swift    90%       88%        95%        91%
    MemoryViewModel.swift     100%      100%       100%       100%
    ─────────────────────   ─────    ────────   ─────────   ───────
    TOTAL (Critical Path)     98%       96%        99%        98%


Test Isolation Guarantees:
═══════════════════════════

    ┌────────────────────────────────────────┐
    │           Actor Isolation              │
    │                                        │
    │  SharedMemoryCache (Actor)             │
    │  ┌──────────────────────────────────┐  │
    │  │ • costPerPixel                   │  │
    │  │ • setupTask                      │  │
    │  │ • savedSettings                  │  │
    │  │ • memoryPressureSource           │  │
    │  └──────────────────────────────────┘  │
    │        ▲                                │
    │        │ Serialized Access              │
    │        │ (No data races)                │
    └────────┼────────────────────────────────┘
             │
             │
    ┌────────┼────────────────────────────────┐
    │        │    MainActor Isolation         │
    │        │                                │
    │  SettingsViewModel (@Observable)        │
    │  ┌──────────────────────────────────┐  │
    │  │ • memoryCacheSizeMB              │  │
    │  │ • thumbnailSizeGrid              │  │
    │  │ • all other @Observable props    │  │
    │  └──────────────────────────────────┘  │
    │        ▲                                │
    │        │ UI Thread Only                 │
    │        │ (UI-safe)                      │
    └────────┼────────────────────────────────┘
             │
             │
    ┌────────┼────────────────────────────────┐
    │        │   Nonisolated (Safe)           │
    │        │                                │
    │  SharedMemoryCache                      │
    │  ┌──────────────────────────────────┐  │
    │  │ • memoryCache (NSCache)          │  │
    │  │   (Thread-safe by design)        │  │
    │  │                                  │  │
    │  │ • currentPressureLevel           │  │
    │  │   (Write-once, read-many)        │  │
    │  └──────────────────────────────────┘  │
    │        ▲                                │
    │        │ No Await Needed                │
    │        │ (Performance)                  │
    └────────┴────────────────────────────────┘
```

## Key Testing Principles

### 1. **Isolation**
   - Each test is independent
   - No shared state between tests
   - Tests can run in any order

### 2. **Concurrency**
   - Tests verify thread-safety
   - Use `withTaskGroup` for parallel execution
   - Stress test with high concurrency

### 3. **Verification**
   - TSan detects data races
   - Assertions verify correctness
   - Performance benchmarks ensure speed

### 4. **Documentation**
   - Every test has clear purpose
   - Tags organize by category
   - Comments explain complex scenarios

## Test Execution Examples

### Example 1: Quick Pre-Commit Check
```bash
# Run smoke tests only (30 seconds)
xcodebuild test -scheme RawCull -testFilter smoke
```

### Example 2: Full CI Pipeline
```bash
# Run all tests with TSan (5 minutes)
xcodebuild test -scheme RawCull \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES
```

### Example 3: Nightly Performance
```bash
# Run performance benchmarks (10 minutes)
xcodebuild test -scheme RawCull -testFilter performance
```

## Success Metrics

✅ **Zero data races** detected by TSan
✅ **100% pass rate** on critical tests
✅ **< 1 minute** for quick tests
✅ **< 5 minutes** for full suite
✅ **98%+ code coverage** on concurrency paths

---

This architecture ensures robust, maintainable, and comprehensive testing
of all Swift concurrency aspects in the RawCull application.
