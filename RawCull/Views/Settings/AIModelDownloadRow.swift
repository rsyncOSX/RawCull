import SwiftUI

struct AIModelDownloadRow: View {
    let presentation: RawCullAIModelDownloadPresentation
    let model: RawCullAIModelDownloadsModel
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
