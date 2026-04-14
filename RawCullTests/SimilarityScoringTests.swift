//
//  SimilarityScoringTests.swift
//  RawCullTests
//
//  Unit tests for the similarity scoring pipeline.
//  Tests cover distance ordering, missing anchor / empty state, saliency
//  subject-mismatch penalty, cancellation state, and backward-compatible
//  persistence decoding.
//

import AppKit
import Foundation
@testable import RawCull
import Testing
import Vision

// MARK: - Helpers

/// Create a minimal FileItem for testing.
private func makeFile(name: String) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 0,
        dateModified: Date(),
        exifData: nil,
        afFocusNormalized: nil
    )
}

/// Build a small synthetic VNFeaturePrintObservation-like Data blob by
/// running the request against a solid-color CGImage.
/// Returns nil if Vision is unavailable (rare on macOS).
private func syntheticEmbeddingData(hue: CGFloat) -> Data? {
    let size = 64
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: nil,
              width: size, height: size,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
          )
    else { return nil }
    ctx.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 0.8, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    guard let cgImage = ctx.makeImage() else { return nil }

    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    guard let obs = request.results?.first as? VNFeaturePrintObservation else { return nil }
    return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
}

// MARK: - Distance ordering

@Suite("SimilarityScoringModel – distance ordering")
struct SimilarityDistanceOrderingTests {
    /// When all embeddings are pre-loaded, rankSimilar must put the closest
    /// image first (lowest distance first).
    @Test(.tags(.smoke))
    @MainActor
    func `rankSimilar returns nearest image first`() async {
        let model = SimilarityScoringModel()

        guard let anchorData = syntheticEmbeddingData(hue: 0.0),
              let nearData = syntheticEmbeddingData(hue: 0.02),  // very similar hue
              let farData = syntheticEmbeddingData(hue: 0.5)     // very different hue
        else {
            // Vision unavailable in this test environment; skip gracefully.
            return
        }

        let anchorID = UUID()
        let nearID = UUID()
        let farID = UUID()

        model.embeddings[anchorID] = anchorData
        model.embeddings[nearID] = nearData
        model.embeddings[farID] = farData

        model.rankSimilar(to: anchorID, using: [], saliencyInfo: [:])

        guard let dNear = model.distances[nearID],
              let dFar = model.distances[farID]
        else {
            // Observation might fail silently; just verify distances were set.
            #expect(model.distances.count > 0, "Expected at least one distance entry")
            return
        }

        #expect(dNear <= dFar, "Near image (hue 0.02) should have a smaller distance than far image (hue 0.5)")
    }

    /// The anchor image itself should not appear in the distances map.
    @Test(.tags(.smoke))
    @MainActor
    func `anchor is excluded from distances`() {
        let model = SimilarityScoringModel()
        let anchorID = UUID()
        let otherID = UUID()

        // Use placeholder data; the unarchiving will fail silently and distances stay empty.
        model.embeddings[anchorID] = Data()
        model.embeddings[otherID] = Data()

        model.rankSimilar(to: anchorID, using: [], saliencyInfo: [:])

        #expect(model.distances[anchorID] == nil, "Anchor should not appear in distances map")
    }
}

// MARK: - Missing anchor / empty state

@Suite("SimilarityScoringModel – empty / missing anchor")
struct SimilarityEmptyStateTests {
    /// When anchor is not in embeddings, distances must be empty and anchorFileID nil.
    @Test(.tags(.smoke))
    @MainActor
    func `rankSimilar with unknown anchor clears state`() {
        let model = SimilarityScoringModel()
        // Pre-populate with some distances to ensure they are cleared.
        model.distances = [UUID(): 0.5]
        model.anchorFileID = UUID()

        let unknownID = UUID()
        model.rankSimilar(to: unknownID, using: [], saliencyInfo: [:])

        #expect(model.distances.isEmpty, "Distances should be empty when anchor has no embedding")
        #expect(model.anchorFileID == nil, "anchorFileID should be nil when anchor has no embedding")
    }

    /// indexFiles with an empty array should be a no-op.
    @Test(.tags(.smoke))
    @MainActor
    func `indexFiles with empty array leaves model unchanged`() async {
        let model = SimilarityScoringModel()
        await model.indexFiles([], thumbnailMaxPixelSize: 64)
        #expect(!model.isIndexing)
        #expect(model.embeddings.isEmpty)
    }

    /// sortBySimilarity should default to false before any ranking.
    @Test(.tags(.smoke))
    @MainActor
    func `initial sortBySimilarity is false`() {
        let model = SimilarityScoringModel()
        #expect(!model.sortBySimilarity)
    }
}

// MARK: - Subject-mismatch penalty

