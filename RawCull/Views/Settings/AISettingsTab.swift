import SwiftUI

struct AISettingsTab: View {
    @Bindable var model: RawCullAISettingsModel

    @State private var showModelDownloads = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AIModelSettingsCard(model: model)
                AIIntegrationReadinessCard(
                    capabilities: model.capabilities,
                    selectedSegmentationModel: model.selectedSegmentationModel,
                )

                HStack {
                    Button {
                        showModelDownloads = true
                    } label: {
                        Label("Download AI Models", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(RefinedGlassButtonStyle())

                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .disabled(model.isScanningSavedBurstData)
                    .buttonStyle(RefinedGlassButtonStyle())

                    Spacer()
                }
            }
        }
        .task {
            await model.refresh()
        }
        .sheet(isPresented: $showModelDownloads) {
            AIModelDownloadsView(model: model.modelManagementModel)
        }
    }
}

private struct AIModelSettingsCard: View {
    @Bindable var model: RawCullAISettingsModel

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Models")
                    .font(.system(size: 14, weight: .semibold))
                Divider()

                ForEach(RawCullAIModelInclusion.segmentationModels) { segmentationModel in
                    AICapabilityStatusView(
                        title: "\(segmentationModel.displayName) model",
                        status: model.capabilities.segmentationModelStatus(
                            for: segmentationModel,
                        ),
                        availableMessage: "\(segmentationModel.displayName) model resources are installed.",
                        missingMessage: "\(segmentationModel.displayName) model resources are not installed.",
                        showsLocationAction: true,
                    )
                }

                if !RawCullAIModelInclusion.segmentationModels.isEmpty {
                    Text(segmentationModelMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            model.selectedSegmentationModelStatus.isAvailable
                                ? .green
                                : .secondary,
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                if RawCullAIModelInclusion.segmentationModels.count > 1 {
                    Picker(
                        "Selected Deep Review model",
                        selection: $model.selectedSegmentationModel,
                    ) {
                        ForEach(RawCullAIModelInclusion.segmentationModels) {
                            segmentationModel in
                            Text(segmentationModel.displayName)
                                .tag(segmentationModel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 12, weight: .medium))
                    .help("Choose the segmentation model RawCull uses for Deep Review.")
                }

                ForEach(RawCullAIModelInclusion.clipModels) { clipModel in
                    Divider()

                    AICapabilityStatusView(
                        title: "\(clipModel.displayName) CLIP model",
                        status: model.capabilities.clipModelStatus(for: clipModel),
                        availableMessage: "\(clipModel.displayName) CLIP model resources are installed.",
                        missingMessage: "\(clipModel.displayName) CLIP is not installed.",
                        showsLocationAction: true,
                    )
                }

                if RawCullAIModelInclusion.clipModels.count > 1 {
                    Divider()

                    Picker("Selected CLIP model", selection: $model.selectedCLIPModel) {
                        ForEach(RawCullAIModelInclusion.clipModels) { clipModel in
                            Text(clipModel.displayName)
                                .tag(clipModel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 12, weight: .medium))
                    .help("Choose the single CLIP model RawCull uses for similarity and semantic search.")
                }

                Toggle(
                    "Use selected CLIP model for similarity",
                    isOn: $model.useCLIPForSimilarity,
                )
                .font(.system(size: 12, weight: .medium))
                .toggleStyle(.switch)
                .help(Text(clipSimilarityHelp))
                .accessibilityValue(similarityBackendMessage)
                .accessibilityHint(String(localized: clipSimilarityHelp))

                Text(similarityBackendMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        model.useCLIPForSimilarity && model.selectedCLIPModelStatus.isAvailable
                            ? .green
                            : .secondary,
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Active similarity backend")
                    .accessibilityValue(similarityBackendMessage)

                Divider()

                SavedBurstSimilarityEvidenceView(
                    evidence: model.savedBurstEvidence,
                    scanFailure: model.savedBurstScanFailure,
                    isScanning: model.isScanningSavedBurstData,
                )
            }
        }
    }

    private var similarityBackendMessage: String {
        let selectedName = model.selectedCLIPModel.displayName
        if model.useCLIPForSimilarity, model.selectedCLIPModelStatus.isAvailable {
            return "Similarity indexing uses the selected \(selectedName) CLIP model."
        }
        if model.selectedCLIPModelStatus.isAvailable {
            return "Similarity indexing uses Vision feature prints until the selected \(selectedName) CLIP model is enabled."
        }
        if model.useCLIPForSimilarity {
            return "The selected \(selectedName) CLIP model is unavailable, so similarity indexing uses Vision feature prints."
        }
        return "Similarity indexing currently uses Vision feature prints."
    }

    private var segmentationModelMessage: String {
        let name = model.selectedSegmentationModel.displayName
        if model.selectedSegmentationModelStatus.isAvailable {
            return "Deep Review uses the selected \(name) model."
        }
        return "The selected \(name) model becomes active when its bundle is installed and valid."
    }

    private var clipSimilarityHelp: LocalizedStringResource {
        if model.selectedCLIPModelStatus.isAvailable {
            return "Use validated \(model.selectedCLIPModel.displayName) CLIP embeddings. Invalid output is retried before an image is excluded."
        }
        return "Save the selected CLIP preference now; it becomes active when that model is installed and valid."
    }
}

private struct AIIntegrationReadinessCard: View {
    let capabilities: RawCullAICapabilities
    let selectedSegmentationModel: RawCullSegmentationModel

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Integration Readiness")
                    .font(.system(size: 14, weight: .semibold))
                Divider()

                AICapabilityStatusView(
                    title: "Vision similarity",
                    status: capabilities.visionFeaturePrint,
                    availableMessage: "Vision feature-print similarity is available.",
                    missingMessage: "Vision feature-print similarity is unavailable.",
                    showsLocationAction: false,
                )

                Divider()

                AICapabilityStatusView(
                    title: "Subject mask storage",
                    status: capabilities.subjectMaskStorage,
                    availableMessage: "PhotoAIKit mask storage is ready at RawCull's cache location.",
                    missingMessage: "Subject mask storage is unavailable.",
                    showsLocationAction: false,
                )

                Divider()

                AICapabilityStatusView(
                    title: "In-process \(selectedSegmentationModel.displayName) review",
                    status: capabilities.inProcessMaskGeneration,
                    availableMessage: "\(selectedSegmentationModel.displayName) mask generation runs inside RawCull.",
                    missingMessage: "In-process mask generation needs a valid \(selectedSegmentationModel.displayName) model.",
                    showsLocationAction: false,
                )
            }
        }
    }
}

