import AppKit
import Foundation
import MCP

enum AnalysisTools {
    private static let defaultLimit = 10
    private static let maximumLimit = 25
    private static let uuid: Value = .object(["type": .string("string"), "format": .string("uuid")])

    private static func tool(
        _ name: String, _ description: String, required: [String: Value], optional: [String: Value] = [:]
    ) -> Tool {
        Tool(name: name, description: description, inputSchema: .object([
            "type": .string("object"),
            "properties": .object(required.merging(optional) { first, _ in first }),
            "required": .array(required.keys.sorted().map(Value.string)),
            "additionalProperties": .bool(false),
        ]))
    }

    static let start = tool(
        "start_catalog_analysis",
        "Open RawCull and queue analysis of the authorized catalog. Generate a requestId UUID and reuse it if retrying this request.",
        required: ["catalogId": uuid, "requestId": uuid]
    )
    static let status = tool(
        "get_analysis_status", "Read the current analysis job's progress and coverage.",
        required: ["catalogId": uuid, "jobId": uuid]
    )
    static let cancel = tool(
        "cancel_analysis", "Request cancellation of the current analysis job.",
        required: ["catalogId": uuid, "jobId": uuid]
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
    static let all = [start, status, cancel, bursts]

    static func call(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let isStart = params.name == start.name
        let idKey = isStart ? "requestId" : "jobId"
        let keys = params.name == bursts.name ? ["catalogId", idKey, "limit", "cursor"] : ["catalogId", idKey]
        guard let arguments = params.arguments, Set(arguments.keys).isSubset(of: keys),
              let catalogId = arguments["catalogId"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let jobId = arguments[idKey]?.stringValue.flatMap(UUID.init(uuidString:))
        else { throw MCPError.invalidParams("Provide catalogId and \(idKey) UUIDs.") }

        let store = AnalysisJobStore(directory: grantStore.directory)
        try requireAnalysisGrant(catalogId)
        do {
            let current = try store.expireInterruptedJob()
            let job: AnalysisJob
            if isStart {
                job = try await submit(catalogId: catalogId, jobId: jobId, store: store)
            } else {
                guard let current, current.catalogId == catalogId, current.jobId == jobId else {
                    throw MCPError.invalidParams("No current job matches that catalog and job ID.")
                }
                job = params.name == cancel.name ? try requestCancellation(current, store: store) : current
            }
            _ = try requireCatalog(catalogId)
            if params.name == bursts.name {
                return try page(job, arguments: arguments)
            }
            var details = job
            details.bursts = nil
            details.previousRequestIds = nil
            return try reply(job.message ?? "Analysis job \(job.jobId): \(job.stage).", value: Value(details))
        } catch let error as MCPError {
            throw error
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
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
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
    private static func openBundledRawCull(at url: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
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
            guard current.state.isActive, !current.cancellationRequested else { return nil }
            if current.state == .running, current.heartbeatAt == nil {
                current.heartbeatAt = current.updatedAt
            }
            current.cancellationRequested = true
            if current.state == .queued {
                current.finish(.cancelled)
            }
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
        return try reply("Returned \(end - start) of \(bursts.count) ranked bursts.", value: .object([
            "catalogId": .string(job.catalogId.uuidString),
            "jobId": .string(job.jobId.uuidString),
            "coverage": Value(coverage),
            "bursts": Value(Array(bursts[start ..< end])),
            "nextCursor": end < bursts.count ? .string("\(prefix)\(end)") : .null,
        ]))
    }

    private static func reply(_ message: String, value: Value) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], structuredContent: Optional.some(value))
    }
}
