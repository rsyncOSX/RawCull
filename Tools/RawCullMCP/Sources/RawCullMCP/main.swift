import Foundation
import MCP

let version = "0.2.0"
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
let availableTools = [statusTool, listCatalogsTool]
let grantStore = CatalogGrantStore(
    directory: FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: CatalogGrantStore.applicationGroup
    )
)

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
    guard params.arguments?.isEmpty ?? true else {
        throw MCPError.invalidParams("\(params.name) takes no arguments.")
    }

    switch params.name {
    case listCatalogsTool.name:
        let catalog: CatalogGrant?
        do {
            catalog = try grantStore.authorizedCatalog()
        } catch {
            throw MCPError.internalError("The RawCull MCP catalog grant could not be read.")
        }
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
