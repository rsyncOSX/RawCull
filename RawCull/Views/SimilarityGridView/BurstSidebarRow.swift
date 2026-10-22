import OSLog
import SwiftUI

struct BurstSidebarRow: View {
    let title: String
    var count: Int?
    var countColor: Color = .accentColor
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 20)
                Text(title)
                Spacer()
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(countColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 9))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
    }
}
