import AppKit
import Foundation
@testable import RawCull
import RawCullCore
import Testing

/// Opt-in integration benchmark. Run only through Scripts/RunCatalogPerformance.py.
/// The singleton grid cache requires a dedicated, nonparallel test process.
@Suite("Real ARW catalog performance")
struct CatalogPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_CATALOG_PERFORMANCE_RUN"] == "1"))
    @MainActor
    func benchmark() async throws {
        let environment = ProcessInfo.processInfo.environment
        let catalog = try URL(fileURLWithPath: #require(environment["RAWCULL_CATALOG_PERFORMANCE_INPUT"]))
        let output = try URL(fileURLWithPath: #require(environment["RAWCULL_CATALOG_PERFORMANCE_OUTPUT"]))
        let runs = Int(environment["RAWCULL_CATALOG_PERFORMANCE_RUNS"] ?? "3") ?? 3
        let steps = Int(environment["RAWCULL_CATALOG_PERFORMANCE_STEPS"] ?? "100") ?? 100
        let pixelSize = Int(environment["RAWCULL_CATALOG_PERFORMANCE_PIXELS"] ?? "1600") ?? 1600
        try #require((1 ... 10).contains(runs) && (1 ... 10000).contains(steps) && (200 ... 4096).contains(pixelSize))
        await SharedMemoryCache.shared.ensureReady(config: CacheConfig(
            totalCostLimit: 256 * 1024 * 1024, countLimit: 1000, gridTotalCostLimit: 128 * 1024 * 1024,
        ))
        for run in 1 ... runs {
            try await runCatalog(catalog, output: output, run: run, steps: steps, pixelSize: pixelSize)
        }
    }

    @MainActor
    private func runCatalog(_ catalog: URL, output: URL, run: Int, steps: Int, pixelSize: Int) async throws {
        let directory = output.appendingPathComponent("run-\(run)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = try CatalogPerformanceJournal(url: directory.appendingPathComponent("events.jsonl"))
        let sampler = Task { @concurrent in
            while !Task.isCancelled {
                await journal.sample()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
        let loader = CatalogPerformanceLoader(journal: journal)
        let disk = DiskCacheManager(cacheDirectory: directory.appendingPathComponent("thumbnail-cache"))
        let preloader = ScanAndCreateThumbnails(diskCache: disk, rawLoader: loader, measure: { measurement in
            await journal.record(measurement)
        }, saveToDisk: { data, key in
            await journal.beginSave(bytes: data.count)
            let start = ProcessInfo.processInfo.systemUptime
            await disk.save(data, for: key)
            let cacheURL = await disk.cacheFileURL(for: key)
            await journal.record(
                "cache.save",
                since: start,
                succeeded: FileManager.default.fileExists(atPath: cacheURL.path),
                detail: key.source.standardizedURL.lastPathComponent,
            )
            await journal.endSave()
        })
        print("Catalog benchmark: run \(run), \(catalog.path)")
        do {
            let pipeline = Pipeline(journal: journal, loader: loader, disk: disk, preloader: preloader)
            try await exercise(catalog, directory: directory, steps: steps, pixelSize: pixelSize, pipeline: pipeline)
        } catch {
            await journal.record(
                "run.error",
                since: ProcessInfo.processInfo.systemUptime,
                succeeded: false,
                detail: String(describing: error),
            )
            Issue.record(error)
        }
        sampler.cancel()
        await sampler.value
        await journal.sample()
        let snapshot = try await journal.snapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent("results.json"), options: .atomic)
        SharedMemoryCache.shared.removeAllObjects()
        SharedMemoryCache.shared.removeAllGridObjects()
        for metric in snapshot.metrics where !metric.succeeded {
            Issue.record("\(metric.phase): \(metric.detail)")
        }
        #expect(snapshot.peakSaves <= RawImageLoadingConcurrency.thumbnailPreloadLimit)
        #expect(snapshot.counts["peak.metadata", default: 0] <= RawImageLoadingConcurrency.metadataScanLimit)
        #expect(snapshot.counts["peak.thumbnailImage", default: 0] <= RawImageLoadingConcurrency.thumbnailPreloadLimit)
        print("Catalog benchmark: run \(run) finished; \(directory.path)")
    }

    private struct Pipeline {
        let journal: CatalogPerformanceJournal
        let loader: CatalogPerformanceLoader
        let disk: DiskCacheManager
        let preloader: ScanAndCreateThumbnails
    }

}

extension CatalogPerformanceTests {
    @MainActor
    private func exercise(
        _ catalog: URL,
        directory: URL,
        steps: Int,
        pixelSize: Int,
        pipeline: Pipeline,
    ) async throws {
        let (journal, loader, disk, preloader) = (pipeline.journal, pipeline.loader, pipeline.disk, pipeline.preloader)
        var start = ProcessInfo.processInfo.systemUptime
        await journal.phase("catalog.discovery")
        let discovered = await DiscoverFiles().discoverFiles(at: catalog, recursive: false)
        try #require(
            !discovered.isEmpty && discovered.allSatisfy { $0.pathExtension.lowercased() == "arw" },
            "Use a catalog containing ARW files and no other supported RAW formats",
        )
        await journal.record("catalog.discovery", since: start, succeeded: true, detail: "\(discovered.count) files")

        start = ProcessInfo.processInfo.systemUptime
        await journal.phase("catalog.metadata")
        let files = await ScanFiles(rawLoader: loader).scanFiles(url: catalog)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let complete = Set(files.map(\.url)) == Set(discovered)
        await journal.record("catalog.metadata", since: start, succeeded: complete, detail: "\(files.count) files")
        try #require(complete && !files.isEmpty, "Metadata scan must return every discovered file")
        let sample = evenlySpaced(files, count: min(steps, files.count))

        clearRAM()
        start = ProcessInfo.processInfo.systemUptime
        await journal.phase("preload.emptyDiskCache")
        let prepared = await preloader.preloadCatalog(at: catalog, targetSize: pixelSize)
        await journal.record(
            "preload.emptyDiskCache",
            since: start,
            succeeded: prepared == files.count,
            detail: "\(prepared)/\(files.count) files",
        )
        try await verifyDiskOutputs(files, pixelSize: pixelSize, disk: disk)
        let coldMetrics = await journal.metrics
        try #require(coldMetrics.filter { $0.phase == "jpeg.encode" }.count == files.count,
                     "Every cold thumbnail must have an encoding measurement")
        try #require(coldMetrics.filter { $0.phase == "grid.preloadResize" }.count == files.count,
                     "Every cold thumbnail must have a grid creation measurement")
        let countsBeforeWarm = await journal.counts
        clearRAM()
        start = ProcessInfo.processInfo.systemUptime
        await journal.phase("preload.warmDiskCache")
        let warmPrepared = await preloader.preloadCatalog(at: catalog, targetSize: pixelSize)
        let countsAfterWarm = await journal.counts
        await journal.record(
            "preload.warmDiskCache",
            since: start,
            succeeded: warmPrepared == files.count && countsBeforeWarm == countsAfterWarm,
            detail: "Warm preload must require no RAW decodes or saves",
        )

        let requester = RequestThumbnail(diskCache: disk, rawLoader: loader)
        clearRAM()
        try await browse(sample, requester: requester, size: pixelSize, phase: "browse.disk", journal: journal)
        try await browse(sample.reversed(), requester: requester, size: pixelSize, phase: "browse.revisit", journal: journal)
        let afterBrowse = await journal.counts
        await journal.record(
            "browse.noSourceFallback",
            since: ProcessInfo.processInfo.systemUptime,
            succeeded: afterBrowse == countsAfterWarm,
            detail: "Prepared thumbnail requests must use RAM or disk",
        )

        // The same warm-disk requests now compete with real background grid preparation.
        clearRAM()
        await journal.phase("preload.withBrowsing")
        let concurrentStart = ProcessInfo.processInfo.systemUptime
        let warmTask = Task { await preloader.preloadCatalog(at: catalog, targetSize: pixelSize) }
        do {
            try await browse(sample, requester: requester, size: pixelSize, phase: "browse.duringPreload", journal: journal)
        } catch {
            warmTask.cancel()
            _ = await warmTask.value
            throw error
        }
        let concurrentPrepared = await warmTask.value
        await journal.record(
            "preload.withBrowsing",
            since: concurrentStart,
            succeeded: concurrentPrepared == files.count,
        )

        try await sampleImages(files, pixelSize: pixelSize, journal: journal, loader: loader)
        await journal.phase("navigation")
        try await presentation(files, steps: steps, journal: journal)
        await journal.phase("preload.cancelAndDrain")
        try await cancellation(catalog, directory: directory, pixelSize: pixelSize, journal: journal)
        clearRAM()
        start = ProcessInfo.processInfo.systemUptime
        await journal.phase("preload.recovery")
        let recovered = await preloader.preloadCatalog(at: catalog, targetSize: pixelSize)
        await journal.record("preload.recovery", since: start, succeeded: recovered == files.count)
    }

    private func verifyDiskOutputs(_ files: [FileItem], pixelSize: Int, disk: DiskCacheManager) async throws {
        // Preload reports decode success before JPEG saving; verify all disk outputs separately.
        for file in files {
            let key = try #require(ThumbnailCacheKey.resolve(
                for: file.url,
                purpose: .preview,
                requestedPixelSize: pixelSize,
            ))
            let cacheURL = await disk.cacheFileURL(for: key)
            try #require(FileManager.default.fileExists(atPath: cacheURL.path), "Missing cached JPEG: \(file.name)")
        }
    }

    @MainActor
    private func sampleImages(
        _ files: [FileItem],
        pixelSize: Int,
        journal: CatalogPerformanceJournal,
        loader: CatalogPerformanceLoader,
    ) async throws {
        for file in evenlySpaced(files, count: min(10, files.count)) {
            guard let source = await loader.thumbnailCGImage(for: file.url, maxPixelSize: pixelSize) else {
                throw RawImageLoadingError.invalidSource
            }
            let image = NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height))
            let start = ProcessInfo.processInfo.systemUptime
            let resized = GridThumbnailResizer.resize(image, source: source)
            let bitmap = resized?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            await journal.record(
                "grid.resize",
                since: start,
                succeeded: bitmap
                    .map { max($0.width, $0.height) <= 200 && $0.width > 0 && $0.height > 0 } ?? false,
                detail: file.name,
            )
        }
        for file in evenlySpaced(files, count: min(10, files.count)) {
            let start = ProcessInfo.processInfo.systemUptime
            let image = await loader.previewCGImage(for: file.url)
            await journal.record(
                "zoom.previewReady",
                since: start,
                succeeded: image.map { $0.width > 0 && $0.height > 0 } ?? false,
                detail: file.name,
            )
            try #require(image != nil, "Preview decode failed: \(file.name)")
        }
    }

    @MainActor
    private func browse(
        _ files: some Sequence<FileItem>,
        requester: RequestThumbnail,
        size: Int,
        phase: String,
        journal: CatalogPerformanceJournal,
    ) async throws {
        await journal.phase(phase)
        for file in files {
            try Task.checkCancellation()
            let start = ProcessInfo.processInfo.systemUptime
            let image = await requester.requestThumbnail(for: file.url, targetSize: size, purpose: .preview)
            await journal.record(
                phase,
                since: start,
                succeeded: image.map { $0.width > 0 && $0.height > 0 } ?? false,
                detail: file.name,
            )
            try #require(image != nil, "Thumbnail request failed: \(file.name)")
        }
    }

    @MainActor
    func presentation(_ files: [FileItem], steps: Int, journal: CatalogPerformanceJournal) async throws {
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullPerformance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: artifactDirectory) }
        let model = makeModel(directory: artifactDirectory)
        model.files = files
        model.filteredFiles = files
        let navigation = ZoomNavigationPresentation(viewModel: model)
        var start = ProcessInfo.processInfo.systemUptime
        _ = navigation.orderedZoomFiles
        await journal.record("navigation.build", since: start, succeeded: navigation.orderedZoomFiles.count == files.count)
        let builds = model.zoomNavigationBuildCount
        for index in 0 ..< steps {
            let position = index % files.count
            start = ProcessInfo.processInfo.systemUptime
            model.selectedFileID = files[position].id
            let actual = navigation.currentZoomIndex
            let previous = navigation.canNavigatePrevious
            let next = navigation.canNavigateNext
            let count = model.sharpnessScoringTargetCount
            let description = model.sharpnessScoringTargetDescription
            await journal.record(
                "navigation.selectionAndControls",
                since: start,
                succeeded: actual == position && previous == (position > 0)
                    && next == (position + 1 < files.count) && count == files.count && !description.isEmpty,
            )
        }
        try #require(model.zoomNavigationBuildCount == builds, "Selection-only navigation rebuilt ordering")
        model.selectedFileIDs = Set(files.prefix(3).map(\.id))
        try #require(model.sharpnessScoringTargetCount == min(3, files.count))
        model.selectedFileIDs = []
        start = ProcessInfo.processInfo.systemUptime
        model.ratingCache = Dictionary(uniqueKeysWithValues: files.prefix(3).map { ($0.name, 5) })
        model.ratingFilter = .stars(5)
        let filtered = navigation.orderedZoomFiles
        await journal.record(
            "navigation.ratingFilter",
            since: start,
            succeeded: filtered.count == min(3, files.count) && model.zoomNavigationBuildCount > builds,
        )
        model.ratingFilter = .all
        model.zoomOverlayNavigationContext = ZoomOverlayNavigationContext(orderedFileIDs: files.reversed().map(\.id))
        try #require(navigation.orderedZoomFiles.map(\.id) == files.reversed().map(\.id))
        model.files = []
        model.filteredFiles = []
        try #require(navigation.orderedZoomFiles.isEmpty && navigation.currentZoomIndex == nil)
        // Keep a structural regression visible in the machine-readable report.
        await journal.record(
            "navigation.reuseAndInvalidation",
            since: ProcessInfo.processInfo.systemUptime,
            succeeded: true,
            detail: "\(steps) selection changes reused one projection; filter/context/catalog invalidated it",
        )
    }

    @MainActor
    private func cancellation(
        _ catalog: URL, directory: URL, pixelSize: Int, journal: CatalogPerformanceJournal,
    ) async throws {
        clearRAM()
        let cancellationJournal = try CatalogPerformanceJournal(url: directory
            .appendingPathComponent("cancellation-events.jsonl"))
        let loader = CatalogPerformanceLoader(journal: cancellationJournal)
        let disk = DiskCacheManager(cacheDirectory: directory.appendingPathComponent("cancellation-cache"))
        let provider = ScanAndCreateThumbnails(diskCache: disk, rawLoader: loader)
        let task = Task {
            let count = await provider.preloadCatalog(at: catalog, targetSize: pixelSize)
            await cancellationJournal.finishDecodeWait()
            return count
        }
        await cancellationJournal.waitForDecode()
        let start = ProcessInfo.processInfo.systemUptime
        await provider.cancelPreload()
        _ = await task.value
        let snapshot = try await cancellationJournal.snapshot()
        await journal.record(
            "preload.cancelAndDrain",
            since: start,
            succeeded: snapshot.counts["thumbnailImage", default: 0] > 0,
            detail: "Cancellation requested after first source decode started; waits for native reads already running",
        )
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("cancellation-results.json"))
    }

    @MainActor
    private func makeModel(directory: URL) -> RawCullViewModel {
        let similarity = SimilarityScoringModel(
            semanticSearchCapability: .unavailable(
                reason: "Performance benchmark does not load AI models",
                expectedLocations: [],
            ),
            artifactStore: PerFileAnalysisArtifactStore(storageDirectory: directory),
        )
        let feature = RawCullSimilarityFeature(similarityModel: similarity)
        let semantic = RawCullSemanticSearchFeature(similarityModel: similarity, similarityFeature: feature)
        let model = RawCullViewModel(
            similarityModel: similarity,
            similarityFeature: feature,
            semanticSearchFeature: semantic,
            deepAIReviewController: DeepAIReviewController(),
        )
        model.cullingModel = CullingModel(saveHandler: { _ in })
        semantic.bindApplicationTarget(model)
        return model
    }

    @MainActor
    private func clearRAM() {
        SharedMemoryCache.shared.removeAllObjects()
        SharedMemoryCache.shared.removeAllGridObjects()
    }

    private func evenlySpaced(_ files: [FileItem], count: Int) -> [FileItem] {
        guard count > 1 else { return Array(files.prefix(count)) }
        return (0 ..< count).map { files[$0 * (files.count - 1) / (count - 1)] }
    }
}
