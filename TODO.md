# RawCull - Comprehensive TODO List

**Last Updated:** February 16, 2026  
**Overall Quality Score:** 9.9/10  
**Status:** Production Ready with Enhancement Opportunities

---

## 📋 Priority Levels

- 🔴 **Critical** - Security, stability, or major functionality issues
- 🟠 **High** - Important improvements affecting user experience or code quality
- 🟡 **Medium** - Valuable enhancements and technical debt reduction
- 🟢 **Low** - Nice-to-have improvements with minimal impact

---

## 🔴 CRITICAL ISSUES

### None Currently Identified
The application has been validated on 1100+ files with excellent performance and no critical issues detected.

---

## 🟠 HIGH PRIORITY

### Documentation & Discoverability

- [ ] **Add inline documentation to complex algorithms**
  - Location: [ExtractSonyThumbnail.swift](RawCull/Actors/ExtractSonyThumbnail.swift)
  - Issue: Sony thumbnail extraction logic lacks docstring comments
  - Impact: Developers need to reverse-engineer the binary format parsing
  - Effort: 1-2 hours

- [ ] **Document memory pressure handling strategy**
  - Location: [SharedMemoryCache.swift](RawCull/Actors/SharedMemoryCache.swift) lines 190-215
  - Issue: Memory pressure thresholds (60%, 50MB min) need explanation
  - Impact: Hard to understand pressure response rates without context
  - Effort: 1 hour

- [ ] **Create architecture decision records (ADRs)**
  - Issue: Why use actors vs. other concurrency models not documented
  - Impact: Future maintainers won't understand design rationale
  - Effort: 3-4 hours
  - Scope:
    - Why SharedMemoryCache uses nonisolated(unsafe) NSCache
    - Why separate ScanAndCreateThumbnails and SharedRequestThumbnail actors
    - Cache eviction policy rationale

### Testing Gaps

- [ ] **Add ViewModel unit tests**
  - Location: [RawCullTests](RawCullTests/)
  - Issue: ViewModels not covered by unit tests (noted in QUALITY.md 7.5/10)
  - Impact: Logic errors in ViewModel layer could go undetected
  - Test Cases Needed:
    - handleSourceChange() with empty and non-empty file lists
    - updateRating() with invalid sources
    - Search and sort filtering logic
    - Culling manager integration
  - Effort: 4-6 hours

- [ ] **Add JSON serialization error scenarios**
  - Location: [WriteSavedFilesJSON.swift](RawCull/Model/JSON/WriteSavedFilesJSON.swift)
  - Issue: Error handling paths for corrupted JSON not tested
  - Impact: Untested error paths could fail in production
  - Test Cases Needed:
    - Invalid JSON structure recovery
    - Permission denied scenarios
    - Disk space exhaustion handling
  - Effort: 2-3 hours

### Code Quality Improvements

- [ ] **Refactor memory pressure monitoring start/stop**
  - Location: [SharedMemoryCache.swift](RawCull/Actors/SharedMemoryCache.swift)
  - Issue: `startMemoryPressureMonitoring()` never called, source not properly cleaned up
  - Risk: Potential resource leak of DispatchSourceMemoryPressure
  - Fix: Implement cleanup in deinit or explicit stop method
  - Effort: 1-2 hours

- [ ] **Unify naming conventions across module**
  - Issues Found:
    - `fileHandler` vs `fileHandlers` (inconsistent plural/singular)
    - `savedsettings` vs `savedSettings` (camelCase inconsistency)
    - `memorypressurewarning` vs `memory_pressure_warning`
  - Impact: Makes code harder to search and understand intent
  - Files Affected: [RawCullViewModel.swift](RawCull/Model/ViewModels/RawCullViewModel.swift), [SharedMemoryCache.swift](RawCull/Actors/SharedMemoryCache.swift), [ScanAndCreateThumbnails.swift](RawCull/Actors/ScanAndCreateThumbnails.swift)
  - Effort: 2-3 hours

---

## 🟡 MEDIUM PRIORITY

### Feature Enhancements

