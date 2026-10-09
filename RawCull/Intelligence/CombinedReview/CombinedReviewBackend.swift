import CoreGraphics
import Foundation

nonisolated struct CombinedReviewCLIPGeometry: Codable, Sendable {
    let inputSize: CGSize
    let retainedInputRect: CGRect
    let encoderSize: CGSize
    let scaleX: Double
    let scaleY: Double
}

nonisolated struct CombinedReviewCLIPResult: Codable, Sendable {
    let relevance: Float
    let embedding: [Float]
    let model: ReviewModelSnapshot
    var geometry: CombinedReviewCLIPGeometry?
}

nonisolated protocol CombinedReviewBackendServing: Sendable {
    func models() async throws -> [String: ReviewModelSnapshot]
    func respond(instruction: String, image: CGImage, tokens: Int) async throws -> String
    func segment(image: CGImage, file: ReviewFileSnapshot, concept: String) async throws -> [ObjectInstanceDeduplicator.Candidate]
    func clip(image: CGImage, criteria: String, model: ReviewModelSnapshot) async throws -> CombinedReviewCLIPResult
}
