import SwiftUI

struct BurstShortcutGuide: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                shortcut("P/N", action: "frame")
                separator
                shortcut("G", action: "next group")
                separator
                shortcut("+/−", action: "zoom")
                separator
                shortcut("2–5", action: "rate")
                separator
                shortcut("0", action: "pick")
                separator
                shortcut("X", action: "reject")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .scrollIndicators(.hidden)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Keyboard shortcuts: P or N changes frame, G opens the next group, plus or minus zooms, 2 through 5 rates, 0 picks, and X rejects"
        )
    }

    private func shortcut(_ key: String, action: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(action)
        }
    }

    private var separator: some View {
        Text("·")
            .accessibilityHidden(true)
    }
}
