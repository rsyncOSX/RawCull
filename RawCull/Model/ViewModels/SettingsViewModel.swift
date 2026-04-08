//
//  SettingsViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

// @Environment(SettingsManager.self) var settingsManager

import Foundation
import OSLog

// Observable settings manager for app configuration
// Persists settings to JSON in Application Support directory

@Observable
final class SettingsViewModel {
    @MainActor static let shared = SettingsViewModel()

    // MARK: - Initialization

    private init() {
        Task {
            await loadSettings()
        }
    }

    // MARK: - Memory Cache Settings

    /// Maximum memory cache size in MB (default: 10000)
    var memoryCacheSizeMB: Int = 10000

    // MARK: - Thumbnail Size Settings

    /// Grid thumbnail size in pixels (default: 100)
    var thumbnailSizeGrid: Int = 200
    /// Grid View thumbnail size in pixels (default: 200)
    var thumbnailSizeGridView: Int = 200
    /// Preview thumbnail size in pixels (default: 1024)
    var thumbnailSizePreview: Int = 2048
    /// Full size thumbnail in pixels (default: 8700)
    var thumbnailSizeFullSize: Int = 8700
    /// Estimated cost per pixel for thumbnail (in bytes, default: 4 for RGBA)
    var thumbnailCostPerPixel: Int = 6
    /// Use thumbnail as zoom preview (default: true)
    var useThumbnailAsZoomPreview: Bool = false

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
                self.thumbnailSizeGrid = savedSettings.thumbnailSizeGrid
                self.thumbnailSizePreview = savedSettings.thumbnailSizePreview
                self.thumbnailSizeFullSize = savedSettings.thumbnailSizeFullSize
                self.thumbnailCostPerPixel = savedSettings.thumbnailCostPerPixel
                self.thumbnailSizeGridView = savedSettings.thumbnailSizeGridView
                self.useThumbnailAsZoomPreview = savedSettings.useThumbnailAsZoomPreview
                self.showScoringBadge = savedSettings.showScoringBadge
                self.showSaliencyBadge = savedSettings.showSaliencyBadge
                self.scoringBorderInsetFraction = savedSettings.scoringBorderInsetFraction
                self.scoringEnableSubjectClassification = savedSettings.scoringEnableSubjectClassification
                self.scoringSalientWeight = savedSettings.scoringSalientWeight
                self.scoringSubjectSizeFactor = savedSettings.scoringSubjectSizeFactor
                self.scoringThumbnailMaxPixelSize = savedSettings.scoringThumbnailMaxPixelSize
            }

            Logger.process.debugMessageOnly("SettingsManager: Settings loaded successfully")
        } catch {
            Logger.process.errorMessageOnly("Failed to load settings: \(error.localizedDescription)")
        }
    }

    /// Save settings to JSON file
    func saveSettings() async {
        do {
            // Validate settings before saving
            validateSettings()

            let fileURL = settingsURL

            // Create directory if it doesn't exist
            let dirURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )

            let settingsToSave = SavedSettings(
                memoryCacheSizeMB: memoryCacheSizeMB,
                thumbnailSizeGrid: thumbnailSizeGrid,
                thumbnailSizePreview: thumbnailSizePreview,
                thumbnailSizeFullSize: thumbnailSizeFullSize,
                thumbnailCostPerPixel: thumbnailCostPerPixel,
                thumbnailSizeGridView: thumbnailSizeGridView,
                useThumbnailAsZoomPreview: useThumbnailAsZoomPreview,
                showScoringBadge: showScoringBadge,
                showSaliencyBadge: showSaliencyBadge,
                scoringBorderInsetFraction: scoringBorderInsetFraction,
                scoringEnableSubjectClassification: scoringEnableSubjectClassification,
                scoringSalientWeight: scoringSalientWeight,
                scoringSubjectSizeFactor: scoringSubjectSizeFactor,
                scoringThumbnailMaxPixelSize: scoringThumbnailMaxPixelSize,
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settingsToSave)

            try data.write(to: fileURL, options: .atomic)
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
            self.memoryCacheSizeMB = 10000
        }
        await saveSettings()
    }

    func resetToDefaultsThumbnails() async {
        await MainActor.run {
            self.thumbnailSizeGrid = 200
            self.thumbnailSizePreview = 2048
            self.thumbnailSizeFullSize = 8700
            self.thumbnailCostPerPixel = 6
            self.thumbnailSizeGridView = 200
        }
        await saveSettings()
    }

    /// Get a snapshot of current settings (safe to call from any context)
    nonisolated func asyncgetsettings() async -> SavedSettings {
        await MainActor.run {
            SavedSettings(
                memoryCacheSizeMB: self.memoryCacheSizeMB,
                thumbnailSizeGrid: self.thumbnailSizeGrid,
                thumbnailSizePreview: self.thumbnailSizePreview,
                thumbnailSizeFullSize: self.thumbnailSizeFullSize,
                thumbnailCostPerPixel: self.thumbnailCostPerPixel,
                thumbnailSizeGridView: self.thumbnailSizeGridView,
                useThumbnailAsZoomPreview: self.useThumbnailAsZoomPreview,
                showScoringBadge: self.showScoringBadge,
                showSaliencyBadge: self.showSaliencyBadge,
                scoringBorderInsetFraction: self.scoringBorderInsetFraction,
                scoringEnableSubjectClassification: self.scoringEnableSubjectClassification,
                scoringSalientWeight: self.scoringSalientWeight,
                scoringSubjectSizeFactor: self.scoringSubjectSizeFactor,
                scoringThumbnailMaxPixelSize: self.scoringThumbnailMaxPixelSize,
            )
        }
    }
}

