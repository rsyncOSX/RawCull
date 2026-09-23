//
//  ExecuteCopyFiles.swift
//  Created by Thomas Evensen on 10/06/2025.
//

import Foundation
import OSLog
import RsyncProcessStreaming

struct CopyDataResult {
    let output: [String]?
    let viewOutput: [RsyncOutputData]?
    let outcome: CopyOutcome
    let operation: CopyOperation
}

enum CopyOutcome: Equatable {
    case success
    case failed(message: String)
    case cancelled
}

/// The settings and resolved folders used by this operation, retained for its result.
struct CopyOperation {
    let dryRun: Bool
    let sourceURL: URL
    let destinationURL: URL

    func title(for outcome: CopyOutcome) -> LocalizedStringResource {
        switch outcome {
        case .success: dryRun ? "Dry run complete" : "Copy complete"
        case .failed: dryRun ? "Dry run failed" : "Copy incomplete"
        case .cancelled: dryRun ? "Dry run cancelled" : "Copy cancelled"
        }
    }
}

enum CopyStartupFailure: Error, Equatable, LocalizedError {
    case rsyncArgumentsUnavailable
    case missingViewModel
    case noMatchingFiles
    case applicationSupportDirectoryUnavailable
    case includeFileWriteFailed(String)
    case sourceAccessFailed
    case destinationAccessFailed
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .rsyncArgumentsUnavailable:
            "Unable to prepare rsync arguments."

        case .missingViewModel:
            "Unable to read the selected photo list."

        case .noMatchingFiles:
            "No matching files to copy."

        case .applicationSupportDirectoryUnavailable:
            "Unable to create RawCull's copy-list folder."

        case let .includeFileWriteFailed(message):
            "Unable to write the copy-list file: \(message)"

        case .sourceAccessFailed:
            "RawCull could not access the current catalog. Please reopen the catalog and try again."

        case .destinationAccessFailed:
            "Unable to access the selected destination folder. Please reselect the destination folder and try again."

        case let .processLaunchFailed(message):
            "Unable to start rsync: \(message)"
        }
    }
}

struct RsyncOutputData: Identifiable, Equatable, Hashable {
    let id = UUID()
    var record: String
}

@Observable @MainActor
final class ExecuteCopyFiles {
    weak var sidebarRawCullViewModel: RawCullViewModel?

    let config: SynchronizeConfiguration
    let dryrun: Bool
    let rating: Int
    let copyTaggedFiles: Bool
    private let includeListDirectoryOverride: URL?
    private let fileManager: FileManager
    private let bookmarkStore: CopyBookmarkStore
    private(set) var includeListURL: URL?

    // Streaming references
    private var streamingHandlers: RsyncProcessStreaming.ProcessHandlers?
    private var activeStreamingProcess: RsyncProcessStreaming.RsyncProcess?

    // Security-scoped URL references
    private var sourceAccess: CopyScopedAccess?
    private var destinationAccess: CopyScopedAccess?
    private var didCleanUp = false
    private var isClosing = false
    private var operation: CopyOperation?

    /// Callback
    var onCompletion: ((CopyDataResult) -> Void)?

    /// Progress update
    var progressStream: AsyncStream<Int>?
    private var progressContinuation: AsyncStream<Int>.Continuation?

    func startCopyFiles() -> Result<Void, CopyStartupFailure> {
        guard var arguments = ArgumentsSynchronize(config: config).argumentsSynchronize(
            dryRun: dryrun,
        ) else {
            return .failure(.rsyncArgumentsUnavailable)
        }

        setupStreamingHandlers()

        guard let streamingHandlers, arguments.count > 2 else {
            cleanup()
            return .failure(.rsyncArgumentsUnavailable)
        }

        let filelist: [String]
        guard let sidebarRawCullViewModel else {
            cleanup()
            return .failure(.missingViewModel)
        }

        if copyTaggedFiles {
            filelist = sidebarRawCullViewModel.extractTaggedfilenames()
        } else {
            filelist = sidebarRawCullViewModel.extractRatedfilenames(rating)
        }

        guard !filelist.isEmpty else {
            cleanup()
            return .failure(.noMatchingFiles)
        }

        let savePath: URL
        do {
            savePath = try writeUniqueIncludeFile(filelist)
        } catch let failure as CopyStartupFailure {
            cleanup()
            return .failure(failure)
        } catch {
            cleanup()
            return .failure(.includeFileWriteFailed(error.localizedDescription))
        }

        arguments.append("--from0")
        arguments.append("--files-from=" + savePath.path)

        // Add itemize parameter to get a nice formatted output
        let itemizedParameter = "--itemize-changes"
        arguments.append(itemizedParameter)
        let updateParameter = "--update"
        arguments.append(updateParameter)

        guard let selectedSourceURL = sidebarRawCullViewModel.selectedSource?.url,
              let sourceAccess = try? bookmarkStore.acquireSource(selectedSourceURL) else {
            Logger.process.errorMessageOnly("Failed to access folders")
            cleanup()
            return .failure(.sourceAccessFailed)
        }

        self.sourceAccess = sourceAccess

        guard let destinationAccess = try? bookmarkStore.acquireDestination() else {
            Logger.process.errorMessageOnly("Failed to access folders")
            cleanup()
            return .failure(.destinationAccessFailed)
        }

        self.destinationAccess = destinationAccess
        let sourceURL = sourceAccess.url
        let destURL = destinationAccess.url
        operation = CopyOperation(dryRun: dryrun, sourceURL: sourceURL, destinationURL: destURL)

        arguments.append(sourceURL.path + "/")
        arguments.append(destURL.path + "/")

        Logger.process.debugMessageOnly("Final arguments: \(arguments)")
        Logger.process.debugMessageOnly("Number of arguments: \(arguments.count)")

        let process = RsyncProcessStreaming.RsyncProcess(
            arguments: arguments,
            hiddenID: 0,
            handlers: streamingHandlers,
            useFileHandler: true,
        )

        do {
            try process.executeProcess()
            activeStreamingProcess = process
            return .success(())
        } catch {
            Logger.process.errorMessageOnly(": executeProcess failed: \(error)")
            cleanup()
            return .failure(.processLaunchFailed(error.localizedDescription))
        }
    }

