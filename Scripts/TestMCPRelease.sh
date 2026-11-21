#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package=$(mktemp -d "${TMPDIR:-/tmp}/rawcull-mcp-release.XXXXXX")
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/Sources/RawCull" "$package/Tests/RawCullTests"

store_sources="$repo/Tools/RawCullMCP/Sources/RawCullMCP"
for source in AnalysisJob.swift AnalysisJobStore.swift AnalysisJobStore+FollowUps.swift CatalogSetupStore.swift \
    MCPAssessmentStopReason.swift CatalogGrantStore.swift; do
    cp "$store_sources/$source" "$package/Sources/RawCull/"
done
cp "$repo/RawCull/Intelligence/Qwen/QwenPhotoAssessment.swift" "$package/Sources/RawCull/"
cp "$repo/RawCullTests/MCPJobLifecycleTests.swift" "$package/Tests/RawCullTests/"

# Compile the shared stores in Release without bringing in app tests that depend on DEBUG hooks.
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RawCullMCPReleaseTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RawCull"),
        .testTarget(name: "RawCullTests", dependencies: ["RawCull"])
    ]
)
SWIFT

swift test --package-path "$package" -c release "$@"
