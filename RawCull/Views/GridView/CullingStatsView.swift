//
//  CullingStatsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

struct CullingStatsView: View {
    let stats: (rejected: Int, kept: Int, r2: Int, r3: Int, r4: Int, r5: Int, unrated: Int, total: Int)
    @Binding var ratingFilter: GridRatingFilter

    var body: some View {
        let ratingSum = stats.rejected + stats.kept + stats.r2 + stats.r3 + stats.r4 + stats.r5 + stats.unrated
        HStack(alignment: .top, spacing: 12) {
            // Table 1: rejected / kept
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                GridRow {
                    Text("✕").foregroundStyle(Color.red)
                    Text("\(stats.rejected)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("P").foregroundStyle(Color.accentColor)
                    Text("\(stats.kept)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
            }

            // Table 2: star ratings
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                GridRow {
                    Text("★2").foregroundStyle(Color.yellow)
                    Text("\(stats.r2)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("★3").foregroundStyle(Color.green)
                    Text("\(stats.r3)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("★4").foregroundStyle(Color.blue)
                    Text("\(stats.r4)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("★5").foregroundStyle(Color.purple)
                    Text("\(stats.r5)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                }
            }

            // Unrated + sum
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    ratingFilter = ratingFilter == .unrated ? .all : .unrated
                } label: {
                    Text("\(stats.unrated) unrated")
                        .foregroundStyle(ratingFilter == .unrated ? Color.primary : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Show only unrated images")
                Text("= \(ratingSum) / \(stats.total)")
                    .foregroundStyle(ratingSum == stats.total ? Color.secondary : Color.red)
            }
        }
        .font(.caption.monospacedDigit())
    }
}
