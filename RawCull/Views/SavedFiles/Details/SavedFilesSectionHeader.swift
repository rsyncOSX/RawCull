import SwiftUI

struct SavedFilesSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(1.0)
            .padding(.bottom, 4)
    }
}
