//
//  SettingsViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import Foundation
import OSLog

// Observable settings manager for app configuration
// Persists settings to JSON in Application Support directory

@Observable
final class SettingsViewModel {
    @MainActor static let shared = SettingsViewModel()

    // MARK: - Initialization

    /// Retained so callers can `await ensureLoaded()` before reading settings.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private init() {
        // Phase 1: all stored properties must be set before self can be captured.
        loadTask = nil
        // Phase 2: self is now fully initialized — safe to capture in the Task closure.
        loadTask = Task {
            await self.loadSettings()
        }
    }

    /// Awaits the initial settings load. Safe to call multiple times.
    func ensureLoaded() async {
        await loadTask?.value
    }

    // MARK: - Memory Cache Settings

    /// Maximum memory cache size in MB (default: 4000)
    var memoryCacheSizeMB: Int = 4000

    /// Maximum grid (200px) memory cache size in MB (default: 400)
    var gridCacheSizeMB: Int = 400

    // MARK: - Thumbnail Size Settings

    /// Grid thumbnail size in pixels (default: 100)
    var thumbnailSizeGrid: Int = 200
    /// Preview thumbnail size in pixels (default: 1024)
    var thumbnailSizePreview: Int = 1616
    /// Full size thumbnail in pixels (default: 8700)
    var thumbnailSizeFullSize: Int = 8700
    /// Estimated cost per pixel for thumbnail (in bytes, default: 4 for RGBA).
    /// `CachedThumbnail` already adds a 10% overhead buffer on top of this,
    /// so 4 = decoded RGBA without double-counting wrapper overhead.
    var thumbnailCostPerPixel: Int = 4
    /// Use thumbnail as zoom preview (default: true)
    var useThumbnailAsZoomPreview: Bool = false

    /// When enabled, bypasses the cached embedded-JPEG thumbnail and runs the zoom preview
    /// through a CIRAWFilter pipeline (demosaiced raw → noise reduction → small-radius
    /// unsharp + sharpenLuminance). See `ThumbnailSharpener.sharpenedPreview`. Default: false.
    var enableThumbnailSharpening: Bool = false
    /// Sharpening amount for the CIRAWFilter preview pipeline, 0.0–2.0 (default: 1.0).
    /// Drives `unsharpMask.intensity = amount * 0.4` and `sharpenLuminance.sharpness = amount * 0.3`.
    var thumbnailSharpenAmount: Float = 1.0

    /// Show sharpness score badge on thumbnails (default: false = hidden, for scroll performance)
    var showScoringBadge: Bool = false
    /// Show cyan saliency badge on thumbnails (default: false = hidden)
    var showSaliencyBadge: Bool = false

    // MARK: - Scoring Parameters

    /// Border inset fraction for sharpness scoring (default: 0.04)
    var scoringBorderInsetFraction: Float = 0.04
    /// Run subject classification pass during scoring (default: true)
    var scoringEnableSubjectClassification: Bool = true
    /// Weight for salient-region score vs full-frame score (default: 0.75)
    var scoringSalientWeight: Float = 0.75
    /// Subject size bonus multiplier (default: 0.1)
    var scoringSubjectSizeFactor: Float = 0.1
    /// Thumbnail pixel size used when decoding images for sharpness scoring (default: 512)
    var scoringThumbnailMaxPixelSize: Int = 512

    // MARK: - Focus Mask Parameters

    /// Pre-blur radius applied before Laplacian (default: 1.92)
    var focusMaskPreBlurRadius: Float = 1.92
    /// Laplacian threshold for focus detection (default: 0.46)
    var focusMaskThreshold: Float = 0.46
    /// Energy amplification multiplier (default: 7.62)
    var focusMaskEnergyMultiplier: Float = 7.62
    /// Erosion radius for noise removal (default: 1.0)
    var focusMaskErosionRadius: Float = 1.0
    /// Dilation radius for connecting regions (default: 1.0)
    var focusMaskDilationRadius: Float = 1.0
    /// Feather radius for mask edges (default: 2.0)
    var focusMaskFeatherRadius: Float = 2.0

    // MARK: - Private Properties

    private let settingsFileName = "settings.json"

    private var settingsURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("RawCull", isDirectory: true)
        return appFolder.appendingPathComponent(settingsFileName)
    }

    // MARK: - Public Methods

    /// Load settings from JSON file
    func loadSettings() async {
        do {
            let fileURL = settingsURL

            // Create directory if it doesn't exist
            let dirURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )

            // If file doesn't exist, just use defaults
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Logger.process.debugMessageOnly("Settings file not found, using defaults")
                return
            }

            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: fileURL)
            }.value
            let decoder = JSONDecoder()
            let savedSettings = try decoder.decode(SavedSettings.self, from: data)

            await MainActor.run {
                self.memoryCacheSizeMB = savedSettings.memoryCacheSizeMB
                self.gridCacheSizeMB = savedSettings.gridCacheSizeMB
                self.thumbnailSizeGrid = savedSettings.thumbnailSizeGrid
                self.thumbnailSizePreview = savedSettings.thumbnailSizePreview
                self.thumbnailSizeFullSize = savedSettings.thumbnailSizeFullSize
                self.thumbnailCostPerPixel = savedSettings.thumbnailCostPerPixel
                self.useThumbnailAsZoomPreview = savedSettings.useThumbnailAsZoomPreview
                self.enableThumbnailSharpening = savedSettings.enableThumbnailSharpening
                self.thumbnailSharpenAmount = savedSettings.thumbnailSharpenAmount
                self.showScoringBadge = savedSettings.showScoringBadge
                self.showSaliencyBadge = savedSettings.showSaliencyBadge
                self.scoringBorderInsetFraction = savedSettings.scoringBorderInsetFraction
                self.scoringEnableSubjectClassification = savedSettings.scoringEnableSubjectClassification
                self.scoringSalientWeight = savedSettings.scoringSalientWeight
                self.scoringSubjectSizeFactor = savedSettings.scoringSubjectSizeFactor
                self.scoringThumbnailMaxPixelSize = savedSettings.scoringThumbnailMaxPixelSize
                self.focusMaskPreBlurRadius = savedSettings.focusMaskPreBlurRadius
                self.focusMaskThreshold = savedSettings.focusMaskThreshold
                self.focusMaskEnergyMultiplier = savedSettings.focusMaskEnergyMultiplier
                self.focusMaskErosionRadius = savedSettings.focusMaskErosionRadius
                self.focusMaskDilationRadius = savedSettings.focusMaskDilationRadius
                self.focusMaskFeatherRadius = savedSettings.focusMaskFeatherRadius
            }

            Logger.process.debugMessageOnly("SettingsManager: Settings loaded successfully")
        } catch {
            Logger.process.errorMessageOnly("Failed to load settings: \(error.localizedDescription)")
        }
    }

    /// Save settings to JSON file. Encodes on the MainActor then writes on a background thread.
    func saveSettings() async {
        do {
            validateSettings()

            let fileURL = settingsURL
            let dirURL = fileURL.deletingLastPathComponent()

            let settingsToSave = SavedSettings(
                memoryCacheSizeMB: memoryCacheSizeMB,
                gridCacheSizeMB: gridCacheSizeMB,
                thumbnailSizeGrid: thumbnailSizeGrid,
                thumbnailSizePreview: thumbnailSizePreview,
                thumbnailSizeFullSize: thumbnailSizeFullSize,
                thumbnailCostPerPixel: thumbnailCostPerPixel,
                useThumbnailAsZoomPreview: useThumbnailAsZoomPreview,
                enableThumbnailSharpening: enableThumbnailSharpening,
                thumbnailSharpenAmount: thumbnailSharpenAmount,
                showScoringBadge: showScoringBadge,
                showSaliencyBadge: showSaliencyBadge,
                scoringBorderInsetFraction: scoringBorderInsetFraction,
                scoringEnableSubjectClassification: scoringEnableSubjectClassification,
                scoringSalientWeight: scoringSalientWeight,
                scoringSubjectSizeFactor: scoringSubjectSizeFactor,
                scoringThumbnailMaxPixelSize: scoringThumbnailMaxPixelSize,
                focusMaskPreBlurRadius: focusMaskPreBlurRadius,
                focusMaskThreshold: focusMaskThreshold,
                focusMaskEnergyMultiplier: focusMaskEnergyMultiplier,
                focusMaskErosionRadius: focusMaskErosionRadius,
                focusMaskDilationRadius: focusMaskDilationRadius,
                focusMaskFeatherRadius: focusMaskFeatherRadius,
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settingsToSave)

            // Offload blocking directory creation and file write to a background thread
            // to avoid stalling the MainActor. data and URLs are Sendable value types.
            try await Task.detached(priority: .background) {
                try FileManager.default.createDirectory(
                    at: dirURL,
                    withIntermediateDirectories: true,
                    attributes: nil,
                )
                try data.write(to: fileURL, options: .atomic)
            }.value

            Logger.process.debugMessageOnly("Settings saved successfully")
        } catch {
            Logger.process.errorMessageOnly("Failed to save settings: \(error.localizedDescription)")
        }
    }

    /// Validate settings and warn about potentially aggressive values
    private func validateSettings() {
        // Check minimum safety threshold
        let minimumCacheMB = 500
        if memoryCacheSizeMB < minimumCacheMB {
            let message = "Cache size: \(self.memoryCacheSizeMB)MB is below " +
                "recommended minimum of \(minimumCacheMB)MB. Performance may suffer."
            Logger.process.errorMessageOnly("\(message)")
        }

        // Check if cache size exceeds 80% of available system memory (increased from 50%)
        // This allows 10GB caches on 16GB+ systems
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemoryMB = Int(availableMemory / (1024 * 1024))
        let memoryThresholdPercent = 80

        if memoryCacheSizeMB > availableMemoryMB * memoryThresholdPercent / 100 {
            let message = "Cache size: \(self.memoryCacheSizeMB)MB exceeds " +
                "\(memoryThresholdPercent)% of available system memory " +
                "(\(availableMemoryMB)MB). This may cause system memory pressure."
            Logger.process.errorMessageOnly("\(message)")
        }
    }

    /// Reset settings to defaults
    func resetToDefaultsMemoryCache() async {
        await MainActor.run {
            self.memoryCacheSizeMB = 20000
            self.gridCacheSizeMB = 400
        }
        await saveSettings()
    }

    func resetToDefaultsThumbnails() async {
        await MainActor.run {
            self.thumbnailSizeGrid = 200
            self.thumbnailSizePreview = 1616
            self.thumbnailSizeFullSize = 8700
            self.thumbnailCostPerPixel = 4
        }
        await saveSettings()
    }
    
