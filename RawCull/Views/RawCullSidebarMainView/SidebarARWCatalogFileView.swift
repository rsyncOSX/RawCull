import SwiftUI

struct SidebarARWCatalogFileView: View {
    @Environment(\.openWindow) var openWindow
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Bindable var viewModel: RawCullViewModel
    @Binding var selectedSource: ARWSourceCatalog?

    @Binding var scanning: Bool
    @Binding var creatingThumbnails: Bool

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    let issorting: Bool

    var body: some View {
        if selectedSource == nil {
            // Empty State when no catalog is selected
            ContentUnavailableView {
                Label("No Catalog Selected", systemImage: "folder.badge.plus")
            } description: {
                Text("Choose File > Add Catalog… to start culling your photos.")
            }
        } else if scanning {
            ProgressView("Scanning images: \(viewModel.scanDiscoveredCount)")
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

                        LoupeSortBadge(status: sortStatus)
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
                        ProgressCount(
                            completed: viewModel.fileOperationCompleted,
                            total: viewModel.fileOperationTotal,
                            estimatedSeconds: viewModel.fileOperationEstimatedSeconds,
                            statusText: progressStatusText,
                        )
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

    private var sortStatus: LoupeSortStatus {
        if viewModel.similarityModel.sortBySimilarity {
            return .similarity
        }
        if viewModel.sharpnessModel.sortBySharpness {
            return .sharpness
        }
        return .name
    }
}

private enum LoupeSortStatus {
    case name
    case sharpness
    case similarity

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .sharpness: "Sharpness"
        case .similarity: "Similarity"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat"
        case .sharpness: "scope"
        case .similarity: "photo.stack"
        }
    }

    var helpText: LocalizedStringResource {
        switch self {
        case .name: "Images are sorted by name"
        case .sharpness: "Images are sorted by sharpness"
        case .similarity: "Images are sorted by similarity"
        }
    }
}

private struct LoupeSortBadge: View {
    let status: LoupeSortStatus

    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.systemImage)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        }
        .help(Text(status.helpText))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image sorting")
        .accessibilityValue(Text(status.helpText))
    }
}
