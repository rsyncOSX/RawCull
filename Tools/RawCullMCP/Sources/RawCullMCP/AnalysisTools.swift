import AppKit
import Darwin
import Foundation
import MCP

enum AnalysisTools {
    private static let defaultLimit = 10
    private static let maximumLimit = 25
    private static let uuid: Value = .object(["type": .string("string"), "format": .string("uuid")])
    private static let jobAnnotations = Tool.Annotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false,
    )

    private static func tool(
        _ name: String, _ description: String, required: [String: Value], optional: [String: Value] = [:],
        annotations: Tool.Annotations = jobAnnotations, outputSchema: Value? = nil,
        exactlyOneOf selectors: [String] = [],
    ) -> Tool {
        var input: [String: Value] = [
            "type": .string("object"),
            "properties": .object(required.merging(optional) { first, _ in first }),
            "required": .array(required.keys.sorted().map(Value.string)),
            "additionalProperties": .bool(false)
        ]
        if !selectors.isEmpty {
            input["oneOf"] = .array(selectors.map { .object(["required": .array([.string($0)])]) })
        }
        return Tool(name: name, description: description, inputSchema: .object(input),
                    annotations: annotations, outputSchema: outputSchema)
    }

    static let start = tool(
        "start_catalog_analysis",
        "Open RawCull and queue analysis of the authorized catalog. Generate a requestId UUID and reuse it if retrying this request.",
        required: ["catalogId": uuid, "requestId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false),
    )
    static let status = tool(
        "get_analysis_status", "Read the current analysis job's progress and coverage.",
        required: ["catalogId": uuid, "jobId": uuid],
    )
    static let cancel = tool(
        "cancel_analysis", "Request cancellation of the current analysis job.",
        required: ["catalogId": uuid, "jobId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false),
    )
    static let bursts = tool(
        "list_bursts", "List ranked bursts from a completed analysis. Pass nextCursor for the next page. For a confidence shortlist, order low, medium, then high, preserving source order within ties and leaving unknown confidence unclassified.",
        required: ["catalogId": uuid, "jobId": uuid],
        optional: [
            "limit": .object([
                "type": .string("integer"), "minimum": .int(1),
                "maximum": .int(maximumLimit), "default": .int(defaultLimit)
            ]),
            "cursor": .object(["type": .string("string")])
        ],
        annotations: .init(readOnlyHint: true, openWorldHint: false),
    )
    static let requestSetup = tool(
        "request_catalog_setup",
        "Find a catalog by exact name or absolute path (up to 512 Unicode scalars) and start burst analysis if it is already authorized. RawCull asks for approval or folder selection when needed. Reuse the requestId UUID on retry.",
        required: ["catalogHint": .object(["type": .string("string")]), "jobType": .object([
            "type": .string("string"), "enum": .array([.string("burstAnalysis")])
        ]), "requestId": uuid],
        annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false),
    )
    static let setupStatus = tool(
        "get_catalog_setup_status", "Read the setup status. When queued, use the returned catalogId and jobId with get_analysis_status. Setup already started the job.",
        required: ["requestId": uuid],
    )
    static let all = [start, status, cancel, bursts, requestSetup, setupStatus]

    private static func stringList(maximum: Int, values: [String]? = nil) -> Value {
        var item: [String: Value] = ["type": .string("string"), "maxLength": .int(128)]
        if let values {
            item["enum"] = .array(values.map(Value.string))
        }
        return .object(["type": .string("array"), "items": .object(item),
                        "minItems": .int(1), "maxItems": .int(maximum), "uniqueItems": .bool(true)])
    }

    private static let followUpStateSchema = objectSchema(required: [
        "requestId": uuid, "state": .object(["type": .string("string")]),
        "cancellationRequested": .object(["type": .string("boolean")]),
        "resultCleared": .object(["type": .string("boolean")])
    ], optional: ["errorCode": .object(["type": .string("string")])])

    private static let followUpResultSchema = objectSchema(required: [
        "requestId": uuid, "sourceJobId": uuid, "model": .object(["type": .string("string")]),
        "promptTemplateVersion": .object(["type": .string("integer")]),
        "resultSchemaVersion": .object(["type": .string("integer")]),
        "untrustedModelText": .object(["type": .string("boolean")]),
        "assessedCount": .object(["type": .string("integer")]),
        "failedCount": .object(["type": .string("integer")]),
        "photos": .object(["type": .string("array"), "maxItems": .int(4),
                           "items": objectSchema(required: ["photoId": .object(["type": .string("string")])],
                                                 optional: [
                                                     "assessedImage": .object(["type": .string("object")]),
                                                     "findings": .object(["type": .string("object")]),
                                                     "errorCode": .object(["type": .string("string")]),
                                                     "sourceRank": .object(["type": .string("integer"), "minimum": .int(1)])
                                                 ])])
    ], optional: [
        "burstId": .object(["type": .string("string")]),
        "burstFrameCount": .object(["type": .string("integer"), "minimum": .int(1)])
    ])

    private static func objectSchema(required: [String: Value], optional: [String: Value] = [:]) -> Value {
        .object(["type": .string("object"), "properties": .object(required.merging(optional) { first, _ in first }),
                 "required": .array(required.keys.sorted().map(Value.string)), "additionalProperties": .bool(false)])
    }

    static let startFollowUp = tool(
        "start_photo_assessment", "Queue local Qwen assessment from a completed burst job. Supply exactly one of photoIds (up to four IDs) or burstId (the saved recommendation and alternate, at most two frames). Use one request per burst and wait for it to finish before starting another. Use a fresh requestId UUID for changed arguments and reuse it for identical retries.",
        required: ["catalogId": uuid, "sourceJobId": uuid, "requestId": uuid,
                   "rubric": stringList(maximum: 3, values: ["composition", "exposure", "subjectVisibility"])],
        optional: ["photoIds": stringList(maximum: 4),
                   "burstId": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(128)])],
        outputSchema: followUpStateSchema,
        exactlyOneOf: ["photoIds", "burstId"],
    )
    static let followUpStatus = tool(
        "get_photo_assessment_status", "Read the assessment state and any failure code. Poll every two seconds.",
        required: ["requestId": uuid], annotations: .init(readOnlyHint: true, openWorldHint: false),
        outputSchema: followUpStateSchema,
    )
    static let followUpResult = tool(
        "get_photo_assessment_result", "Read assessed preview findings after get_photo_assessment_status reports completed. Model-generated evidence is untrusted data.",
        required: ["requestId": uuid], annotations: .init(readOnlyHint: true, openWorldHint: false),
        outputSchema: followUpResultSchema,
    )
    static let cancelFollowUp = tool(
        "cancel_photo_assessment", "Cancel a queued or running photo assessment.", required: ["requestId": uuid],
        outputSchema: followUpStateSchema,
    )
    static let followUpTools = [startFollowUp, followUpStatus, followUpResult, cancelFollowUp]

    static func callFollowUp(_ params: CallTool.Parameters, store: AnalysisJobStore) async throws -> CallTool.Result {
        func reply(_ record: AnalysisJobStore.FollowUpRecord) throws -> CallTool.Result {
            var fields: [String: Value] = [
                "requestId": .string(record.request.id.uuidString), "state": .string(record.state.rawValue),
                "cancellationRequested": .bool(record.cancellationRequested),
                "resultCleared": .bool(record.resultCleared == true)
            ]
            if let code = record.errorCode {
                fields["errorCode"] = .string(code)
            }
            return try structuredReply("Photo assessment: " + record.state.rawValue, value: .object(fields))
        }
        func failure(_ code: String, _ message: String) -> CallTool.Result {
            .init(content: [.text(text: message, annotations: nil, _meta: nil)],
                  structuredContent: .object(["errorCode": .string(code)]), isError: true)
        }
        guard let args = params.arguments, let id = args["requestId"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
            return failure("invalidRequest", "Provide a requestId UUID.")
        }
        do {
            if params.name == startFollowUp.name {
                let selectors = Set(args.keys).subtracting(["requestId", "catalogId", "sourceJobId", "rubric"])
                guard selectors == ["photoIds"] || selectors == ["burstId"],
                      let catalog = args["catalogId"]?.stringValue.flatMap(UUID.init(uuidString:)),
                      let source = args["sourceJobId"]?.stringValue.flatMap(UUID.init(uuidString:)),
                      case let .array(fields)? = args["rubric"], (1 ... 3).contains(fields.count),
                      fields.allSatisfy({ ["composition", "exposure", "subjectVisibility"].contains($0.stringValue ?? "") })
                else {
                    return failure("invalidRequest", "Provide requestId, catalogId, sourceJobId, rubric, and exactly one of photoIds or burstId.")
                }
                let target: AnalysisJobStore.FollowUpRequest.Target
                if selectors == ["burstId"] {
                    guard let burstID = args["burstId"]?.stringValue, (1 ... 128).contains(burstID.utf8.count) else {
                        return failure("invalidRequest", "Provide a nonempty burstId from list_bursts.")
                    }
                    target = .burst(burstID)
                } else {
                    guard case let .array(photos)? = args["photoIds"], (1 ... 4).contains(photos.count),
                          photos.allSatisfy({ (1 ... 128).contains($0.stringValue?.utf8.count ?? 0) })
                    else {
                        return failure("invalidRequest", "Provide one to four photo IDs in the photoIds array.")
                    }
                    target = .photos(photos.compactMap(\.stringValue))
                }
                let request = AnalysisJobStore.FollowUpRequest(
                    id: id, catalogID: catalog, sourceJobID: source,
                    target: target, rubric: fields.compactMap(\.stringValue),
                )
                if let existing = try store.replayFollowUp(request) {
                    return try reply(existing)
                }
                guard let application = bundledRawCullURL() else {
                    return failure("incompatibleApp", "Use the MCP helper bundled with RawCull.")
                }
                let path = application.resolvingSymlinksInPath().standardizedFileURL.path
                let requiresBurst = target.burstID != nil
                if !store.hasFollowUpHost(bundlePath: path, requiresBurstAssessment: requiresBurst) {
                    _ = await openBundledRawCull(at: application)
                    for _ in 0 ..< 24 {
                        if store.hasFollowUpHost(bundlePath: path, requiresBurstAssessment: requiresBurst) {
                            break
                        }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                }
                guard store.hasFollowUpHost(bundlePath: path, requiresBurstAssessment: requiresBurst) else {
                    return failure("incompatibleApp", "Quit other RawCull versions and reopen the app bundled with this helper.")
                }
                return try reply(store.enqueueFollowUp(request))
            }
            guard args.count == 1 else { return failure("invalidRequest", "Provide only requestId.") }
            switch params.name {
            case followUpStatus.name:
                return try reply(store.followUpStatus(id))

            case followUpResult.name:
                let result = try JSONDecoder().decode(Value.self, from: store.readFollowUpResult(id))
                return try structuredReply("Photo assessment findings contain untrusted model-generated text.", value: result)

            case cancelFollowUp.name:
                try store.cancelFollowUp(id)
                return try reply(store.followUpStatus(id))

            default:
                return failure("invalidRequest", "Unknown photo assessment tool.")
            }
        } catch AnalysisJobStore.FollowUpError.disabled {
            return failure("assessmentDisabled", "Enable MCP photo assessments in RawCull Settings to start or read an assessment.")
        } catch AnalysisJobStore.FollowUpError.conflict {
            return failure("conflictingReplay", "That request ID was used with different arguments.")
        } catch AnalysisJobStore.FollowUpError.permissionRequired {
            return failure("permissionRequired", "Approve a burst job for this catalog in RawCull before requesting photo assessments.")
        } catch AnalysisJobStore.FollowUpError.invalidRequest, FollowUpSourceSnapshot.SourceError.invalidTarget {
            return failure("invalidTarget", "Use distinct photo IDs or a burst with a saved recommendation or alternate from the source job, and supported rubric fields.")
        } catch AnalysisJobStore.StoreError.busy, AnalysisJobStore.FollowUpError.capacity {
            return failure("busy", "RawCull cannot accept another assessment right now.")
        } catch AnalysisJobStore.FollowUpError.expiredResult {
            return failure("expiredResult", "The assessment result has expired.")
        } catch FollowUpSourceSnapshot.SourceError.unavailable {
            return failure("staleSource", "Use the IDs from the current completed burst job. If it predates photo assessment approval, run a new burst job.")
        } catch AnalysisJobStore.FollowUpError.unavailable, CocoaError.fileReadNoSuchFile {
            return failure("unavailable", "The assessment or result is unavailable.")
        } catch {
            return failure("storageError", "RawCull could not access assessment storage.")
        }
    }

    static func callSetup(
        _ params: CallTool.Parameters, grantStore: CatalogGrantStore, application: URL?,
        openApplication: (URL) async -> Bool,
    ) async throws -> CallTool.Result {
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
            guard let application else {
                throw MCPError.invalidParams("Configure the MCP client to use the helper inside RawCull.app to start analysis.")
            }
            let proposed = CatalogSetupRequest(
                requestId: id, catalogHint: hint, jobType: "burstAnalysis", createdAt: .now, usesExactHint: true,
            )
            let submission: CatalogSetupStore.Submission
            do {
                submission = try store.submit(proposed)
            } catch CatalogSetupStore.StoreError.invalidHint {
                throw MCPError.invalidParams(
                    "catalogHint must contain at most \(CatalogSetupRequest.maximumHintScalars) Unicode scalars.",
                )
            } catch CatalogSetupStore.StoreError.pendingRequest {
                throw MCPError.invalidParams("Another catalog setup request is awaiting a response in RawCull.")
            } catch let CatalogSetupStore.StoreError.storageFull(retryAt) {
                let retry = retryAt.map { "Try again after \($0.ISO8601Format())." }
                    ?? "Try again when an older request ages out."
                throw MCPError.invalidParams("The catalog setup replay store is full. \(retry)")
            } catch let CatalogSetupStore.StoreError.denialCooldown(secondsRemaining) {
                throw MCPError.invalidParams("A catalog setup request was declined. Wait at least \(secondsRemaining) seconds and try again if the user wants to proceed.")
            }
            request = submission.request
            guard request.matches(proposed) else {
                throw MCPError.invalidParams("That requestId belongs to a different request. Use a new UUID.")
            }
            if request.state == .pendingApproval, !request.isExpired,
               await !openApplication(application) {
                request.message = "Open RawCull to respond, or configure your client to use the bundled helper."
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
        request.catalogHint = request.catalogHint.map(catalogMetadataText)
        request.usesExactHint = nil
        request.hintDigest = nil
        request.deniedAt = nil
        let message = request.state == .queued
            ? "Catalog setup queued the burst job. Poll get_analysis_status with the returned catalogId and jobId."
            : "Catalog setup: \(request.state.rawValue)."
        return try structuredReply(request.message ?? message, value: Value(request))
    }

    static func call(
        _ params: CallTool.Parameters, grantStore: CatalogGrantStore,
    ) async throws -> CallTool.Result {
        if params.name == requestSetup.name || params.name == setupStatus.name {
            do {
                return try await callSetup(
                    params, grantStore: grantStore, application: bundledRawCullURL(),
                    openApplication: openBundledRawCull,
                )
            } catch CatalogSetupStore.StoreError.expiredRequest {
                throw MCPError.invalidParams("That catalog setup request is outside the replay window. Use a fresh UUID for a new run.")
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
        if isStart {
            guard bundledRawCullURL() != nil else {
                throw MCPError.invalidParams("Configure the MCP client to use the helper inside RawCull.app to start analysis.")
            }
            try requireAnalysisGrant(catalogId, in: grantStore)
        }
        do {
            if params.name == bursts.name {
                return try store.withLock {
                    guard let latest = try store.read(), latest.jobId == jobId, latest.catalogId == catalogId,
                          latest.resultCleared != true
                    else {
                        throw MCPError.invalidParams("That job was cleared, replaced, or revoked.")
                    }
                    if !latest.usesSetupApproval {
                        try requireAnalysisGrant(catalogId, in: grantStore)
                    }
                    return try page(latest, arguments: arguments)
                }
            }
            let current = try store.readRecovering()
            let job: AnalysisJob
            if isStart {
                _ = try store.expireInterruptedJob()
                job = try await submit(catalogId: catalogId, jobId: jobId, store: store, grantStore: grantStore)
            } else {
                guard let current, current.catalogId == catalogId, current.jobId == jobId else {
                    throw MCPError.invalidParams("No current job matches that catalog and job ID.")
                }
                if !current.usesSetupApproval {
                    try requireAnalysisGrant(catalogId, in: grantStore)
                }
                if params.name == cancel.name {
                    job = try requestCancellation(current, store: store)
                } else {
                    guard let latest = try store.expireInterruptedJob(),
                          latest.jobId == jobId, latest.catalogId == catalogId
                    else {
                        throw MCPError.invalidParams("That job has been replaced.")
                    }
                    job = latest
                }
            }
            if !job.usesSetupApproval {
                _ = try requireCatalog(catalogId, in: grantStore)
            }
            guard let latest = try store.read(), latest.jobId == jobId, latest.catalogId == catalogId,
                  latest.resultCleared != true
            else {
                throw MCPError.invalidParams("That job was cleared, replaced, or revoked.")
            }
            var details = latest
            details.catalogDisplayName = nil
            details.heartbeatUptime = nil
            details.heartbeatBootID = nil
            details.bursts = nil
            details.previousRequestIds = nil
            details.setupRequestId = nil
            details.setupHintDigest = nil
            details.usesSavedGrant = nil
            details.allowsJobPhotoAccess = nil
            if latest.usesWorkerLease, latest.isExpired(at: .now), details.message == nil {
                details.message = "RawCull still owns this job, but its last heartbeat is stale."
            }
            return try structuredReply(details.message ?? "Analysis job \(latest.jobId): \(latest.stage).", value: Value(details))
        } catch let error as MCPError {
            throw error
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            throw MCPError.internalError("The analysis job uses an unsupported format. Use the helper from the current RawCull installation.")
        } catch AnalysisJobStore.StoreError.busy {
            throw MCPError.internalError("RawCull MCP job storage is busy. Retry this call.")
        } catch AnalysisJobStore.StoreError.damagedActiveJob {
            throw MCPError.internalError("The active RawCull job record could not be decoded. Retry after the worker exits.")
        } catch {
            throw MCPError.internalError("The RawCull analysis job could not be read or updated.")
        }
    }

    private static func requireAnalysisGrant(_ catalogId: UUID, in grantStore: CatalogGrantStore) throws {
        guard try requireCatalog(catalogId, in: grantStore).analysisEnabled == true else {
            throw MCPError.invalidParams("Enable catalog analysis when authorizing this loaded catalog in RawCull's MCP settings.")
        }
    }

    private static func submit(
        catalogId: UUID, jobId: UUID, store: AnalysisJobStore, grantStore: CatalogGrantStore,
    ) async throws -> AnalysisJob {
        let updated = try store.withLock {
            try requireAnalysisGrant(catalogId, in: grantStore)
            return try store.updateLocked { current in
                if let current, current.catalogId == catalogId, current.jobId == jobId {
                    return nil
                }
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
                    next.previousRequestIds = current.nextDirectRequestHistory()
                }
                return next
            }
        }
        guard let job = updated else { throw MCPError.internalError("The job could not be queued.") }

        if job.state == .queued {
            let url = bundledRawCullURL()
            if let url, await openBundledRawCull(at: url) {
                return job
            }
            let latest = try store.update { current in
                guard var current, current.jobId == jobId, current.catalogId == catalogId,
                      current.state == .queued else { return nil }
                current.message = "Open RawCull to start the queued analysis."
                return current
            }
            if let latest, latest.catalogId == catalogId, latest.jobId == jobId {
                return latest
            }
        }
        return job
    }

    static func bundledRawCullURL() -> URL? {
        bundledRawCull()?.url
    }

    static func bundledRawCullBuild() -> String? {
        bundledRawCull()?.build
    }

    private static func bundledRawCull() -> (url: URL, build: String?)? {
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
        return (app, info["CFBundleVersion"] as? String)
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
            guard current.state.isActive else { return nil }
            if current.state == .queued || (!current.usesWorkerLease && current.isExpired(at: .now)) {
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
              (1 ... maximumLimit).contains(limit)
        else {
            throw MCPError.invalidParams("limit must be an integer between 1 and \(maximumLimit).")
        }
        let prefix = job.burstCursorPrefix
        var start = 0
        if let cursor = arguments["cursor"] {
            guard let token = cursor.stringValue,
                  let offset = job.burstCursorOffset(token, count: bursts.count)
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
            "nextCursor": end < bursts.count ? .string("\(prefix)\(end)") : .null
        ]))
    }
}