/*
    // MARK: - Memory Projection

    /// Empirically-calibrated projection of RawCull's RAM payload from the two
    /// cache-size sliders. App baseline (no caches populated) is ~100 MB.
    /// Interpolates between baseline and a per-slider payload ceiling using
    /// each slider's fraction of its own range, weighted by the slider's
    /// range share of the combined payload. Calibration anchor: with
    /// `thumbnailCostPerPixel=4`, mem=8000 MB / grid=2000 MB, real process
    /// RSS measured ~9330 MB peak; `maxPayloadMB = 9300` makes the formula
    /// reproduce that ceiling. Used by both the Cache settings tab and the
    /// Memory Diagnostics console (the console logs this side-by-side with
    /// the real process RSS so the calibration can be tuned against real usage).
    func projectedRawCullMemoryBytes() -> UInt64 {
        let memMin = 1000.0, memMax = 8000.0
        let gridMin = 400.0, gridMax = 2000.0
        let memFrac = (Double(memoryCacheSizeMB) - memMin) / (memMax - memMin)
        let gridFrac = (Double(gridCacheSizeMB) - gridMin) / (gridMax - gridMin)
        let memRange = memMax - memMin
        let gridRange = gridMax - gridMin
        let totalRange = memRange + gridRange
        let combined = memFrac * (memRange / totalRange) + gridFrac * (gridRange / totalRange)
        let baselineMB = 100.0
        let maxPayloadMB = 9300.0
        let clamped = min(1.0, max(0.0, combined))
        let projectedMB = baselineMB + clamped * maxPayloadMB
        return UInt64(projectedMB * 1024.0 * 1024.0)
    }
*/
    /// Get a snapshot of current settings (safe to call from any context)
    nonisolated func asyncgetsettings() async -> SavedSettings {
        await MainActor.run {
            SavedSettings(
                memoryCacheSizeMB: self.memoryCacheSizeMB,
                gridCacheSizeMB: self.gridCacheSizeMB,
                thumbnailSizeGrid: self.thumbnailSizeGrid,
                thumbnailSizePreview: self.thumbnailSizePreview,
                thumbnailSizeFullSize: self.thumbnailSizeFullSize,
                thumbnailCostPerPixel: self.thumbnailCostPerPixel,
                useThumbnailAsZoomPreview: self.useThumbnailAsZoomPreview,
                enableThumbnailSharpening: self.enableThumbnailSharpening,
                thumbnailSharpenAmount: self.thumbnailSharpenAmount,
                showScoringBadge: self.showScoringBadge,
                showSaliencyBadge: self.showSaliencyBadge,
                scoringBorderInsetFraction: self.scoringBorderInsetFraction,
                scoringEnableSubjectClassification: self.scoringEnableSubjectClassification,
                scoringSalientWeight: self.scoringSalientWeight,
                scoringSubjectSizeFactor: self.scoringSubjectSizeFactor,
                scoringThumbnailMaxPixelSize: self.scoringThumbnailMaxPixelSize,
                focusMaskPreBlurRadius: self.focusMaskPreBlurRadius,
                focusMaskThreshold: self.focusMaskThreshold,
                focusMaskEnergyMultiplier: self.focusMaskEnergyMultiplier,
                focusMaskErosionRadius: self.focusMaskErosionRadius,
                focusMaskDilationRadius: self.focusMaskDilationRadius,
                focusMaskFeatherRadius: self.focusMaskFeatherRadius,
            )
        }
    }
}

