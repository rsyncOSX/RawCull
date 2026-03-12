//
//  FocusDetectorControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/03/2026.
//

import SwiftUI

struct FocusDetectorControlsView: View {
    @Bindable var model: FocusDetectorMaskModel
    @State private var isCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — title centered, button pinned to trailing via overlay
            Text("Focus Mask Controls")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Label(
                            isCollapsed ? "Show" : "Hide",
                            systemImage: isCollapsed ? "eye" : "eye.slash",
                        )
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Show controls" : "Hide controls")
                }
                .padding()
        }
    }
}

// MARK: - Shared Slider Component

struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
