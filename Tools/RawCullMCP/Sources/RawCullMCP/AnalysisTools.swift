import AppKit
import Darwin
import Foundation
import MCP

enum AnalysisTools {
    private static let defaultLimit = 10
    private static let maximumLimit = 25
    private static let uuid: Value = .object(["type": .string("string"), "format": .string("uuid")])
    private static let jobAnnotations = Tool.Annotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false
    )

    private static func tool(
        _ name: String, _ description: String, required: [String: Value], optional: [String: Value] = [:],
        annotations: Tool.Annotations = jobAnnotations
    ) -> Tool {
        Tool(name: name, description: description, inputSchema: .object([
            "type": .string("object"),
            "properties": .object(required.merging(optional) { first, _ in first }),
            "required": .array(required.keys.sorted().map(Value.string)),
            "additionalProperties": .bool(false),
        ]), annotations: annotations)
    }

    static let start = tool(
        "start_catalog_analysis",
        "Open RawCull and queue analysis of the authorized catalog. Generate a requestId UUID and reuse it if retrying this request.",
        required: ["catalogId": uuid, "requestId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
    )
    static let status = tool(
        "get_analysis_status", "Read the current analysis job's progress and coverage.",
        required: ["catalogId": uuid, "jobId": uuid]
    )
    static let cancel = tool(
        "cancel_analysis", "Request cancellation of the current analysis job.",
        required: ["catalogId": uuid, "jobId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
    )
    static let bursts = tool(
        "list_bursts", "List ranked bursts from a completed analysis. Pass nextCursor for the next page.",
        required: ["catalogId": uuid, "jobId": uuid],
        optional: [
            "limit": .object([
                "type": .string("integer"), "minimum": .int(1),
                "maximum": .int(maximumLimit), "default": .int(defaultLimit),
            ]),
            "cursor": .object(["type": .string("string")]),
        ]
    )
    static let requestSetup = tool(
        "request_catalog_setup",
        "Find a catalog by exact name or absolute path and start burst analysis if it is already authorized. RawCull asks for approval or folder selection when needed. Reuse the requestId UUID on retry.",
        required: ["catalogHint": .object(["type": .string("string")]), "jobType": .object([
            "type": .string("string"), "enum": .array([.string("burstAnalysis")]),
        ]), "requestId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
    )
    static let setupStatus = tool(
        "get_catalog_setup_status", "Read the status of a catalog setup request and find its analysis job.",
        required: ["requestId": uuid], annotations: catalogReadAnnotations
    )
    static let all = [start, status, cancel, bursts, requestSetup, setupStatus]

    private static func callSetup(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let isSubmission = params.name == requestSetup.name
        let keys: Set<String> = isSubmission ? ["requestId", "catalogHint", "jobType"] : ["requestId"]
        guard let args = params.arguments, Set(args.keys) == keys,
              let id = args["requestId"]?.stringValue.flatMap(UUID.init(uuidString:))
        else { throw MCPError.invalidParams("Provide a requestId UUID and the required setup arguments.") }

        let store = CatalogSetupStore(jobs: AnalysisJobStore(directory: grantStore.directory))
        var request: CatalogSetupRequest
        if isSubmission {
            guard let hint = args["catalogHint"]?.stringValue, args["jobType"]?.stringValue == "burstAnalysis" else {
                throw MCPError.invalidParams("Provide a catalog hint and use burstAnalysis as the job type.")
            }
            let proposed = CatalogSetupRequest(
                requestId: id, catalogHint: catalogMetadataText(hint), jobType: "burstAnalysis", createdAt: .now
            )
            do {
                request = try store.submit(proposed)
            } catch CatalogSetupStore.StoreError.pendingRequest {
                throw MCPError.invalidParams("Another catalog setup request is awaiting a response in RawCull.")
            }
            guard request.catalogHint == proposed.catalogHint, request.jobType == proposed.jobType else {
                throw MCPError.invalidParams("That requestId belongs to a different request. Use a new UUID.")
            }
            if request.state == .pendingApproval, !request.isExpired {
                if let app = bundledRawCullURL() {
                    _ = await openBundledRawCull(at: app, activates: true)
                } else {
                    request.message = "Open RawCull to respond, or configure your client to use the bundled helper."
                }
            }
        } else {
            guard let existing = try store.request(id) else {
                throw MCPError.invalidParams("No catalog setup request matches that ID.")
            }
            request = existing
        }
        if request.state == .pendingApproval, request.isExpired {
            request.state = .failed
            request.message = "The catalog setup request expired. Start a new request."
        }
        return try structuredReply(
            request.message ?? "Catalog setup: \(request.state.rawValue).", value: Value(request)
        )
    }

    static func call(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if params.name == requestSetup.name || params.name == setupStatus.name {
            do {
                return try await callSetup(params)
            } catch let error as MCPError {
                throw error
            } catch {
                throw MCPError.internalError("The RawCull catalog setup request could not be read or saved.")
            }
        }
        let isStart = params.name == start.name
        let idKey = isStart ? "requestId" : "jobId"
        let keys = params.name == bursts.name ? ["catalogId", idKey, "limit", "cursor"] : ["catalogId", idKey]
        guard let arguments = params.arguments, Set(arguments.keys).isSubset(of: keys),
              let catalogId = arguments["catalogId"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let jobId = arguments[idKey]?.stringValue.flatMap(UUID.init(uuidString:))
        else { throw MCPError.invalidParams("Provide catalogId and \(idKey) UUIDs.") }

        let store = AnalysisJobStore(directory: grantStore.directory)
        if isStart { try requireAnalysisGrant(catalogId) }
        do {
            let current = try store.readRecovering()
            let job: AnalysisJob
            if isStart {
                _ = try store.expireInterruptedJob()
                job = try await submit(catalogId: catalogId, jobId: jobId, store: store)
            } else {
                guard let current, current.catalogId == catalogId, current.jobId == jobId else {
                    throw MCPError.invalidParams("No current job matches that catalog and job ID.")
                }
                if !current.usesSetupApproval { try requireAnalysisGrant(catalogId) }
                if params.name == cancel.name {
                    job = try requestCancellation(current, store: store)
                } else {
                    guard let latest = try store.expireInterruptedJob(),
                          latest.jobId == jobId, latest.catalogId == catalogId else {
                        throw MCPError.invalidParams("That job has been replaced.")
                    }
                    job = latest
                }
            }
            if params.name == bursts.name {
                return try store.withLock {
                    guard let latest = try store.read(), latest.jobId == jobId, latest.catalogId == catalogId,
                          latest.resultCleared != true else {
                        throw MCPError.invalidParams("That job was cleared, replaced, or revoked.")
                    }
                    if !latest.usesSetupApproval { try requireAnalysisGrant(catalogId) }
                    return try page(latest, arguments: arguments)
                }
            }
            if !job.usesSetupApproval {
                _ = try requireCatalog(catalogId)
            }
            guard let latest = try store.read(), latest.jobId == jobId, latest.catalogId == catalogId,
                  latest.resultCleared != true else {
                throw MCPError.invalidParams("That job was cleared, replaced, or revoked.")
            }
            var details = latest
            details.catalogDisplayName = nil
            details.heartbeatUptime = nil
            details.heartbeatBootID = nil
            details.bursts = nil
            details.previousRequestIds = nil
            details.setupRequestId = nil
            details.usesSavedGrant = nil
            return try structuredReply(latest.message ?? "Analysis job \(latest.jobId): \(latest.stage).", value: Value(details))
        } catch let error as MCPError {
            throw error
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            throw MCPError.internalError("The analysis job uses an unsupported format. Use the helper from the current RawCull installation. If the error persists, reauthorize the catalog in RawCull settings to clear the saved job.")
        } catch {
            throw MCPError.internalError("The RawCull analysis job could not be read or updated.")
        }
    }

    private static func requireAnalysisGrant(_ catalogId: UUID) throws {
        guard try requireCatalog(catalogId).analysisEnabled == true else {
            throw MCPError.invalidParams("Enable catalog analysis when authorizing this loaded catalog in RawCull's MCP settings.")
        }
    }

    private static func submit(
        catalogId: UUID, jobId: UUID, store: AnalysisJobStore
    ) async throws -> AnalysisJob {
        let updated = try store.withLock {
            try requireAnalysisGrant(catalogId)
            return try store.updateLocked { current in
                if let current, current.catalogId == catalogId, current.jobId == jobId { return nil }
                if current?.state.isActive == true {
                    throw MCPError.invalidParams("An analysis is already active. Wait for it to finish or cancel it.")
                }
                let now = Date.now
                var next = AnalysisJob(jobId: jobId, catalogId: catalogId, createdAt: now, updatedAt: now)
                if let current, current.catalogId == catalogId {
                    let previous = current.previousRequestIds ?? []
                    guard !previous.contains(jobId) else {
                        throw MCPError.invalidParams("That request ID belongs to a replaced job. Use a new request ID.")
                    }
                    next.previousRequestIds = previous + [current.jobId]
                }
                return next
            }
        }
        guard let job = updated else { throw MCPError.internalError("The job could not be queued.") }

        if job.state == .queued {
            let url = bundledRawCullURL()
            if let url, await openBundledRawCull(at: url) { return job }
            let latest = try store.update { current in
                guard var current, current.jobId == jobId, current.catalogId == catalogId,
                      current.state == .queued else { return nil }
                if url == nil {
                    current.finish(.failed, message: "Configure the MCP client to use the helper inside RawCull.app.")
                } else {
                    current.message = "Open RawCull to start the queued analysis."
                }
                return current
            }
            if let latest, latest.catalogId == catalogId, latest.jobId == jobId { return latest }
        }
        return job
    }

    private static func bundledRawCullURL() -> URL? {
        // The helper has its own executable metadata. Read the enclosing app's
        // Info.plist directly instead of asking Bundle.main for its identity.
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var path = [CChar](repeating: 0, count: Int(size))
        guard let executable = path.withUnsafeMutableBufferPointer({ buffer -> URL? in
            guard let address = buffer.baseAddress, _NSGetExecutablePath(address, &size) == 0 else { return nil }
            return URL(fileURLWithFileSystemRepresentation: address, isDirectory: false, relativeTo: nil)
        })?.resolvingSymlinksInPath() else { return nil }
        let macOS = executable.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              app.pathExtension == "app",
              let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "no.blogspot.RawCull" else { return nil }
        return app
    }

    @MainActor
    private static func openBundledRawCull(at url: URL, activates: Bool = false) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch {
            // A running RawCull can still claim the job from the shared store.
            let launchError = error as NSError
            let diagnostic = "RawCull launch failed (\(launchError.domain) \(launchError.code)).\n"
            FileHandle.standardError.write(Data(diagnostic.utf8))
            return false
        }
    }

    private static func requestCancellation(_ job: AnalysisJob, store: AnalysisJobStore) throws -> AnalysisJob {
        let updated = try store.update { current in
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId else {
                throw MCPError.invalidParams("That job has been replaced.")
            }
            guard current.state.isActive else { return nil }
            if current.state == .queued || current.isExpired(at: .now) {
                current.cancellationRequested = true
                current.finish(.cancelled)
                return current
            }
            guard !current.cancellationRequested else { return nil }
            if current.heartbeatAt == nil {
                current.heartbeatAt = current.updatedAt
            }
            current.cancellationRequested = true
            return current
        }
        return updated ?? job
    }

    private static func page(_ job: AnalysisJob, arguments: [String: Value]) throws -> CallTool.Result {
        guard job.state == .completed, let bursts = job.bursts, let coverage = job.coverage else {
            throw MCPError.invalidParams("Bursts are available after the job completes. Check get_analysis_status.")
        }
        guard let limit = (arguments["limit"] ?? .int(defaultLimit)).intValue,
              (1 ... maximumLimit).contains(limit) else {
            throw MCPError.invalidParams("limit must be an integer between 1 and \(maximumLimit).")
        }
        let prefix = "\(job.catalogId.uuidString):\(job.jobId.uuidString):"
        var start = 0
        if let cursor = arguments["cursor"] {
            guard let token = cursor.stringValue, token.hasPrefix(prefix),
                  let offset = Int(token.dropFirst(prefix.count)), offset > 0, offset < bursts.count
            else { throw MCPError.invalidParams("Use nextCursor from a page of this analysis job.") }
            start = offset
        }
        let end = min(start + limit, bursts.count)
        let page = bursts[start ..< end].map { burst in
            var display = burst
            for index in display.candidates.indices {
                display.candidates[index].name = catalogMetadataText(display.candidates[index].name)
            }
            return display
        }
        return try structuredReply("Returned \(end - start) of \(bursts.count) ranked bursts.", value: .object([
            "catalogId": .string(job.catalogId.uuidString),
            "jobId": .string(job.jobId.uuidString),
            "coverage": Value(coverage),
            "bursts": Value(page),
            "nextCursor": end < bursts.count ? .string("\(prefix)\(end)") : .null,
        ]))
    }
}
