import CoreGraphics

@MainActor
enum ImageReviewSubjectOutlineLoader {
    static func load(
        file: FileItem, mask subject: ReviewSubjectMask,
        masks: ReviewSubjectMasks,
    ) async -> CGImage? {
        let mask = await masks.image(for: subject, file: file)
        guard !Task.isCancelled, let mask else { return nil }
        let outline = await DeepAIReviewMaskOutlineRenderer.outline(from: mask) ?? mask
        return Task.isCancelled ? nil : outline
    }
}