- [ ] **Implement configurable disk cache size limits**
  - Location: [DiskCacheManager.swift](RawCull/Actors/DiskCacheManager.swift)
  - Current State: Age-based pruning only (no hard size limit)
  - Issue: Disk usage can grow unbounded on systems with many photos
  - Solution: Add configuration option for maximum cache size
  - Effort: 3-4 hours

- [ ] **Add cache statistics UI view**
  - Location: [Views/Settings/](RawCull/Views/Settings/)
  - Current State: Statistics available via API but not displayed to user
  - Enhancement: Dashboard showing:
    - Hit rate percentage
    - Memory cache utilization
    - Disk cache utilization
    - Eviction counts
  - Effort: 3-4 hours

- [ ] **Implement batch file operations**
  - Issue: Users can only tag/rate one file at a time
  - Enhancements:
    - Batch rate selected files
    - Batch tag selected files
    - Bulk export functionality
  - Files Affected: [ObservableCullingManager.swift](RawCull/Model/Culling/ObservableCullingManager.swift), Views layer
  - Effort: 5-6 hours

- [ ] **Add advanced filtering capabilities**
  - Current: Search by filename only
  - Enhancements:
    - Filter by rating range
    - Filter by file size
    - Filter by modification date
  - Location: [RawCullViewModel.swift](RawCull/Model/ViewModels/RawCullViewModel.swift)
  - Effort: 4-5 hours

### Performance Optimizations

- [ ] **Optimize disk cache lookup performance**
  - Location: [DiskCacheManager.swift](RawCull/Actors/DiskCacheManager.swift)
  - Issue: Sequential directory scan for age-based pruning could be slow with thousands of files
  - Solution: Implement file metadata index (SQLite or similar)
  - Effort: 6-8 hours

- [ ] **Implement lazy thumbnail loading in grid**
  - Location: [PhotoGridView.swift](RawCull/Views/PhotoGridView.swift)
  - Issue: All thumbnails loaded concurrently on data source change
  - Solution: Load visible + buffer zone only, progressive loading
  - Effort: 4-5 hours

- [ ] **Cache expensive calculations**
  - Location: [MemoryViewModel.swift](RawCull/Model/ViewModels/MemoryViewModel.swift)
  - Issue: System memory stats fetched on every view update
  - Solution: Cache with configurable TTL (e.g., 500ms)
  - Effort: 1-2 hours

### Logging & Monitoring

- [ ] **Add debug logging for file operations**
  - Location: [ExecuteCopyFiles.swift](RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift)
  - Issue: File copy operations lack detailed progress logging
  - Impact: Hard to diagnose copy failures or hangs
  - Solution: Add file-level logging for rsync operations
  - Effort: 2 hours

- [ ] **Implement performance tracing**
  - Scope:
    - Measure thumbnail extraction time per file
    - Track cache hit/miss timings
    - Monitor actor crossings overhead
  - Files: [ScanAndCreateThumbnails.swift](RawCull/Actors/ScanAndCreateThumbnails.swift), [SharedRequestThumbnail.swift](RawCull/Actors/SharedRequestThumbnail.swift)
  - Effort: 3-4 hours

### Security & Error Handling

- [ ] **Improve error messages in copy operations**
  - Location: [ExecuteCopyFiles.swift](RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift)
  - Issue: Generic error logging makes troubleshooting difficult
  - Solution: Add context about which file/step failed
  - Effort: 1-2 hours

- [ ] **Add error recovery for corrupted disk cache**
  - Location: [DiskCacheManager.swift](RawCull/Actors/DiskCacheManager.swift)
  - Issue: Corrupted cache files may cause load failures
  - Solution: Implement graceful skip with automatic re-generation
  - Effort: 2-3 hours

---

## 🟢 LOW PRIORITY

### Code Organization

- [ ] **Extract common handler patterns**
  - Location: [Handlers/](RawCull/Model/Handlers/)
  - Issue: Multiple handler files with similar structure
  - Solution: Create base handler protocol to reduce duplication
  - Effort: 2-3 hours

