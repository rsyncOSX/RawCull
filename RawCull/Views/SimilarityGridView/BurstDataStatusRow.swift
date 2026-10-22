import OSLog
import SwiftUI

struct BurstDataStatusRow: View {
    let title: String
    let detail: String
    let count: Int
    let total: Int
    let isRunning: Bool
    var isUsed = true
    var isOptional = false

    private var isComplete: Bool {
        total > 0 && count >= total
    }

    private var status: String {
        if !isUsed {
            return "Not used"
        }
        if isRunning {
            return "Preparing · \(count)/\(total)"
        }
        if total == 0 {
            return "No photos"
        }
        if isComplete {
            return "Ready · \(count)/\(total)"
        }
        if count > 0 {
            return "Partial · \(count)/\(total)"
        }
        return isOptional ? "Not available" : "Needed"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: !isUsed ? "minus.circle" : isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(!isUsed ? Color.secondary : isComplete ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).fontWeight(.medium)
                    Spacer(minLength: 4)
                    Text(status).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(isUsed ? .primary : .secondary)
        .opacity(isUsed ? 1 : 0.5)
        .accessibilityElement(children: .combine)
    }
}
