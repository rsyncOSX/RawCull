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
    let linesCount: Int
}

struct RsyncOutputData: Identifiable, Equatable, Hashable {
    let id = UUID()
    var record: String
}

@Observable @MainActor
final class ExecuteCopyFiles {
    weak var sidebarRawCullViewModel: RawCullViewModel?

    private let fileName = "copyfilelist.txt"
    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    let config: SynchronizeConfiguration
    var dryrun: Bool
    var rating: Int
    var copytaggedfiles: Bool

    // Streaming references
    private var streamingHandlers: RsyncProcessStreaming.ProcessHandlers?
    private var activeStreamingProcess: RsyncProcessStreaming.RsyncProcess?

    // Security-scoped URL references
    private var sourceAccessedURL: URL?
    private var destAccessedURL: URL?

    // Callbacks
    var onProgressUpdate: ((Double) -> Void)?
    var onCompletion: ((CopyDataResult) -> Void)?

    func startcopyfiles(
        fallbacksource: String,
        fallbackdest: String
    ) {
        let arguments = ArgumentsSynchronize(config: config).argumentsSynchronize(
            dryRun: dryrun
        )

        setupStreamingHandlers()

        guard var arguments, let streamingHandlers, arguments.count > 2 else { return }

        // Add filter file if needed
        let includeparameter = "--include-from=" + savePath.path
        arguments.append(includeparameter)

        if dryrun == false {
            arguments.append("--include=*/")
        }
        arguments.append("--exclude=*")

        // Add itemize parameter to get a nice formatted output
        let itemizeparameter = "--itemize-changes"
        arguments.append(itemizeparameter)
        let updateparamter = "--update"
        arguments.append(updateparamter)

        guard let sourceURL = getAccessedURL(fromBookmarkKey: "sourceBookmark", fallbackPath: fallbacksource),
              let destURL = getAccessedURL(fromBookmarkKey: "destBookmark", fallbackPath: fallbackdest)
        else {
            Logger.process.errorMessageOnly("Failed to access folders")
            return
        }

        self.sourceAccessedURL = sourceURL
        self.destAccessedURL = destURL

        arguments.append(sourceURL.path + "/")
        arguments.append(destURL.path + "/")

        Logger.process.debugMessageOnly("Final arguments: \(arguments)")
        Logger.process.debugMessageOnly("Number of arguments: \(arguments.count)")

        // Write filter file
        Logger.process.debugMessageOnly("ExecuteCopyFiles: writing copyfilelist at \(savePath.path)")

        if copytaggedfiles {
            if let filelist = sidebarRawCullViewModel?.extractTaggedfilenames() {
                do {
                    try writeincludefilelist(filelist, to: savePath)
                } catch {
                    Logger.process.errorMessageOnly(": Failed to write filter file: \(error)")
                }
            }
        } else {
            if let filelist = sidebarRawCullViewModel?.extractRatedfilenames(rating) {
                do {
                    try writeincludefilelist(filelist, to: savePath)
                } catch {
                    Logger.process.errorMessageOnly(": Failed to write filter file: \(error)")
                }
            }
        }

        let process = RsyncProcessStreaming.RsyncProcess(
            arguments: arguments,
            hiddenID: 0,
            handlers: streamingHandlers,
            useFileHandler: true
        )

        do {
            try process.executeProcess()
            activeStreamingProcess = process
        } catch {
            Logger.process.errorMessageOnly(": executeProcess failed: \(error)")
            Task { @MainActor in
                self.cleanup()
            }
        }
    }

    @discardableResult
    init(
        configuration: SynchronizeConfiguration,
        dryrun: Bool = true,
        rating: Int = 0,
        copytaggedfiles: Bool = true,
        sidebarRawCullViewModel: RawCullViewModel
    ) {
        self.config = configuration
        self.dryrun = dryrun
        self.rating = rating
        self.sidebarRawCullViewModel = sidebarRawCullViewModel
        self.copytaggedfiles = copytaggedfiles
    }

    deinit {
        Logger.process.debugMessageOnly("ExecuteCopyFiles: DEINIT")
        // Note: Can't call async cleanup in deinit, but the URLs will be released
        // when the properties are deallocated
    }

    private func setupStreamingHandlers() {
        streamingHandlers = CreateStreamingHandlers().createHandlersWithCleanup(
            fileHandler: { [weak self] count in
                Task { @MainActor in
                    let progress = Double(count)
                    self?.onProgressUpdate?(progress)
                }
            },
            processTermination: { [weak self] output, hiddenID in
                Task { @MainActor in
                    await self?.handleProcessTermination(
                        stringoutputfromrsync: output,
                        hiddenID: hiddenID
                    )
                }
            },
            cleanup: { [weak self] in
                Logger.process.debugMessageOnly("DEBUG cleanup called")
                Task { @MainActor in
                    self?.cleanup()
                }
            }
        )
    }

    private func handleProcessTermination(stringoutputfromrsync: [String]?, hiddenID _: Int?) async {
        let linesCount = stringoutputfromrsync?.count ?? 0

        // Create view output asynchronously
        let viewOutput = await ActorCreateOutputforView().createOutputForView(stringoutputfromrsync)

        // Create the result
        let result = CopyDataResult(
            output: stringoutputfromrsync,
            viewOutput: viewOutput,
            linesCount: linesCount
        )

        // Call completion handler
        onCompletion?(result)

        // Clean up
        cleanup()
    }

    private func cleanup() {
        // Stop accessing security-scoped resources
        sourceAccessedURL?.stopAccessingSecurityScopedResource()
        destAccessedURL?.stopAccessingSecurityScopedResource()

        sourceAccessedURL = nil
        destAccessedURL = nil

        activeStreamingProcess = nil
        streamingHandlers = nil
    }

    private func writeincludefilelist(_ filelist: [String], to URLpath: URL) throws {
        let newlogadata = filelist.joined(separator: "\n") + "\n"
        guard let newdata = newlogadata.data(using: .utf8) else {
            throw NSError(domain: "ExecuteCopyFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode log data"])
        }
        do {
            try newdata.write(to: URLpath, options: .atomic)
        } catch {
            throw NSError(
                domain: "ExecuteCopyFiles",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write filelist to URL: \(error)"]
            )
        }
    }

    func getAccessedURL(fromBookmarkKey key: String, fallbackPath: String) -> URL? {
        // Try bookmark first
        if let bookmarkData = UserDefaults.standard.data(forKey: key) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                guard url.startAccessingSecurityScopedResource() else {
                    Logger.process.errorMessageOnly(": Failed to start accessing bookmark for \(key)")
                    // Try fallback instead
                    return tryFallbackPath(fallbackPath, key: key)
                }
                Logger.process.debugMessageOnly("Successfully resolved bookmark for \(key)")
                return url
            } catch {
                Logger.process.errorMessageOnly(": Bookmark resolution failed for \(key): \(error)")
                // Try fallback instead
                return tryFallbackPath(fallbackPath, key: key)
            }
        }

        // If no bookmark exists, try the fallback path
        return tryFallbackPath(fallbackPath, key: key)
    }

    private func tryFallbackPath(_ fallbackPath: String, key: String) -> URL? {
        Logger.process.warning("WARNING: No bookmark found for \(key), attempting direct path access")
        let fallbackURL = URL(fileURLWithPath: fallbackPath)
        guard fallbackURL.startAccessingSecurityScopedResource() else {
            Logger.process.errorMessageOnly(": Failed to access fallback path for \(key)")
            return nil
        }
        Logger.process.debugMessageOnly("Successfully accessed fallback path for \(key)")
        return fallbackURL
    }
}
