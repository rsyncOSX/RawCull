import AppKit
import CoreGraphics
import Foundation
import ImageIO
@testable import RawCull
import SwiftUI
import Testing
import UniformTypeIdentifiers

@Suite("Review priority and inspection", .tags(.smoke))
struct ReviewSubjectPriorityTests {
    @Test func `main rabbit precedes contextual flowers without using SAM confidence`() throws {
        let rabbit = record("rabbit", "z-rabbit", score: 0.5), flower = record("flower", "a-flower", score: 0.99)
        let values = try ReviewSubjectPriority.assign([flower, rabbit], cues: [.init(concept: "rabbit", location: nil, reason: "Main narrative subject")], contextual: ["flower"], masks: [:], provenance: "overview")
        #expect(values.first?.id == rabbit.id)
        #expect(values.first?.relevance?.role == .primaryCandidate)
        #expect(values.last?.relevance?.role == .contextual)
        #expect(values.first?.relevance?.provenance.contains("overview") == true)
    }

    @Test func `primary mallard point must belong to registered foreground and ambiguity remains visible`() throws {
        let a = record("bird", "a-secondary", score: 0.99), b = record("bird", "z-primary", score: 0.5)
        let left = try mask(right: false), right = try mask(right: true)
        let cues: [ReviewPrimarySubjectCue] = [.init(concept: "bird", location: .init(x: 0.75, y: 0.5), reason: "Foreground principal bird")]
        let values = try ReviewSubjectPriority.assign([a, b], cues: cues, contextual: [], masks: [a.id: left, b.id: right], provenance: "overview")
        #expect(values.first?.id == b.id)
        #expect(values.first?.relevance?.role == .primaryCandidate)
        let ambiguous = try ReviewSubjectPriority.assign([a, b], cues: cues, contextual: [], masks: [a.id: right, b.id: right], provenance: "overview")
        #expect(ambiguous.allSatisfy { $0.relevance?.role == .equallyImportantCandidate })
        #expect(ambiguous.first?.id == a.id)
        let noCues = try ReviewSubjectPriority.assign([b, a], cues: [], contextual: [], masks: [:], provenance: "overview")
        #expect(noCues.allSatisfy { $0.relevance?.role == .unassigned })
        #expect(try ReviewSubjectPriority.assign([], cues: [], contextual: [], masks: [:], provenance: "overview").isEmpty)
    }

    @Test func `overview priority cues require discovered concepts and normalized locations`() throws {
        let response = #"{"observations":"Rabbit with flowers","uncertainty":"Importance uncertain","concepts":[{"query":"rabbit","displayName":"Rabbit","reason":"Visible animal"},{"query":"flower","displayName":"Flower","reason":"Context"}],"primarySubjects":[{"concept":"rabbit","location":{"x":0.7,"y":0.4},"reason":"Principal animal"}],"contextualConcepts":["flower"]}"#
        let value = try CombinedReviewResponse.overview(response)
        #expect(value.primarySubjects?.first?.location?.x == 0.7)
        #expect(value.contextualConcepts == ["flower"])
        #expect(throws: (any Error).self) { try CombinedReviewResponse.overview(response.replacingOccurrences(of: "0.7", with: "1.7")) }
        #expect(throws: (any Error).self) { try CombinedReviewResponse.overview(response.replacingOccurrences(of: #""concept":"rabbit""#, with: #""concept":"deer""#)) }
    }

    @Test func `overlay leaves background transparent and maps all source coordinates at different sizes`() throws {
        let mask = try mask(right: true)
        let overlay = try ReviewInspectionOverlay.tint(mask)
        let data = try #require(overlay.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(bytes[3] == 0)
        #expect(bytes[(40 * 4) + 3] == 110)
        for scale in [0.5, 2.0, 4.0] {
            let rect = ReviewInspectionOverlay.displayRect(CGRect(x: 32, y: 0, width: 32, height: 48), sourceSize: CGSize(width: 64, height: 48), displaySize: CGSize(width: 64 * scale, height: 48 * scale))
            #expect(rect == CGRect(x: 32 * scale, y: 0, width: 32 * scale, height: 48 * scale))
        }
    }

    @Test @MainActor func `inspection canvas renders aligned transparent foreground at two sizes`() throws {
        let mask = try mask(right: true)
        let tint = try ReviewInspectionOverlay.tint(mask)
        let record = ReviewRegionRecord(id: .init(rawValue: "region"), imageID: .init(rawValue: "image"), subjectID: nil,
                                        sourceIdentity: "source", purpose: "fixture", requestedRect: CGRect(x: 32, y: 4, width: 24, height: 40),
                                        paddedRect: CGRect(x: 28, y: 0, width: 32, height: 48), sourceRect: CGRect(x: 28, y: 0, width: 32, height: 48),
                                        retainedSourceRect: CGRect(x: 32, y: 4, width: 24, height: 40), encoderSize: CGSize(width: 448, height: 448),
                                        scaleX: 1, scaleY: 1, edgeClipped: true, intendedRegionRetained: true, fidelity: "fixture", policy: "appearance", inputReference: nil)
        for width in [320, 640] {
            let renderer = ImageRenderer(content: CombinedReviewInspectionCanvas(image: mask, tint: tint, sourceSize: CGSize(width: 64, height: 48), region: record).frame(width: CGFloat(width), height: CGFloat(width * 3 / 4)))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == width)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("RawCull-InspectionQA-\(width).png")
            try ReviewImageSource.pngData(for: image).write(to: url)
        }
    }

    private func record(_ concept: String, _ id: String, score: Float) -> ReviewSubjectRecord {
        .init(id: .init(rawValue: id), imageID: .init(rawValue: "image"), concept: concept, normalizedBounds: CGRect(x: 0, y: 0, width: 1, height: 1), maskConfidence: score, aliases: [], maskInputReference: nil, availability: .available)
    }

    private func mask(right: Bool) throws -> CGImage {
        let data = Data((0 ..< 64 * 48).map { index in ((index % 64 >= 32) == right) ? UInt8(255) : 0 })
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGImage(width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 64,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
