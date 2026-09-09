import SwiftUI

struct DeepAIReviewMaskAvailabilityBadge: View {
    var body: some View {
        Image(systemName: "scope")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.orange.opacity(0.9), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .help("Deep Review subject mask available")
            .accessibilityLabel("Deep Review subject mask available")
    }
}
