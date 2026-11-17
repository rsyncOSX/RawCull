#if DEBUG
import Foundation
import Observation

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
        return snapshot.results.compactMap { record, bytes in
            let request = record.request
            guard let burstID = request.target.burstID,
                  let burst = snapshot.source.bursts[burstID],
                  let ids = try? request.target.photoIDs(in: snapshot.source),
                  let result = try? decoder.decode(MCPPhotoAssessmentResult.self, from: bytes),
                  result.resultSchemaVersion == 1,
                  result.requestId == request.id, result.sourceJobId == request.sourceJobID,
                  result.burstId == burstID, result.burstFrameCount == burst.photoIDs.count,
                  Set(result.photos.map(\.photoId)) == Set(ids), result.photos.count == ids.count,
                  result.photos.allSatisfy({ $0.sourceRank == burst.ranks[$0.photoId] }),
                  result.assessedCount > 0,
                  result.assessedCount == result.photos.filter({ $0.findings != nil }).count,
                  result.failedCount == ids.count - result.assessedCount else { return nil }

            let outcomes = Dictionary(uniqueKeysWithValues: result.photos.map { ($0.photoId, $0) })
            let frames = burst.photoIDs.compactMap { id -> Frame? in
                guard let photo = snapshot.source.photos[id] else { return nil }
                return Frame(id: id, source: photo, rank: burst.ranks[id], outcome: outcomes[id])
            }
            guard frames.count == burst.photoIDs.count, Set(frames.map(\.id)).count == frames.count else { return nil }
            return Self(
                request: request, requestedAt: record.createdAt, catalogName: snapshot.job.catalogDisplayName,
                burstNumber: Int(burstID.split(separator: ":").last ?? ""),
                burstConfidence: confidenceByBurst[burstID], result: result, frames: frames, recommendation: burst.recommendedPhotoID,
                alternate: burst.alternatePhotoID == burst.recommendedPhotoID ? nil : burst.alternatePhotoID,
            )
        }
    }

    @concurrent
    func isAvailable() async -> Bool {
        let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
        return (try? jobs.readFollowUpResult(id)) != nil
    }
}

@MainActor @Observable
final class AIAssessmentNavigation {
    static let windowID = "ai-assessments"
    enum Destination: Equatable {
        case list
        case result(UUID)
    }

    var destination: Destination?
}
#endif
