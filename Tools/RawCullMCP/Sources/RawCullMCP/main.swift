import Foundation
import MCP

let version = "0.5.0"
let emptyArguments: Value = .object([
    "type": .string("object"),
    "properties": .object([:]),
    "additionalProperties": .bool(false),
])
let catalogReadAnnotations = Tool.Annotations(readOnlyHint: true, openWorldHint: false)
let statusTool = Tool(
    name: "rawcull_status",
    description: "Report the RawCull MCP helper version and available capabilities.",
    inputSchema: emptyArguments,
    annotations: catalogReadAnnotations
)
let listCatalogsTool = Tool(
    name: "list_catalogs",
    description: "List the catalog RawCull has authorized for MCP access.",
    inputSchema: emptyArguments,
    annotations: catalogReadAnnotations
)
let catalogSummaryTool = Tool(
    name: "catalog_summary",
    description: "Read the authorized catalog's saved scan summary. Use the ID from list_catalogs.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object(["catalogId": .object(["type": .string("string"), "format": .string("uuid")])]),
        "required": .array([.string("catalogId")]),
        "additionalProperties": .bool(false),
    ]),
    annotations: catalogReadAnnotations
)
let photoPageSize = 50
let maximumPhotoPageSize = 100
let listPhotosTool = Tool(
    name: "list_photos",
    description: "List a page of photos in the authorized catalog's saved scan. Use the ID from list_catalogs and pass nextCursor to fetch the next page.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "catalogId": .object(["type": .string("string"), "format": .string("uuid")]),
            "limit": .object([
                "type": .string("integer"), "minimum": .int(1),
                "maximum": .int(maximumPhotoPageSize), "default": .int(photoPageSize),
            ]),
            "cursor": .object(["type": .string("string")]),
        ]),
        "required": .array([.string("catalogId")]),
        "additionalProperties": .bool(false),
    ]),
    annotations: catalogReadAnnotations
)
let availableTools = [statusTool, listCatalogsTool, catalogSummaryTool, listPhotosTool] + AnalysisTools.all
let grantStore = CatalogGrantStore.shared()

func catalogMetadataText(_ value: String) -> String {
    String(String.UnicodeScalarView(value.unicodeScalars.prefix(512).map { scalar in
        CharacterSet.controlCharacters.contains(scalar) ? " " : scalar
    }))
}

func readCatalogGrant() throws -> CatalogGrant? {
    do {
        return try grantStore.authorizedCatalog()
    } catch {
        throw MCPError.internalError("The RawCull MCP catalog grant could not be read.")
    }
}

func requireCatalog(_ id: UUID) throws -> CatalogGrant {
    guard let catalog = try readCatalogGrant(), catalog.id == id else {
        throw MCPError.invalidParams("No authorized catalog matches that ID. Call list_catalogs for the current ID.")
    }
    return catalog
}

