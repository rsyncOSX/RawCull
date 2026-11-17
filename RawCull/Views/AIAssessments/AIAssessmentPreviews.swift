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
    @GestureState private var drag: CGSize = .zero

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
                    case let .image(image):
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(viewport.scale)
                            .offset(clampedOffset(drag, in: geometry.size, image: image))
                            .accessibilityLabel("Preview of \(frame.name)")
                            .contentShape(Rectangle())
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .task(id: access?.url) {
            state = .loading
            guard let access else { return }
            let result = await AssessmentPreviewState.load(frame, access: access, size: 2048)
            if !Task.isCancelled { state = result }
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
                        Menu {
                            Button("Show on left") { select(frame.id, .left) }
                            Button("Show on right") { select(frame.id, .right) }
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
                                    if frame.id == leftID { Text("Left") }
                                    if frame.id == rightID { Text("Right") }
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(width: 104, alignment: .leading)
                            .font(.caption)
                            .padding(4)
                            .background {
                                if frame.id == leftID || frame.id == rightID {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.14))
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Choose pane for \(frame.name)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            Button(action: reset) {
                Label("Reset to saved pair", systemImage: "arrow.counterclockwise")
            }
            .disabled(!canReset)
            .padding(.trailing, 20)
        }
        .frame(height: 130)
        .accessibilityLabel("Burst filmstrip")
    }
}
#endif
