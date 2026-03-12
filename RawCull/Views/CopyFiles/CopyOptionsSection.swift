import SwiftUI

struct CopyOptionsSection: View {
    @Binding var copytaggedfiles: Bool
    @Binding var copyratedfiles: Int
    @Binding var dryrun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy Options")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                // Copy tagged files toggle
                ToggleViewDefault(text: "Copy tagged files?",
                                  binding: $copytaggedfiles)

                // Dry run toggle
                ToggleViewDefault(text: "Dry run?",
                                  binding: $dryrun)

                // Rating picker (only shown when not copying tagged files)
                RatingPickerSection(rating: $copyratedfiles)
                    .disabled(copytaggedfiles)
            }
        }
    }
}
