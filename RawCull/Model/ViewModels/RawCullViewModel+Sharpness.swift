//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

extension RawCullViewModel {
    /// Auto-calibrates focus config from the current catalog, then scores and re-sorts.
    func calibrateAndScoreCurrentCatalog() async {
        await sharpnessModel.calibrateFromBurst(files)
        await sharpnessModel.scoreFiles(files)
        await handleSortOrderChange()
    }
}
