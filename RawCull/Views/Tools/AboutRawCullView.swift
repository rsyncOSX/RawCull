//
//  AboutRawCullView.swift
//  RawCull
//

import AppKit
import SwiftUI

struct AboutRawCullView: View {
    private let shortcuts = [
        ShortcutRow(context: "Grid", keys: "Arrow keys", action: "Select previous or next image"),
        ShortcutRow(context: "Grid", keys: "Z", action: "Inspect focus point at actual pixels"),
        ShortcutRow(context: "Grid", keys: "X", action: "Reject and advance"),
        ShortcutRow(context: "Grid", keys: "P / 0", action: "Keep neutral and advance"),
        ShortcutRow(context: "Grid", keys: "1-5 / T", action: "Rate/tag and advance"),
        ShortcutRow(context: "Zoom", keys: "Arrow keys", action: "Show previous or next image"),
        ShortcutRow(context: "Zoom", keys: "+ / -", action: "Zoom in or out"),
        ShortcutRow(context: "Zoom", keys: "J / R", action: "Switch embedded JPG or developed RAW"),
        ShortcutRow(context: "Zoom", keys: "F / A", action: "Show focus mask or AF point"),
        ShortcutRow(context: "Zoom", keys: "Esc", action: "Close zoom"),
        ShortcutRow(context: "Compare", keys: "B", action: "Keep the best candidate"),
        ShortcutRow(context: "Burst", keys: "Return / B / 2 / U", action: "Compare, keep best, keep top two, or undo"),
        ShortcutRow(context: "Menu", keys: "Cmd-J / Cmd-K", action: "Extract JPGs or abort the active task")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RawCull")
                        .font(.title2.weight(.semibold))

                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Fast Sony RAW culling with embedded JPEG previews, ratings, focus masks, AF point overlays, sharpness scoring, and burst comparison.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Keystrokes")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(shortcuts) { shortcut in
                        GridRow {
                            Text(shortcut.context)
                                .foregroundStyle(.secondary)
                            Text(shortcut.keys)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                            Text(shortcut.action)
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
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

private struct ShortcutRow: Identifiable {
    let context: String
    let keys: String
    let action: String

    var id: String {
        "\(context)-\(keys)-\(action)"
    }
}
