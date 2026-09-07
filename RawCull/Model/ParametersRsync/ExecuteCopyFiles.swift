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
            "Unable to access the source folder for the current catalog. Please reselect the source folder to match the current catalog and try again."

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
    var dryrun: Bool
    var rating: Int
    var copytaggedfiles: Bool
    private let includeListDirectoryOverride: URL?
    private let fileManager: FileManager
    private let bookmarkDefaults: UserDefaults
    private let displayedSourceURL: URL?
    private(set) var includeListURL: URL?

    // Streaming references
    private var streamingHandlers: RsyncProcessStreaming.ProcessHandlers?
    private var activeStreamingProcess: RsyncProcessStreaming.RsyncProcess?

    // Security-scoped URL references
    private var sourceAccessedURL: URL?
    private var destAccessedURL: URL?
    private var didCleanUp = false
    private var isClosing = false

    /// Callback
    var onCompletion: ((CopyDataResult) -> Void)?

    /// Progress update
    var progressStream: AsyncStream<Int>?
    private var progressContinuation: AsyncStream<Int>.Continuation?

    func startcopyfiles() -> Result<Void, CopyStartupFailure> {
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

        if copytaggedfiles {
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
        let itemizeparameter = "--itemize-changes"
        arguments.append(itemizeparameter)
        let updateparamter = "--update"
        arguments.append(updateparamter)

        guard let catalogURL = sidebarRawCullViewModel.selectedSource?.url,
              let displayedSourceURL,
              Self.sameFolder(catalogURL, displayedSourceURL),
              let sourceURL = getAccessedURL(
                  fromBookmarkKey: "sourceBookmark",
                  matching: catalogURL,
              ) else {
            Logger.process.errorMessageOnly("Failed to access folders")
            cleanup()
            return .failure(.sourceAccessFailed)
        }

        self.sourceAccessedURL = sourceURL

        guard let destURL = getAccessedURL(fromBookmarkKey: "destBookmark") else {
            Logger.process.errorMessageOnly("Failed to access folders")
            cleanup()
            return .failure(.destinationAccessFailed)
        }

        self.destAccessedURL = destURL

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
        copytaggedfiles: Bool = true,
        sidebarRawCullViewModel: RawCullViewModel,
        includeListDirectory: URL? = nil,
        fileManager: FileManager = .default,
        bookmarkDefaults: UserDefaults = .standard,
        displayedSourceURL: URL? = nil,
    ) {
        self.config = configuration
        self.dryrun = dryrun
        self.rating = rating
        self.sidebarRawCullViewModel = sidebarRawCullViewModel
        self.copytaggedfiles = copytaggedfiles
        self.includeListDirectoryOverride = includeListDirectory
        self.fileManager = fileManager
        self.bookmarkDefaults = bookmarkDefaults
        self.displayedSourceURL = displayedSourceURL ?? sidebarRawCullViewModel.selectedSource?.url

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
            processTermination: { [weak self] output, hiddenID in
                Task { @MainActor in
                    await self?.handleProcessTermination(
                        stringoutputfromrsync: output,
                        hiddenID: hiddenID,
                    )
                }
            },
        )
    }

    private func handleProcessTermination(stringoutputfromrsync: [String]?, hiddenID _: Int?) async {
        guard !isClosing else {
            cleanup()
            return
        }

        // Create view output asynchronously
        let viewOutput = await CreateOutputforView().createOutputForView(stringoutputfromrsync)

        // Create the result
        let result = CopyDataResult(
            output: stringoutputfromrsync,
            viewOutput: viewOutput,
        )

        // Call completion handler - let it finish before cleanup
        onCompletion?(result)

        // Give a tiny delay to ensure completion handler processes
        try? await Task.sleep(for: .milliseconds(10))

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
        sourceAccessedURL?.stopAccessingSecurityScopedResource()
        destAccessedURL?.stopAccessingSecurityScopedResource()

        sourceAccessedURL = nil
        destAccessedURL = nil

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

    private static func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL == rhs.resolvingSymlinksInPath().standardizedFileURL
    }

    func getAccessedURL(fromBookmarkKey key: String, matching expectedURL: URL? = nil) -> URL? {
        guard let bookmarkData = bookmarkDefaults.data(forKey: key) else {
            Logger.process.warning("No bookmark for \(key); folder reselection is required")
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            )
            // A valid grant can still belong to a previously selected catalog.
            // Never apply the current catalog's filenames to that older source.
            if let expectedURL, !Self.sameFolder(url, expectedURL) {
                Logger.process.warning("Bookmark for \(key) does not match the selected catalog; reselect the folder")
                return nil
            }
            guard url.startAccessingSecurityScopedResource() else {
                Logger.process.errorMessageOnly("Cannot access bookmark for \(key); reselect the folder")
                return nil
            }
            // Refresh a stale bookmark only while its resolved grant is active.
            if isStale {
                do {
                    let refreshed = try url.bookmarkData(options: .withSecurityScope)
                    bookmarkDefaults.set(refreshed, forKey: key)
                } catch {
                    Logger.process.warning("Could not refresh bookmark for \(key): \(error)")
                }
            }
            return url
        } catch {
            Logger.process.errorMessageOnly("Bookmark resolution failed for \(key): \(error); reselect the folder")
            return nil
        }
    }
}
