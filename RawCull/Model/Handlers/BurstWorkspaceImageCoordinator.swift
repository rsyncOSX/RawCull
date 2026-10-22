import OSLog
import RawCullCore
import SwiftUI

@MainActor
struct BurstWorkspaceImageCoordinator {
    let session: BurstWorkspaceSessionModel
    let viewModel: RawCullViewModel

    func loadWindow(files: [FileItem], selectedFile: FileItem?, selectedIndex: Int) async {
        guard let selectedFile else {
            session.imageCache = [:]
            return
        }

        let source = session.sourceSelection.selected
        let windowFiles = session.cachedWindowIndices(
            selectedIndex: selectedIndex,
            itemCount: files.count,
        ).map { files[$0] }
        let retainedKeys = Set(windowFiles.map { cacheKey(for: $0, source: source) })
        session.imageCache = session.imageCache.filter { retainedKeys.contains($0.key) }

        let loadOrder = [selectedFile] + windowFiles.filter { $0.id != selectedFile.id }
        for file in loadOrder {
            let loaded = await ensureDecodedImage(
                for: file,
                source: source,
                reportsDevelopedRAWFailure: file.id == selectedFile.id,
            )
            guard !Task.isCancelled else { return }
            if file.id == selectedFile.id, !loaded {
                return
            }
        }
    }

    private func ensureDecodedImage(
        for file: FileItem,
        source: ImagePreviewSource,
        reportsDevelopedRAWFailure: Bool,
    ) async -> Bool {
        let key = cacheKey(for: file, source: source)
        if let state = session.imageCache[key], !state.isLoading {
            return true
        }

        session.imageCache[key] = ComparisonImageState(id: file.id, isLoading: true)

        let decodedState: ComparisonImageState
        switch source {
        case .thumbnail, .embeddedJPG:
            decodedState = await ComparisonGridImageCoordinator.loadDecodedState(
                for: file,
                useThumbnailSource: source == .thumbnail,
            )

        case .developedRAW:
            do {
                let image = try await ZoomPreviewHandler.loadDevelopedRAWPreview(for: file.url)
                decodedState = ComparisonImageState(id: file.id, cgImage: image)
            } catch is CancellationError {
                return false
            } catch {
                guard !Task.isCancelled else { return false }
                session.imageCache.removeValue(forKey: key)
                if reportsDevelopedRAWFailure {
                    session.sourceSelection.markDevelopedRAWUnavailable()
                }
                return false
            }
        }

        guard !Task.isCancelled else { return false }
        session.imageCache[key] = decodedState
        return true
    }

    func analyzeFocusIfNeeded(
        for file: FileItem,
        source: ImagePreviewSource,
    ) async {
        let key = cacheKey(for: file, source: source)
        guard let state = session.imageCache[key],
              !state.isLoading,
              state.cgImage != nil,
              state.focusMask == nil
        else { return }

        Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice("Generating focus mask")
        let analyzedState = await ComparisonGridImageCoordinator.analyzeFocus(
            for: file,
            state: state,
            viewModel: viewModel,
        )
        guard !Task.isCancelled, session.imageCache[key] != nil else { return }
        Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice("Mask returned: \(analyzedState.focusMask != nil)")
        session.imageCache[key] = analyzedState
    }

    private func cacheKey(
        for file: FileItem,
        source: ImagePreviewSource,
    ) -> BurstFrameCacheKey {
        BurstFrameCacheKey(fileID: file.id, source: source)
    }
}
