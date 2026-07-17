import SwiftUI

struct AISettingsTab: View {
    @Bindable var model: RawCullAISettingsModel

    @State private var showDownloadPlaceholder = false
    @State private var showDeleteBurstDataConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AIModelSettingsCard(model: model)
                AIIntegrationReadinessCard(capabilities: model.capabilities)

                HStack {
                    Button {
                        showDownloadPlaceholder = true
                    } label: {
                        Label("Download SAM 3 Model", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .disabled(model.capabilities.sam3Model.isAvailable)
                    .buttonStyle(RefinedGlassButtonStyle())

                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .disabled(model.isScanningSavedBurstData || model.isDeletingSavedBurstData)
                    .buttonStyle(RefinedGlassButtonStyle())

                    Spacer()
                }

                deleteSavedBurstDataButton
            }
        }
        .task {
            await model.refresh()
        }
        .alert("SAM 3 Model Download", isPresented: $showDownloadPlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sam3DownloadMessage)
        }
    }

    private var deleteSavedBurstDataButton: some View {
        Button {
            showDeleteBurstDataConfirmation = true
        } label: {
            Label(
                model.isDeletingSavedBurstData ? "Deleting..." : "Delete Saved Burst Data",
                systemImage: "trash",
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
        }
        .disabled(model.isScanningSavedBurstData || model.isDeletingSavedBurstData)
        .buttonStyle(RefinedGlassButtonStyle())
        .confirmationDialog(
            "Delete All Saved Burst Data?",
            isPresented: $showDeleteBurstDataConfirmation,
        ) {
            Button("Delete All", role: .destructive) {
                Task { await model.deleteSavedBurstData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This control is reserved for the AI integration. Its action is " +
                    "intentionally empty until saved AI artifacts are introduced. " +
                    "Original photos are never deleted.",
            )
        }
    }

    private var sam3DownloadMessage: String {
        let location = model.capabilities.sam3Model.primaryLocation?.path
            ?? "the RawCull Application Support Models folder"
        return "The SAM 3 model download location will be added later. For now, install " +
            "the model files manually in \(location)."
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

                AICapabilityStatusView(
                    title: "SAM 3 model",
                    status: model.capabilities.sam3Model,
                    availableMessage: "SAM 3 model resources are installed.",
                    missingMessage: "SAM 3 model resources are not installed.",
                )

                Divider()

                AICapabilityStatusView(
                    title: "CLIP model",
                    status: model.capabilities.clipModel,
                    availableMessage: "CLIP model resources are installed.",
                    missingMessage: "CLIP is not installed; Vision feature prints remain available.",
                )

                Toggle("Use CLIP for similarity", isOn: $model.useCLIPForSimilarity)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .disabled(!model.capabilities.clipModel.isAvailable)
                    .help(clipSimilarityHelp)

                Text(similarityBackendMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        model.useCLIPForSimilarity && model.capabilities.clipModel.isAvailable
                            ? .green
                            : .secondary,
                    )
                    .fixedSize(horizontal: false, vertical: true)

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
        if model.useCLIPForSimilarity, model.capabilities.clipModel.isAvailable {
            return "Similarity indexing will use CLIP image embeddings with a whole-batch Vision fallback."
        }
        if model.capabilities.clipModel.isAvailable {
            return "Similarity indexing currently uses Vision feature prints. The CLIP control is present but intentionally not connected yet."
        }
        return "Similarity indexing currently uses Vision feature prints."
    }

    private var clipSimilarityHelp: String {
        if model.capabilities.clipModel.isAvailable {
            return "This Phase 2 control is present but intentionally not connected yet."
        }
        return "Install a valid CLIP model before enabling CLIP similarity."
    }
}

private struct AIIntegrationReadinessCard: View {
    let capabilities: RawCullAICapabilities

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Integration Readiness")
                    .font(.system(size: 14, weight: .semibold))
                Divider()

                AICapabilityStatusView(
                    title: "Vision fallback",
                    status: capabilities.visionFeaturePrint,
                    availableMessage: "Vision feature-print similarity is available.",
                    missingMessage: "Vision feature-print similarity is unavailable.",
                )

                Divider()

                AICapabilityStatusView(
                    title: "Subject mask storage",
                    status: capabilities.subjectMaskStorage,
                    availableMessage: "PhotoAIKit mask storage is ready at RawCull's cache location.",
                    missingMessage: "Subject mask storage is unavailable.",
                )

                Divider()

                AICapabilityStatusView(
                    title: "SAM 3 mask worker",
                    status: capabilities.maskWorker,
                    availableMessage: "The source-controlled mask worker is available.",
                    missingMessage: "The source-controlled mask worker has not been added yet.",
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: status.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status.color)

                Text("\(title):")
                    .font(.system(size: 12, weight: .medium))

                Text(status.displayTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(status.color)

                Spacer()
            }
            .accessibilityElement(children: .combine)

            Text(detailMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detailMessage: String {
        switch status {
        case let .available(location):
            if let location {
                return "\(availableMessage) Location: \(location.path)"
            }
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
            .accessibilityElement(children: .combine)

            Text(detailText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusTitle: String {
        if scanFailure != nil { return "Unavailable" }
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
        if scanFailure != nil { return "xmark.circle.fill" }
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
        if scanFailure != nil { return .red }
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
        case .available: "Available"
        case .missing: "Missing"
        case .invalid: "Invalid"
        case .unavailable: "Not configured"
        }
    }

    var iconName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle"
        case .invalid: "xmark.circle.fill"
        case .unavailable: "clock.badge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .available: .green
        case .missing, .unavailable: .orange
        case .invalid: .red
        }
    }

    var primaryLocation: URL? {
        switch self {
        case let .available(location): location
        case let .missing(expectedLocations): expectedLocations.first
        case let .invalid(location, _): location
        case .unavailable: nil
        }
    }
}
