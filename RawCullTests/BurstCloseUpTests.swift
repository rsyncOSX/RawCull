import Foundation
import PhotoEvidenceContracts
import PhotoEvidenceUI
@testable import RawCull
import Testing

@Suite("Burst Close-ups integration") @MainActor
struct BurstCloseUpTests {
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
