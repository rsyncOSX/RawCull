import SwiftUI

struct SidebarARWCatalogFileView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(SettingsViewModel.self) private var settings

    @Bindable var viewModel: RawCullViewModel
    @Binding var isShowingPicker: Bool
    @Binding var progress: Double
    @Binding var selectedSource: ARWSourceCatalog?

    @Binding var scanning: Bool
    @Binding var creatingThumbnails: Bool

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    @State var counterScannedFiles: Int = 0
    @State var verticalimages: Bool = true

    let issorting: Bool
    let max: Double

    var body: some View {
        Group {
            if selectedSource == nil {
                // Empty State when no catalog is selected
                ContentUnavailableView {
                    Label("No Catalog Selected", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add a Catalog to start culling your photos.")
                } actions: {
                    Button("+ Add Catalog") { isShowingPicker = true }
                }
            } else if scanning {
                ProgressView("Scanning for ARW images: \(counterScannedFiles)")
            } else if files.isEmpty, !scanning {
                ContentUnavailableView {
                    Label("No Files Found", systemImage: "folder.badge.plus")
                } description: {
                    Text("This folder has no ARW images. Try a different folder.")
                }
            } else {
                ZStack {
                    VStack(alignment: .leading) {
                        HStack {
                            ConditionalGlassButton(
                                systemImage: verticalimages == true ? "text.justify" : "photo.stack",
                                text: verticalimages ? "Table" : "Images",
                                helpText: "View table or images",
                                style: .softCapsule,
                            ) {
                                verticalimages.toggle()
                            }

                            if !viewModel.files.isEmpty, verticalimages == false {
                                Picker("Filter", selection: $viewModel.ratingFilter) {
                                    Text("All").tag(RatingFilter.all)
                                    Text("✕ Rejected").foregroundStyle(.red).tag(RatingFilter.rejected)
                                    Text("Keep").tag(RatingFilter.keepers)
                                    ForEach(2 ... 5, id: \.self) { n in
                                        HStack(spacing: 2) {
                                            ForEach(0 ..< n, id: \.self) { _ in
                                                Image(systemName: "star.fill").font(.caption2)
                                            }
                                        }
                                        .tag(RatingFilter.minimum(n))
                                    }
                                }
                                .pickerStyle(DefaultPickerStyle())
                            }

                            if verticalimages {
                                ConditionalGlassButton(
                                    systemImage: "arrow.counterclockwise",
                                    text: "Clear",
                                    helpText: "Clear rated ARW-files",
                                    style: .softCapsule,
                                ) {
                                    viewModel.alertType = .clearToggledFiles
                                    viewModel.showingAlert = true
                                }
                                .disabled(viewModel.creatingthumbnails)
                            }
                        }
                        .padding()

                        Group {
                            // Default start show all thumbnails vertical on the
                            // left side. If verticalimage == false then show ARW
                            // files in a table view

                            if verticalimages {
                                ImageTableVerticalView(viewModel: viewModel)
                            } else {
                                // This is the plain table view
                                FileTableRowView(viewModel: viewModel,
                                                 nsImage: $nsImage,
                                                 cgImage: $cgImage,
                                                 openWindow: { id in openWindow(id: id) })
                            }
                        }
                        .frame(width: verticalimages ? (thumbnailSizeGrid + 20) : 510)
                        .fixedSize(horizontal: true, vertical: false)

                        if creatingThumbnails {
                            ProgressCount(progress: $progress,
                                          estimatedSeconds: $viewModel.estimatedSeconds,
                                          max: Double(max),
                                          statusText: viewModel.currentScanAndCreateThumbnailsActor != nil ? "Creating Thumbnails" : "Extracting JPGs")
                        }
                    }

                    if issorting {
                        HStack {
                            ProgressView()
                                .fixedSize()

                            Text("Sorting files…")
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
        viewModel.filteredFiles
    }

    var thumbnailSizeGrid: CGFloat {
        CGFloat(settings.thumbnailSizeGrid)
    }
}
