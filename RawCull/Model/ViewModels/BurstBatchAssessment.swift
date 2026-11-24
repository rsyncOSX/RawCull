//
//  BurstBatchAssessment.swift
//  RawCull
//
//  Runs the local Qwen photo assessment on the recommended and alternate
//  frames of every burst in the open catalog — the in-app counterpart of
//  Scripts/AssessBursts.py. Results are session-only `AIAssessmentEntry`
//  values shown in the existing AI Assessment workspace.
//

import CoreGraphics
import Foundation
import Observation
import OSLog
import RawCullCore

@Observable @MainActor
final class BurstBatchAssessment {
    /// Same rubric as Scripts/AssessBursts.py.
    static let rubric = ["composition", "exposure", "subjectVisibility"]

    enum Phase: Equatable {
        case idle
        case preparing
        case running
        case cancelling
        case finished
        case cancelled
        case failed(String)
    }

    /// One burst to assess, captured when the run starts.
    nonisolated struct Frame: Sendable {
        let photoID: String
        let url: URL
        let photo: FollowUpSourceSnapshot.Photo
        let rank: Int?
    }

    nonisolated struct Item: Sendable {
        let groupID: Int
        let confidence: String
        /// Members in burst order, with catalog-relative identity.
        let frames: [Frame]
        let recommended: String?
        let alternate: String?

        var targets: [String] {
            [recommended, alternate == recommended ? nil : alternate].compactMap { $0 }
        }
    }

    nonisolated struct Plan: Sendable {
        let catalog: URL
        let catalogName: String
        let generation: Int
        let items: [Item]
    }

    private(set) var phase: Phase = .idle
    private(set) var completedBursts = 0
    private(set) var totalBursts = 0
    private(set) var assessedPhotos = 0
    private(set) var failedPhotos = 0
    private(set) var currentGroupID: Int?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let qwen: (any MCPPhotoAssessing)?
    @ObservationIgnored private let prepareModel: @MainActor () async -> Void
    @ObservationIgnored private let lease: CombinedReviewLease
    /// Why Qwen can't run on this Mac, or nil.
    let unavailableReason: String?

    init(
        qwen: (any MCPPhotoAssessing)?,
        prepareModel: @escaping @MainActor () async -> Void,
        unavailableReason: String? = nil,
        lease: CombinedReviewLease = .shared,
    ) {
        self.qwen = qwen
        self.prepareModel = prepareModel
        self.lease = lease
        self.unavailableReason = qwen == nil
            ? String(localized: "The Qwen assessment model is unavailable.") : unavailableReason
    }

    /// True while another AI task (AI Review or an MCP assessment) holds the shared lease.
    var isBlockedByOtherAIWork: Bool {
        lease.isHeld && !isRunning
    }

    var isRunning: Bool {
        switch phase {
        case .preparing, .running, .cancelling: true
        default: false
        }
    }

    var fractionCompleted: Double {
        totalBursts == 0 ? 0 : Double(completedBursts) / Double(totalBursts)
    }

    var statusText: String {
        switch phase {
        case .idle:
            ""

        case .preparing:
            String(localized: "Loading the Qwen model…")

        case .running:
            String(localized: "Assessing burst \(min(completedBursts + 1, totalBursts)) of \(totalBursts)")

        case .cancelling:
            String(localized: "Cancelling after the current photo…")

        case .finished:
            String(localized: "Assessed \(completedBursts) bursts: \(assessedPhotos) photos assessed, \(failedPhotos) failed.")

        case .cancelled:
            String(localized: "Cancelled after \(completedBursts) of \(totalBursts) bursts.")

        case let .failed(message):
            message
        }
    }

    // MARK: Plan

    /// Bursts with at least two frames and a ranked recommendation, in group order.
    static func makePlan(
        catalog: URL, catalogName: String, generation: Int, groups: [BurstGroup],
        results: [Int: BurstAnalysisResult], files: [FileItem],
    ) -> Plan {
        let root = catalog.standardizedFileURL.pathComponents
        let filesByID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = groups.sorted { $0.id < $1.id }.compactMap { group -> Item? in
            guard group.id != -1, group.fileIDs.count > 1, let result = results[group.id],
                  Set(result.fileIDs) == Set(group.fileIDs) else { return nil }
            var ranks: [UUID: Int] = [:]
            for (index, candidate) in result.candidates.enumerated() where ranks[candidate.fileID] == nil {
                ranks[candidate.fileID] = index + 1
            }
            var frames: [Frame] = []
            for id in group.fileIDs {
                guard let file = filesByID[id] else { return nil }
                let path = file.url.standardizedFileURL.pathComponents
                guard path.count > root.count, path.starts(with: root) else { return nil }
                frames.append(Frame(
                    photoID: id.uuidString, url: file.url,
                    photo: .init(relativePath: path.dropFirst(root.count).joined(separator: "/"),
                                 size: file.size, modified: file.dateModified),
                    rank: ranks[id],
                ))
            }
            let item = Item(
                groupID: group.id, confidence: result.confidence.rawValue, frames: frames,
                recommended: result.recommendedFileID?.uuidString,
                alternate: result.secondBestFileID?.uuidString,
            )
            return item.targets.isEmpty ? nil : item
        }
        return Plan(catalog: catalog, catalogName: catalogName, generation: generation, items: items)
    }

    // MARK: Run

