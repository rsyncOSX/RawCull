import SwiftUI

struct ComparisonGridView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var imageStates: [FileItem.ID: ComparisonImageState] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFocusMask = false
    @State private var showFocusPoints = false
    @State private var useThumbnailSource = false
    @FocusState private var isFocused: Bool

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                if files.count > 1 {
                    ScrollView {
                        LazyVGrid(columns: columns(for: geo.size), spacing: 12) {
                            ForEach(files) { file in
                                ComparisonImagePaneView(
                                    file: file,
                                    state: imageStates[file.id],
                                    focusPoints: focusPoints(for: file),
                                    scale: scale,
                                    offset: offset,
                                    showFocusMask: showFocusMask,
                                    showFocusPoints: showFocusPoints,
                                    markerSize: viewModel.focusPointMarkerSize,
                                    zoomPanGesture: zoomPanGesture,
                                    onToggleZoom: toggleZoom,
                                )
                                .aspectRatio(3 / 2, contentMode: .fit)
                            }
                        }
                        .padding(12)
                    }

                    VStack {
                        Spacer()

                        ImageOverlayControlsView(
                            showFocusMask: $showFocusMask,
                            focusMaskAvailable: focusMaskAvailable,
                            hasFocusPoints: hasFocusPoints,
                            showFocusPoints: $showFocusPoints,
                            showImageSourceToggle: true,
                            useThumbnailSource: $useThumbnailSource,
                            scale: scale,
                            canZoomOut: scale > 0.5,
                            canZoomIn: scale < 5.0,
                            canReset: scale != 1.0 || offset != .zero,
                            onZoomOut: decreaseZoom,
                            onZoomReset: { withAnimation(.spring()) { resetToFit() } },
                            onZoomIn: increaseZoom,
                        )
                        .padding(.bottom, 14)
                    }
                } else {
                    ContentUnavailableView(
                        "Select Images to Compare",
                        systemImage: "rectangle.split.2x1",
                        description: Text("Select two to four thumbnails in a grid view, then use Compare."),
                    )
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJ")) { press in
            switch press.characters {
            case "+": increaseZoom(); return .handled
            case "-": decreaseZoom(); return .handled
            case "j", "J": useThumbnailSource.toggle(); return .handled
            default: return .ignored
            }
        }
        .onAppear {
            isFocused = true
            resetToFit()
        }
        .task(id: loadKey) {
            await loadImages()
        }
        .onChange(of: viewModel.sharpnessModel.focusMaskModel.config) { _, _ in
            Task {
                await regenerateFocusMasks()
            }
        }
    }

    private var files: [FileItem] {
        let selected = Set(viewModel.comparisonFileIDs)
        return viewModel.filteredFiles
            .filter { selected.contains($0.id) }
            .prefix(4)
            .map { $0 }
    }

    private var loadKey: String {
        let ids = files.map(\.id.uuidString).joined(separator: ",")
        return "\(ids)-\(useThumbnailSource)"
    }

    private var focusMaskAvailable: Bool {
        imageStates.values.contains { $0.focusMask != nil }
    }

    private var hasFocusPoints: Bool {
        files.contains { focusPoints(for: $0) != nil }
    }

    private var zoomPanGesture: AnyGesture<Void> {
        AnyGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale = lastScale * $0 }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.0 {
                            withAnimation(.spring()) { resetToFit() }
                        }
                    },
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height,
                            )
                        }
                    }
                    .onEnded { _ in lastOffset = offset },
            )
            .map { _ in () },
        )
    }

    private func columns(for size: CGSize) -> [GridItem] {
        let columnCount = size.width >= 1_200 ? 2 : 1
        return Array(
            repeating: GridItem(.flexible(minimum: 320), spacing: 12),
            count: columnCount,
        )
    }

    private func loadImages() async {
        let currentFiles = files
        imageStates = Dictionary(
            uniqueKeysWithValues: currentFiles.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: true))
            },
        )

        for file in currentFiles {
            guard !Task.isCancelled else { return }
            let (cgImage, nsImage) = await ComparisonImageLoader.loadImage(
                for: file,
                useThumbnailSource: useThumbnailSource,
            )
            guard !Task.isCancelled else { return }

            var state = ComparisonImageState(
                id: file.id,
                cgImage: cgImage,
                nsImage: nsImage,
                isLoading: false,
            )
            if let cgImage {
                let downscaled = cgImage.downscaled(toWidth: 1024)
                state.focusMask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
                    from: downscaled ?? cgImage,
                    scale: 1.0,
                )
            }
            imageStates[file.id] = state
        }
    }

    private func regenerateFocusMasks() async {
        for file in files {
            guard !Task.isCancelled else { return }
            guard let cgImage = imageStates[file.id]?.cgImage else { continue }
            let downscaled = cgImage.downscaled(toWidth: 1024)
            let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
                from: downscaled ?? cgImage,
                scale: 1.0,
            )
            guard !Task.isCancelled else { return }
            imageStates[file.id]?.focusMask = mask
        }
    }

    private func focusPoints(for file: FileItem) -> [FocusPoint]? {
        guard let points = viewModel.focusPoints?.filter({ $0.sourceFile == file.name }),
              points.count == 1 else { return nil }
        return points[0].focusPoints
    }

    private func toggleZoom() {
        withAnimation(.spring()) {
            scale > 1.0 ? resetToFit() : zoomToTarget()
        }
    }

    private func resetToFit() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func zoomToTarget() {
        scale = zoomLevel
        lastScale = zoomLevel
        offset = .zero
        lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            scale = min(5.0, scale + 0.4)
            lastScale = scale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            scale = max(0.5, scale - 0.4)
            lastScale = scale
        }
    }
}
