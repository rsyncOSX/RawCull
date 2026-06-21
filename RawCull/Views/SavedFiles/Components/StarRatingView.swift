import SwiftUI

struct StarRatingView: View {
    let rating: Int
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: compact ? 10 : 14))
                    .foregroundStyle(star <= rating ? Color.yellow : Color(NSColor.separatorColor))
            }
        }
    }
}
