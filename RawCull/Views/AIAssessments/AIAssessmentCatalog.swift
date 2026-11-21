import Foundation
import Observation
import OSLog
import RawCullCore
import SwiftUI

nonisolated struct AIAssessmentEntry: Identifiable, Equatable, Sendable {
    struct Frame: Identifiable, Equatable, Sendable {
        let id: String
        let source: FollowUpSourceSnapshot.Photo
        let rank: Int?
        let outcome: MCPPhotoAssessmentResult.Photo?

        var name: String {
            (source.relativePath as NSString).lastPathComponent
        }
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

    var id: UUID {
        request.id
    }

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
                  let ids = try? request.target.photoIDs(in: snapshot.source)
            else {
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
                  result.failedCount == ids.count - result.assessedCount
            else {
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

/// Polling should report new failures without repeating the same warning every second.
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
    var presentedID: UUID? {
        didSet {
            if presentedID != oldValue {
                initialPair = nil
            }
        }
    }

    private(set) var returnsToBurstViewer = false
    private(set) var initialPair: (recommended: String, sharpest: String)?

    func openFromBurstList(_ id: UUID) {
        returnsToBurstViewer = false
        presentedID = id
    }

    func compareSharpness(in entry: AIAssessmentEntry, recommended: String, sharpest: String) {
        returnsToBurstViewer = true
        presentedID = entry.id
        initialPair = (recommended, sharpest)
    }

    func entry(matching files: [FileItem], catalog: URL) -> AIAssessmentEntry? {
        entries.first { $0.matches(files: files, catalog: catalog) }
    }

    private(set) var entries: [AIAssessmentEntry] = []
    private(set) var loadFailed = false

    func observeResults() async {
        while !Task.isCancelled {
            do {
                let latest = try await AIAssessmentEntry.available()
                guard !Task.isCancelled else { return }
                if latest != entries {
                    entries = latest
                }
                loadFailed = false
            } catch AnalysisJobStore.StoreError.busy {
                // The writer still owns the store. Retry without changing selection.
            } catch FollowUpSourceSnapshot.SourceError.unavailable {
                entries = []
                loadFailed = false
            } catch {
                entries = []
                loadFailed = true
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}

struct BurstAssessmentButton: View {
    let catalog: CatalogWorkspace
    let files: [FileItem]
    @Environment(AIAssessmentNavigation.self) private var navigation: AIAssessmentNavigation?

    var body: some View {
        if let navigation, let catalogURL = catalog.selectedSource?.url,
           let entry = navigation.entry(matching: files, catalog: catalogURL)
        {
            Button {
                navigation.openFromBurstList(entry.id)
            } label: {
                Label("View AI Assessment", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
        }
    }
}

extension AIAssessmentEntry.Frame {
    func summary(for rubric: [String]) -> String? {
        guard let findings = outcome?.findings else { return nil }
        let fields = ["composition"] + rubric.filter { $0 != "composition" }
        return fields.lazy.compactMap { field in
            findings[field]?.evidence?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.first { !$0.isEmpty }
    }
}

extension AIAssessmentEntry {
    func frame(for file: FileItem, in catalog: URL) -> Frame? {
        frames.first {
            catalog.appendingPathComponent($0.source.relativePath).standardizedFileURL == file.url.standardizedFileURL
                && $0.source.size == file.size && $0.source.modified == file.dateModified
        }
    }

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
