# Swift Concurrency Testing Guide for RawCull

This document explains how to run and interpret the concurrency tests for the RawCull project.

## Overview

We've created three comprehensive test suites to verify Swift concurrency safety:

1. **ConcurrencyTests.swift** - General concurrency safety tests
2. **ConcurrencyFixVerificationTests.swift** - Tests specifically verifying the 6 critical fixes
3. **DataRaceDetectionTests.swift** - TSan-compatible tests for detecting data races

## Running the Tests

### Standard Test Run

```bash
# Run all tests
⌘ + U (in Xcode)

# Or via command line
xcodebuild test -scheme RawCull -destination 'platform=macOS'
```

### Running with Thread Sanitizer (Recommended)

Thread Sanitizer (TSan) detects data races at runtime:

1. Open Xcode
2. Go to **Product → Scheme → Edit Scheme**
3. Select **Test** in the left sidebar
4. Go to the **Diagnostics** tab
5. Check **Thread Sanitizer**
6. Click **Close**
7. Run tests with **⌘ + U**

⚠️ **Note:** Tests will run slower with TSan enabled, but this is the most reliable way to detect concurrency bugs.

### Running Specific Test Suites

```swift
// In Xcode's Test Navigator (⌘ + 6):
// - Click the play button next to specific suites
// - Right-click → "Run Selected Tests"

// Via command line with filtering:
xcodebuild test -scheme RawCull \
  -only-testing:RawCullTests/ConcurrencyTests
```

## Test Organization

### 1. ConcurrencyTests.swift

#### Test Suites:
- **CacheDelegate Concurrency** - Tests actor-based eviction counting
- **SharedMemoryCache Concurrency** - Tests actor isolation and cache thread safety
- **SettingsViewModel Concurrency** - Tests MainActor isolation and property access
- **ExecuteCopyFiles Concurrency** - Tests cleanup timing and resource management
- **MemoryViewModel Concurrency** - Tests non-blocking updates
- **Actor Isolation Verification** - Tests actor guarantees under load
- **Sendable Type Safety** - Tests type safety across isolation boundaries
- **Race Condition Tests** - Stress tests to detect races
- **Concurrency Performance** - Performance benchmarks

#### Key Tests:
```swift
@Test("CacheDelegate handles concurrent evictions safely")
@Test("SharedMemoryCache handles concurrent access safely")
@Test("SettingsViewModel handles concurrent reads safely")
@Test("No race in cache delegate eviction counting")
```

### 2. ConcurrencyFixVerificationTests.swift

Tests each of the 6 critical fixes:

#### Fix #1: CacheDelegate Actor-based Counter
- Replaced `NSLock` with actor for thread-safe counting
- Tests: `evictionCounterNoRaces()`, `concurrentResetAndIncrement()`

#### Fix #2: ExecuteCopyFiles Cleanup Timing
- Ensures cleanup happens after completion handler
- Tests: `cleanupOrderingCorrect()`, `noAccessAfterCleanup()`

#### Fix #3: SharedMemoryCache DispatchSource Handler
- Removed unnecessary `Task.detached`
- Tests: `memoryPressureHandlerEfficiency()`, `weakCapturePatternCorrect()`

#### Fix #4: SettingsViewModel MainActor Isolation
- Wrapped property access in `MainActor.run`
- Tests: `asyncGetSettingsIsolation()`, `concurrentReadsNoRaces()`

#### Fix #5: SharedMemoryCache ensureReady Race
- Fixed task storage timing
- Tests: `noDuplicateInitialization()`, `rapidConcurrentCalls()`

#### Fix #6: MemoryViewModel MainActor Offloading
- Moved heavy mach calls off MainActor
- Tests: `machCallsOffloaded()`, `updatePerformance()`

#### Integration Test:
```swift
@Test("All concurrency fixes work harmoniously under load")
@Test("No deadlocks under maximum concurrent load")
```

### 3. DataRaceDetectionTests.swift

TSan-compatible tests designed to catch data races:

#### Categories:
- **Shared State Access** - Tests `nonisolated(unsafe)` access patterns
- **Actor State Protection** - Verifies actor serialization
- **Observable Property Access** - Tests MainActor protection
- **Weak Reference Safety** - Tests weak capture patterns
- **Sendable Conformance** - Verifies type safety
- **CacheDelegate Data Race** - Tests atomic operations
- **Memory Pressure Handler** - Tests concurrent reads/writes
- **Task Cancellation Safety** - Tests cleanup under cancellation
- **Stress Tests** - Maximum load testing

