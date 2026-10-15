import Foundation

/// A live, read-only adapter over culling data. Reads participate in the source
/// model's observation tracking; no second copy of saved state is maintained.
@MainActor
struct SavedFilesPresentation {
    private let cullingModel: CullingModel

    init(cullingModel: CullingModel) {
        self.cullingModel = cullingModel
    }

    var catalogs: [SavedCatalogPresentation] {
        cullingModel.savedFiles.map(SavedCatalogPresentation.init)
    }

    func records(in catalogID: UUID?) -> [SavedFileRowPresentation] {
        catalog(withID: catalogID)?.filerecords?.map(SavedFileRowPresentation.init) ?? []
    }

    func detail(in catalogID: UUID?, recordID: UUID?) -> SavedFileDetailPresentation? {
        guard let recordID,
              let record = catalog(withID: catalogID)?.filerecords?.first(where: { $0.id == recordID })
        else { return nil }
        return SavedFileDetailPresentation(record)
    }

    func recordsTitle(in catalogID: UUID?) -> String {
        catalog(withID: catalogID)?.catalog?.lastPathComponent ?? "Files"
    }

    private func catalog(withID id: UUID?) -> SavedFiles? {
        guard let id else { return nil }
        return cullingModel.savedFiles.first { $0.id == id }
    }
}

struct SavedCatalogPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let dateStarted: String?
    let fileCount: Int

    fileprivate init(_ entry: SavedFiles) {
        id = entry.id
        name = entry.catalog?.lastPathComponent ?? "Unknown Catalog"
        dateStarted = entry.dateStart.flatMap { $0.isEmpty ? nil : $0 }
        fileCount = entry.filerecords?.count ?? 0
    }
}

struct SavedFileRowPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let dateTagged: String?
    let rating: Int?

    fileprivate init(_ record: FileRecord) {
        id = record.id
        name = record.fileName ?? "Unnamed File"
        dateTagged = record.dateTagged
        rating = record.rating
    }
}

struct SavedFileDetailPresentation: Equatable {
    let name: String
    let dateTagged: String
    let dateCopied: String
    let rating: Int?
    let sharpness: String?
    let subject: String?

    fileprivate init(_ record: FileRecord) {
        name = record.fileName ?? "Unnamed File"
        dateTagged = record.dateTagged ?? "—"
        dateCopied = record.dateCopied ?? "—"
        rating = record.rating
        sharpness = record.sharpnessScore.map { String(format: "%.2f", $0) }
        subject = record.saliencySubject
    }
}
