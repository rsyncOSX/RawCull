import Foundation

struct CatalogGrant: Codable {
    let id: UUID
    let displayName: String
    let summary: CatalogSummary?
}

struct CatalogSummary: Codable {
    let photoCount: Int
    let earliestCaptureDate: String?
    let latestCaptureDate: String?
    let cameraCounts: [String: Int]
    let snapshotAt: String
    let photos: [CatalogPhoto]?
}

struct CatalogPhoto: Codable {
    let name: String
    let captureDate: String?
    let camera: String?
}

struct CatalogGrantStore: Sendable {
    static let applicationGroup = "93M47F4H9T.no.blogspot.RawCull.mcp"

    let directory: URL?

    static func shared() -> Self {
        Self(directory: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroup
        ))
    }

    private func manifestURL() throws -> URL {
        guard let directory else { throw StoreError.unavailable }
        return directory.appendingPathComponent("catalog-grant.json")
    }

    func authorizedCatalog() throws -> CatalogGrant? {
        let manifest = try manifestURL()
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A missing manifest means integration is disabled or access was revoked.
            return nil
        }

        return try JSONDecoder().decode(CatalogGrant.self, from: data)
    }

    func authorize(displayName: String, summary: CatalogSummary?) throws -> CatalogGrant {
        let manifest = try manifestURL()
        let grant = CatalogGrant(id: UUID(), displayName: displayName, summary: summary)
        try JSONEncoder().encode(grant).write(to: manifest, options: .atomic)
        return grant
    }

    func revoke() throws {
        let manifest = try manifestURL()
        do {
            try FileManager.default.removeItem(at: manifest)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // An already absent manifest is revoked.
        }
    }

    enum StoreError: Error {
        case unavailable
    }
}
