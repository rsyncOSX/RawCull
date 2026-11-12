import Foundation
import MCP

let version = "0.3.0"
let emptyArguments: Value = .object([
    "type": .string("object"),
    "properties": .object([:]),
    "additionalProperties": .bool(false),
])
let statusTool = Tool(
    name: "rawcull_status",
    description: "Report the RawCull MCP helper version and available capabilities.",
    inputSchema: emptyArguments
)
let listCatalogsTool = Tool(
    name: "list_catalogs",
    description: "List the catalog RawCull has authorized for MCP access.",
    inputSchema: emptyArguments
)
let catalogSummaryTool = Tool(
    name: "catalog_summary",
    description: "Read the authorized catalog's saved scan summary. Use the ID from list_catalogs.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object(["catalogId": .object(["type": .string("string"), "format": .string("uuid")])]),
        "required": .array([.string("catalogId")]),
        "additionalProperties": .bool(false),
    ])
)
let availableTools = [statusTool, listCatalogsTool, catalogSummaryTool]
let grantStore = CatalogGrantStore.shared()

func readCatalogGrant() throws -> CatalogGrant? {
    do {
        return try grantStore.authorizedCatalog()
    } catch {
        throw MCPError.internalError("The RawCull MCP catalog grant could not be read.")
    }
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
    if params.name == catalogSummaryTool.name {
        guard let arguments = params.arguments, arguments.count == 1,
              case let .string(id)? = arguments["catalogId"], let catalogID = UUID(uuidString: id)
        else { throw MCPError.invalidParams("catalog_summary requires one catalogId UUID.") }

        guard let catalog = try readCatalogGrant(), catalog.id == catalogID else {
            throw MCPError.invalidParams("No authorized catalog matches that ID. Call list_catalogs for the current ID.")
        }
        guard let summary = catalog.summary else {
            return .init(
                content: [.text(text: "No saved scan summary. Open the catalog in RawCull, wait for the photos to load, and authorize it again.", annotations: nil, _meta: nil)],
                structuredContent: .object(["catalogId": .string(id), "scanStatus": .string("unavailable")])
            )
        }
        return .init(
            content: [.text(text: "RawCull's saved scan for \(catalog.displayName) contains \(summary.photoCount) photos as of \(summary.snapshotAt).", annotations: nil, _meta: nil)],
            structuredContent: .object([
                "catalogId": .string(catalog.id.uuidString),
                "scanStatus": .string("saved_snapshot"),
                "snapshotAt": .string(summary.snapshotAt),
                "photoCount": .int(summary.photoCount),
                "earliestCaptureDate": summary.earliestCaptureDate.map(Value.string) ?? .null,
                "latestCaptureDate": summary.latestCaptureDate.map(Value.string) ?? .null,
                "cameraCounts": .object(summary.cameraCounts.mapValues(Value.int)),
            ])
        )
    }

    guard params.arguments?.isEmpty ?? true else {
        throw MCPError.invalidParams("\(params.name) takes no arguments.")
    }

    switch params.name {
    case listCatalogsTool.name:
        let catalog = try readCatalogGrant()
        let catalogs: [Value] = catalog.map {
            [.object(["id": .string($0.id.uuidString), "displayName": .string($0.displayName)])]
        } ?? []
        return .init(
            content: [.text(
                text: catalog.map { "Authorized catalog: \($0.displayName)" } ?? "No catalog is authorized.",
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
