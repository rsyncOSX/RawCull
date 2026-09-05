import Foundation
@testable import RawCull
import Testing
import RawCullCore

@MainActor
struct ExecuteCopyFilesStartupTests {
    @Test
    func `empty tagged list fails before copy starts`() {
        let viewModel = makeRawCullViewModel()
        let manager = makeManager(viewModel: viewModel, copytaggedfiles: true)

        let result = manager.startcopyfiles()

        guard case .failure(.noMatchingFiles) = result else {
            Issue.record("Expected noMatchingFiles, got \(result)")
            return
        }
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `empty rated list fails before copy starts`() {
        let viewModel = makeRawCullViewModel()
        let manager = makeManager(viewModel: viewModel, copytaggedfiles: false)

        let result = manager.startcopyfiles()

        guard case .failure(.noMatchingFiles) = result else {
            Issue.record("Expected noMatchingFiles, got \(result)")
            return
        }
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `missing view model fails before copy starts`() {
        let manager: ExecuteCopyFiles
        do {
            let viewModel = makeRawCullViewModel()
            manager = makeManager(viewModel: viewModel)
        }

        let result = manager.startcopyfiles()

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
        let viewModel = makeRawCullViewModel()
        let firstManager = makeManager(viewModel: viewModel, includeListDirectory: firstDirectory)
        let secondManager = makeManager(viewModel: viewModel, includeListDirectory: secondDirectory)

        let firstURL = try firstManager.writeIncludeFileForCurrentOperation(["A.ARW"])
        let secondURL = try secondManager.writeIncludeFileForCurrentOperation(["A.ARW"])

        #expect(firstURL != secondURL)
        #expect(firstURL.lastPathComponent.hasPrefix("copyfilelist-"))
        #expect(secondURL.lastPathComponent.hasPrefix("copyfilelist-"))
        #expect(firstURL.pathExtension == "list0")
        #expect(secondURL.pathExtension == "list0")
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
        let viewModel = makeRawCullViewModel()
        let manager = makeManager(viewModel: viewModel, includeListDirectory: directory)

        let includeListURL = try manager.writeIncludeFileForCurrentOperation(["A.ARW"])
        #expect(FileManager.default.fileExists(atPath: includeListURL.path))

        manager.close()

        #expect(!FileManager.default.fileExists(atPath: includeListURL.path))
        #expect(manager.includeListURL == nil)
    }

    @Test
    func `copy list is nul separated for literal rsync files-from matching`() throws {
        let directory = try temporaryDirectory()
        let viewModel = makeRawCullViewModel()
        let manager = makeManager(viewModel: viewModel, includeListDirectory: directory)
        let fileNames = [
            "normal.ARW",
            "[bracket]*question?.ARW",
            "#not-a-comment!.ARW",
            "+not-a-filter-rule.ARW"
        ]

        let includeListURL = try manager.writeIncludeFileForCurrentOperation(fileNames)
        let data = try Data(contentsOf: includeListURL)
        let expected = fileNames.reduce(into: Data()) { partialResult, fileName in
            partialResult.append(Data(fileName.utf8))
            partialResult.append(0)
        }

        #expect(data == expected)
        #expect(!data.contains(10))

        manager.close()
    }

    @Test(arguments: [false, true])
    func `missing or corrupt bookmark requires folder reselection`(corrupt: Bool) throws {
        let suite = "RawCullCopyBookmarks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        if corrupt { defaults.set(Data("invalid bookmark".utf8), forKey: "sourceBookmark") }
        let viewModel = makeRawCullViewModel()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FileItem(url: directory.appendingPathComponent("A.ARW"), name: "A.ARW", size: 1,
                            dateModified: Date(), exifData: nil, afFocusNormalized: nil)
        viewModel.filteredFiles = [file]
        let manager = ExecuteCopyFiles(configuration: SynchronizeConfiguration(), rating: 0, copytaggedfiles: false,
                                       sidebarRawCullViewModel: viewModel, includeListDirectory: directory,
                                       bookmarkDefaults: defaults)
        guard case .failure(.sourceAccessFailed) = manager.startcopyfiles() else {
            Issue.record("Expected source access failure")
            return
        }
        #expect(manager.includeListURL == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(manager.getAccessedURL(fromBookmarkKey: "sourceBookmark") == nil)
        #expect(manager.getAccessedURL(fromBookmarkKey: "destBookmark") == nil)
        #expect(CopyStartupFailure.sourceAccessFailed.localizedDescription.contains("reselect the source"))
        #expect(CopyStartupFailure.destinationAccessFailed.localizedDescription.contains("reselect the destination"))
        manager.close()
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
