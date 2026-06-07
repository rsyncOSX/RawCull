import AppKit
import RawCullCore
import SwiftUI

enum CullingGridSelectionModifier {
    case normal
    case command
    case shift

    init(flags: NSEvent.ModifierFlags) {
        if flags.contains(.command) {
            self = .command
        } else if flags.contains(.shift) {
            self = .shift
        } else {
            self = .normal
        }
    }
}

struct CullingGridSelectionState: Equatable {
    var selectedFileID: FileItem.ID?
    var selectedFileIDs: Set<FileItem.ID>
}

enum CullingGridSelectionCoordinator {
    static func toggleSelection(
        fileID: FileItem.ID,
        state: CullingGridSelectionState,
        visibleIDs: [FileItem.ID],
        modifier: CullingGridSelectionModifier,
    ) -> CullingGridSelectionState {
        var next = state

        switch modifier {
        case .command:
            if next.selectedFileIDs.contains(fileID) {
                next.selectedFileIDs.remove(fileID)
            } else {
                next.selectedFileIDs.insert(fileID)
                if let anchor = next.selectedFileID {
                    next.selectedFileIDs.insert(anchor)
                }
            }
            next.selectedFileID = fileID

        case .shift:
            guard let anchorID = next.selectedFileID,
                  let from = visibleIDs.firstIndex(of: anchorID),
                  let to = visibleIDs.firstIndex(of: fileID)
            else { return next }
            let range = from <= to ? from ... to : to ... from
            next.selectedFileIDs = Set(visibleIDs[range])

        case .normal:
            next.selectedFileIDs = []
            next.selectedFileID = fileID
        }

        return next
    }

    static func selectFiles(
        matchingIDs: Set<FileItem.ID>,
        state: CullingGridSelectionState,
        visibleFiles: [FileItem],
        modifier: CullingGridSelectionModifier,
    ) -> CullingGridSelectionState {
        guard !matchingIDs.isEmpty else { return state }
        var next = state

        switch modifier {
        case .command:
            if matchingIDs.isSubset(of: next.selectedFileIDs) {
                next.selectedFileIDs.subtract(matchingIDs)
            } else {
                next.selectedFileIDs.formUnion(matchingIDs)
            }

        case .shift, .normal:
            next.selectedFileIDs = matchingIDs
        }

        if let selectedID = next.selectedFileID,
           next.selectedFileIDs.contains(selectedID) {
            return next
        }
        next.selectedFileID = visibleFiles.first { next.selectedFileIDs.contains($0.id) }?.id
        return next
    }

    static func badgeSelectionItems(
        visibleFiles: [FileItem],
        burstGroupLookup: [FileItem.ID: Int],
        burstAnalysisResults: [Int: BurstAnalysisResult],
        saliencyInfo: [FileItem.ID: SaliencyInfo],
    ) -> [BatchBadgeSelectionItem] {
        let counts = visibleFiles.reduce(into: [String: Int]()) { result, file in
            for label in badgeLabels(
                for: file,
                burstGroupLookup: burstGroupLookup,
                burstAnalysisResults: burstAnalysisResults,
                saliencyInfo: saliencyInfo,
            ) {
                result[label, default: 0] += 1
            }
        }

        return counts
            .map { BatchBadgeSelectionItem(label: $0.key, count: $0.value, color: badgeSelectionColor(for: $0.key)) }
            .sorted { lhs, rhs in
                let lhsRank = badgeSelectionSortRank(lhs.label)
                let rhsRank = badgeSelectionSortRank(rhs.label)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    static func badgeLabels(
        for file: FileItem,
        burstGroupLookup: [FileItem.ID: Int],
        burstAnalysisResults: [Int: BurstAnalysisResult],
        saliencyInfo: [FileItem.ID: SaliencyInfo],
    ) -> Set<String> {
        var labels: Set<String> = []

        if let groupID = burstGroupLookup[file.id],
           let analysis = burstAnalysisResults[groupID],
           let candidate = analysis.candidates.first(where: { $0.fileID == file.id }),
           let badge = BurstGroupPresentation.recommendationBadge(for: candidate, in: analysis) {
            labels.insert(badge)
        }

        if let subject = saliencyInfo[file.id]?.subjectLabel,
           !subject.isEmpty {
            labels.insert(String(subject.prefix(10)))
        }

        return labels
    }

    static func matchingIDs(
        forBadge badge: String,
        visibleFiles: [FileItem],
        burstGroupLookup: [FileItem.ID: Int],
        burstAnalysisResults: [Int: BurstAnalysisResult],
        saliencyInfo: [FileItem.ID: SaliencyInfo],
    ) -> Set<FileItem.ID> {
        Set(visibleFiles
            .filter {
                badgeLabels(
                    for: $0,
                    burstGroupLookup: burstGroupLookup,
                    burstAnalysisResults: burstAnalysisResults,
                    saliencyInfo: saliencyInfo,
                )
                .contains(badge)
            }
            .map(\.id))
    }

    static func zoomNavigationIDs(
        for file: FileItem,
        showsBurstGroups: Bool,
        visibleBurstGroups: [CullingGridVisibleBurstGroup],
        files: [FileItem],
    ) -> [FileItem.ID] {
        if showsBurstGroups,
           let group = visibleBurstGroups.first(where: { group in
               group.files.contains { $0.id == file.id }
           }) {
            return group.files.map(\.id)
        }
        return files.map(\.id)
    }

    private static func badgeSelectionSortRank(_ label: String) -> Int {
        switch label {
        case "Suggested best": 0
        case "Check frame": 1
        case "Manual": 3
        default: 10
        }
    }

    private static func badgeSelectionColor(for label: String) -> Color {
        switch label {
        case "Suggested best": .orange
        case "Manual": .orange
        case "Check frame": .gray
        default: .cyan
        }
    }
}
