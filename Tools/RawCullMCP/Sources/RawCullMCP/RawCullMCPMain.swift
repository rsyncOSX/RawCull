import MCP

@main
enum RawCullMCPMain {
    static func main() async throws {
        let grantStore = CatalogGrantStore.shared()
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
                return try await callKnownTool(params, grantStore: grantStore)
            } catch MCPError.invalidParams(let message) {
                return .init(
                    content: [.text(text: message ?? "Invalid tool arguments.", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        try await server.start(transport: StatusStdioTransport())
        await server.waitUntilCompleted()
    }
}
