//
//  RatingView.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/01/2026.
//

import SwiftUI

struct RatingView: View {
    let rating: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { star in
                Button(action: {
                    onChange(star)
                }, label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? .yellow : .gray)
                        .font(.system(size: 12))
                })
                .buttonStyle(.plain)
            }
        }
    }
}