// MARK: - Codable Model

struct SavedSettings: Codable {
    let memoryCacheSizeMB: Int

    let thumbnailSizeGrid: Int
    let thumbnailSizePreview: Int
    let thumbnailSizeFullSize: Int
    let thumbnailCostPerPixel: Int
    let thumbnailSizeGridView: Int
    let useThumbnailAsZoomPreview: Bool
    let showScoringBadge: Bool
    let showSaliencyBadge: Bool

    let scoringBorderInsetFraction: Float
    let scoringEnableSubjectClassification: Bool
    let scoringSalientWeight: Float
    let scoringSubjectSizeFactor: Float
    let scoringThumbnailMaxPixelSize: Int

    init(
        memoryCacheSizeMB: Int,
        thumbnailSizeGrid: Int,
        thumbnailSizePreview: Int,
        thumbnailSizeFullSize: Int,
        thumbnailCostPerPixel: Int,
        thumbnailSizeGridView: Int,
        useThumbnailAsZoomPreview: Bool,
        showScoringBadge: Bool = false,
        showSaliencyBadge: Bool = false,
        scoringBorderInsetFraction: Float = 0.04,
        scoringEnableSubjectClassification: Bool = true,
        scoringSalientWeight: Float = 0.75,
        scoringSubjectSizeFactor: Float = 0.1,
        scoringThumbnailMaxPixelSize: Int = 512,
    ) {
        self.memoryCacheSizeMB = memoryCacheSizeMB
        self.thumbnailSizeGrid = thumbnailSizeGrid
        self.thumbnailSizePreview = thumbnailSizePreview
        self.thumbnailSizeFullSize = thumbnailSizeFullSize
        self.thumbnailCostPerPixel = thumbnailCostPerPixel
        self.thumbnailSizeGridView = thumbnailSizeGridView
        self.useThumbnailAsZoomPreview = useThumbnailAsZoomPreview
        self.showScoringBadge = showScoringBadge
        self.showSaliencyBadge = showSaliencyBadge
        self.scoringBorderInsetFraction = scoringBorderInsetFraction
        self.scoringEnableSubjectClassification = scoringEnableSubjectClassification
        self.scoringSalientWeight = scoringSalientWeight
        self.scoringSubjectSizeFactor = scoringSubjectSizeFactor
        self.scoringThumbnailMaxPixelSize = scoringThumbnailMaxPixelSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memoryCacheSizeMB = try c.decode(Int.self, forKey: .memoryCacheSizeMB)
        thumbnailSizeGrid = try c.decode(Int.self, forKey: .thumbnailSizeGrid)
        thumbnailSizePreview = try c.decode(Int.self, forKey: .thumbnailSizePreview)
        thumbnailSizeFullSize = try c.decode(Int.self, forKey: .thumbnailSizeFullSize)
        thumbnailCostPerPixel = try c.decode(Int.self, forKey: .thumbnailCostPerPixel)
        thumbnailSizeGridView = try c.decode(Int.self, forKey: .thumbnailSizeGridView)
        useThumbnailAsZoomPreview = try c.decode(Bool.self, forKey: .useThumbnailAsZoomPreview)
        showScoringBadge = (try? c.decode(Bool.self, forKey: .showScoringBadge)) ?? false
        showSaliencyBadge = (try? c.decode(Bool.self, forKey: .showSaliencyBadge)) ?? false
        scoringBorderInsetFraction = (try? c.decode(Float.self, forKey: .scoringBorderInsetFraction)) ?? 0.04
        scoringEnableSubjectClassification = (try? c.decode(Bool.self, forKey: .scoringEnableSubjectClassification)) ?? true
        scoringSalientWeight = (try? c.decode(Float.self, forKey: .scoringSalientWeight)) ?? 0.75
        scoringSubjectSizeFactor = (try? c.decode(Float.self, forKey: .scoringSubjectSizeFactor)) ?? 0.1
        scoringThumbnailMaxPixelSize = (try? c.decode(Int.self, forKey: .scoringThumbnailMaxPixelSize)) ?? 512
    }
}
