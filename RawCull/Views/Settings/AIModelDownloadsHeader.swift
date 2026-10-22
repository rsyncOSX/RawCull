import SwiftUI

struct AIModelDownloadsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Model Downloads")
                .font(.title2.weight(.semibold))

            Text("RawCull uses on-demand Managed Background Assets. macOS stores and manages downloaded models, which run locally after installation. Their current access location can change between app launches.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
