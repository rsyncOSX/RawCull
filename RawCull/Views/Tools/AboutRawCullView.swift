//
//  AboutRawCullView.swift
//  RawCull
//

import AppKit
import SwiftUI

struct AboutRawCullView: View {
    @Environment(RawCullViewModel.self) private var viewModel

    private var activeShortcutSection: ShortcutSection {
        if viewModel.zoomOverlayVisible {
            .zoomPreview(navigationAxis: viewModel.zoomOverlayNavigationAxis)
        } else if viewModel.mainViewMode == .comparisonGrid,
                  viewModel.activeBurstComparisonGroupID != nil {
            viewModel.showsDetailedBurstComparison ? .burstComparison : .burstReview
        } else if viewModel.showsBurstGroups {
            .burstGroups
        } else {
            switch viewModel.mainViewMode {
            case .loupe:
                .loupe

            case .grid:
                .browse(title: "Grid View", context: "Catalog thumbnail grid.")

            case .similarityGrid:
                .browse(title: "Similarity Grid", context: "Photos grouped or sorted by similarity.")

            case .ratedGrid:
                .browse(title: "Rated Grid", context: "Thumbnail grid filtered by photo rating.")

            case .aiAnalysis:
                .browse(
                    title: "AI Analysis",
                    context: "Photos in the AI analysis workspace.",
                    navigationKeys: ["←", "→"],
                )

            case .comparisonGrid:
                .manualComparison
            }
        }
    }

    private var shortcutSections: [ShortcutSection] {
        [activeShortcutSection, .appCommands]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                aboutHeader

                VStack(alignment: .leading, spacing: 6) {
                    Text(shortcutSectionTitle)
                        .font(.title3.weight(.semibold))

                    Text(shortcutContextDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16,
                ) {
                    ForEach(shortcutSections) { section in
                        ShortcutSectionCard(section: section)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 620, idealWidth: 840, minHeight: 520, idealHeight: 720)
    }

    private var shortcutSectionTitle: String {
        "\(activeShortcutSection.title) Shortcuts"
    }

    private var shortcutContextDescription: String {
        "Showing only the shortcuts available in \(activeShortcutSection.title), plus app commands."
    }

    private var aboutHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("RawCull")
                    .font(.title2.weight(.semibold))

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Fast Sony RAW culling with local CLIP semantic search and similarity, Deep Review, and built-in Vision fallback when an optional model is unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return switch (version, build) {
        case let (version?, build?):
            "Version \(version) (\(build))"

        case let (version?, nil):
            "Version \(version)"

        case let (nil, build?):
            "Build \(build)"

        default:
            "Version unavailable"
        }
    }
}

private struct ShortcutSectionCard: View {
    let section: ShortcutSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(section.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)

                    Text(section.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.shortcuts) { shortcut in
                    ShortcutRowView(shortcut: shortcut)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(section.tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(section.title)
    }
}

private struct ShortcutRowView: View {
    let shortcut: ShortcutRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(shortcut.keys, id: \.self) { key in
                    KeyCap(text: key)
                }
            }
            .frame(minWidth: 84, alignment: .leading)

            Text(shortcut.action)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shortcut.accessibleKeys): \(shortcut.action)")
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
    }
}

private struct ShortcutSection: Identifiable {
    let title: String
    let context: String
    let symbol: String
    let tint: Color
    let shortcuts: [ShortcutRow]

    var id: String {
        title
    }

    private static let ratingShortcuts = [
        ShortcutRow(["X"], "Reject and advance"),
        ShortcutRow(["P", "0"], "Keep neutral and advance"),
        ShortcutRow(["1", "2"], "Apply rating 2 and advance"),
        ShortcutRow(["3", "T"], "Apply rating 3 and advance"),
        ShortcutRow(["4"], "Apply rating 4 and advance"),
        ShortcutRow(["5"], "Apply rating 5 and advance")
    ]

    static func browse(
        title: String,
        context: String,
        navigationKeys: [String] = ["↑", "↓", "←", "→"],
    ) -> ShortcutSection {
        ShortcutSection(
            title: title,
            context: "\(context) Ratings apply to every selected photo.",
            symbol: "photo.on.rectangle.angled",
            tint: .blue,
            shortcuts: [
                ShortcutRow(navigationKeys, "Move to the previous or next photo"),
                ShortcutRow(["Z"], "Inspect actual pixels with the AF point")
            ] + ratingShortcuts,
        )
    }

    static let loupe = ShortcutSection(
        title: "Loupe View",
        context: "Large photo preview beside the catalog browser.",
        symbol: "photo",
        tint: .teal,
        shortcuts: [
            ShortcutRow(["↑", "↓"], "Move to the previous or next photo"),
            ShortcutRow(["+", "-"], "Zoom in or out"),
            ShortcutRow(["E/e"], "Show or hide EXIF data and histogram"),
            ShortcutRow(["J"], "Show the embedded JPEG"),
            ShortcutRow(["R"], "Show the developed RAW preview"),
            ShortcutRow(["F", "A"], "Toggle the focus mask or AF point"),
            ShortcutRow(["S"], "Toggle the subject outline"),
            ShortcutRow(["Z"], "Inspect actual pixels with the AF point")
        ] + ratingShortcuts,
    )

