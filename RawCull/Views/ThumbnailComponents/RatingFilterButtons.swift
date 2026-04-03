//
//  RatingFilterButtons.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

/// Rating-filter pill row shared by the main toolbar and the grid selection header.
///
/// - `activeRating`: the currently active filter expressed as `Int?`
///   (`nil` = all, `-1` = rejected, `0` = keepers, `2–5` = star rating).
/// - `onSelect`: called with the tapped rating; callers decide toggle semantics.
/// - `onClear`: called when the ✕ button is tapped.
struct RatingFilterButtons: View {
    let activeRating: Int?
    let onSelect: (Int) -> Void
    let onClear: () -> Void

    private let ratings: [(Int, Color)] = [
        (-1, .red), (2, .yellow), (3, .green), (4, .blue), (5, .purple)
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ratings, id: \.0) { rating, color in
                Button { onSelect(rating) } label: {
                    Circle()
                        .fill(color.opacity(activeRating == rating ? 1.0 : 0.25))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help(rating == -1 ? "Show only rejected images" : "Show only \(rating)-star images")
            }

            // Keepers button (rating == 0)
            Button { onSelect(0) } label: {
                Text("P")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(activeRating == 0 ? .white : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(activeRating == 0 ? Color.accentColor : Color.secondary.opacity(0.2)),
                    )
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help("Show only keepers (rating 0)")

            if activeRating != nil {
                Button { onClear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help("Show all thumbnails")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }
}
