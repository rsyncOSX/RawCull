#if DEBUG
import SwiftUI

private enum AssessmentPreviewState {
    case loading
    case image(CGImage)
    case changed
    case unreadable

    static func load(_ frame: AIAssessmentEntry.Frame, access: RawCullCatalogGrant, size: Int) async -> Self {
        guard let url = try? frame.source.resolve(in: access.url) else { return .changed }
        guard let image = await RawParserKitImageLoader.shared.thumbnailCGImage(for: url, maxPixelSize: size) else {
            return .unreadable
        }
        guard (try? frame.source.resolve(in: access.url)) == url else { return .changed }
        return .image(image)
    }
}

struct AIAssessmentPreview: View {
    let frame: AIAssessmentEntry.Frame
    let access: RawCullCatalogGrant?
    let accessChecked: Bool
    @Binding var viewport: ComparisonViewportInteractionState

    @State private var state = AssessmentPreviewState.loading
    @State private var fullSizeImage: CGImage?
    @State private var rawImage: CGImage?
    @State private var usesRAW9 = false
    @State private var supportsRAW9 = false
    @State private var isLoadingZoom = false
    @State private var zoomError: LocalizedStringResource?
    @State private var loadedCatalog: URL?
    @State private var activeLoadID = UUID()
    @GestureState private var drag: CGSize = .zero

    private struct LoadRequest: Equatable {
        let catalog: URL?
        let zoomed: Bool
        let raw: Bool
    }

    private var loadRequest: LoadRequest {
        LoadRequest(catalog: access?.url, zoomed: viewport.scale > 1, raw: usesRAW9)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if !accessChecked {
                    ProgressView().tint(.white)
                } else if access == nil {
                    Text("RawCull couldn’t access the original catalog.")
                        .foregroundStyle(.white)
                        .padding()
                } else {
                    switch state {
                    case .loading:
                        ProgressView().tint(.white)
                    case let .image(thumbnail):
                        let image = viewport.scale > 1
                            ? (usesRAW9 ? rawImage ?? fullSizeImage ?? thumbnail : fullSizeImage ?? thumbnail)
                            : thumbnail
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(viewport.scale)
                            .offset(clampedOffset(drag, in: geometry.size, image: image))
                            .accessibilityLabel("Preview of \(frame.name)")
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { toggleZoom() }
                            .help("Double-click to zoom in or fit. Drag to pan when zoomed in.")
                            .accessibilityAction(named: viewport.scale == 1 ? Text("Zoom in") : Text("Fit")) {
                                toggleZoom()
                            }
                            .gesture(DragGesture()
                                .updating($drag) { value, drag, _ in drag = value.translation }
                                .onEnded { value in
                                    viewport.offset = clampedOffset(value.translation, in: geometry.size, image: image)
                                }, isEnabled: viewport.scale > 1)
                    case .changed:
                        Text("The original photo moved or changed.")
                            .foregroundStyle(.white)
                            .padding()
                    case .unreadable:
                        Text("RawCull couldn’t load the photo preview.")
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if viewport.scale > 1, access != nil {
                    zoomControls
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .task(id: loadRequest) {
            await loadPreview()
        }
        .task(id: access?.url) {
            supportsRAW9 = false
            guard let access, let url = try? frame.source.resolve(in: access.url) else { return }
            let supported = await RAW9Support.isSupported(for: url)
            guard !Task.isCancelled,
                  (try? frame.source.resolve(in: access.url)) == url else { return }
            supportsRAW9 = supported
        }
    }

    private var zoomControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if isLoadingZoom {
                    ProgressView().controlSize(.small)
                    Text(usesRAW9 ? "Developing RAW 9…" : "Loading full-size JPG…")
                }
                if supportsRAW9 {
                    Button(usesRAW9 ? "Show JPG" : "RAW 9") {
                        usesRAW9.toggle()
                    }
                    .help(usesRAW9 ? "Show the extracted JPEG preview" : "Develop the original image using RAW 9")
                }
                if !isLoadingZoom {
                    if usesRAW9, rawImage != nil {
                        Text("RAW 9")
                    } else if fullSizeImage != nil {
                        Text("Full-size JPG")
                    }
                }
            }
            if let zoomError {
                Text(zoomError)
            }
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func loadPreview() async {
        let loadID = UUID()
        activeLoadID = loadID
        isLoadingZoom = false
        zoomError = nil
        if loadedCatalog != access?.url {
            state = .loading
            fullSizeImage = nil
            rawImage = nil
            loadedCatalog = access?.url
        }
        guard let access else { return }
        guard let url = try? frame.source.resolve(in: access.url) else {
            state = .changed
            return
        }
        switch state {
        case .image:
            break
        default:
            let result = await AssessmentPreviewState.load(frame, access: access, size: 2048)
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            state = result
        }
        guard viewport.scale > 1 else { return }
        guard case .image = state else { return }

        let raw = usesRAW9
        guard raw ? rawImage == nil : fullSizeImage == nil else { return }
        isLoadingZoom = true
        defer {
            if activeLoadID == loadID { isLoadingZoom = false }
        }
        let image: CGImage?
        if raw {
            let supported = await RAW9Support.isSupported(for: url)
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            guard supported else {
                supportsRAW9 = false
                zoomError = "RAW 9 is unavailable. Showing the JPEG preview."
                return
            }
            // The renderer keeps developed pixels separate from the extracted JPEG disk cache.
            image = try? await RAWPreviewRenderer.shared.render(url: url).image
        } else {
            image = await FullSizePreviewLoader.shared.loadEmbeddedPreview(for: url)
        }
        guard !Task.isCancelled, activeLoadID == loadID else { return }
        guard (try? frame.source.resolve(in: access.url)) == url else {
            state = .changed
            return
        }
        if let image {
            if raw { rawImage = image } else { fullSizeImage = image }
        } else {
            zoomError = raw ? "Couldn’t develop RAW 9. Showing the JPEG preview." : "Couldn’t load the full-size JPG. Showing the smaller preview."
        }
    }

    private func toggleZoom() {
        if viewport.scale == 1 {
            viewport.scale = 2
        } else {
            viewport.resetTransform()
        }
    }

    private func clampedOffset(_ translation: CGSize, in size: CGSize, image: CGImage) -> CGSize {
        let fit = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let limitX = max(0, (CGFloat(image.width) * fit * viewport.scale - size.width) / 2)
        let limitY = max(0, (CGFloat(image.height) * fit * viewport.scale - size.height) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, viewport.offset.width + translation.width)),
            height: min(limitY, max(-limitY, viewport.offset.height + translation.height)),
        )
    }
}

