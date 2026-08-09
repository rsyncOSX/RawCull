import SwiftUI

struct AIModelDownloadsView: View {
    let model: RawCullAISettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLicenceID: RawCullAIModelDownloadID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AIModelDownloadsHeader()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.modelDownloadPresentations) { presentation in
                        AIModelDownloadRow(
                            presentation: presentation,
                            model: model,
                            selectedLicenceID: $selectedLicenceID,
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("Models run locally after installation. RawCull never uploads photographs as part of a model download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 650)
        .sheet(item: $selectedLicenceID) { id in
            if let presentation = model.modelDownloadPresentations.first(
                where: { $0.id == id },
            ) {
                AIModelLicenceReviewView(
                    presentation: presentation,
                    model: model,
                )
            }
        }
        .task {
            await model.refresh()
        }
    }
}

private struct AIModelDownloadsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Model Downloads")
                .font(.title2.weight(.semibold))

            Text("RawCull uses on-demand Managed Background Assets. macOS stores and manages downloaded models, which run locally after installation. Their current access location can change between app launches.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AIModelDownloadRow: View {
    let presentation: RawCullAIModelDownloadPresentation
    let model: RawCullAISettingsModel
    @Binding var selectedLicenceID: RawCullAIModelDownloadID?

    @State private var showRemoveConfirmation = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                AIModelDownloadIdentityView(
                    descriptor: presentation.descriptor,
                    state: presentation.state,
                    licenceAccepted: presentation.licenceAccepted,
                )

                Divider()

                AIModelLicenceSummaryView(
                    descriptor: presentation.descriptor,
                    licenceAccepted: presentation.licenceAccepted,
                )

                AIModelDownloadProgressView(state: presentation.state)

                ViewThatFits {
                    HStack(spacing: 8) {
                        actionButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        actionButtons
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove downloaded model?",
            isPresented: $showRemoveConfirmation,
        ) {
            Button("Remove Model", role: .destructive) {
                Task {
                    await model.removeManagedModel(presentation.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RawCull will remove only its managed asset pack. A manually installed model is not deleted.")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            selectedLicenceID = presentation.id
        } label: {
            Label("Review Licence", systemImage: "doc.text")
        }
        .accessibilityHint("Reviews the complete model licence and verification status.")

        switch presentation.state {
        case .ready:
            Button {
                model.startModelDownload(presentation.id)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .accessibilityHint("Downloads this model locally using Managed Background Assets.")

        case .licenceRequired:
            Button {
                selectedLicenceID = presentation.id
            } label: {
                Label("Accept and Download", systemImage: "checkmark.shield")
            }
            .accessibilityHint("Reviews the licence before this model can be downloaded.")

        case .downloading:
            Button(role: .cancel) {
                model.cancelModelDownload(presentation.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
            .accessibilityHint("Cancels this model download without affecting installed models.")

        case let .installed(location):
            ModelLocationButton(location: location)

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .accessibilityHint("Removes only RawCull's managed asset pack.")

        case .failed:
            Button {
                model.startModelDownload(presentation.id)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .accessibilityHint("Retries this model download.")

        case .checking, .unavailable, .notConfigured, .validating, .removing:
            EmptyView()
        }
    }
}

private struct AIModelDownloadIdentityView: View {
    let descriptor: RawCullAIModelDownloadDescriptor
    let state: RawCullAIModelDownloadState
    let licenceAccepted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(descriptor.displayName)
                    .font(.headline)

                Spacer()

                Label {
                    Text(state.title)
                } icon: {
                    Image(systemName: state.iconName)
                        .accessibilityHidden(true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.color)
            }

            Text(descriptor.purpose)
                .font(.callout)

            Text("Publisher: \(descriptor.publisher) · Version: \(descriptor.modelVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if case .installed = state {
                Text("Stored and managed by macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .blocked(reason) = descriptor.releaseReadiness {
                Label {
                    Text(reason)
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if case let .failed(message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(RawCullAccessibilityPresentation.modelDownloadValue(
            state: state,
            licenceAccepted: licenceAccepted,
        ))
    }
}

private struct AIModelLicenceSummaryView: View {
    let descriptor: RawCullAIModelDownloadDescriptor
    let licenceAccepted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Licence:")
                    .font(.caption.weight(.medium))

                Text(descriptor.licence.name)
                    .font(.caption)

                if licenceAccepted {
                    Label("Accepted", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(descriptor.licence.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(descriptor.displayName) licence")
        .accessibilityValue("\(descriptor.licence.name). \(licenceAccepted ? "Accepted" : "Not accepted"). \(descriptor.licence.summary)")
    }
}

private struct AIModelDownloadProgressView: View {
    let state: RawCullAIModelDownloadState

    var body: some View {
        switch state {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Model download progress")
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))

        case .checking, .validating, .removing:
            ProgressView(state.activityTitle)
                .controlSize(.small)
                .accessibilityLabel("Model download status")
                .accessibilityValue(Text(state.activityTitle))

        case .unavailable, .licenceRequired, .notConfigured, .ready,
             .installed, .failed:
            EmptyView()
        }
    }
}

private struct AIModelLicenceReviewView: View {
    let presentation: RawCullAIModelDownloadPresentation
    let model: RawCullAISettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var isAccepting = false
    @State private var bundledLicenceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(presentation.descriptor.displayName) Licence")
                .font(.title2.weight(.semibold))

            AIModelLicenceMetadataView(
                descriptor: presentation.descriptor,
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(presentation.descriptor.licence.summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let licenceText = bundledLicenceText {
                        Text(verbatim: licenceText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ContentUnavailableView(
                            "Verified Licence Text Not Packaged",
                            systemImage: "doc.badge.ellipsis",
                            description: Text("Acceptance and downloading remain disabled until RawCull includes a checksum-verified complete licence document."),
                        )
                    }
                }
            }

            HStack {
                Link(
                    "Open Complete Licence",
                    destination: presentation.descriptor.licence.completeTextURL,
                )
                Link(
                    "Model Card",
                    destination: presentation.descriptor.modelCardURL,
                )

                Spacer()

                Button("Close", role: .cancel) {
                    dismiss()
                }

                if presentation.descriptor.licence.requiresExplicitAcceptance {
                    Button("Accept") {
                        isAccepting = true
                        Task {
                            await model.acceptModelLicence(for: presentation.id)
                            isAccepting = false
                            dismiss()
                        }
                    }
                    .disabled(!canAccept || isAccepting)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(
                        canAccept
                            ? "Accepts the checksum-verified complete licence for this model."
                            : "Acceptance is disabled until the complete licence and release evidence are verified.",
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .task(id: presentation.id) {
            bundledLicenceText = loadBundledLicenceText()
        }
    }

    private var canAccept: Bool {
        presentation.descriptor.releaseReadiness.isReady
            && presentation.descriptor.licence.textSHA256 != nil
            && bundledLicenceText != nil
    }

    private func loadBundledLicenceText() -> String? {
        presentation.descriptor.licence.verifiedBundledText(
            in: .main,
        )
    }
}

private struct AIModelLicenceMetadataView: View {
    let descriptor: RawCullAIModelDownloadDescriptor

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Publisher")
                    .foregroundStyle(.secondary)
                Text(descriptor.publisher)
                    .textSelection(.enabled)
            }
            GridRow {
                Text("Model version")
                    .foregroundStyle(.secondary)
                Text(descriptor.modelVersion)
                    .textSelection(.enabled)
            }
            GridRow {
                Text("Licence")
                    .foregroundStyle(.secondary)
                Text(descriptor.licence.name)
                    .textSelection(.enabled)
            }
            if let revision = descriptor.upstreamRevision {
                GridRow {
                    Text("Upstream revision")
                        .foregroundStyle(.secondary)
                    Text(revision)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .font(.caption)
    }
}

private extension RawCullAIModelDownloadState {
    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking"
        case .unavailable: "Distribution blocked"
        case .licenceRequired: "Licence required"
        case .notConfigured: "Server pending"
        case .ready: "Ready"
        case .downloading: "Downloading"
        case .validating: "Validating"
        case .installed: "Installed"
        case .removing: "Removing"
        case .failed: "Failed"
        }
    }

    var activityTitle: LocalizedStringResource {
        switch self {
        case .checking: "Checking model service…"
        case .validating: "Validating model…"
        case .removing: "Removing model…"

        case .unavailable, .licenceRequired, .notConfigured, .ready,
             .downloading, .installed, .failed:
            ""
        }
    }

    var iconName: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .unavailable: "exclamationmark.shield"
        case .licenceRequired: "doc.badge.ellipsis"
        case .notConfigured: "network.slash"
        case .ready: "arrow.down.circle"
        case .downloading: "arrow.down.circle.fill"
        case .validating: "checkmark.shield"
        case .installed: "checkmark.circle.fill"
        case .removing: "trash.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .installed: .green
        case .ready, .downloading, .validating: .blue
        case .checking, .removing: .secondary
        case .unavailable, .licenceRequired, .notConfigured: .orange
        case .failed: .red
        }
    }
}
