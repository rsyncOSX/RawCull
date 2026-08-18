//
//  MenuCommands.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/01/2026.
//

import Foundation
import SwiftUI

struct MenuCommands: Commands {
    @FocusedBinding(\.addCatalog) private var addCatalog
    @FocusedBinding(\.aborttask) private var aborttask
    @FocusedBinding(\.extractJPGs) private var extractJPGs
    @FocusedBinding(\.copyTaggedFiles) private var copyTaggedFiles
    @FocusedBinding(\.showSavedFiles) private var showSavedFiles
    @FocusedValue(\.canCopyTaggedFiles) private var canCopyTaggedFiles
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Catalog…") {
                addCatalog = true
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(addCatalog == nil)
        }

        CommandGroup(after: .newItem) {
            Button("Copy Tagged Files…") {
                copyTaggedFiles = true
            }
            .disabled(copyTaggedFiles == nil || canCopyTaggedFiles != true)

            Button("Show Saved Files") {
                showSavedFiles = true
            }
            .disabled(showSavedFiles == nil)
        }

        CommandMenu("Actions") {
            CommandButton("Extract JPGs", action: { extractJPGs = true }, shortcut: "j")
                .disabled(extractJPGs == nil)

            Divider()

            CommandButton("Abort task", action: { aborttask = true }, shortcut: "k")
                .disabled(aborttask == nil)
        }

        CommandMenu("Diagnostics") {
            Button("Memory Console") {
                openWindow(id: "memory-diagnostics")
            }

            Button("Similarity Console") {
                openWindow(id: "similarity-diagnostics")
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

struct FocusedAddCatalog: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedExtractJPGs: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedCopyTaggedFiles: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedShowSavedFiles: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedCanCopyTaggedFiles: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var addCatalog: FocusedAddCatalog.Value? {
        get { self[FocusedAddCatalog.self] }
        set { self[FocusedAddCatalog.self] = newValue }
    }

    var aborttask: FocusedAborttask.Value? {
        get { self[FocusedAborttask.self] }
        set { self[FocusedAborttask.self] = newValue }
    }

    var extractJPGs: FocusedExtractJPGs.Value? {
        get { self[FocusedExtractJPGs.self] }
        set { self[FocusedExtractJPGs.self] = newValue }
    }

    var copyTaggedFiles: FocusedCopyTaggedFiles.Value? {
        get { self[FocusedCopyTaggedFiles.self] }
        set { self[FocusedCopyTaggedFiles.self] = newValue }
    }

    var showSavedFiles: FocusedShowSavedFiles.Value? {
        get { self[FocusedShowSavedFiles.self] }
        set { self[FocusedShowSavedFiles.self] = newValue }
    }

    var canCopyTaggedFiles: FocusedCanCopyTaggedFiles.Value? {
        get { self[FocusedCanCopyTaggedFiles.self] }
        set { self[FocusedCanCopyTaggedFiles.self] = newValue }
    }
}