    static let appCommands = ShortcutSection(
        title: "App Commands",
        context: "Available from the Actions menu throughout RawCull.",
        symbol: "command",
        tint: .green,
        shortcuts: [
            ShortcutRow(["⌘J"], "Extract JPEGs"),
            ShortcutRow(["⌘K"], "Abort the active task")
        ],
    )

    static let burstGroups = ShortcutSection(
        title: "Burst Groups",
        context: "Thumbnail grid while detected burst groups are visible.",
        symbol: "square.stack.3d.up",
        tint: .orange,
        shortcuts: [
            ShortcutRow(["Return"], "Open the selected burst for comparison"),
            ShortcutRow(["B"], "Keep the best photo in the burst"),
            ShortcutRow(["2"], "Keep the top two photos in the burst"),
            ShortcutRow(["U"], "Undo the last burst action"),
            ShortcutRow(["Esc"], "Leave burst grouping")
        ],
    )

    static func zoomPreview(navigationAxis: ZoomOverlayNavigationAxis) -> ShortcutSection {
        ShortcutSection(
            title: "Zoom Preview",
            context: "Full-window photo inspection overlay.",
            symbol: "magnifyingglass",
            tint: .purple,
            shortcuts: [
                ShortcutRow(navigationAxis == .vertical ? ["↑", "↓"] : ["←", "→"], "Show the previous or next photo"),
                ShortcutRow(["+", "-"], "Zoom in or out"),
                ShortcutRow(["J", "R"], "Switch to embedded JPEG or developed RAW"),
                ShortcutRow(["F", "A"], "Toggle the focus mask or AF point"),
                ShortcutRow(["S"], "Toggle the subject outline"),
                ShortcutRow(["X"], "Reject and advance"),
                ShortcutRow(["P", "0"], "Keep neutral and advance"),
                ShortcutRow(["1", "2"], "Apply rating 2 and advance"),
                ShortcutRow(["3", "T"], "Apply rating 3 and advance"),
                ShortcutRow(["4", "5"], "Apply rating 4 or 5 and advance"),
                ShortcutRow(["Esc"], "Close the zoom preview")
            ],
        )
    }

    static let manualComparison = ShortcutSection(
        title: "Manual Comparison",
        context: "Comparison opened from a manual thumbnail selection.",
        symbol: "rectangle.split.2x1",
        tint: .indigo,
        shortcuts: [
            ShortcutRow(["←", "→"], "Select the previous or next candidate"),
            ShortcutRow(["+", "-"], "Zoom the selected candidate"),
            ShortcutRow(["J"], "Toggle the selected image source"),
            ShortcutRow(["I"], "Show or hide the candidate inspector"),
            ShortcutRow(["F", "A"], "Toggle the focus mask or AF point"),
            ShortcutRow(["Z"], "Inspect the selected candidate at actual pixels"),
            ShortcutRow(["X"], "Reject and advance"),
            ShortcutRow(["P", "0"], "Keep neutral and advance"),
            ShortcutRow(["1", "2"], "Apply rating 2 and advance"),
            ShortcutRow(["3", "T"], "Apply rating 3 and advance"),
            ShortcutRow(["4", "5"], "Apply rating 4 or 5 and advance")
        ],
    )

    static let burstComparison = ShortcutSection(
        title: "Burst Comparison",
        context: "Detailed comparison of frames from a detected burst.",
        symbol: "rectangle.split.2x1",
        tint: .pink,
        shortcuts: manualComparison.shortcuts + [
            ShortcutRow(["B"], "Keep the best photo in the burst"),
            ShortcutRow(["Esc"], "Return to the burst group")
        ],
    )

    static let burstReview = ShortcutSection(
        title: "Burst Review",
        context: "Detected-burst review workspace.",
        symbol: "rectangle.stack",
        tint: .pink,
        shortcuts: [
            ShortcutRow(["P", "N"], "Show the previous or next frame"),
            ShortcutRow(["←", "→"], "Show the previous or next frame"),
            ShortcutRow(["G"], "Advance to the next burst group"),
            ShortcutRow(["+", "-"], "Zoom the selected frame"),
            ShortcutRow(["J", "R"], "Choose JPEG or RAW"),
            ShortcutRow(["F", "A"], "Toggle the focus mask or AF point"),
            ShortcutRow(["S"], "Toggle the subject outline"),
            ShortcutRow(["X"], "Reject and advance"),
            ShortcutRow(["0"], "Keep neutral — P means previous here"),
            ShortcutRow(["1", "2"], "Apply rating 2 and advance"),
            ShortcutRow(["3", "T"], "Apply rating 3 and advance"),
            ShortcutRow(["4", "5"], "Apply rating 4 or 5 and advance"),
            ShortcutRow(["Esc"], "Return to the burst group")
        ],
    )
}

private struct ShortcutRow: Identifiable {
    let keys: [String]
    let action: String

    init(_ keys: [String], _ action: String) {
        self.keys = keys
        self.action = action
    }

    var id: String {
        "\(keys.joined(separator: "-"))-\(action)"
    }

    var accessibleKeys: String {
        keys.joined(separator: " or ")
    }
}
