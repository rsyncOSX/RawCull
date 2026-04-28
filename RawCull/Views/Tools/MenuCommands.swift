//
//  MenuCommands.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/01/2026.
//

import Foundation
import SwiftUI

struct MenuCommands: Commands {
    @FocusedBinding(\.aborttask) private var aborttask
    @FocusedBinding(\.extractJPGs) private var extractJPGs
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Actions") {
            CommandButton("Extract JPGs", action: { extractJPGs = true }, shortcut: "j")

            Divider()

            CommandButton("Abort task", action: { aborttask = true }, shortcut: "k")
        }

        CommandMenu("Diagnostics") {
            Button("Memory Console") {
                openWindow(id: "memory-diagnostics")
            }
        }
    }
}

// MARK: - Reusable Command Button

struct CommandButton: View {
    let label: String
    let action: () -> Void
    let shortcut: KeyboardShortcut?

    init(_ label: String, action: @escaping () -> Void, shortcut: String? = nil) {
        self.label = label
        self.action = action
        if let shortcut {
            self.shortcut = .init(KeyEquivalent(shortcut.first ?? "t"), modifiers: [.command])
        } else {
            self.shortcut = nil
        }
    }

    var body: some View {
        if let shortcut {
            Button(label, action: action).keyboardShortcut(shortcut)
        } else {
            Button(label, action: action)
        }
    }
}

// MARK: - Focused Value Keys

struct FocusedAborttask: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedExtractJPGs: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var aborttask: FocusedAborttask.Value? {
        get { self[FocusedAborttask.self] }
        set { self[FocusedAborttask.self] = newValue }
    }

    var extractJPGs: FocusedExtractJPGs.Value? {
        get { self[FocusedExtractJPGs.self] }
        set { self[FocusedExtractJPGs.self] = newValue }
    }
}
