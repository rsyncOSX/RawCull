import SwiftUI

struct CullingQueueHeader: View {
    let title: String
    let isSingleImages: Bool
    let burstCount: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                onBack()
            } label: {
                Label("Burst Groups", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(isSingleImages ? "1 group visible" : "\(burstCount) bursts visible")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if !isSingleImages {
                Text("·  pick of burst highlighted")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