    /// Starts assessing every burst in `plan`. `isStillCurrent` is checked
    /// between bursts so a re-analysis or catalog change stops the run.
    func start(
        _ plan: Plan, navigation: AIAssessmentNavigation,
        isStillCurrent: @escaping @MainActor () -> Bool,
    ) {
        guard !isRunning else { return }
        guard let qwen, unavailableReason == nil else {
            phase = .failed(unavailableReason ?? String(localized: "The Qwen assessment model is unavailable."))
            return
        }
        guard !plan.items.isEmpty else {
            phase = .failed(String(localized: "No bursts with two or more frames to assess."))
            return
        }
        let runID = UUID()
        do {
            try lease.acquire(runID)
        } catch {
            phase = .failed(String(localized: "Another AI task is running. Try again when it finishes."))
            return
        }
        lease.invalidateOwner = { [weak self] in self?.cancel() }
        completedBursts = 0
        totalBursts = plan.items.count
        assessedPhotos = 0
        failedPhotos = 0
        currentGroupID = nil
        phase = .preparing
        navigation.clearSessionEntries()

        task = Task { [weak self] in
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "RawCull burst AI assessment",
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                self?.lease.release(runID)
                self?.task = nil
            }
            await self?.run(plan, runID: runID, qwen: qwen, navigation: navigation, isStillCurrent: isStillCurrent)
        }
    }

    func cancel() {
        guard isRunning, let task else { return }
        phase = .cancelling
        task.cancel()
    }

    /// Clears a finished, cancelled or failed status line.
    func dismissStatus() {
        guard !isRunning else { return }
        phase = .idle
    }

    private func run(
        _ plan: Plan, runID: UUID, qwen: any MCPPhotoAssessing, navigation: AIAssessmentNavigation,
        isStillCurrent: @MainActor () -> Bool,
    ) async {
        if await qwen.assessmentIdentity() == nil {
            await prepareModel()
        }
        guard let identity = await qwen.assessmentIdentity() else {
            phase = .failed(String(localized: "The Qwen model could not be loaded. Check AI models in Settings."))
            return
        }
        if !Task.isCancelled {
            phase = .running
        }
        for item in plan.items {
            guard !Task.isCancelled else { break }
            guard isStillCurrent() else {
                phase = .failed(String(localized: "The bursts changed during the run. Results so far are kept."))
                return
            }
            currentGroupID = item.groupID
            do {
                let result = try await assess(item, runID: runID, model: identity, qwen: qwen)
                assessedPhotos += result.assessedCount
                failedPhotos += result.failedCount
                if result.assessedCount > 0 {
                    navigation.appendSessionEntry(Self.entry(for: item, result: result, plan: plan, runID: runID))
                }
            } catch is CancellationError {
                break
            } catch {
                Logger.process.error("Burst AI assessment stopped: \(error.localizedDescription, privacy: .public)")
                phase = .failed(String(localized: "The assessment stopped: the Qwen model changed or became unavailable."))
                return
            }
            completedBursts += 1
        }
        currentGroupID = nil
        phase = Task.isCancelled || phase == .cancelling ? .cancelled : .finished
    }

    /// Mirrors `MCPAnalysisController.assessFollowUp` for one burst.
    private func assess(
        _ item: Item, runID: UUID, model identity: QwenInferenceRuntime.Identity, qwen: any MCPPhotoAssessing,
    ) async throws -> MCPPhotoAssessmentResult {
        let byID = Dictionary(item.frames.map { ($0.photoID, $0) }, uniquingKeysWith: { first, _ in first })
        var outcomes: [MCPPhotoAssessmentResult.Photo] = []
        for id in item.targets {
            try Task.checkCancellation()
            let rank = byID[id]?.rank
            guard let frame = byID[id],
                  let image = await RawParserKitImageLoader.shared.thumbnailCGImage(for: frame.url, maxPixelSize: 2048)
            else {
                outcomes.append(.init(photoId: id, errorCode: "unreadablePhoto", sourceRank: rank))
                continue
            }
            do {
                let assessment = try await qwen.assessForMCP(rubric: Self.rubric, image: image, identity: identity)
                outcomes.append(.init(
                    photoId: id, assessedImage: .init(width: image.width, height: image.height),
                    findings: assessment.mcpFindings(for: Self.rubric), sourceRank: rank,
                ))
            } catch QwenModelError.invalidStructuredResponse {
                outcomes.append(.init(photoId: id, errorCode: "invalidAssessment", sourceRank: rank))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as QwenInferenceRuntime.MCPAssessmentError {
                throw error
            } catch {
                outcomes.append(.init(photoId: id, errorCode: "inferenceFailed", sourceRank: rank))
            }
        }
        let assessed = outcomes.count { $0.findings != nil }
        return .init(
            requestId: UUID(), sourceJobId: runID, model: identity.name,
            assessedCount: assessed, failedCount: outcomes.count - assessed, photos: outcomes,
            burstId: Self.burstID(runID: runID, groupID: item.groupID), burstFrameCount: item.frames.count,
        )
    }

    nonisolated static func burstID(runID: UUID, groupID: Int) -> String {
        "\(runID.uuidString):\(groupID)"
    }

    static func entry(
        for item: Item, result: MCPPhotoAssessmentResult, plan: Plan, runID: UUID,
    ) -> AIAssessmentEntry {
        let outcomes = Dictionary(result.photos.map { ($0.photoId, $0) }, uniquingKeysWith: { first, _ in first })
        let request = AnalysisJobStore.FollowUpRequest(
            id: result.requestId, catalogID: runID, sourceJobID: runID,
            target: .burst(burstID(runID: runID, groupID: item.groupID)), rubric: rubric,
        )
        return AIAssessmentEntry(
            request: request, requestedAt: .now, catalogName: plan.catalogName, burstNumber: item.groupID,
            burstConfidence: item.confidence, result: result,
            frames: item.frames.map { .init(id: $0.photoID, source: $0.photo, rank: $0.rank, outcome: outcomes[$0.photoID]) },
            recommendation: item.recommended,
            alternate: item.alternate == item.recommended ? nil : item.alternate,
            sessionCatalog: plan.catalog,
        )
    }
}
