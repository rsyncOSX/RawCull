//
//  RawCullViewModel+Thumbnails.swift
//  RawCull
//

import OSLog

extension RawCullViewModel {
    func setMemoryPressureWarning(_ warning: Bool) {
        Logger.process.debugMessageOnly("RawCullViewModel.setMemoryPressureWarning()")
        presentation.memoryPressureWarning = warning
    }

    func extractionNeeded() {
        // Logger.process.debugMessageOnly("RawCullViewModel.extractionNeeded()")
        catalog.isCreatingThumbnails = true
    }

    func applyStoredScoringSettings() async {
        Logger.process.debugMessageOnly("RawCullViewModel.applyStoredScoringSettings()")
        // Wait for the initial settings load to complete before reading.
        // Without this, we may race with the fire-and-forget Task in SettingsViewModel.init()
        // and read default values from the JSON before the file I/O finishes.
        await SettingsViewModel.shared.ensureLoaded()
        let s = SettingsViewModel.shared
        sharpnessModel.thumbnailMaxPixelSize = SharpnessScoringSizeOption.normalizedPixelSize(
            s.scoringThumbnailMaxPixelSize,
            for: s.scoringQuality,
        )
        sharpnessModel.focusMaskModel.config.borderInsetFraction = s.scoringBorderInsetFraction
        sharpnessModel.focusMaskModel.config.enableSubjectClassification = s.scoringEnableSubjectClassification
        sharpnessModel.focusMaskModel.config.salientWeight = s.scoringSalientWeight
        sharpnessModel.focusMaskModel.config.subjectSizeFactor = s.scoringSubjectSizeFactor
        sharpnessModel.focusMaskModel.config.preBlurRadius = s.focusMaskPreBlurRadius
        sharpnessModel.photoType = s.scoringPhotoType
        sharpnessModel.scoringQuality = s.scoringQuality
        sharpnessModel.scoringSource = s.scoringSource
        sharpnessModel.focusMaskModel.config.threshold = s.focusMaskThreshold
        sharpnessModel.focusMaskModel.config.energyMultiplier = s.focusMaskEnergyMultiplier
        sharpnessModel.focusMaskModel.config.erosionRadius = s.focusMaskErosionRadius
        sharpnessModel.focusMaskModel.config.dilationRadius = s.focusMaskDilationRadius
        sharpnessModel.focusMaskModel.config.featherRadius = s.focusMaskFeatherRadius
    }

    func abort() {
        Logger.process.debugMessageOnly("RawCullViewModel.abort()")

        cancelCatalogLoad()
        fileOperations.cancelJPGOperations()
        catalog.isCreatingThumbnails = false
    }
}

extension RawCullViewModel: FileOperationsCatalog {
    func startSecurityScopedResource(_ url: URL) -> Bool {
        catalogLifecycle.startSecurityScopedResource(url)
    }

    func stopSecurityScopedResource(_ url: URL) {
        catalogLifecycle.stopSecurityScopedResource(url)
    }
}
