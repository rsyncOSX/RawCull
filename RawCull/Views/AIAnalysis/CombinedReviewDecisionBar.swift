import SwiftUI

/// Tag, Rate and Mark Reviewed for the photo a review describes. The review itself never
/// sets these; only these controls and the grid's rating keys do.
struct CombinedReviewDecisionBar: View {
    let review: ReviewFileSnapshot
    let decisions: ReviewDecisionActions
    @State private var changedOnDisk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = decisions.unavailableReason(for: review) {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else if let file = decisions.liveFile(for: review) {
                controls(for: file)
                if changedOnDisk {
                    Text("The photo changed on disk after this review. Run the review again to tag or rate it here.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: review.fingerprint) { changedOnDisk = false }
    }

    private func controls(for file: FileItem) -> some View {
        let rating = decisions.rating(for: file)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tagButton(file)
                ratingButtons(rating)
                reviewedButton(file)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    tagButton(file)
                    reviewedButton(file)
                }
                ratingButtons(rating)
            }
        }
    }

    private func tagButton(_ file: FileItem) -> some View {
        let tagged = decisions.isTagged(file)
        return Button {
            perform { file, catalog in decisions.toggleTag(file, in: catalog) }
        } label: {
            Label(tagged ? "Untag" : "Tag", systemImage: tagged ? "tag.fill" : "tag")
        }
        .accessibilityLabel(tagged ? Text("Untag \(file.name)") : Text("Tag \(file.name)"))
    }

    private func ratingButtons(_ current: RatingDisplay) -> some View {
        HStack(spacing: 2) {
            ForEach(ImageReviewRatingAction.standardActions, id: \.value) { action in
                let display = RatingDisplay(rating: action.value)
                Button(display.label) {
                    perform { file, _ in decisions.rate(file, action.value) }
                }
                .buttonStyle(.bordered)
                .tint(display == current ? .accentColor : nil)
                .help(action.help)
                .accessibilityLabel(Text(action.help))
                .accessibilityAddTraits(display == current ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func reviewedButton(_ file: FileItem) -> some View {
        if let group = decisions.burstGroupID(for: file) {
            let reviewed = decisions.isReviewed(groupID: group)
            Button {
                perform { _, _ in decisions.toggleReviewed(groupID: group) }
            } label: {
                Label(reviewed ? "Undo Reviewed" : "Mark Reviewed",
                      systemImage: reviewed ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help("Marks the photo's burst as reviewed, as in the burst workspace.")
        }
    }

    private func perform(_ action: (FileItem, URL) -> Void) {
        changedOnDisk = !decisions.act(on: review, action)
    }
}
