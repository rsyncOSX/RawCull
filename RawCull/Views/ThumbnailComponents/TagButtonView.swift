//
//  TagButtonView.swift
//  RawCull
//
//  Created by Thomas Evensen on 15/03/2026.
//

import SwiftUI

struct TagButtonView: View {
    let isTagged: Bool
    let isHovered: Bool
    var onToggle: () -> Void

    var body: some View {
        Image(systemName: isTagged ? "checkmark.circle.fill" : "circle")
            .font(.system(size: isHovered ? 14 : 10))
            .foregroundStyle(isTagged ? Color.green : Color.white.opacity(0.8))
            .shadow(color: .black.opacity(0.5), radius: 2)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}
