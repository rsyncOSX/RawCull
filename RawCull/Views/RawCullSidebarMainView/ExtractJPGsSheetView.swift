import SwiftUI
import UniformTypeIdentifiers

struct ExtractJPGsSheetView: View {
    @Bindable var viewModel: RawCullViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingDestination = false

    private var selectedFiles: [FileItem] {
        viewModel.fileOperations.filesForJPGExtraction
    }

    private var destinationOptions: [ARWSourceCatalog] {
        guard let destination = viewModel.fileOperations.extractJPGDestination,
              !viewModel.catalog.sources.contains(where: { $0.url == destination.url })
        else {
            return viewModel.catalog.sources
        }

        return viewModel.catalog.sources + [destination]
    }

    private var canExtract: Bool {
        !selectedFiles.isEmpty &&
            viewModel.fileOperations.extractJPGDestination != nil &&
            viewModel.fileOperations.currentExtractAndSaveJPGsActor == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Extract JPGs")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Images", selection: Bindable(viewModel.fileOperations).extractJPGSelectedOnly) {
                    if !viewModel.fileOperations.selectedFilesForJPGExtraction.isEmpty {
                        Text("Selected images").tag(true)
                    }
                    Text("Complete catalog").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("Export", selection: Bindable(viewModel.fileOperations).extractJPGExportMode) {
                    ForEach(ExtractJPGExportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Destination", selection: Bindable(viewModel.fileOperations).extractJPGDestination) {
                    ForEach(destinationOptions) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }

                LabeledContent("Folder") {
                    HStack {
                        Text(viewModel.fileOperations.extractJPGDestination?.url.path(percentEncoded: false) ?? "No folder selected")
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Choose...") {
                            isChoosingDestination = true
                        }
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
                    guard let destination = viewModel.fileOperations.extractJPGDestination else { return }
                    viewModel.fileOperations.startSelectedJPGExtraction(
                        destination: destination,
                        exportMode: viewModel.fileOperations.extractJPGExportMode,
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
        .fileImporter(isPresented: $isChoosingDestination, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                viewModel.fileOperations.extractJPGDestination = ARWSourceCatalog(
                    name: url.lastPathComponent,
                    url: url,
                )
            }
        }
    }

    private var sourceSummary: String {
        if !viewModel.fileOperations.extractJPGSelectedOnly {
            return "Complete catalog"
        }
        if viewModel.selection.selectedFileIDs.isEmpty {
            return viewModel.selectedFile?.name ?? "No image selected"
        }
        return "Selected thumbnails"
    }
}
