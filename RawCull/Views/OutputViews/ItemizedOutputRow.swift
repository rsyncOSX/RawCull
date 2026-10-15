import SwiftUI

struct ItemizedOutputRow: View {
    let record: String

    var body: some View {
        if let parsed = ItemizedOutputRecord(record) {
            HStack(spacing: 10) {
                Label(parsed.kind.rawValue, systemImage: parsed.kind.systemImage)
                    .foregroundStyle(parsed.kind.color)
                    .font(.caption.weight(.semibold))
                    .frame(width: 92, alignment: .leading)

                Text(parsed.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer()

                Text(parsed.code)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(record)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private extension ItemizedChangeKind {
    var systemImage: String {
        switch self {
        case .added: "plus.circle.fill"
        case .updated: "arrow.triangle.2.circlepath.circle.fill"
        case .deleted: "minus.circle.fill"
        case .metadata: "info.circle.fill"
        case .other: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: .green
        case .updated: .blue
        case .deleted: .red
        case .metadata: .orange
        case .other: .secondary
        }
    }
}
