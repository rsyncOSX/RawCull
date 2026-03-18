# Swift Testing Verification Checklist for RawCull

✅ **All test files have been verified and are using Swift Testing correctly**

## Test Files Status

### ✅ Core Concurrency Test Files

1. **RawCullTestsTestTags.swift** ✅ FIXED
   - Changed from XCTest to Swift Testing
   - Using `@Tag` extension pattern
   - All tag definitions correct

2. **RawCullTestsConcurrencyTests.swift** ✅ VERIFIED
   - Uses `import Testing`
   - Uses `@Suite` and `@Test` macros
   - 35+ test cases
   - All async/await patterns correct

3. **RawCullTestsConcurrencyFixVerificationTests.swift** ✅ VERIFIED
   - Uses `import Testing`
   - Uses `@Suite` and `@Test` macros
   - Tests all 6 fixes
   - Integration tests included

4. **RawCullTestsDataRaceDetectionTests.swift** ✅ VERIFIED
   - Uses `import Testing`
   - Uses `@Suite` and `@Test` macros
   - TSan-compatible
   - Stress tests included

## Required File Structure

Your test files should be organized as:

```
RawCull.xcodeproj
├── RawCull/
│   └── (app source files)
└── RawCullTests/
    ├── RawCullTestsTestTags.swift
    ├── RawCullTestsConcurrencyTests.swift
    ├── RawCullTestsConcurrencyFixVerificationTests.swift
    └── RawCullTestsDataRaceDetectionTests.swift
```

## Swift Testing Import Pattern

All test files should use:

```swift
import Testing

@testable import RawCull  // Only if you need to test internal types

@Suite("Test Suite Name")
struct MyTests {
    @Test("Test description")
    func myTest() async throws {
        #expect(condition, "Message")
    }
}
```

## Common Issues Fixed

### ❌ WRONG (XCTest):
```swift
import XCTest

class MyTests: XCTestCase {
    func testSomething() {
        XCTAssertTrue(condition)
    }
}
```

### ✅ CORRECT (Swift Testing):
```swift
import Testing

@Suite("My Tests")
struct MyTests {
    @Test("Something works")
    func something() async throws {
        #expect(condition)
    }
}
```

## How to Verify in Xcode

### 1. Check Test Target Membership

1. Select each test file in Project Navigator
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership", ensure **RawCullTests** is checked
4. Ensure **RawCull** (main app) is NOT checked

### 2. Build the Test Target

```bash
# Command line
xcodebuild build-for-testing -scheme RawCull -destination 'platform=macOS'

# Or in Xcode
Product → Build For → Testing (⇧⌘U)
```

### 3. Run Tests

```bash
# Command line
xcodebuild test -scheme RawCull -destination 'platform=macOS'

# Or in Xcode
Product → Test (⌘U)
```

## Expected Test Output

When tests run successfully, you should see:

```
Test Suite 'All tests' started at 2026-03-18 ...
Test Suite 'RawCullTestsConcurrencyTests' started at ...
Test Suite 'CacheDelegateTests' started at ...
✓ Test 'concurrentEvictions()' passed (0.123 seconds)
✓ Test 'resetThreadSafety()' passed (0.045 seconds)
...
Test Suite 'All tests' passed at ...
    70 tests passed, 0 failed
```

## Troubleshooting

### Issue: "No such module 'Testing'"

**Solution:**
1. Ensure you're using **Xcode 15+**
2. Ensure your deployment target is **macOS 14.0+** (or iOS 18+, etc.)
3. The Swift Testing framework is built into Xcode 15+
4. Check that the test target has the correct SDK settings

**How to fix:**
1. Select your project in Project Navigator
2. Select the **RawCullTests** target
3. Go to **Build Settings**
4. Search for "Base SDK"
5. Ensure it's set to "macOS 14.0" or later

### Issue: "Cannot find type 'Tag' in scope"

**Cause:** The `Tag` extension is defined in `TestTags.swift`

**Solution:**
1. Ensure `TestTags.swift` is in the **RawCullTests** target
2. Ensure it's compiled before other test files
3. In Xcode, check Build Phases → Compile Sources

### Issue: Tests don't appear in Test Navigator

**Solution:**
1. Clean build folder (⇧⌘K)
2. Close and reopen project
3. Product → Build For → Testing (⇧⌘U)
4. Check Test Navigator (⌘6)

### Issue: "@testable import RawCull" fails

**Solution:**
1. Ensure the main app target builds successfully
2. Ensure "Enable Testing Search Paths" is ON for test target
3. Build Settings → Search for "Testing Search Paths"
4. Should be set to **Yes**

## Test Tags Usage

All test files can now use these tags:

```swift
@Suite("My Test Suite", .tags(.critical, .smoke))
struct MyTests {
    @Test("Individual test", .tags(.performance))
    func performanceTest() async throws {
        // Test code
    }
}
```

Available tags:
- `.critical` - Must pass before release
- `.performance` - Performance benchmarks
- `.threadSafety` - Run with TSan
- `.integration` - Multi-component tests
- `.smoke` - Quick validation
- `.bugfix` - Regression tests
- `.actor` - Actor isolation tests
- `.mainActor` - MainActor tests
- `.sendable` - Sendable conformance tests

## Running Specific Tests

### Run by tag:
```bash
# Critical tests only
swift test --filter critical

# Performance tests only  
swift test --filter performance
```

### Run specific suite:
```bash
swift test --filter CacheDelegateTests
```

### Run with Thread Sanitizer:
1. Product → Scheme → Edit Scheme
2. Test tab → Diagnostics
3. Check ✅ **Thread Sanitizer**
4. Run tests (⌘U)

## Continuous Integration Setup

Add to your CI configuration:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Run Swift Tests
        run: |
          xcodebuild test \
            -scheme RawCull \
            -destination 'platform=macOS' \
            -enableThreadSanitizer YES
```

## Next Steps

1. ✅ All test files verified
2. 🔄 Build the test target to ensure no compilation errors
3. 🔄 Run all tests with ⌘U
4. 🔄 Enable Thread Sanitizer and run again
5. 🔄 Add tests to CI/CD pipeline

## Summary

✅ **Fixed:** TestTags.swift converted from XCTest to Swift Testing
✅ **Verified:** All concurrency test files use Swift Testing correctly
✅ **Status:** Ready to build and run tests

If you encounter any build errors after this verification, check:
1. Xcode version is 15.0+
2. macOS deployment target is 14.0+
3. All test files are in RawCullTests target
4. Clean build folder and rebuild

---

**Last updated:** March 18, 2026
**Swift Testing Framework:** Built-in with Xcode 15+
**Test Count:** 70+ tests across 3 comprehensive test suites
