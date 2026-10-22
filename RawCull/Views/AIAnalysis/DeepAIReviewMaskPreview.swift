import SwiftUI

struct DeepAIReviewMaskPreview: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let candidate: DeepAIReviewCandidate?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    @State private var image: CGImage?
    @State private var focusMap: CGImage?
    @State private var autofocusPoint: CGPoint?
    @State private var maskOverlay: CGImage?
    @State private var isLoading = false
    @State private var isOrganicOutline = false

    private var file: FileItem? {
        guard let candidate else { return nil }
        return files.first { $0.id == candidate.fileID }
    }

    private var loadIdentity: String? {
        guard let candidate, let prompt = candidate.maskPromptUsed else { return nil }
        return "\(candidate.fileID.uuidString):\(prompt.rawValue)"
    }

    var body: some View {
        Group {
            if let candidate, file != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(candidate.fileName).font(.headline).lineLimit(1)
                    ZStack {
                        if let image {
                            DeepAIReviewImageOverlay(
                                image: image,
                                focusMap: focusMap,
                                maskOverlay: maskOverlay,
                                autofocusPoint: autofocusPoint,
                            )
                        } else {
                            ProgressView("Loading preview…")
                        }

                        if isLoading {
                            ProgressView("Loading mask…")
                                .padding(10)
                                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black, in: .rect(cornerRadius: 8))
                    .clipShape(.rect(cornerRadius: 8))

                    Text(maskOverlayLabel)
                        .foregroundStyle(maskOverlay == nil ? Color.orange : Color.secondary)
                        .font(.caption)
                    Text("Focus map and camera AF point shown when available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Mask preview for \(candidate.fileName)")
            } else {
                ContentUnavailableView(
                    "Select an Image",
                    systemImage: "photo.badge.magnifyingglass",
                    description: Text("Select a completed row to inspect its stored subject mask."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: file?.id) {
            image = nil
            focusMap = nil
            autofocusPoint = nil
            guard let file else { return }
            let loadedImage = await AnalysisPreviewPreparation.loadImage(
                for: file, maxPixelSize: 1200,
            )
            guard !Task.isCancelled, let loadedImage else { return }
            image = loadedImage

            guard let focus = await AnalysisPreviewPreparation.prepareFocus(
                image: loadedImage, file: file, model: focusMaskModel, config: focusConfig,
            ) else { return }
            autofocusPoint = focus.autofocusPoint
            focusMap = focus.mask
        }
        .task(id: loadIdentity) {
            maskOverlay = nil
            isOrganicOutline = false
            isLoading = false
            guard let candidate, loadIdentity != nil else { return }
            isLoading = true
            let loadedMask = await controller.mask(for: candidate, in: files)
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            if let loadedMask {
                let outline = await DeepAIReviewMaskOutlineRenderer.outline(from: loadedMask)
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }
                if let outline {
                    maskOverlay = outline
                    isOrganicOutline = true
                } else {
                    // The stored subject mask remains a useful fallback if Core
                    // Image cannot derive a contour on a particular machine.
                    maskOverlay = loadedMask
                }
            } else {
                maskOverlay = nil
            }
            isLoading = false
        }
    }

    private var maskOverlayLabel: LocalizedStringResource {
        if isOrganicOutline {
            "Orange subject outline"
        } else if maskOverlay != nil {
            "Orange subject mask"
        } else {
            "Mask unavailable"
        }
    }
}
