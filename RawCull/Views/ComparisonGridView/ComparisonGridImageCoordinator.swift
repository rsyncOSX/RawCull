import RawCullCore
import SwiftUI

typealias ComparisonFocusMaskResult = (
    mask: CGImage?,
    saliency: SaliencyInfo?,
    breakdown: SharpnessBreakdown?,
)

@MainActor
enum ComparisonGridImageCoordinator {
    static func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
        viewModel: RawCullViewModel,
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool],
    ) {
        let syncedFlags = syncSourceStates(for: files, sourceFlags: sourceFlags)
        var states = Dictionary(
            uniqueKeysWithValues: files.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: true))
            },
        )

        for file in files {
            guard !Task.isCancelled else { return (states, syncedFlags) }
            let state = await loadState(
                for: file,
                useThumbnailSource: syncedFlags[file.id] ?? false,
                viewModel: viewModel,
            )
            guard !Task.isCancelled else { return (states, syncedFlags) }
            states[file.id] = state
        }

        return (states, syncedFlags)
    }

    static func reloadImage(
        for file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
        viewModel: RawCullViewModel,
    ) async -> ComparisonImageState {
        await loadState(
            for: file,
            useThumbnailSource: sourceFlags[file.id] ?? false,
            viewModel: viewModel,
        )
    }

    static func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
        viewModel: RawCullViewModel,
    ) async -> [FileItem.ID: ComparisonImageState] {
        var updatedStates = states
        for file in files {
            guard !Task.isCancelled else { return updatedStates }
            guard let cgImage = updatedStates[file.id]?.cgImage else { continue }
            let result = await focusResult(for: file, cgImage: cgImage, viewModel: viewModel)
            guard !Task.isCancelled else { return updatedStates }
            updatedStates[file.id]?.focusMask = result.mask
            updatedStates[file.id]?.sharpnessBreakdown = result.breakdown
            persist(result: result, for: file.id, viewModel: viewModel)
        }
        return updatedStates
    }

    static func syncSourceStates(
        for files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) -> [FileItem.ID: Bool] {
        let currentIDs = Set(files.map(\.id))
        var syncedFlags = sourceFlags.filter { currentIDs.contains($0.key) }
        for file in files where syncedFlags[file.id] == nil {
            syncedFlags[file.id] = false
        }
        return syncedFlags
    }

    private static func loadState(
        for file: FileItem,
        useThumbnailSource: Bool,
        viewModel: RawCullViewModel,
    ) async -> ComparisonImageState {
        let (cgImage, nsImage) = await ComparisonImageLoader.loadImage(
            for: file,
            useThumbnailSource: useThumbnailSource,
        )
        guard !Task.isCancelled else {
            return ComparisonImageState(id: file.id, isLoading: true)
        }

        var state = ComparisonImageState(
            id: file.id,
            cgImage: cgImage,
            nsImage: nsImage,
            isLoading: false,
        )
        await populateFocusMask(in: &state, for: file, viewModel: viewModel)
        return state
    }

    private static func populateFocusMask(
        in state: inout ComparisonImageState,
        for file: FileItem,
        viewModel: RawCullViewModel,
    ) async {
        guard let cgImage = state.cgImage else { return }
        let result = await focusResult(for: file, cgImage: cgImage, viewModel: viewModel)
        state.focusMask = result.mask
        state.sharpnessBreakdown = result.breakdown
        persist(result: result, for: file.id, viewModel: viewModel)
    }

    private static func focusResult(
        for file: FileItem,
        cgImage: CGImage,
        viewModel: RawCullViewModel,
    ) async -> ComparisonFocusMaskResult {
        let downscaled = cgImage.downscaled(toWidth: 1024)
        let config = focusMaskConfig(for: file, viewModel: viewModel)
        return await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: downscaled ?? cgImage,
            scale: 1.0,
            configOverride: config,
            afPoint: file.afFocusNormalized,
        )
    }

    private static func focusMaskConfig(
        for file: FileItem,
        viewModel: RawCullViewModel,
    ) -> FocusDetectorConfig {
        var config = viewModel.sharpnessModel.effectiveFocusConfig
        config.iso = file.exifData?.isoValue ?? 400
        config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        if let score = viewModel.sharpnessModel.scores[file.id],
           SharpnessLabel(score: score, maxScore: viewModel.sharpnessModel.maxScore) == .sharp {
            config.guaranteeVisibleFocusEvidence = true
        }
        return config
    }

    private static func persist(
        result: ComparisonFocusMaskResult,
        for fileID: FileItem.ID,
        viewModel: RawCullViewModel,
    ) {
        if let breakdown = result.breakdown {
            viewModel.sharpnessModel.breakdowns[fileID] = breakdown
        }
        if let saliency = result.saliency {
            viewModel.sharpnessModel.saliencyInfo[fileID] = saliency
        }
    }
}