let server = Server(
    name: "rawcull-mcp",
    version: version,
    capabilities: .init(resources: .init(), tools: .init())
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(ListResources.self) { _ in
    .init(resources: [])
}

await server.withMethodHandler(ListResourceTemplates.self) { _ in
    .init(templates: [])
}

await server.withMethodHandler(CallTool.self) { params in
    guard availableTools.contains(where: { $0.name == params.name }) else {
        throw MCPError.invalidParams("Unknown tool: \(params.name)")
    }
    do {
        return try await callKnownTool(params)
    } catch MCPError.invalidParams(let message) {
        return .init(
            content: [.text(text: message ?? "Invalid tool arguments.", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

func callKnownTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
    if AnalysisTools.all.contains(where: { $0.name == params.name }) {
        return try await AnalysisTools.call(params)
    }

    if params.name == listPhotosTool.name {
        guard let arguments = params.arguments,
              Set(arguments.keys).isSubset(of: ["catalogId", "limit", "cursor"]),
              case let .string(id)? = arguments["catalogId"], let catalogID = UUID(uuidString: id)
        else { throw MCPError.invalidParams("list_photos requires a catalogId UUID and accepts limit and cursor.") }

        guard case let .int(limit) = arguments["limit"] ?? .int(photoPageSize),
              (1 ... maximumPhotoPageSize).contains(limit)
        else { throw MCPError.invalidParams("limit must be an integer between 1 and \(maximumPhotoPageSize).") }

        let catalog = try requireCatalog(catalogID)
        guard let summary = catalog.summary, let photos = summary.photos else {
            return .init(
                content: [.text(text: "No saved photo list. Open the catalog in RawCull, wait for the photos to load, and authorize it again.", annotations: nil, _meta: nil)],
                structuredContent: .object(["catalogId": .string(catalogID.uuidString), "scanStatus": .string("unavailable")])
            )
        }

        let cursorPrefix = "\(catalogID.uuidString):"
        var start = 0
        if let cursor = arguments["cursor"] {
            guard case let .string(token) = cursor, token.hasPrefix(cursorPrefix),
                  let offset = Int(token.dropFirst(cursorPrefix.count)),
                  offset > 0, offset < photos.count
            else { throw MCPError.invalidParams("Invalid cursor. Use nextCursor from a page of this catalog snapshot.") }
            start = offset
        }

        let end = start + min(limit, photos.count - start)
        let page: [Value] = (start ..< end).map { index in
            let photo = photos[index]
            return .object([
                "id": .string("\(cursorPrefix)\(index)"),
                "name": .string(catalogMetadataText(photo.name)),
                "captureDate": photo.captureDate.map(Value.string) ?? .null,
                "camera": photo.camera.map { .string(catalogMetadataText($0)) } ?? .null,
            ])
        }
        return .init(
            content: [.text(text: "Returned \(page.count) of \(photos.count) photos from the saved scan for \(catalogMetadataText(catalog.displayName)).", annotations: nil, _meta: nil)],
            structuredContent: .object([
                "catalogId": .string(catalogID.uuidString),
                "scanStatus": .string("saved_snapshot"),
                "snapshotAt": .string(summary.snapshotAt),
                "photos": .array(page),
                "nextCursor": end < photos.count ? .string("\(cursorPrefix)\(end)") : .null,
            ])
        )
    }

    if params.name == catalogSummaryTool.name {
        guard let arguments = params.arguments, arguments.count == 1,
              case let .string(id)? = arguments["catalogId"], let catalogID = UUID(uuidString: id)
        else { throw MCPError.invalidParams("catalog_summary requires one catalogId UUID.") }

        let catalog = try requireCatalog(catalogID)
        guard let summary = catalog.summary else {
            return .init(
                content: [.text(text: "No saved scan summary. Open the catalog in RawCull, wait for the photos to load, and authorize it again.", annotations: nil, _meta: nil)],
                structuredContent: .object(["catalogId": .string(id), "scanStatus": .string("unavailable")])
            )
        }
        let cameraCounts = summary.cameraCounts.reduce(into: [String: Int]()) { counts, entry in
            counts[catalogMetadataText(entry.key), default: 0] += entry.value
        }
        var details: [String: Value] = [
            "catalogId": .string(catalog.id.uuidString),
            "scanStatus": .string("saved_snapshot"),
            "snapshotAt": .string(summary.snapshotAt),
            "photoCount": .int(summary.photoCount),
            "earliestCaptureDate": summary.earliestCaptureDate.map(Value.string) ?? .null,
            "latestCaptureDate": summary.latestCaptureDate.map(Value.string) ?? .null,
            "cameraCounts": .object(cameraCounts.mapValues(Value.int)),
        ]
        if catalog.analysisEnabled == true,
           let job = try? AnalysisJobStore(directory: grantStore.directory).read(),
           job.catalogId == catalog.id, job.state == .completed, let coverage = job.coverage {
            do {
                details["analysisCoverage"] = try Value(coverage)
            } catch {
                throw MCPError.internalError("The analysis coverage could not be encoded.")
            }
        }
        return .init(
            content: [.text(text: "RawCull's saved scan for \(catalogMetadataText(catalog.displayName)) contains \(summary.photoCount) photos as of \(summary.snapshotAt).", annotations: nil, _meta: nil)],
            structuredContent: .object(details)
        )
    }

    guard params.arguments?.isEmpty ?? true else {
        throw MCPError.invalidParams("\(params.name) takes no arguments.")
    }

    switch params.name {
    case listCatalogsTool.name:
        let catalog = try readCatalogGrant()
        let catalogs: [Value] = catalog.map {
            [.object(["id": .string($0.id.uuidString), "displayName": .string(catalogMetadataText($0.displayName)), "analysisEnabled": .bool($0.analysisEnabled == true)])]
        } ?? []
        return .init(
            content: [.text(
                text: catalog.map { "Authorized catalog: \(catalogMetadataText($0.displayName))" } ?? "No catalog is authorized.",
                annotations: nil,
                _meta: nil
            )],
            structuredContent: .object(["catalogs": .array(catalogs)])
        )
    case statusTool.name:
        break
    default:
        throw MCPError.invalidParams("Unknown tool: \(params.name)")
    }

    let capabilities = availableTools.map(\.name)
    return .init(
        content: [.text(
            text: "RawCull MCP helper \(version). Available capabilities: \(capabilities.joined(separator: ", ")). Transport: stdio.",
            annotations: nil,
            _meta: nil
        )],
        structuredContent: .object([
            "version": .string(version),
            "capabilities": .array(capabilities.map(Value.string)),
            "transport": .string("stdio"),
        ])
    )
}

try await server.start(transport: StatusStdioTransport())
await server.waitUntilCompleted()