struct AIAssessmentThumbnail: View {
    let frame: AIAssessmentEntry.Frame
    let access: RawCullCatalogGrant?

    @State private var state = AssessmentPreviewState.loading

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            switch state {
            case let .image(image) where access != nil:
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            case .loading where access != nil:
                ProgressView().controlSize(.small)
            default:
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 65)
        .accessibilityHidden(true)
        .task(id: access?.url) {
            state = .loading
            guard let access else { return }
            let result = await AssessmentPreviewState.load(frame, access: access, size: 224)
            if !Task.isCancelled { state = result }
        }
    }
}
struct AIAssessmentFilmstrip: View {
    let frames: [AIAssessmentEntry.Frame]
    let leftID: String?
    let rightID: String?
    let access: RawCullCatalogGrant?
    let select: (String, AIAssessmentSide) -> Void
    let reset: () -> Void
    let canReset: Bool

    var body: some View {
        HStack {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(frames) { frame in
                        AIAssessmentFilmstripItem(
                            frame: frame, access: access, isLeft: frame.id == leftID, isRight: frame.id == rightID,
                            select: select,
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .fixedSize(horizontal: false, vertical: true)

            Button(action: reset) {
                Label("Reset to saved pair", systemImage: "arrow.counterclockwise")
            }
            .disabled(!canReset)
            .padding(.trailing, 20)
        }
        .accessibilityLabel("Burst filmstrip")
    }
}

private struct AIAssessmentFilmstripItem: View {
    let frame: AIAssessmentEntry.Frame
    let access: RawCullCatalogGrant?
    let isLeft: Bool
    let isRight: Bool
    let select: (String, AIAssessmentSide) -> Void

    @State private var showsPaneChoices = false

    var body: some View {
        Button {
            showsPaneChoices = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                AIAssessmentThumbnail(frame: frame, access: access)
                Text(verbatim: frame.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let rank = frame.rank {
                        Text("Rank \(rank)")
                    }
                    if isLeft { Text("Left") }
                    if isRight { Text("Right") }
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)
            .font(.caption)
            .padding(4)
            .background {
                if isLeft || isRight {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose pane for \(frame.name)")
        .popover(isPresented: $showsPaneChoices, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Show on left") { choose(.left) }
                Button("Show on right") { choose(.right) }
            }
            .padding()
        }
    }

    private func choose(_ side: AIAssessmentSide) {
        showsPaneChoices = false
        select(frame.id, side)
    }
}
#endif
