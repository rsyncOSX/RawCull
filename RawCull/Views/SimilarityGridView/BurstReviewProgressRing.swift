import OSLog
import SwiftUI

struct BurstReviewProgressRing: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.14), lineWidth: 15)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.secondary)
                Text("\(completedCount) of \(totalCount)")
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("completed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(totalCount) burst groups completed")
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(completedCount) / Double(totalCount), 1)
    }
}
