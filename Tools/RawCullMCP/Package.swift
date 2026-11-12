// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RawCullMCP",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "rawcull-mcp", targets: ["RawCullMCP"])],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .executableTarget(name: "RawCullMCP", dependencies: [
            .product(name: "MCP", package: "swift-sdk"),
        ]),
    ],
)
