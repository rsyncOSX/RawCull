import SwiftUI

struct AIModelLicenceReviewView: View {
    let presentation: RawCullAIModelDownloadPresentation
    let model: RawCullAIModelDownloadsModel

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