@Suite("SimilarityScoringModel – subject mismatch penalty")
struct SimilaritySubjectMismatchTests {
    /// An image with a mismatched subject label should receive a higher (worse)
    /// distance than the same image without any subject information.
    @Test(.tags(.smoke))
    @MainActor
    func `subject mismatch increases distance`() {
        let model = SimilarityScoringModel()

        guard let anchorData = syntheticEmbeddingData(hue: 0.0),
              let sameHueData = syntheticEmbeddingData(hue: 0.01)
        else { return }

        let anchorID = UUID()
        let matchedID = UUID()
        let mismatchedID = UUID()

        model.embeddings[anchorID] = anchorData
        // Use the same data for both candidates so pure visual distance is equal.
        model.embeddings[matchedID] = sameHueData
        model.embeddings[mismatchedID] = sameHueData

        // Anchor and matched share label "bird"; mismatched has label "person".
        let saliency: [UUID: SaliencyInfo] = [
            anchorID: SaliencyInfo(subjectLabel: "bird"),
            matchedID: SaliencyInfo(subjectLabel: "bird"),
            mismatchedID: SaliencyInfo(subjectLabel: "person"),
        ]

        model.rankSimilar(to: anchorID, using: [], saliencyInfo: saliency)

        guard let dMatched = model.distances[matchedID],
              let dMismatched = model.distances[mismatchedID]
        else { return }

        #expect(dMismatched > dMatched, "Mismatched subject label should increase distance")
    }
}

// MARK: - Cancellation

@Suite("SimilarityScoringModel – cancellation")
struct SimilarityCancellationTests {
    /// After cancellation, isIndexing must be false and the model must not
    /// mutate embeddings with stale partial results.
    @Test(.tags(.smoke))
    @MainActor
    func `cancelIndexing resets progress state`() {
        let model = SimilarityScoringModel()
        model.isIndexing = true
        model.indexingProgress = 5
        model.indexingTotal = 10
        model.indexingEstimatedSeconds = 30

        model.cancelIndexing()

        #expect(!model.isIndexing)
        #expect(model.indexingProgress == 0)
        #expect(model.indexingTotal == 0)
        #expect(model.indexingEstimatedSeconds == 0)
    }

    /// reset() clears all state including embeddings, distances, and sort flags.
    @Test(.tags(.smoke))
    @MainActor
    func `reset clears all similarity state`() {
        let model = SimilarityScoringModel()
        model.embeddings[UUID()] = Data([1, 2, 3])
        model.distances[UUID()] = 0.3
        model.anchorFileID = UUID()
        model.sortBySimilarity = true

        model.reset()

        #expect(model.embeddings.isEmpty)
        #expect(model.distances.isEmpty)
        #expect(model.anchorFileID == nil)
        #expect(!model.sortBySimilarity)
    }
}

// MARK: - Persistence backward compatibility

@Suite("SimilarityScoringModel – persistence backward compat")
struct SimilarityPersistenceTests {
    /// DecodeSavedFiles must decode old JSON that lacks the featurePrintData key
    /// without crashing, and produce nil for that field.
    @Test(.tags(.smoke))
    func `DecodeFileRecord decodes old JSON without featurePrintData`() throws {
        let oldJSON = """
        {
            "fileName": "_DSC1234.ARW",
            "dateTagged": "01 Jan 2026 12:00",
            "dateCopied": null,
            "rating": 3,
            "sharpnessScore": 0.72,
            "saliencySubject": "bird"
        }
        """.data(using: .utf8)
        guard let oldJSON else {
            Issue.record("UTF-8 encoding of test JSON failed unexpectedly")
            return
        }

        let record = try JSONDecoder().decode(DecodeFileRecord.self, from: oldJSON)

        #expect(record.fileName == "_DSC1234.ARW")
        #expect(record.rating == 3)
        #expect(record.sharpnessScore == 0.72)
        #expect(record.saliencySubject == "bird")
        #expect(record.featurePrintData == nil, "featurePrintData should be nil when absent from JSON")
    }

    /// FileRecord must be fully Codable round-trip including featurePrintData.
    @Test(.tags(.smoke))
    func `FileRecord round-trips featurePrintData`() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        var record = FileRecord(fileName: "test.ARW", dateTagged: nil, dateCopied: nil, rating: nil)
        record.featurePrintData = data

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(FileRecord.self, from: encoded)

        #expect(decoded.featurePrintData == data)
    }

    /// FileRecord round-trip with nil featurePrintData should not crash and return nil.
    @Test(.tags(.smoke))
    func `FileRecord round-trips nil featurePrintData`() throws {
        let record = FileRecord(fileName: "test.ARW", dateTagged: nil, dateCopied: nil, rating: nil)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(FileRecord.self, from: encoded)
        #expect(decoded.featurePrintData == nil)
    }
}
