import AppKit
import Foundation
import PhotoEvidenceContracts
import PhotoEvidenceUI
@testable import RawCull
import Testing

@Suite("Burst Close-ups integration") @MainActor
struct BurstCloseUpTests {
    @Test(arguments: Array(UInt32(1)...UInt32(8)))
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
        let urls = (0..<4).map { URL(filePath: "/fixture/\($0).arw") }
        let selected = BurstCloseUpSelection.select(
            urls[2], in: urls, current: urls[0], selection: [urls[0]], modifiers: .command
        )
        #expect(selected == [urls[0], urls[2]])
        #expect(BurstCloseUpSelection.select(
            urls[2], in: urls, current: urls[2], selection: selected, modifiers: .command
        ) == [urls[0]])
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[2], selection: selected, modifiers: []
        ) == [urls[1]])
    }

    @Test func `shift click selects ranges in displayed order`() {
        let urls = (0..<5).map { URL(filePath: "/fixture/\($0).arw") }
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[3], selection: [urls[4]], modifiers: .shift
        ) == Set(urls[1...3]))
        #expect(BurstCloseUpSelection.select(
            urls[1], in: urls, current: urls[3], selection: [urls[4]], modifiers: [.command, .shift]
        ) == Set(urls[1...4]))
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
