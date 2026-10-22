import SwiftUI

struct AIModelDownloadsView: View {
    let model: RawCullAIModelDownloadsModel

    @Environment(\.dismiss) private var dismiss
    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var selectedLicenceID: RawCullAIModelDownloadID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AIModelDownloadsHeader()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.presentations) { presentation in
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
            if let presentation = model.presentations.first(
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