## Understanding Test Results

### ✅ Success Indicators

```
Test Case 'ConcurrencyTests.concurrentEvictions()' passed (0.123 seconds)
```

### ❌ Common Failures

#### Data Race Detected (TSan):
```
WARNING: ThreadSanitizer: data race
  Write of size 8 at 0x7b0400000000
  Previous read of size 8 at 0x7b0400000000
```
**Action:** Review the actor isolation or MainActor requirements for the flagged code.

#### Timeout:
```
Test Case 'ConcurrencyTests.noDeadlocks()' exceeded time limit of 5 seconds
```
**Action:** Possible deadlock. Check for actor reentrancy issues or circular waits.

#### Assertion Failure:
```
#expect(count >= 0) failed: Count should never be negative
```
**Action:** Race condition in counter logic. Verify actor isolation.

## Performance Benchmarks

### Expected Performance:
- **Cache lookup (1000 concurrent):** < 1 second
- **Actor serialization (100 calls):** < 100ms
- **Memory stats update:** < 100ms
- **ensureReady (1000 concurrent):** < 1 second

### Performance Test Tags:
```swift
@Test("Cache lookup performance", .tags(.performance))
```

Run only performance tests:
```bash
# Filter by tag in test plan or use command line
```

## Debugging Tips

### 1. Enable Detailed Logging

In your scheme's test environment variables:
```
OS_ACTIVITY_MODE = default
```

### 2. Run Tests in Isolation

If a test is flaky:
```swift
@Test("Flaky test", .timeLimit(.minutes(1)))
func flakyTest() async throws {
    // Add detailed logging
    print("Step 1...")
}
```

### 3. Use Xcode's Memory Graph Debugger

1. Pause test execution
2. Click the memory graph icon in the debug bar
3. Look for unexpected reference cycles

### 4. Analyze Thread Sanitizer Reports

When TSan reports an issue:
1. Note the memory address
2. Look at both stacks (Write and Previous read)
3. Identify the shared state
4. Add actor isolation or MainActor annotation

## Continuous Integration

### GitHub Actions Example:

```yaml
name: Swift Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run tests with TSan
        run: |
          xcodebuild test \
            -scheme RawCull \
            -destination 'platform=macOS' \
            -enableThreadSanitizer YES
```

## Test Coverage Goals

- **Critical paths:** 100% coverage
- **Concurrency code:** 100% coverage with TSan
- **Actor methods:** 100% coverage
- **MainActor methods:** 100% coverage

## Best Practices

### 1. Always Run TSan Before Release
```bash
# Pre-release checklist:
# ☐ All tests pass
# ☐ TSan enabled tests pass
# ☐ Performance tests meet benchmarks
# ☐ No memory leaks in Instruments
```

### 2. Add Tests for New Concurrency Code

When adding new actors or async code:
```swift
@Suite("NewFeature Concurrency")
struct NewFeatureTests {
    @Test("Feature is thread-safe")
    func threadSafety() async throws {
        // Test concurrent access
    }
}
```

### 3. Document Intentional Race Conditions

If you have a benign race (rare):
```swift
// This is a benign race - reading stale data is acceptable
nonisolated(unsafe) var cacheHint: Int = 0
```

## Troubleshooting

### Problem: Tests fail only in CI
**Solution:** CI may have different timing. Add longer timeouts or use `.timeLimit()`.

### Problem: TSan reports false positives
**Solution:** Use `nonisolated(unsafe)` with clear documentation, but verify it's truly safe.

### Problem: Tests are too slow
**Solution:** 
1. Reduce iteration counts for CI
2. Use `.tags()` to separate quick tests from stress tests
3. Run stress tests nightly, not on every commit

### Problem: Flaky test failures
**Solution:**
1. Add more generous timeouts
2. Use `Task.sleep(for:)` with longer durations
3. Add synchronization points with continuations

## Resources

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Swift Testing Framework](https://github.com/apple/swift-testing)
- [Thread Sanitizer Guide](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)
- [Actor Isolation Best Practices](https://developer.apple.com/videos/play/wwdc2021/10133/)

## Questions?

If tests are failing unexpectedly:
1. Check this README first
2. Review the specific test's documentation comments
3. Run with TSan to identify the root cause
4. Add detailed logging to understand execution order

---

Last updated: March 18, 2026
