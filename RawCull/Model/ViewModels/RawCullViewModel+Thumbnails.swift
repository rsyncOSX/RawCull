//
//  RawCullViewModel+Thumbnails.swift
//  RawCull
//

import OSLog

extension RawCullViewModel {
    func fileHandler(_ update: Int) {
        progress = Double(update)
    }

    func maxfilesHandler(_ maxfiles: Int) {
        max = Double(maxfiles)
    }

    func estimatedTimeHandler(_ seconds: Int) {
        estimatedSeconds = seconds
    }

    func memorypressurewarning(_ warning: Bool) {
        memorypressurewarning = warning
    }

    func applyStoredScoringSettings() async {
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        sharpnessModel.thumbnailMaxPixelSize = settings.scoringThumbnailMaxPixelSize
        sharpnessModel.focusMaskModel.config.borderInsetFraction = settings.scoringBorderInsetFraction
        sharpnessModel.focusMaskModel.config.enableSubjectClassification = settings.scoringEnableSubjectClassification
        sharpnessModel.focusMaskModel.config.salientWeight = settings.scoringSalientWeight
        sharpnessModel.focusMaskModel.config.subjectSizeFactor = settings.scoringSubjectSizeFactor
    }

    func abort() {
        Logger.process.debugMessageOnly("Abort scanning")

        preloadTask?.cancel()
        preloadTask = nil
        if let actor = currentScanAndCreateThumbnailsActor {
            Task { await actor.cancelPreload() }
        }
        currentScanAndCreateThumbnailsActor = nil

        if let actor = currentExtractAndSaveJPGsActor {
            Task { await actor.cancelExtractJPGSTask() }
        }
        currentExtractAndSaveJPGsActor = nil

        creatingthumbnails = false
    }
}