private struct AICapabilityStatusView: View {
    let title: String
    let status: RawCullAICapabilityStatus
    let availableMessage: String
    let missingMessage: String
    let showsLocationAction: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: status.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(status.color)
                        .accessibilityHidden(true)

                    Text("\(title):")
                        .font(.system(size: 12, weight: .medium))

                    Text(status.displayTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(status.color)

                    Spacer()
                }
                Text(detailMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(RawCullAccessibilityPresentation.capabilityValue(
                status: status,
                availableMessage: availableMessage,
                missingMessage: missingMessage,
            ))

            if showsLocationAction,
               case let .available(location?) = status {
                ModelLocationButton(location: location)
            }
        }
    }

    private var detailMessage: String {
        switch status {
        case let .checking(expectedLocations):
            guard let first = expectedLocations.first else {
                return "Checking model resources."
            }
            return "Checking model resources at \(first.path)."

        case .available:
            return availableMessage

        case let .missing(expectedLocations):
            guard let first = expectedLocations.first else { return missingMessage }
            return "\(missingMessage) Expected location: \(first.path)"

        case let .invalid(location, reason):
            if let location {
                return "Invalid resource at \(location.path): \(reason)"
            }
            return "Invalid resource: \(reason)"

        case let .unavailable(reason):
            return reason
        }
    }
}

private struct SavedBurstSimilarityEvidenceView: View {
    let evidence: RawCullSavedBurstEvidence?
    let scanFailure: String?
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                Text("Saved burst evidence:")
                    .font(.system(size: 12, weight: .medium))

                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)

                Spacer()

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .fixedSize()
                }
            }
            Text(detailText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved burst similarity evidence")
        .accessibilityValue("\(statusTitle). \(detailText)")
    }

    private var statusTitle: String {
        if scanFailure != nil {
            return "Unavailable"
        }
        guard let evidence else { return "Scanning..." }
        return switch evidence.backend {
        case .noSavedData: "No saved data"
        case .clip: "CLIP"
        case .visionFeaturePrint: "Vision"
        case .visionFallback: "Vision fallback"
        case .mixed: "Mixed"
        }
    }

    private var iconName: String {
        if scanFailure != nil {
            return "xmark.circle.fill"
        }
        guard let evidence else { return "internaldrive" }
        return switch evidence.backend {
        case .noSavedData: "tray"
        case .clip: "checkmark.circle.fill"
        case .visionFeaturePrint: "eye.circle.fill"
        case .visionFallback: "arrow.counterclockwise.circle.fill"
        case .mixed: "square.stack.3d.up.fill"
        }
    }

    private var statusColor: Color {
        if scanFailure != nil {
            return .red
        }
        guard let evidence else { return .secondary }
        return switch evidence.backend {
        case .noSavedData: .secondary
        case .clip: .green
        case .visionFeaturePrint: .blue
        case .visionFallback, .mixed: .orange
        }
    }

    private var detailText: String {
        if let scanFailure {
            return "RawCull could not inspect saved burst data: \(scanFailure)"
        }
        guard let evidence else {
            return "Scanning RawCull's saved burst analysis caches."
        }
        guard evidence.totalEmbeddingCount > 0 else {
            if evidence.skippedCacheFileCount > 0 {
                return "No current-format burst embeddings were found. " +
                    "\(countLabel(evidence.skippedCacheFileCount, singular: "cache file")) could not be read or was outdated."
            }
            return "No saved burst analysis embeddings were found. Run Analyze Bursts to create cache evidence."
        }

        let embeddings = countLabel(evidence.totalEmbeddingCount, singular: "embedding")
        let catalogs = countLabel(evidence.decodedCatalogCount, singular: "saved catalog")
        let groups = countLabel(evidence.burstGroupCount, singular: "burst group")
        var text = "Found \(embeddings) in \(catalogs) across \(groups): " +
            "\(evidence.clipEmbeddingCount) CLIP and \(evidence.visionEmbeddingCount) Vision."
        if evidence.skippedCacheFileCount > 0 {
            text += " \(countLabel(evidence.skippedCacheFileCount, singular: "cache file")) could not be read or was outdated."
        }
        return text + " Counts come from saved payloads, not the preference control."
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

private extension RawCullAICapabilityStatus {
    var displayTitle: String {
        switch self {
        case .checking: "Checking..."
        case .available: "Available"
        case .missing: "Missing"
        case .invalid: "Invalid"
        case .unavailable: "Not configured"
        }
    }

    var iconName: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .available: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle"
        case .invalid: "xmark.circle.fill"
        case .unavailable: "clock.badge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .available: .green
        case .missing, .unavailable: .orange
        case .invalid: .red
        }
    }
}
