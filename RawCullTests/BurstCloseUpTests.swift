import AppKit
import Foundation
import PhotoAnalysisKit
import PhotoEvidenceContracts
import PhotoEvidenceUI
@testable import RawCull
import Testing

@Suite("Burst Close-ups integration") @MainActor
struct BurstCloseUpTests {
    @Test(arguments: Array(UInt32(1) ... UInt32(8)))
    func `AF placement maps sensor coordinates to oriented images`(orientation: UInt32) throws {
        let frame = CloseUpFrame(id: URL(filePath: "/fixture/a.arw"), name: "a", revision: "1")
        let expected = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3),
                        CGPoint(x: 0.8, y: 0.7), CGPoint(x: 0.2, y: 0.7),
                        CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2),
                        CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.3, y: 0.8)]
        let availability = BurstCloseUpAFPoint.availability(frame: frame, point: CGPoint(x: 0.2, y: 0.3), orientation: orientation)
        let target = try #require(availability.target(for: frame))
        #expect(target.center == expected[Int(orientation) - 1])
        #expect(availability.target(for: CloseUpFrame(id: frame.id, name: frame.name, revision: "2")) == nil)
    }

    @Test func `AF placement explains unavailable metadata`() {
        let frame = CloseUpFrame(id: URL(filePath: "/fixture/a.arw"), name: "a", revision: "1")
        for (point, orientation): (CGPoint?, UInt32?) in [(nil, 1), (.zero, nil), (.zero, 9),
                                                          (CGPoint(x: Double.nan, y: 0), 1),
                                                          (CGPoint(x: 2, y: 0), 1)] {
            let availability = BurstCloseUpAFPoint.availability(frame: frame, point: point, orientation: orientation)
            #expect(availability.target(for: frame) == nil)
            #expect(!availability.explanation(for: frame).isEmpty)
        }
    }

    @Test func `command click keeps current frame and toggles additional frames`() {
        let urls = (0 ..< 4).map { URL(filePath: "/fixture/\($0).arw") }
        let selected = BurstCloseUpSelection.select(
            urls[2], in: urls, current: urls[0], selection: [urls[0]], modifiers: .command,
        )
        #expect(selected == [urls[0], urls[2]])
        #expect(BurstCloseUpSelection.select(
            urls[2], in: urls, current: urls[2], selection: selected, modifiers: .command,
        ) == [urls[0]])
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[2], selection: selected, modifiers: [],
        ) == [urls[1]])
    }

    @Test func `shift click selects ranges in displayed order`() {
        let urls = (0 ..< 5).map { URL(filePath: "/fixture/\($0).arw") }
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[3], selection: [urls[4]], modifiers: .shift,
        ) == Set(urls[1 ... 3]))
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[3], selection: [urls[4]], modifiers: [.command, .shift],
        ) == Set(urls[1 ... 4]))
    }

    @Test func `regions survive new session and reject replaced file`() throws {
        let suite = "BurstCloseUps." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let frame = CloseUpFrame(id: URL(filePath: "/fixture/burst.arw"), name: "burst", revision: "one")
        let first = CloseUpModel(storage: BurstCloseUpRegionStore(defaults: defaults))
        first.updateFrames([frame])
        let region = CloseUpRegion(center: CGPoint(x: 0.2, y: 0.7), fraction: 0.2)
        first.setRegion(region, for: frame.id)
        let reopened = CloseUpModel(storage: BurstCloseUpRegionStore(defaults: defaults))
        reopened.updateFrames([frame])
        #expect(reopened.region(for: frame.id) == region)
        reopened.updateFrames([CloseUpFrame(id: frame.id, name: frame.name, revision: "two")])
        #expect(reopened.region(for: frame.id) == CloseUpRegion())
    }

    @Test func `sidecar change invalidates preview without erasing file identity`() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "frame.arw")
        try Data([1]).write(to: url)
        let fileRevision = BurstCloseUpIdentity.revision(url)
        let preview = BurstCloseUpIdentity.source(url, raw: false)
        let raw = BurstCloseUpIdentity.source(url, raw: true)
        try Data([2, 3]).write(to: FullSizePreviewLoader.sidecarJPEGURL(for: url))
        #expect(preview != BurstCloseUpIdentity.source(url, raw: false))
        #expect(raw == BurstCloseUpIdentity.source(url, raw: true))
        #expect(fileRevision == BurstCloseUpIdentity.revision(url))
        try Data([4, 5, 6]).write(to: url)
        #expect(fileRevision != BurstCloseUpIdentity.revision(url))
    }
}

