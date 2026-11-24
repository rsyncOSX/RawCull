import SwiftUI

/// Names each method's best frame when the AI disagrees with the measured picks.
/// Shows nothing while the AI has no clear leader or every method agrees.
struct BurstFramePicksBar: View {
    let picks: [BurstFramePick]

    static func isShown(for picks: [BurstFramePick]) -> Bool {
        picks.contains { $0.kind == .aiTop } && Set(picks.map(\.fileName)).count > 1
    }

    var body: some View {
        if Self.isShown(for: picks) {
            HStack(spacing: 14) {
                Label("Best frame differs", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                ForEach(picks) { pick in
                    Button(action: pick.select) {
                        HStack(spacing: 4) {
                            Image(systemName: Self.systemImage(pick.kind))
                                .foregroundStyle(pick.kind == .aiTop ? Color.purple : Color.secondary)
                            Text(Self.title(pick.kind)).foregroundStyle(.secondary)
                            Text(verbatim: pick.fileName).font(.caption.monospaced())
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show \(pick.fileName)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.purple.opacity(0.08))
        }
    }

    private static func title(_ kind: BurstFramePick.Kind) -> LocalizedStringResource {
        switch kind {
        case .aiTop: "AI top score"
        case .suggested: "Best Frame"
        case .sharpest: "Sharpest"
        }
    }

    private static func systemImage(_ kind: BurstFramePick.Kind) -> String {
        switch kind {
        case .aiTop: "sparkles"
        case .suggested: "star"
        case .sharpest: "scope"
        }
    }
}
