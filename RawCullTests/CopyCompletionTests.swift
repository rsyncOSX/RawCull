import Foundation
@testable import RawCull
import RawCullCore
import RsyncProcessStreaming
import Testing

@MainActor
struct CopyCompletionTests {
    @Test
    func `runtime errors and cancellation survive process termination`() {
        let errors: [RsyncProcessError] = [
            .processFailed(exitCode: 23, errors: ["Some photographs could not be copied"]),
            .timeout(30),
            .processCancelled
        ]
        for error in errors {
            var outcomes: [CopyOutcome] = []
            let handlers = CreateStreamingHandlers().createHandlers(
                fileHandler: { _ in },
                processTermination: { _, _, outcome in outcomes.append(outcome) },
            )
            #expect(handlers.checkForErrorInRsyncOutput)
            handlers.propagateError(error)
            handlers.processTermination(["partial output"], nil)
            if case .processCancelled = error {
                #expect(outcomes == [.cancelled])
            } else {
                #expect(outcomes == [.failed(message: error.localizedDescription)])
            }
        }
    }

    @Test(arguments: [false, true])
    func `real rsync completion reports success or missing source failure`(missingFile: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RawCullCopyResult-\(UUID())")
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        for url in [source, destination] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "RawCullCopyResult-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try source.bookmarkData(options: .withSecurityScope), forKey: "sourceBookmark")
        defaults.set(try destination.bookmarkData(options: .withSecurityScope), forKey: "destBookmark")
        let bytes = Data("test photograph".utf8)
        try bytes.write(to: source.appendingPathComponent("Present.ARW"))

        let viewModel = makeRawCullViewModel()
        viewModel.selectedSource = ARWSourceCatalog(name: "Source", url: source)
        let names = missingFile ? ["Present.ARW", "Missing.ARW"] : ["Present.ARW"]
        viewModel.filteredFiles = names.map { name in
            FileItem(url: source.appendingPathComponent(name), name: name, size: 1,
                     dateModified: Date(), exifData: nil, afFocusNormalized: nil)
        }
        let manager = ExecuteCopyFiles(
            configuration: SynchronizeConfiguration(), dryrun: false, rating: 0,
            copytaggedfiles: false, sidebarRawCullViewModel: viewModel,
            includeListDirectory: root, bookmarkDefaults: defaults,
        )
        defer { manager.close() }
        let result: CopyDataResult? = await withCheckedContinuation { continuation in
            manager.onCompletion = { result in continuation.resume(returning: result) }
            if case let .failure(error) = manager.startcopyfiles() {
                Issue.record("Unexpected startup failure: \(error)")
                continuation.resume(returning: nil)
            }
        }
        let completed = try #require(result)
        if missingFile {
            guard case let .failed(message) = completed.outcome else {
                Issue.record("A missing source file must not be reported as success")
                return
            }
            #expect(!message.isEmpty)
            #expect(completed.output?.joined(separator: "\n").contains(message) == true)
        } else {
            #expect(completed.outcome == .success)
            #expect(try Data(contentsOf: destination.appendingPathComponent("Present.ARW")) == bytes)
        }
        #expect(!completed.operation.dryRun)
        #expect(completed.operation.sourceURL == source)
        #expect(completed.operation.destinationURL == destination)
        #expect(manager.includeListURL == nil)
    }

    @Test(arguments: [false, true])
    func `result title uses captured operation mode`(dryRun: Bool) {
        let operation = CopyOperation(dryRun: dryRun,
                                      sourceURL: URL(fileURLWithPath: "/source"),
                                      destinationURL: URL(fileURLWithPath: "/destination"))
        #expect(operation.title(for: .success) == (dryRun ? "Dry run complete" : "Copy complete"))
        #expect(operation.title(for: .failed(message: "Disk full")) == (dryRun ? "Dry run failed" : "Copy incomplete"))
        #expect(operation.title(for: .cancelled) == (dryRun ? "Dry run cancelled" : "Copy cancelled"))
    }
}
