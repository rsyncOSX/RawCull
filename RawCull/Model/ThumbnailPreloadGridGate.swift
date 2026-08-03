import Foundation

/// The 2.3.4 low-risk contention fallback. Thumbnail grids are not constructed
/// while the selected catalog's preload actor is active, preventing their
/// `.task` loaders from competing with the batch scan.
nonisolated enum ThumbnailPreloadGridGate {
    static func shouldBlock(
        activeCatalogURL: URL?,
        selectedCatalogURL: URL?,
        hasActivePreloader: Bool,
    ) -> Bool {
        guard hasActivePreloader,
              let activeCatalogURL,
              let selectedCatalogURL
        else { return false }
        return activeCatalogURL.standardizedFileURL == selectedCatalogURL.standardizedFileURL
    }
}
