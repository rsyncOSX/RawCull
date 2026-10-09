import Foundation

nonisolated enum ReleaseRunError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(text): text }
    }
}

nonisolated struct ReleaseRunConfiguration {
    let directory: URL
    let qwenPath: String?
    let samPath: String?
    let modelRoots: [URL]

    init(environment: [String: String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directory = URL(fileURLWithPath: environment["RAWCULL_RELEASE_DIRECTORY"] ?? home.appendingPathComponent("Downloads").path, isDirectory: true)
        qwenPath = environment["RAWCULL_RELEASE_QWEN"].flatMap { $0.isEmpty ? nil : $0 }
        samPath = environment["RAWCULL_RELEASE_SAM3"].flatMap { $0.isEmpty ? nil : $0 }
        modelRoots = [
            home.appendingPathComponent("ModelAssets/Release/Models"),
            home.appendingPathComponent("Library/Application Support/RawCull/Models"),
            home.appendingPathComponent("Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models")
        ]
    }

    static func discoverARWFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { url in
                guard url.pathExtension.lowercased() == "arw" else { return false }
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func modelURL(override: String?, relativePath: String, option: String) throws -> URL {
        let candidates = override.map { [URL(fileURLWithPath: $0, isDirectory: true)] }
            ?? modelRoots.map { $0.appendingPathComponent(relativePath, isDirectory: true) }
        for url in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        throw ReleaseRunError.message("Model bundle missing. Set \(option)=\"/path/to/model\" when invoking make releastest. Checked: \(candidates.map(\.path).joined(separator: ", "))")
    }
}
