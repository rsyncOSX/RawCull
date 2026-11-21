import Foundation

/// Tag, rate and Mark Reviewed for AI review result screens. These are the grid's own
/// rating and burst-review calls. Nothing here runs unless the photographer acts:
/// running, opening or comparing a review never changes a tag, rating or review state.
@MainActor
struct ReviewDecisionActions {
    let catalog: CatalogWorkspace
    let ratings: RatingsModel
    let culling: CullingController
    let burstWorkflow: BurstWorkflowController

    /// The open catalog, while its ratings are loaded and can be changed.
    var editableCatalog: URL? {
        guard let url = catalog.selectedSource?.url, !catalog.scanning,
              ratings.cullingModel.loadState == .ready, !ratings.cullingModel.isTerminationPending else { return nil }
        return url
    }

    /// Ratings are stored by filename, so a name that appears twice in the catalog can't be rated safely.
    func hasDuplicateFilename(_ file: FileItem) -> Bool {
        catalog.files.lazy.filter { $0.name == file.name }.prefix(2).count > 1
    }

    func rating(for file: FileItem) -> RatingDisplay {
        ImageReviewFeaturePolicy.ratingDisplay(for: file, using: ratings)
    }

    func isTagged(_ file: FileItem) -> Bool {
        ratings.getRating(for: file) >= 2
    }

    func rate(_ file: FileItem, _ rating: Int) {
        culling.updateRating(for: file, rating: rating)
    }

    /// Tagging sets two stars; untagging removes the record, as in the grid.
    func toggleTag(_ file: FileItem, in catalog: URL) {
        if isTagged(file) {
            ratings.cullingModel.applyRatingStates([file.name: nil], in: catalog)
            culling.refreshCullingDerivedState()
        } else {
            culling.updateRating(for: file, rating: 2)
        }
    }

    /// The one burst group in the active catalog scope that contains the file.
    func burstGroupID(for file: FileItem) -> Int? {
        let groups = burstWorkflow.burstGroupsInActiveCatalogScope.filter { $0.fileIDs.contains(file.id) }
        return groups.count == 1 ? groups.first?.id : nil
    }

    func isReviewed(groupID: Int) -> Bool {
        burstWorkflow.burstGroupReviewState(groupID: groupID) == .reviewed
    }

    /// Returns true when the group is now reviewed.
    @discardableResult
    func toggleReviewed(groupID: Int) -> Bool {
        burstWorkflow.toggleBurstGroupReviewed(groupID: groupID)
    }

    /// The catalog file a saved review describes, matched by location. Call
    /// `isUnchanged(_:since:)` before acting, because the file may have changed on disk.
    func liveFile(for review: ReviewFileSnapshot) -> FileItem? {
        guard editableCatalog != nil else { return nil }
        let url = review.url.standardizedFileURL
        return catalog.files.first { $0.url.standardizedFileURL == url }
    }

    /// True when the file on disk is the one that was reviewed.
    func isUnchanged(_ file: FileItem, since review: ReviewFileSnapshot) -> Bool {
        // URL caches resource values per instance; read the file as it is now.
        var url = file.url
        url.removeAllCachedResourceValues()
        return (try? ReviewFileSnapshot.fingerprint(url)) == review.fingerprint
    }
}

extension ReviewDecisionActions {
    /// Why the reviewed photo can't be tagged or rated right now, or nil when it can.
    func unavailableReason(for review: ReviewFileSnapshot) -> LocalizedStringResource? {
        guard editableCatalog != nil else { return "Open the photo's catalog to tag, rate or mark it reviewed." }
        guard let file = liveFile(for: review) else { return "This photo is not in the open catalog." }
        guard !hasDuplicateFilename(file) else {
            return "Tagging is unavailable because more than one file in the open catalog has this filename."
        }
        return nil
    }

    /// Acts on the reviewed photo only while it is in the open catalog and unchanged on disk.
    /// Returns false, and changes nothing, otherwise.
    @discardableResult
    func act(on review: ReviewFileSnapshot, _ action: (FileItem, URL) -> Void) -> Bool {
        guard unavailableReason(for: review) == nil, let catalog = editableCatalog,
              let file = liveFile(for: review), isUnchanged(file, since: review) else { return false }
        action(file, catalog)
        return true
    }
}
