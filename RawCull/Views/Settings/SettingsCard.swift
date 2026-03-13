//
//  SettingsCard.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/03/2026.
//

import SwiftUI

struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
    }
}