// MARK: - Codable Model

struct SavedSettings: Codable {
    let memoryCacheSizeMB: Int
    let gridCacheSizeMB: Int

    let thumbnailSizeGrid: Int
    let thumbnailSizePreview: Int
    let thumbnailSizeFullSize: Int
    let thumbnailCostPerPixel: Int
    let useThumbnailAsZoomPreview: Bool
    let enableThumbnailSharpening: Bool
    let thumbnailSharpenAmount: Float
    let showScoringBadge: Bool
    let showSaliencyBadge: Bool

    let scoringBorderInsetFraction: Float
    let scoringEnableSubjectClassification: Bool
    let scoringSalientWeight: Float
    let scoringSubjectSizeFactor: Float
    let scoringThumbnailMaxPixelSize: Int

    let focusMaskPreBlurRadius: Float
    let focusMaskThreshold: Float
    let focusMaskEnergyMultiplier: Float
    let focusMaskErosionRadius: Float
    let focusMaskDilationRadius: Float
    let focusMaskFeatherRadius: Float

    init(
        memoryCacheSizeMB: Int,
        gridCacheSizeMB: Int = 400,
        thumbnailSizeGrid: Int,
        thumbnailSizePreview: Int,
        thumbnailSizeFullSize: Int,
        thumbnailCostPerPixel: Int,
        useThumbnailAsZoomPreview: Bool,
        enableThumbnailSharpening: Bool = false,
        thumbnailSharpenAmount: Float = 1.0,
        showScoringBadge: Bool = false,
        showSaliencyBadge: Bool = false,
        scoringBorderInsetFraction: Float = 0.04,
        scoringEnableSubjectClassification: Bool = true,
        scoringSalientWeight: Float = 0.75,
        scoringSubjectSizeFactor: Float = 0.1,
        scoringThumbnailMaxPixelSize: Int = 512,
        focusMaskPreBlurRadius: Float = 1.92,
        focusMaskThreshold: Float = 0.46,
        focusMaskEnergyMultiplier: Float = 7.62,
        focusMaskErosionRadius: Float = 1.0,
        focusMaskDilationRadius: Float = 1.0,
        focusMaskFeatherRadius: Float = 2.0,
    ) {
        self.memoryCacheSizeMB = memoryCacheSizeMB
        self.gridCacheSizeMB = gridCacheSizeMB
        self.thumbnailSizeGrid = thumbnailSizeGrid
        self.thumbnailSizePreview = thumbnailSizePreview
        self.thumbnailSizeFullSize = thumbnailSizeFullSize
        self.thumbnailCostPerPixel = thumbnailCostPerPixel
        self.useThumbnailAsZoomPreview = useThumbnailAsZoomPreview
        self.enableThumbnailSharpening = enableThumbnailSharpening
        self.thumbnailSharpenAmount = thumbnailSharpenAmount
        self.showScoringBadge = showScoringBadge
        self.showSaliencyBadge = showSaliencyBadge
        self.scoringBorderInsetFraction = scoringBorderInsetFraction
        self.scoringEnableSubjectClassification = scoringEnableSubjectClassification
        self.scoringSalientWeight = scoringSalientWeight
        self.scoringSubjectSizeFactor = scoringSubjectSizeFactor
        self.scoringThumbnailMaxPixelSize = scoringThumbnailMaxPixelSize
        self.focusMaskPreBlurRadius = focusMaskPreBlurRadius
        self.focusMaskThreshold = focusMaskThreshold
        self.focusMaskEnergyMultiplier = focusMaskEnergyMultiplier
        self.focusMaskErosionRadius = focusMaskErosionRadius
        self.focusMaskDilationRadius = focusMaskDilationRadius
        self.focusMaskFeatherRadius = focusMaskFeatherRadius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memoryCacheSizeMB = try c.decode(Int.self, forKey: .memoryCacheSizeMB)
        gridCacheSizeMB = (try? c.decode(Int.self, forKey: .gridCacheSizeMB)) ?? 400
        thumbnailSizeGrid = try c.decode(Int.self, forKey: .thumbnailSizeGrid)
        thumbnailSizePreview = try c.decode(Int.self, forKey: .thumbnailSizePreview)
        thumbnailSizeFullSize = try c.decode(Int.self, forKey: .thumbnailSizeFullSize)
        thumbnailCostPerPixel = try c.decode(Int.self, forKey: .thumbnailCostPerPixel)
        useThumbnailAsZoomPreview = try c.decode(Bool.self, forKey: .useThumbnailAsZoomPreview)
        enableThumbnailSharpening = (try? c.decode(Bool.self, forKey: .enableThumbnailSharpening)) ?? false
        thumbnailSharpenAmount = (try? c.decode(Float.self, forKey: .thumbnailSharpenAmount)) ?? 1.0
        showScoringBadge = (try? c.decode(Bool.self, forKey: .showScoringBadge)) ?? false
        showSaliencyBadge = (try? c.decode(Bool.self, forKey: .showSaliencyBadge)) ?? false
        scoringBorderInsetFraction = (try? c.decode(Float.self, forKey: .scoringBorderInsetFraction)) ?? 0.04
        scoringEnableSubjectClassification = (try? c.decode(Bool.self, forKey: .scoringEnableSubjectClassification)) ?? true
        scoringSalientWeight = (try? c.decode(Float.self, forKey: .scoringSalientWeight)) ?? 0.75
        scoringSubjectSizeFactor = (try? c.decode(Float.self, forKey: .scoringSubjectSizeFactor)) ?? 0.1
        scoringThumbnailMaxPixelSize = (try? c.decode(Int.self, forKey: .scoringThumbnailMaxPixelSize)) ?? 512
        focusMaskPreBlurRadius = (try? c.decode(Float.self, forKey: .focusMaskPreBlurRadius)) ?? 1.92
        focusMaskThreshold = (try? c.decode(Float.self, forKey: .focusMaskThreshold)) ?? 0.46
        focusMaskEnergyMultiplier = (try? c.decode(Float.self, forKey: .focusMaskEnergyMultiplier)) ?? 7.62
        focusMaskErosionRadius = (try? c.decode(Float.self, forKey: .focusMaskErosionRadius)) ?? 1.0
        focusMaskDilationRadius = (try? c.decode(Float.self, forKey: .focusMaskDilationRadius)) ?? 1.0
        focusMaskFeatherRadius = (try? c.decode(Float.self, forKey: .focusMaskFeatherRadius)) ?? 2.0
    }
}
