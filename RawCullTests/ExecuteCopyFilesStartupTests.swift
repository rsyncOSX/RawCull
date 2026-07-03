import Foundation
@testable import RawCull
import Testing

@MainActor
struct ExecuteCopyFilesStartupTests {
    @Test
    func `empty tagged list fails before copy starts`() {
        let viewModel = RawCullViewModel()
        let manager = makeManager(viewModel: viewModel, copytaggedfiles: true)

        let result = manager.startcopyfiles(
            fallbacksource: "/tmp/rawcull-source",
            fallbackdest: "/tmp/rawcull-destination",
        )

        guard case .failure(.noMatchingFiles) = result else {
            Issue.record("Expected noMatchingFiles, got \(result)")
            return
        }
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `empty rated list fails before copy starts`() {
        let viewModel = RawCullViewModel()
        let manager = makeManager(viewModel: viewModel, copytaggedfiles: false)

        let result = manager.startcopyfiles(
            fallbacksource: "/tmp/rawcull-source",
            fallbackdest: "/tmp/rawcull-destination",
        )

        guard case .failure(.noMatchingFiles) = result else {
            Issue.record("Expected noMatchingFiles, got \(result)")
            return
        }
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `missing view model fails before copy starts`() throws {
        let manager: ExecuteCopyFiles
        do {
            let viewModel = RawCullViewModel()
            manager = makeManager(viewModel: viewModel)
        }

        let result = manager.startcopyfiles(
            fallbacksource: "/tmp/rawcull-source",
            fallbackdest: "/tmp/rawcull-destination",
        )

        guard case .failure(.missingViewModel) = result else {
            Issue.record("Expected missingViewModel, got \(result)")
            return
        }
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `include list paths are unique and outside Documents`() throws {
        let firstDirectory = try temporaryDirectory()
        let secondDirectory = try temporaryDirectory()
        let viewModel = RawCullViewModel()
        let firstManager = makeManager(viewModel: viewModel, includeListDirectory: firstDirectory)
        let secondManager = makeManager(viewModel: viewModel, includeListDirectory: secondDirectory)

        let firstURL = try firstManager.writeIncludeFileForCurrentOperation(["A.ARW"])
        let secondURL = try secondManager.writeIncludeFileForCurrentOperation(["A.ARW"])

        #expect(firstURL != secondURL)
        #expect(firstURL.lastPathComponent.hasPrefix("copyfilelist-"))
        #expect(secondURL.lastPathComponent.hasPrefix("copyfilelist-"))
        #expect(!firstURL.path.contains("/Documents/"))
        #expect(!secondURL.path.contains("/Documents/"))
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        firstManager.close()
        secondManager.close()
    }

    @Test
    func `cleanup removes generated include list`() throws {
        let directory = try temporaryDirectory()
        let viewModel = RawCullViewModel()
        let manager = makeManager(viewModel: viewModel, includeListDirectory: directory)

        let includeListURL = try manager.writeIncludeFileForCurrentOperation(["A.ARW"])
        #expect(FileManager.default.fileExists(atPath: includeListURL.path))

        manager.close()

        #expect(!FileManager.default.fileExists(atPath: includeListURL.path))
        #expect(manager.includeListURL == nil)
    }

    private func makeManager(
        viewModel: RawCullViewModel,
        copytaggedfiles: Bool = true,
        includeListDirectory: URL? = nil,
    ) -> ExecuteCopyFiles {
        ExecuteCopyFiles(
            configuration: SynchronizeConfiguration(),
            dryrun: true,
            rating: 1,
            copytaggedfiles: copytaggedfiles,
            sidebarRawCullViewModel: viewModel,
            includeListDirectory: includeListDirectory,
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
