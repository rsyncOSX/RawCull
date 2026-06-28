import SwiftUI

struct ExtractJPGsSheetView: View {
    @Bindable var viewModel: RawCullViewModel
    @Environment(\.dismiss) private var dismiss

    private var selectedFiles: [FileItem] {
        viewModel.selectedFilesForJPGExtraction
    }

    private var canExtract: Bool {
        !selectedFiles.isEmpty &&
            viewModel.extractJPGDestination != nil &&
            viewModel.currentExtractAndSaveJPGsActor == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Extract JPGs")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Export", selection: $viewModel.extractJPGExportMode) {
                    ForEach(ExtractJPGExportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Destination", selection: $viewModel.extractJPGDestination) {
                    ForEach(viewModel.sources) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }

                LabeledContent("Images", value: "\(selectedFiles.count)")
                LabeledContent("Source", value: sourceSummary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Extract") {
                    guard let destination = viewModel.extractJPGDestination else { return }
                    viewModel.startSelectedJPGExtraction(
                        destination: destination,
                        exportMode: viewModel.extractJPGExportMode,
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canExtract)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var sourceSummary: String {
        if viewModel.selectedFileIDs.isEmpty {
            return viewModel.selectedFile?.name ?? "No image selected"
        }
        return "Selected thumbnails"
    }
}