@Suite("People preview ranking")
struct PeopleRankingPreviewTests {
    @Test func `candidate order falls back until all frames have compatible evidence`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = FaceEvidenceCache(directory: directory.appending(path: "evidence"))
        let urls = [directory.appending(path: "first.raw"), directory.appending(path: "second.raw")]
        for url in urls {
            try Data().write(to: url)
        }

        func save(_ url: URL, width: CGFloat, detail: Double) throws {
            struct FaceFixture: Encodable {
                let id = 0
                let normalizedBounds: CGRect
                let localDetail: Double
            }

            struct EvidenceFixture: Encodable {
                let algorithmVersion: Int
                let detectorRevision: Int
                let previewWidth = 1600
                let previewHeight = 1200
                let faces: [FaceFixture]
            }

            let signature = FaceEvidenceCache.signature(sourceRevision: BurstCloseUpIdentity.revision(url))
            let fixture = EvidenceFixture(
                algorithmVersion: signature.algorithmVersion,
                detectorRevision: signature.detectorRevision,
                faces: [FaceFixture(normalizedBounds: CGRect(x: 0.3, y: 0.3, width: width, height: 0.25),
                                    localDetail: detail)]
            )
            let evidence = try JSONDecoder().decode(FaceEvidenceResult.self, from: JSONEncoder().encode(fixture))
            try cache.save(evidence, for: url, signature: signature)
        }

        try save(urls[0], width: 0.2, detail: 0.1)
        #expect(await PeopleRankingPreview.candidateOrder(for: urls, cache: cache) == nil)
        try save(urls[1], width: 0.4, detail: 1)
        #expect(await PeopleRankingPreview.candidateOrder(for: urls, cache: cache) == nil)
        try save(urls[1], width: 0.2, detail: 1)
        #expect(await PeopleRankingPreview.candidateOrder(for: urls, cache: cache) == Array(urls.reversed()))
    }

    @Test func `face scale checks the full range in both dimensions`() {
        let first = CGSize(width: 0.2, height: 0.25)
        let similar = CGSize(width: 0.24, height: 0.3)
        #expect(PeopleRankingPreview.comparableFaceSizes([first, similar]))
        #expect(!PeopleRankingPreview.comparableFaceSizes([similar, first, CGSize(width: 0.26, height: 0.3)]))
        #expect(!PeopleRankingPreview.comparableFaceSizes([first, CGSize(width: 0.2, height: 0.35)]))
        #expect(!PeopleRankingPreview.comparableFaceSizes([first, .zero]))
    }

    @Test func `only the second baseline frame can take first place`() {
        #expect(PeopleRankingPreview.rankedIndices(details: [0.1, 1, 0.5]) == [1, 0, 2])
        #expect(PeopleRankingPreview.rankedIndices(details: [0.1, 0.6, 1]) == [0, 1, 2])
        #expect(PeopleRankingPreview.rankedIndices(details: [1, 1, 1]) == [0, 1, 2])
    }
}

@Suite("Animal close-up regions")
struct AnimalCloseUpRegionTests {
    @Test func `eye crops stay within the head and image`() throws {
        let eye = CGPoint(x: 5, y: 25)
        let regions = AnimalCloseUpDetector.crops(
            headPoints: [eye, CGPoint(x: 45, y: 25)],
            eyes: [eye, CGPoint(x: 90, y: 90)],
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        try #require(regions.count == 2)
        #expect(regions[0].bounds.minX == 0)
        #expect(regions[1].bounds.minX == 0)
        #expect(regions[0].bounds.contains(regions[1].bounds))
    }

    @Test func `one landmark cannot establish a crop scale`() {
        let eye = CGPoint(x: 20, y: 20)
        #expect(AnimalCloseUpDetector.crops(
            headPoints: [eye], eyes: [eye], in: CGRect(x: 0, y: 0, width: 100, height: 100)
        ).isEmpty)
    }
}
