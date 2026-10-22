import AppKit
import RawCullCore
import SwiftUI

struct BatchBadgeSelectionControlsView: View {
    let items: [BatchBadgeSelectionItem]
    let selectedCount: Int
    @Binding var rating: Int
    let onSelectBadge: (String) -> Void
    let onApplyRating: () -> Void

    private let ratings: [(value: Int, label: String)] = [
        (-1, "X"),
        (0, "P"),
        (2, "2"),
        (3, "3"),
        (4, "4"),
        (5, "5"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            onSelectBadge(item.label)
                        } label: {
                            Text("\(item.label) \(item.count)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(item.color)
                        // swiftformat:disable:next isEmpty
                        // swiftlint:disable:next empty_count
                        .disabled(item.count == 0)
                        .help(
                            "Select \(item.count) visible thumbnails tagged \(item.label). Hold Command to add or remove from the current selection."
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: 360)

            Text("\(selectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)

            Picker("Rating", selection: $rating) {
                ForEach(ratings, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 150)
            .help("Rating to apply to the selected thumbnails")

            Button("Apply") {
                onApplyRating()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(selectedCount == 0)
            .help("Apply the selected rating to the selected thumbnails")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Badge batch selection")
    }
}