- [ ] **Reorganize extensions module**
  - Location: [Extensions/](RawCull/Extensions/)
  - Issue: Only 2 files; could expand and organize by topic
  - Effort: 1 hour

### UI/UX Polish

- [ ] **Add animation for cache statistics updates**
  - Location: [MemoryTab.swift](RawCull/Views/Settings/MemoryTab.swift)
  - Enhancement: Smooth transitions when values change
  - Effort: 1-2 hours

- [ ] **Implement search highlighting**
  - Location: [PhotoItemView.swift](RawCull/Views/PhotoItemView.swift)
  - Enhancement: Highlight matching text in search results
  - Effort: 1-2 hours

### Documentation Enhancements

- [ ] **Add user guide for keyboard shortcuts**
  - Issue: No documentation of available shortcuts
  - Effort: 1 hour

- [ ] **Create troubleshooting guide**
  - Common Issues:
    - App using high memory
    - Thumbnails not generating
    - Copy operations failing
  - Effort: 2 hours

---

## 📊 Quality Improvements Roadmap

### Phase 1: Foundation (Week 1-2)
Priority: 🔴 → 🟠 (High Priority Items)
- [ ] Fix memory pressure monitoring cleanup
- [ ] Unify naming conventions
- [ ] Add ViewModel unit tests
- [ ] Refactor testing code

### Phase 2: Documentation (Week 3)
- [ ] Create ADRs
- [ ] Add algorithm documentation
- [ ] Write troubleshooting guide

### Phase 3: Features (Week 4-5)
- [ ] Disk cache size limits
- [ ] Cache statistics UI
- [ ] Batch operations

### Phase 4: Polish (Week 6+)
- [ ] Performance optimizations
- [ ] UI/UX enhancements
- [ ] Extended monitoring

---

## 📈 Known Limitations (Reference)

From QUALITY.md analysis:

1. **Disk Cache Size** (Low Risk)
   - No hard limit (manages itself via age)
   - Status: Low risk but should be addressed in Phase 2

2. **Initial Load Time** (Expected)
   - First scan ~5 minutes for 1100 files
   - Status: Acceptable for initial indexing

3. **ViewModel Testing** (Medium Priority)
   - Not yet unit tested
   - Status: Planned for Phase 1

---

## ✅ Health Metrics

| Metric | Status | Target | Gap |
|--------|--------|--------|-----|
| Code Quality | 9.9/10 | ≥9.8 | ✅ Exceeds |
| Architecture | 9.8/10 | ≥9.5 | ✅ Exceeds |
| Test Coverage | 7.5/10 | ≥8.0 | 🔴 -0.5 |
| Documentation | 7.5/10 | ≥8.0 | 🔴 -0.5 |
| Performance | 9.5/10 | ≥9.0 | ✅ Exceeds |
| Security | 9.8/10 | ≥9.5 | ✅ Exceeds |

**Overall:** Production ready with clear path for quality improvements

---

## 🔗 Related Documentation

- [QUALITY.md](QUALITY.md) - Detailed quality assessment
- [README.md](README.md) - Project overview
- [Testing/MASTER_SUMMARY.md](Testing/MASTER_SUMMARY.md) - Test documentation
- [Makefile](Makefile) - Build automation

---

## 📝 Notes for Developers

### Before Starting Any Task

1. Run existing tests: `xcodebuild test -scheme RawCull`
2. Verify no SwiftLint violations: `make check`
3. Check memory profile: Build and profile with 100+ test files
4. Update this TODO when completing items

### Adding New Tests

- Follow existing test structure in [RawCullTests](RawCullTests/)
- Use `@Suite` and `@Test` macros
- Include both happy path and error cases
- Document expected performance in test comments

### Naming Conventions to Follow

- Boolean properties: `is`, `has`, `should` prefix (e.g., `isScanning`)
- Methods fetching values: no prefix (e.g., `getRating()`)
- Handler callbacks: `Handler` suffix (e.g., `fileHandler`)
- Use camelCase consistently throughout

---

**Last Review:** February 16, 2026
**Reviewer:** Quality Analysis Tool
**Confidence Level:** High (based on QUALITY.md and code analysis)
