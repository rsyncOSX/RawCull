import SwiftUI

struct SidebarARWCatalogFileView: View {
    @Environment(\.openWindow) var openWindow

    @Bindable var viewModel: RawCullViewModel
    @Binding var isShowingPicker: Bool
    @Binding var progress: Double
    @Binding var selectedSource: ARWSourceCatalog?

    @Binding var scanning: Bool
    @Binding var creatingThumbnails: Bool

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    @State var counterScannedFiles: Int = 0
    
    @State private var verticalimages: Bool = true

    let issorting: Bool
    let max: Double

    // let filetable: AnyView

    var body: some View {
        Group {
            if selectedSource == nil {
                // Empty State when no catalog is selected
                ContentUnavailableView {
                    Label("No Catalog Selected", systemImage: "folder.badge.plus")
                } description: {
                    Text("Select a folder from the sidebar or add a new one to start scanning.")
                } actions: {
                    Button("Add Catalog") { isShowingPicker = true }
                }
            } else if scanning {
                ProgressView("Scanning directory for ARW images, counting files: \(counterScannedFiles)")
            } else if files.isEmpty, !scanning {
                ContentUnavailableView {
                    Label("No Files Found", systemImage: "folder.badge.plus")
                } description: {
                    Text("This catalog does not contain ARW images, or the images are empty. Please try scanning another catalog.")
                }
            } else {
                ZStack {
                    VStack(alignment: .leading) {
                        HStack {
                            
                            ConditionalGlassButton(
                                systemImage: "photo.stack",
                                text: verticalimages ? "Table" : "Images",
                                helpText: "View table or images",
                            ) {
                                verticalimages.toggle()
                            }
                            
                            if verticalimages == false {
                                ConditionalGlassButton(
                                    systemImage: "document.on.document",
                                    text: "Copy",
                                    helpText: "Copy tagged images to destination...",
                                ) {
                                    viewModel.sheetType = .copytasksview
                                    viewModel.showcopyARWFilesView = true
                                }
                                .disabled(viewModel.creatingthumbnails)

                                ConditionalGlassButton(
                                    systemImage: "trash.fill",
                                    text: "Clear",
                                    helpText: "Clear tagged files",
                                ) {
                                    viewModel.alertType = .clearToggledFiles
                                    viewModel.showingAlert = true
                                }
                                .disabled(viewModel.creatingthumbnails)

                                ConditionalGlassButton(
                                    systemImage: "trash",
                                    text: "Reset",
                                    helpText: "Clean up data from previous saves",
                                ) {
                                    viewModel.alertType = .resetSavedFiles
                                    viewModel.showingAlert = true
                                }
                                .disabled(viewModel.creatingthumbnails)

                                if !viewModel.files.isEmpty {
                                    Picker("Rating", selection: $viewModel.rating) {
                                        // Iterate over the range 0 to 5
                                        ForEach(0 ... 5, id: \.self) { number in
                                            Text("\(number)").tag(number)
                                        }
                                    }
                                    .pickerStyle(DefaultPickerStyle())
                                }
                            }
                            
                            if viewModel.focusPoints?.isEmpty == false {
                                Image(systemName: "viewfinder.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.yellow.opacity(0.12), in: Capsule())
                                    .help("Focus Points available")
                            }
                        }
                        .padding()
                        
                        if verticalimages {
                            ImageTableVerticalView(viewModel: viewModel,
                                             nsImage: $nsImage,
                                             cgImage: $cgImage,
                                             zoomCGImageWindowFocused: $zoomCGImageWindowFocused,
                                             zoomNSImageWindowFocused: $zoomNSImageWindowFocused,
                                             openWindow: { id in openWindow(id: id) })
                            
                        } else {
                            FileTableRowView(viewModel: viewModel,
                                             nsImage: $nsImage,
                                             cgImage: $cgImage,
                                             zoomCGImageWindowFocused: $zoomCGImageWindowFocused,
                                             zoomNSImageWindowFocused: $zoomNSImageWindowFocused,
                                             openWindow: { id in openWindow(id: id) })
                        }

                        

                        if creatingThumbnails {
                            ProgressCount(progress: $progress,
                                          estimatedSeconds: $viewModel.estimatedSeconds,
                                          max: Double(max),
                                          statusText: "Creating Thumbnails or extracting JPGs")
                        }
                    }

                    if issorting {
                        HStack {
                            ProgressView()
                                .fixedSize()

                            Text("Sorting files, please wait...")
                                .font(.title)
                                .foregroundColor(Color.green)
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                        )
                    }
                }
            }
        }
        .task(id: scanning) {
            viewModel.countingScannedFiles = { count in
                // Ensure UI state changes happen on the main actor
                Task { @MainActor in
                    // It's safe to access self on the main actor
                    self.counterScannedFiles = count
                }
            }
        }
    }

    var files: [FileItem] {
        viewModel.files
    }
}
