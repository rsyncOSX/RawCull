import SwiftUI

struct SidebarARWCatalogFileView: View {
    @Environment(\.openWindow) var openWindow
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Bindable var viewModel: RawCullViewModel
    @Binding var progress: Double
    @Binding var selectedSource: ARWSourceCatalog?

    @Binding var scanning: Bool
    @Binding var creatingThumbnails: Bool

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    @State var counterScannedFiles: Int = 0

    let issorting: Bool
    let max: Double

    var body: some View {
        Group {
            if selectedSource == nil {
                // Empty State when no catalog is selected
                ContentUnavailableView {
                    Label("No Catalog Selected", systemImage: "folder.badge.plus")
                } description: {
                    Text("Choose File > Add Catalog… to start culling your photos.")
                }
            } else if scanning {
                ProgressView("Scanning images: \(counterScannedFiles)")
            } else if viewModel.files.isEmpty, !scanning {
                ContentUnavailableView {
                    Label("No Files Found", systemImage: "folder.badge.plus")
                } description: {
                    Text("This folder has no RAW images. Choose File > Add Catalog… to try a different folder.")
                }
            } else if files.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Files", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("The catalog contains RAW images, but none match the current filters.")
                }
            } else {
                ZStack {
                    VStack(alignment: .leading) {
                        HStack {
                            ConditionalGlassButton(
                                systemImage: "trash",
                                text: "Clear",
                                helpText: "Clear rated files",
                            ) {
                                viewModel.alertType = .clearRatedFiles
                                viewModel.showingAlert = true
                            }
                            .disabled(viewModel.creatingthumbnails)

                            ConditionalGlassButton(
                                systemImage: "photo.badge.arrow.down",
                                text: "Cache JPGs",
                                helpText: "Cache extracted JPG previews for this catalog",
                            ) {
                                viewModel.alertType = .createJPGDiskCache
                                viewModel.showingAlert = true
                            }
                            .disabled(
                                selectedSource == nil ||
                                    files.isEmpty ||
                                    viewModel.creatingthumbnails,
                            )
                        }
                        .padding()

                        Group {
                            // Default start show all thumbnails vertical on the
                            // left side. If verticalimage == false then show ARW
                            // files in a table view

                            ImageTableVerticalView(viewModel: viewModel)
                        }
                        .frame(width: thumbnailSizeGrid + 20)
                        .fixedSize(horizontal: true, vertical: false)

                        if creatingThumbnails {
                            ProgressCount(progress: $progress,
                                          estimatedSeconds: $viewModel.estimatedSeconds,
                                          max: Double(max),
                                          statusText: progressStatusText)
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
        .onDisappear {
            viewModel.countingScannedFiles = nil
        }
    }

    var files: [FileItem] {
        viewModel.filteredFiles
    }

    var thumbnailSizeGrid: CGFloat {
        CGFloat(settings.thumbnailSizeGrid)
    }

    private var progressStatusText: String {
        if viewModel.currentScanAndCreateThumbnailsActor != nil {
            return "Creating Thumbnails"
        }
        if viewModel.currentScanAndExtractJPGsActor != nil {
            return "Caching JPGs"
        }
        return "Extracting JPGs"
    }
}
