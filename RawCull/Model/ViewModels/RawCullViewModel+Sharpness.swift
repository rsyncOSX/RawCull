//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

extension RawCullViewModel {
    /// Triggers a full batch-score of the current catalog, then re-sorts.
    /// Heavy work runs off the main actor inside SharpnessScoringModel.
    func scoreSharpnessForCurrentCatalog() async {
        await sharpnessModel.scoreFiles(files)
        await handleSortOrderChange()
    }

    /// Auto-calibrates focus config from the current catalog, then scores and re-sorts.
    func calibrateAndScoreCurrentCatalog() async {
        await sharpnessModel.calibrateFromBurst(files)
        await sharpnessModel.scoreFiles(files)
        await handleSortOrderChange()
    }
}
