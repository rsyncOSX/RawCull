import MCP

let version = "0.1.0"
let statusTool = Tool(
    name: "rawcull_status",
    description: "Report the RawCull MCP helper version and available capabilities.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false),
    ])
)

let server = Server(
    name: "rawcull-mcp",
    version: version,
    capabilities: .init(resources: .init(), tools: .init())
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [statusTool])
}

await server.withMethodHandler(ListResources.self) { _ in
    .init(resources: [])
}

await server.withMethodHandler(ListResourceTemplates.self) { _ in
    .init(templates: [])
}

await server.withMethodHandler(CallTool.self) { params in
    guard params.name == statusTool.name else {
        throw MCPError.invalidParams("Unknown tool: \(params.name)")
    }
    guard params.arguments?.isEmpty ?? true else {
        throw MCPError.invalidParams("rawcull_status takes no arguments.")
    }

    return .init(
        content: [.text(text: "RawCull MCP helper \(version). Available capability: rawcull_status. Transport: stdio.", annotations: nil, _meta: nil)],
        structuredContent: .object([
            "version": .string(version),
            "capabilities": .array([.string(statusTool.name)]),
            "transport": .string("stdio"),
        ])
    )
}

try await server.start(transport: StatusStdioTransport())
await server.waitUntilCompleted()
