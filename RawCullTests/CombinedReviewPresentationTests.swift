import CoreGraphics
import Foundation
@testable import RawCull
import SwiftUI
import Testing

@Suite("Combined Review presentation")
struct CombinedReviewPresentationTests {
    @Test(arguments: [520.0, 1024.0]) @MainActor
    func `review layouts fit narrow and desktop widths`(width: Double) throws {
        var result = fixture()
        result.report = .init(id: .init(rawValue: "report"), imageID: result.file.id,
                              claims: [
                                  .init(text: "Puffin fully visible in the foreground, with no occlusion reported.", type: "visibility", evidence: [.init(kind: .image, id: result.file.id.rawValue)], uncertainty: "Subject identity unverified.", contradictions: []),
                                  .init(text: "Even lighting with soft shadows.", type: "exposure", evidence: [.init(kind: .image, id: result.file.id.rawValue)], uncertainty: "Camera preview limits exposure evidence.", contradictions: []),
                                  .init(text: "Feather texture and wing structure reported in the crop.", type: "detail", evidence: [.init(kind: .image, id: result.file.id.rawValue)], uncertainty: "Fine-detail evidence is limited.", contradictions: []),
                              ], limitations: [], incomplete: true, inspectedRegions: [.init(rawValue: "region")], uninspectedRegions: [.init(rawValue: "omitted")])
        result.limitations = [.init(id: .init(rawValue: "eye"), reason: "Eye localization unavailable.", relatedEvidence: []),
                              .init(id: .init(rawValue: "preview"), reason: "Preview reduced from 9984×6656 to 4096×2731.", relatedEvidence: [])]
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                                            lease: CombinedReviewLease(), backendFactory: { throw ReviewRunError.modelUnavailable })
        let presentation = CombinedReviewPresentation(result: result)
        let photo = CombinedReviewPhotoLayout(feature: feature, result: result, presentation: presentation, canChooseRegion: false,
                                              inspect: { _ in }, inspectFinding: { _ in }, showEvidence: {})
            .padding(20).frame(width: width).background(Color(nsColor: .windowBackgroundColor))
        let evidence = CombinedReviewEvidenceLayout(feature: feature, result: result, presentation: presentation, topic: .findings,
                                                    selectedFindingID: nil, selectedRegionID: .constant(""), inspect: { _ in }, selectFinding: { _ in })
            .padding(20).frame(width: width).background(Color(nsColor: .windowBackgroundColor))
        try verifyRendering(photo, width: width, name: "photo")
        try verifyRendering(evidence, width: width, name: "evidence")
    }

    @MainActor private func verifyRendering(_ view: some View, width: Double, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: width, height: nil)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(width))
        #expect(image.height > 100)
        if let directory = ProcessInfo.processInfo.environment["RAWCULL_REVIEW_UI_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(Int(width)).png")
            try ReviewImageSource.pngData(for: image).write(to: url)
        }
    }

    @Test func `selected photo never inherits another photos review`() {
        let first = fixture(), second = fixture()
        let results = [first, second]
        #expect(CombinedReviewPresentation.selectedResult(in: results, fileID: second.file.fileID)?.file.id == second.file.id)
        #expect(CombinedReviewPresentation.selectedResult(in: results, fileID: UUID()) == nil)
        #expect(CombinedReviewPresentation.selectedResult(in: results, fileID: nil)?.file.id == first.file.id)
    }

    @Test func `incomplete review keeps conflicts uncertainty and omitted coverage visible`() throws {
        var result = fixture()
        let ref = ReviewEvidenceReference(kind: .observation, id: "crop-observation")
        let claim = ReviewClaim(text: "Feathers visible", type: "detail", evidence: [ref],
                                uncertainty: "Preview limited", contradictions: [ref])
        result.report = .init(id: .init(rawValue: "report"), imageID: result.file.id,
                              claims: [claim], limitations: [], incomplete: false,
                              inspectedRegions: [.init(rawValue: "region")], uninspectedRegions: [.init(rawValue: "omitted")])
        let presentation = CombinedReviewPresentation(result: result)
        let finding = try #require(presentation.findings.first)
        #expect(presentation.incomplete)
        #expect(presentation.inspectedCount == 1)
        #expect(presentation.uninspectedCount == 1)
        #expect(finding.uncertainty == claim.uncertainty)
        #expect(finding.contradictions == claim.contradictions)
        #expect(!presentation.importantLimits.isEmpty)
        #expect(finding.id == CombinedReviewPresentation(result: result).findings.first?.id)
    }

    @Test func `failed synthesis shows available observations without promoting measurements to findings`() {
        var result = fixture()
        result.observations = [observation(result, id: "available", availability: .available),
                               observation(result, id: "unavailable", availability: .unavailable)]
        result.measurements = [measurement(result)]
        let presentation = CombinedReviewPresentation(result: result)
        #expect(presentation.incomplete)
        #expect(presentation.findings.map(\.id) == ["available"])
        #expect(presentation.findings.allSatisfy { $0.isObservationOnly })
    }

    @Test func `finding links to its cited crop rather than the first region`() throws {
        var result = fixture()
        result.regions = [region(result, id: "first"), region(result, id: "cited")]
        result.observations = [observation(result, id: "crop", regionID: .init(rawValue: "cited"))]
        result.report = .init(id: .init(rawValue: "report"), imageID: result.file.id,
                              claims: [.init(text: "Wing structure visible", type: "detail",
                                             evidence: [.init(kind: .observation, id: "crop")], uncertainty: "", contradictions: [])],
                              limitations: [], incomplete: false, inspectedRegions: [], uninspectedRegions: [])
        let finding = try #require(CombinedReviewPresentation(result: result).findings.first)
        #expect(CombinedReviewPresentation.supportingRegion(for: finding, in: result)?.rawValue == "cited")
        result.regions = [region(result, id: "first")]
        #expect(CombinedReviewPresentation.supportingRegion(for: finding, in: result) == nil)
    }

    @Test func `full record round trips exact measurements and all original limitations`() throws {
        var result = fixture()
        result.measurements = [measurement(result)]
        result.limitations = [.init(id: .init(rawValue: "one"), reason: "Eye localization unavailable. Original details.", relatedEvidence: []),
                              .init(id: .init(rawValue: "two"), reason: "Eye localization unavailable. Original details.", relatedEvidence: [])]
        let record = try CombinedReviewTechnicalRecord(result).json()
        let data = try #require(record.data(using: .utf8))
        struct Record: Decodable { let measurements: [ReviewMeasurement]; let limitations: [ReviewLimitation] }
        let decoded = try JSONDecoder().decode(Record.self, from: data)
        #expect(decoded.measurements[0].values == result.measurements[0].values)
        #expect(decoded.measurements[0].provenance == result.measurements[0].provenance)
        #expect(decoded.limitations.count == 2)
        let presentation = CombinedReviewPresentation(result: result)
        #expect(presentation.limitations.count == 1)
        #expect(presentation.importantLimits.count == 1)
    }

    private func fixture() -> CombinedReviewResult {
        let id = UUID()
        return .init(file: .init(id: .init(rawValue: id.uuidString), fileID: id,
                                 url: URL(fileURLWithPath: "/fixture.ARW"), displayName: "fixture.ARW", fingerprint: "fixture"))
    }

    private func provenance(_ result: CombinedReviewResult) -> ReviewEvidenceProvenance {
        .init(workID: .init(rawValue: "work"), imageID: result.file.id, sourceIdentity: "fixture", renderPolicy: "preview",
              compatibility: .init(fields: [:]), modelIdentity: "model", inputReference: "input")
    }

    private func observation(_ result: CombinedReviewResult, id: String,
                             availability: ReviewEvidenceAvailability = .available, regionID: ReviewRegionID? = nil) -> ReviewObservation
    {
        .init(id: .init(rawValue: id), regionID: regionID, text: "Visible subject", uncertainty: "Identity unverified",
              availability: availability, provenance: provenance(result))
    }

    private func measurement(_ result: CombinedReviewResult) -> ReviewMeasurement {
        .init(id: .init(rawValue: "measurement"), subjectID: .init(rawValue: "subject"),
              values: ["subjectDetail": 0.07313991635692215, "foregroundPixelCount": 97150],
              availability: .available, reason: "Uncalibrated", provenance: provenance(result))
    }

    private func region(_ result: CombinedReviewResult, id: String) -> ReviewRegionRecord {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 80)
        return .init(id: .init(rawValue: id), imageID: result.file.id, subjectID: nil, sourceIdentity: "fixture",
                     purpose: "Wing", requestedRect: rect, paddedRect: rect, sourceRect: rect, retainedSourceRect: rect,
                     encoderSize: CGSize(width: 448, height: 448), scaleX: 1, scaleY: 1, edgeClipped: false,
                     intendedRegionRetained: true, fidelity: "preview", policy: "preview", inputReference: "input")
    }
}
