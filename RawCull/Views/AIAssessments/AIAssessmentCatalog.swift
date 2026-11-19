import Foundation
import RawCullCore
import SwiftUI
import Observation
import OSLog

nonisolated struct AIAssessmentEntry: Identifiable, Equatable, Sendable {
    struct Frame: Identifiable, Equatable, Sendable {
        let id: String
        let source: FollowUpSourceSnapshot.Photo
        let rank: Int?
        let outcome: MCPPhotoAssessmentResult.Photo?

        var name: String { (source.relativePath as NSString).lastPathComponent }
    }

    let request: AnalysisJobStore.FollowUpRequest
    let requestedAt: Date
    let catalogName: String?
    let burstNumber: Int?
    let burstConfidence: String?
    let result: MCPPhotoAssessmentResult
    let frames: [Frame]
    let recommendation: String?
    let alternate: String?

    var id: UUID { request.id }

    @concurrent
    static func available(
        in jobs: AnalysisJobStore = AnalysisJobStore(directory: CatalogGrantStore.shared().directory),
    ) async throws -> [Self] {
        guard let snapshot = try jobs.readBurstAssessmentResults() else { return [] }
        let decoder = JSONDecoder()
        let confidenceByBurst = Dictionary(
            (snapshot.job.bursts ?? []).map { ($0.id, $0.confidence) },
            uniquingKeysWith: { first, _ in first },
        )
        var rejections: [UUID: String] = [:]
        let entries = snapshot.results.compactMap { record, bytes -> Self? in
            let request = record.request
            guard let burstID = request.target.burstID,
                  let burst = snapshot.source.bursts[burstID],
                  let ids = try? request.target.photoIDs(in: snapshot.source) else {
                rejections[request.id] = "Invalid burst target or source snapshot"
                return nil
            }
            let result: MCPPhotoAssessmentResult
            do {
                result = try decoder.decode(MCPPhotoAssessmentResult.self, from: bytes)
            } catch {
                rejections[request.id] = "Result JSON could not be decoded"
                return nil
            }
            guard result.resultSchemaVersion == 1 else {
                rejections[request.id] = "Unsupported result schema version"
                return nil
            }
            guard result.requestId == request.id, result.sourceJobId == request.sourceJobID,
                  result.burstId == burstID, result.burstFrameCount == burst.photoIDs.count,
                  Set(result.photos.map(\.photoId)) == Set(ids), result.photos.count == ids.count,
                  result.photos.allSatisfy({ $0.sourceRank == burst.ranks[$0.photoId] }),
                  result.assessedCount > 0,
                  result.assessedCount == result.photos.filter({ $0.findings != nil }).count,
                  result.failedCount == ids.count - result.assessedCount else {
                rejections[request.id] = "Result identity, photo membership, ranks, or assessment counts do not match the request"
                return nil
            }

            let outcomes = Dictionary(uniqueKeysWithValues: result.photos.map { ($0.photoId, $0) })
            let frames = burst.photoIDs.compactMap { id -> Frame? in
                guard let photo = snapshot.source.photos[id] else { return nil }
                return Frame(id: id, source: photo, rank: burst.ranks[id], outcome: outcomes[id])
            }
            guard frames.count == burst.photoIDs.count, Set(frames.map(\.id)).count == frames.count else {
                rejections[request.id] = "Burst frames are missing or duplicated in the source snapshot"
                return nil
            }
            return Self(
                request: request, requestedAt: record.createdAt, catalogName: snapshot.job.catalogDisplayName,
                burstNumber: Int(burstID.split(separator: ":").last ?? ""),
                burstConfidence: confidenceByBurst[burstID], result: result, frames: frames, recommendation: burst.recommendedPhotoID,
                alternate: burst.alternatePhotoID == burst.recommendedPhotoID ? nil : burst.alternatePhotoID,
            )
        }
        await AIAssessmentRejectionLog.shared.report(rejections)
        return entries
    }

    @concurrent
    func isAvailable() async -> Bool {
        let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
        return (try? jobs.readFollowUpResult(id)) != nil
    }
}

// Polling should report new failures without repeating the same warning every second.
private actor AIAssessmentRejectionLog {
    static let shared = AIAssessmentRejectionLog()
    private let logger = Logger(subsystem: "no.blogspot.RawCull", category: "AIAssessments")
    private var previous: [UUID: String] = [:]

    func report(_ rejections: [UUID: String]) {
        for (id, reason) in rejections where previous[id] != reason {
            logger.warning("Rejected assessment \(id.uuidString, privacy: .public): \(reason, privacy: .public)")
        }
        previous = rejections
    }
}

@MainActor @Observable
final class AIAssessmentNavigation {
    static let windowID = "ai-assessments"
    enum Destination: Equatable {
        case result(UUID)
    }

    var destination: Destination?
    var entries: [AIAssessmentEntry] = []

    func observeResults() async {
        while !Task.isCancelled {
            do { entries = try await AIAssessmentEntry.available() }
            catch AnalysisJobStore.StoreError.busy { }
            catch { entries = [] }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

}
struct BurstAssessmentButton: View {
    let viewModel: RawCullViewModel
    let files: [FileItem]
    @Environment(AIAssessmentNavigation.self) private var navigation: AIAssessmentNavigation?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let navigation, let catalog = viewModel.selectedSource?.url,
           let entry = navigation.entries.first(where: { $0.matches(files: files, catalog: catalog) }) {
            Button {
                navigation.destination = .result(entry.id)
                openWindow(id: AIAssessmentNavigation.windowID)
            } label: {
                Label("View AI Assessment", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
        }
    }
}

extension AIAssessmentEntry {
    func matches(files: [FileItem], catalog: URL) -> Bool {
        guard !frames.isEmpty, files.count == frames.count else { return false }
        let byURL = Dictionary(files.map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { first, _ in first })
        return frames.allSatisfy { frame in
            let url = catalog.appendingPathComponent(frame.source.relativePath).standardizedFileURL
            guard let file = byURL[url] else { return false }
            return file.size == frame.source.size && file.dateModified == frame.source.modified
        }
    }
}