    @discardableResult
    init(
        configuration: SynchronizeConfiguration,
        dryrun: Bool = true,
        rating: Int = 0,
        copyTaggedFiles: Bool = true,
        sidebarRawCullViewModel: RawCullViewModel,
        includeListDirectory: URL? = nil,
        fileManager: FileManager = .default,
        bookmarkStore: CopyBookmarkStore = CopyBookmarkStore(),
    ) {
        self.config = configuration
        self.dryrun = dryrun
        self.rating = rating
        self.sidebarRawCullViewModel = sidebarRawCullViewModel
        self.copyTaggedFiles = copyTaggedFiles
        self.includeListDirectoryOverride = includeListDirectory
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore

        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        self.progressStream = stream
        self.progressContinuation = continuation
    }

    isolated deinit {
        Logger.process.debugMessageOnly("ExecuteCopyFiles: DEINIT")
        cleanup()
    }

    func close() {
        isClosing = true
        activeStreamingProcess?.cancel()
        cleanup()
    }

    private func setupStreamingHandlers() {
        streamingHandlers = CreateStreamingHandlers().createHandlers(
            fileHandler: { [weak self] count in
                Task { @MainActor in
                    self?.progressContinuation?.yield(count)
                }
            },
            processTermination: { [weak self] output, hiddenID, outcome in
                Task { @MainActor in
                    await self?.handleProcessTermination(
                        stringoutputfromrsync: output,
                        hiddenID: hiddenID,
                        outcome: outcome,
                    )
                }
            },
        )
    }

    private func handleProcessTermination(stringoutputfromrsync: [String]?, hiddenID _: Int?, outcome: CopyOutcome) async {
        guard !isClosing, let operation else {
            cleanup()
            return
        }

        // Keep stderr/exit diagnostics available in the detailed output too.
        var output = stringoutputfromrsync ?? []
        if case let .failed(message) = outcome {
            output.append(contentsOf: message.components(separatedBy: .newlines))
        }
        let viewOutput = await CreateOutputforView().createOutputForView(output)
        guard !isClosing else {
            cleanup()
            return
        }

        // Create the result
        let result = CopyDataResult(
            output: output,
            viewOutput: viewOutput,
            outcome: outcome,
            operation: operation,
        )

        // Call completion handler - let it finish before cleanup
        onCompletion?(result)

        // Clean up only after completion has been processed
        cleanup()
    }

    private func cleanup() {
        guard didCleanUp == false else { return }
        didCleanUp = true

        progressContinuation?.finish()
        progressContinuation = nil
        progressStream = nil

        // Stop accessing security-scoped resources
        sourceAccess?.release()
        destinationAccess?.release()

        sourceAccess = nil
        destinationAccess = nil

        if let includeListURL {
            try? fileManager.removeItem(at: includeListURL)
        }
        includeListURL = nil

        activeStreamingProcess = nil
        streamingHandlers = nil
    }

    func writeIncludeFileForCurrentOperation(_ filelist: [String]) throws -> URL {
        try writeUniqueIncludeFile(filelist)
    }

    private func writeUniqueIncludeFile(_ filelist: [String]) throws -> URL {
        let directory: URL
        do {
            directory = try includeListDirectory()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Logger.process.errorMessageOnly(": Failed to create include-list directory: \(error)")
            throw CopyStartupFailure.applicationSupportDirectoryUnavailable
        }

        let URLpath = directory.appendingPathComponent("copyfilelist-\(UUID().uuidString).list0")
        Logger.process.debugMessageOnly("ExecuteCopyFiles: writing copyfilelist at \(URLpath.path)")
        do {
            try writeincludefilelist(filelist, to: URLpath)
            includeListURL = URLpath
            return URLpath
        } catch {
            Logger.process.errorMessageOnly(": Failed to write copy-list file: \(error)")
            throw CopyStartupFailure.includeFileWriteFailed(error.localizedDescription)
        }
    }

    private func includeListDirectory() throws -> URL {
        if let includeListDirectoryOverride {
            return includeListDirectoryOverride
        }

        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CopyStartupFailure.applicationSupportDirectoryUnavailable
        }

        return applicationSupport
            .appendingPathComponent("RawCull", isDirectory: true)
            .appendingPathComponent("CopyLists", isDirectory: true)
    }

    private func writeincludefilelist(_ filelist: [String], to URLpath: URL) throws {
        var newdata = Data()
        for filename in filelist {
            guard let encodedFilename = filename.data(using: .utf8) else {
                throw NSError(domain: "ExecuteCopyFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode filename"])
            }
            newdata.append(encodedFilename)
            newdata.append(0)
        }
        do {
            try newdata.write(to: URLpath, options: .atomic)
        } catch {
            throw NSError(
                domain: "ExecuteCopyFiles",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write filelist to URL: \(error)"],
            )
        }
    }
}
