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

    func setMemoryPressureWarning(_ warning: Bool) {
        memoryPressureWarning = warning
    }

    func extractionNeeded() {
        creatingthumbnails = true
    }

    var selectedFilesForJPGExtraction: [FileItem] {
        if !selectedFileIDs.isEmpty {
            return filteredFiles.filter { selectedFileIDs.contains($0.id) }
        }

        guard let selectedFileID else { return [] }
        if let file = filteredFiles.first(where: { $0.id == selectedFileID }) {
            return [file]
        }
        return files.first(where: { $0.id == selectedFileID }).map { [$0] } ?? []
    }

    func presentExtractJPGsSheet() {
        guard !sources.isEmpty else { return }
        if extractJPGDestination == nil {
            extractJPGDestination = selectedSource ?? sources.first
        }
        activeSheet = .extractJPGs
    }

    func startSelectedJPGExtraction(destination: ARWSourceCatalog, exportMode: ExtractJPGExportMode) {
        let exportFiles = selectedFilesForJPGExtraction
        guard currentScanAndExtractJPGsActor == nil,
              currentScanAndCreateThumbnailsActor == nil,
              currentExtractAndSaveJPGsActor == nil,
              !exportFiles.isEmpty
        else { return }

        progress = 0
        max = Double(exportFiles.count)
        estimatedSeconds = 0
        creatingthumbnails = true

        let handlers = CreateFileHandlers().createFileHandlers(
            fileHandler: fileHandler,
            maxfilesHandler: maxfilesHandler,
            estimatedTimeHandler: estimatedTimeHandler,
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )

        let destinationURL = destination.url
        let destinationAccessStarted = startSecurityScopedResource(destinationURL)
        guard destinationAccessStarted else {
            creatingthumbnails = false
            operationFailurePresentation = OperationFailurePresentation(
                title: "Export Not Started",
                message: "RawCull could not access the selected destination folder. Choose the folder again and retry.",
            )
            return
        }
        let extract = ExtractAndSaveJPGs(
            files: exportFiles,
            destinationCatalogURL: destinationURL,
            exportMode: exportMode,
        )
        currentExtractAndSaveJPGsActor = extract

        Task(priority: .background) {
            await extract.setFileHandlers(handlers)
            let result = await extract.extractAndSavejpgs()

            await MainActor.run {
                self.stopSecurityScopedResource(destinationURL)
                guard self.currentExtractAndSaveJPGsActor === extract else { return }
                self.currentExtractAndSaveJPGsActor = nil
                self.creatingthumbnails = false
                if !result.failures.isEmpty {
                    let firstFailure = result.failures[0]
                    self.operationFailurePresentation = OperationFailurePresentation(
                        title: "Export Incomplete",
                        message: "\(result.failures.count) of \(result.succeeded + result.failures.count) JPG files could not be saved. First failure: \(firstFailure.fileName): \(firstFailure.message)",
                    )
                }
            }
        }
    }

    func startScanAndExtractJPGs() {
        guard currentScanAndExtractJPGsActor == nil,
              currentScanAndCreateThumbnailsActor == nil,
              currentExtractAndSaveJPGsActor == nil,
              !files.isEmpty
        else { return }

        jpgCacheWarmTask?.cancel()

        progress = 0
        max = Double(files.count)
        estimatedSeconds = 0
        creatingthumbnails = true

        let handlers = CreateFileHandlers().createFileHandlers(
            fileHandler: fileHandler,
            maxfilesHandler: maxfilesHandler,
            estimatedTimeHandler: estimatedTimeHandler,
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )

        let actor = ScanAndExtractJPGs(urls: files.map(\.url))
        currentScanAndExtractJPGsActor = actor

        jpgCacheWarmTask = Task(priority: .background) {
            await actor.setFileHandlers(handlers)
            await actor.extractCatalogJPGs()

            await MainActor.run {
                guard self.currentScanAndExtractJPGsActor === actor else { return }
                self.currentScanAndExtractJPGsActor = nil
                self.jpgCacheWarmTask = nil
                self.creatingthumbnails = false
            }
        }
    }

    func applyStoredScoringSettings() async {
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
        Logger.process.debugMessageOnly("Abort scanning")

        cancelCatalogLoad()

        if let actor = currentExtractAndSaveJPGsActor {
            Task { await actor.cancelExtractJPGSTask() }
        }
        currentExtractAndSaveJPGsActor = nil

        jpgCacheWarmTask?.cancel()
        jpgCacheWarmTask = nil

        if let actor = currentScanAndExtractJPGsActor {
            Task { await actor.cancelExtraction() }
        }
        currentScanAndExtractJPGsActor = nil

        creatingthumbnails = false
    }
}
