// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "PhotoAIKit",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "PhotoAIContracts", targets: ["PhotoAIContracts"]),
        .library(name: "CoreAICLIPBackend", targets: ["CoreAICLIPBackend"]),
        .library(name: "CoreAISAM3Backend", targets: ["CoreAISAM3Backend"]),
        .library(name: "VisionFeaturePrintBackend", targets: ["VisionFeaturePrintBackend"]),
        .library(name: "PhotoAIWorkflows", targets: ["PhotoAIWorkflows"]),
        .library(name: "PhotoAIStorage", targets: ["PhotoAIStorage"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/coreai-models.git",
            revision: "bffc38fe48f50e4e962ac9772b64a5b55a605286"
        )
    ],
    targets: [
        .target(name: "PhotoAIContracts"),
        .target(
            name: "CoreAICLIPBackend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
        .target(
            name: "CoreAISAM3Backend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
        .target(
            name: "VisionFeaturePrintBackend",
            dependencies: ["PhotoAIContracts"]
        ),
        .target(
            name: "PhotoAIWorkflows",
            dependencies: ["PhotoAIContracts"]
        ),
        .target(
            name: "PhotoAIStorage",
            dependencies: ["PhotoAIContracts"]
        ),
        .testTarget(
            name: "PhotoAIKitTests",
            dependencies: [
                "PhotoAIContracts",
                "PhotoAIWorkflows",
                "PhotoAIStorage",
                "CoreAICLIPBackend",
                "CoreAISAM3Backend",
                "VisionFeaturePrintBackend",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
