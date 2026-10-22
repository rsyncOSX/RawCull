import CoreGraphics

@MainActor
enum ImageReviewSubjectOutlineLoader {
    static func load(
        file: FileItem, candidate: DeepAIReviewCandidate,
        controller: DeepAIReviewController,
    ) async -> CGImage? {
        let mask = await controller.mask(for: candidate, in: [file])
        guard !Task.isCancelled, let mask else { return nil }
        let outline = await DeepAIReviewMaskOutlineRenderer.outline(from: mask) ?? mask
        return Task.isCancelled ? nil : outline
    }
}
