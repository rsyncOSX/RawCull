import SwiftUI

struct ImageSourceToggleView: View {
    @Binding var useThumbnailSource: Bool
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { useThumbnailSource.toggle() }
        } label: {
            Image(systemName: useThumbnailSource ? "photo.fill" : "photo")
                .font(density == .compact ? .body : .title3)
                .foregroundStyle(useThumbnailSource ? .blue : .primary)
                .symbolEffect(.bounce, value: useThumbnailSource)
        }
        .buttonStyle(.plain)
        .help(useThumbnailSource ? "Using thumbnail — switch to extracted JPG" : "Using extracted JPG — switch to thumbnail")
        .accessibilityLabel("Image source")
        .accessibilityValue(useThumbnailSource ? "Thumbnail" : "Extracted JPEG")
        .accessibilityHint(useThumbnailSource ? "Switches to the extracted JPEG." : "Switches to the thumbnail.")
        .padding(.horizontal, density == .compact ? 6 : 10)
        .padding(.vertical, density == .compact ? 5 : 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(density == .compact ? 2 : 10)
        .animation(.spring(duration: 0.3), value: useThumbnailSource)
    }
}

struct ImageSourceSelectorView: View {
    @Binding var selection: ImageSourceSelectionState
    var imageURL: URL?
    @State private var raw9SupportedURL: URL?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        HStack(spacing: density == .compact ? 2 : 4) {
            sourceButton(.embeddedJPG, icon: "photo.stack", label: "JPG")
            sourceButton(.developedRAW, icon: "camera.aperture", label: supportsRAW9 ? "RAW 9" : "RAW")
                .disabled(!presentation.isDevelopedRAWAvailable)
        }
        .padding(density == .compact ? 3 : 5)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .task(id: imageURL) {
            raw9SupportedURL = nil
            guard let imageURL else { return }
            let supported = await RAW9Support.isSupported(for: imageURL)
            guard !Task.isCancelled else { return }
            raw9SupportedURL = supported ? imageURL : nil
        }
    }

    private var supportsRAW9: Bool {
        imageURL != nil && raw9SupportedURL == imageURL
    }

    private func sourceButton(
        _ source: ImagePreviewSource,
        icon: String,
        label: String,
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection.toggleExtractionSource(source)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(density == .compact ? .caption2 : .caption)
            .padding(.horizontal, density == .compact ? 5 : 8)
            .padding(.vertical, density == .compact ? 3 : 5)
            .background(selection.selected == source ? Color.accentColor.opacity(0.25) : .clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection.selected == source ? Color.accentColor : Color.primary)
        .help(helpText(for: source))
        .accessibilityLabel(accessibilityLabel(for: source))
        .accessibilityValue(selection.selected == source ? "Selected" : "Not selected")
        .accessibilityAddTraits(selection.selected == source ? .isSelected : [])
    }

    private func helpText(for source: ImagePreviewSource) -> String {
        switch source {
        case .thumbnail: "Show thumbnail"
        case .embeddedJPG: "Show embedded JPG"
        case .developedRAW:
            if !presentation.isDevelopedRAWAvailable {
                "RAW development is not supported for this image"
            } else if supportsRAW9 {
                "Develop and show full-size RAW JPEG using RAW 9"
            } else {
                "Develop and show full-size RAW JPEG using the system decoder (RAW 9 unavailable)"
            }
        }
    }

    private var presentation: ImageReviewSourcePresentation {
        ImageReviewSourcePresentation(
            selection: selection,
            showsDevelopedRAWFailure: false,
        )
    }

    private func accessibilityLabel(for source: ImagePreviewSource) -> String {
        switch source {
        case .thumbnail: "Thumbnail image source"
        case .embeddedJPG: "Embedded JPEG image source"
        case .developedRAW: supportsRAW9 ? "Developed RAW 9 image source" : "Developed RAW image source"
        }
    }
}
