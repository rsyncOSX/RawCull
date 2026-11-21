import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeReviewTestFile(_ url: URL, id: UUID = UUID()) -> FileItem {
    FileItem(
        id: id,
        url: url,
        name: url.lastPathComponent,
        size: 8,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

@MainActor
@Suite("Review decision actions", .tags(.smoke))
struct ReviewDecisionActionsTests {
    private struct Fixture {
        let root: URL
        let viewModel: RawCullViewModel
        let file: FileItem
        let review: ReviewFileSnapshot
        let decisions: ReviewDecisionActions
    }

    private func fixture(name: String = #function) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("photo.ARW")
        try Data("original".utf8).write(to: url)
        let file = makeReviewTestFile(url)
        let viewModel = makeRawCullViewModel(name: name)
        viewModel.catalog.selectedSource = ARWSourceCatalog(name: "Catalog", url: root)
        viewModel.ratings.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.catalog.files = [file]
        viewModel.catalog.scanning = false
        let review = try ReviewFileSnapshot(
            id: .init(rawValue: file.id.uuidString),
            fileID: file.id,
            url: url,
            displayName: file.name,
            fingerprint: ReviewFileSnapshot.fingerprint(url),
        )
        let decisions = ReviewDecisionActions(
            catalog: viewModel.catalog,
            ratings: viewModel.ratings,
            culling: viewModel.culling,
            burstWorkflow: viewModel.burstWorkflow,
        )
        return .init(root: root, viewModel: viewModel, file: file, review: review, decisions: decisions)
    }

    @Test func `tag, untag and rate the reviewed photo with the grid's ratings`() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let decisions = fixture.decisions
        #expect(decisions.unavailableReason(for: fixture.review) == nil)
        #expect(!decisions.isTagged(fixture.file))

        #expect(decisions.act(on: fixture.review) { file, catalog in decisions.toggleTag(file, in: catalog) })
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == 2)
        #expect(decisions.isTagged(fixture.file))

        #expect(decisions.act(on: fixture.review) { file, catalog in decisions.toggleTag(file, in: catalog) })
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == nil)

        #expect(decisions.act(on: fixture.review) { file, _ in decisions.rate(file, -1) })
        #expect(decisions.rating(for: fixture.file) == .rejected)
        #expect(decisions.act(on: fixture.review) { file, _ in decisions.rate(file, 4) })
        #expect(decisions.rating(for: fixture.file) == .stars(4))
    }

    @Test(arguments: [3, 4, 5]) func `untag never erases a star rating`(stars: Int) throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let decisions = fixture.decisions
        #expect(decisions.act(on: fixture.review) { file, _ in decisions.rate(file, stars) })
        #expect(decisions.isTagged(fixture.file))
        #expect(!decisions.canToggleTag(fixture.file))

        #expect(decisions.act(on: fixture.review) { file, catalog in decisions.toggleTag(file, in: catalog) })
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == stars)

        // Rejects and keepers can still be tagged; tagging replaces them with two stars.
        #expect(decisions.act(on: fixture.review) { file, _ in decisions.rate(file, -1) })
        #expect(decisions.canToggleTag(fixture.file))
        #expect(decisions.act(on: fixture.review) { file, catalog in decisions.toggleTag(file, in: catalog) })
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == 2)
    }

    @Test func `a photo that changed on disk after the review is not rated`() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("edited after the review".utf8).write(to: fixture.file.url)
        var ran = false
        #expect(!fixture.decisions.act(on: fixture.review) { _, _ in ran = true })
        #expect(!ran)
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == nil)
    }

    @Test func `actions are unavailable outside the open catalog or for duplicate filenames`() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let twin = makeReviewTestFile(fixture.root.appendingPathComponent("sub/photo.ARW"))
        fixture.viewModel.catalog.files = [fixture.file, twin]
        #expect(fixture.decisions.unavailableReason(for: fixture.review) != nil)
        #expect(!fixture.decisions.act(on: fixture.review) { file, _ in fixture.decisions.rate(file, 3) })

        fixture.viewModel.catalog.files = []
        #expect(fixture.decisions.liveFile(for: fixture.review) == nil)
        #expect(fixture.decisions.unavailableReason(for: fixture.review) != nil)

        fixture.viewModel.catalog.files = [fixture.file]
        fixture.viewModel.catalog.selectedSource = nil
        #expect(fixture.decisions.editableCatalog == nil)
        #expect(fixture.viewModel.ratings.rating(for: fixture.file) == nil)
    }

    @Test func `mark reviewed toggles the burst that contains the photo`() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sibling = makeReviewTestFile(fixture.root.appendingPathComponent("sibling.ARW"))
        fixture.viewModel.catalog.files = [fixture.file, sibling]
        #expect(fixture.decisions.burstGroupID(for: fixture.file) == nil)

        fixture.viewModel.similarityModel.burstGroups = [BurstGroup(id: 7, fileIDs: [fixture.file.id, sibling.id])]
        let group = try #require(fixture.decisions.burstGroupID(for: fixture.file))
        #expect(group == 7)
        #expect(!fixture.decisions.isReviewed(groupID: group))
        #expect(fixture.decisions.toggleReviewed(groupID: group))
        #expect(fixture.decisions.isReviewed(groupID: group))
        #expect(!fixture.decisions.toggleReviewed(groupID: group))
        #expect(!fixture.decisions.isReviewed(groupID: group))
    }
}
