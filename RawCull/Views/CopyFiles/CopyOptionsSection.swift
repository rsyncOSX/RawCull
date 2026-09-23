import SwiftUI

struct CopyOptionsSection: View {
    @Binding var copyTaggedFiles: Bool
    @Binding var copyratedfiles: Int
    @Binding var dryrun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy Options")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("Copy", selection: $copyTaggedFiles) {
                Text("Tagged files").tag(true)
                Text("By minimum rating").tag(false)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if !copyTaggedFiles {
                RatingPickerSection(rating: $copyratedfiles)
            }

            HStack(spacing: 8) {
                ToggleViewDefault(text: "Dry run", binding: $dryrun)
                if dryrun {
                    Label("No files will be copied", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
