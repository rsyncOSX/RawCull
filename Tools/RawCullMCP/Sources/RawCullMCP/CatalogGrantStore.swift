import Foundation

struct CatalogGrant: Decodable {
    let id: UUID
    let displayName: String
}

struct CatalogGrantStore: Sendable {
    static let applicationGroup = "93M47F4H9T.no.blogspot.RawCull.mcp"

    let directory: URL?

    func authorizedCatalog() throws -> CatalogGrant? {
        guard let directory else { throw StoreError.unavailable }

        let manifest = directory.appendingPathComponent("catalog-grant.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A missing manifest means integration is disabled or access was revoked.
            return nil
        }

        return try JSONDecoder().decode(CatalogGrant.self, from: data)
    }

    enum StoreError: Error {
        case unavailable
    }
}
