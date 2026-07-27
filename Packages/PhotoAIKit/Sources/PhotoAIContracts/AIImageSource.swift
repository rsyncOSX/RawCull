import Foundation

/// Package-owned source value. Host applications map their photo model to this type.
public struct AIImageSource: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let displayName: String

    public init(id: UUID, url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
    }
}

public struct SourceFileIdentity: Codable, Hashable, Sendable {
    public let fileSize: Int64?
    public let modificationDate: Date?

    public init(fileSize: Int64?, modificationDate: Date?) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public static func read(from url: URL) -> SourceFileIdentity {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return SourceFileIdentity(
            fileSize: (attributes?[.size] as? NSNumber)?.int64Value,
            modificationDate: attributes?[.modificationDate] as? Date
        )
    }
}
