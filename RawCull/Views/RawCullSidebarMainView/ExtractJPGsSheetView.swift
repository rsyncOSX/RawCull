import SwiftUI
import UniformTypeIdentifiers

struct ExtractJPGsSheetView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(FileOperationsModel.self) private var fileOperations
    @Environment(CatalogController.self) private var catalogController
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingDestination = false

    private var selectedFiles: [FileItem] {
        fileOperations.filesForJPGExtraction
    }

    private var destinationOptions: [ARWSourceCatalog] {
        guard let destination = fileOperations.extractJPGDestination,
              !catalog.sources.contains(where: { $0.url == destination.url })
        else {
            return catalog.sources
        }

        return catalog.sources + [destination]
    }

    private var canExtract: Bool {
        !selectedFiles.isEmpty &&
            fileOperations.extractJPGDestination != nil &&
            fileOperations.currentExtractAndSaveJPGsActor == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Extract JPGs")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Images", selection: Bindable(fileOperations).extractJPGSelectedOnly) {
                    if !fileOperations.selectedFilesForJPGExtraction.isEmpty {
                        Text("Selected images").tag(true)
                    }
                    Text("Complete catalog").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("Export", selection: Bindable(fileOperations).extractJPGExportMode) {
                    ForEach(ExtractJPGExportMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Destination", selection: Bindable(fileOperations).extractJPGDestination) {
                    ForEach(destinationOptions) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }

                LabeledContent("Folder") {
                    HStack {
                        Text(fileOperations.extractJPGDestination?.url.path(percentEncoded: false) ?? "No folder selected")
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
                    guard let destination = fileOperations.extractJPGDestination else { return }
                    fileOperations.startSelectedJPGExtraction(
                        destination: destination,
                        exportMode: fileOperations.extractJPGExportMode,
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
                fileOperations.extractJPGDestination = ARWSourceCatalog(
                    name: url.lastPathComponent,
                    url: url,
                )
            }
        }
    }

    private var sourceSummary: String {
        if !fileOperations.extractJPGSelectedOnly {
            return "Complete catalog"
        }
        if selection.selectedFileIDs.isEmpty {
            return catalogController.selectedFile?.name ?? "No image selected"
        }
        return "Selected thumbnails"
    }
}
