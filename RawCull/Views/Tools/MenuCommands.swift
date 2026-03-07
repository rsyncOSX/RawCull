//
//  MenuCommands.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/01/2026.
//

import Foundation
import SwiftUI

struct MenuCommands: Commands {
    @FocusedBinding(\.tagimage) private var tagimage
    @FocusedBinding(\.aborttask) private var aborttask
    @FocusedBinding(\.hideInspector) private var hideInspector
    @FocusedBinding(\.extractJPGs) private var extractJPGs

    var body: some Commands {
        CommandMenu("Actions") {
            CommandButton("Tag Image", action: { tagimage = true }, shortcut: "t")
            CommandButton("Abort task", action: { aborttask = true }, shortcut: "k")

            Divider()

            CommandButton("Toggle Hide Inspector", action: { hideInspector = true }, shortcut: "i")
            CommandButton("Extract JPGs", action: { extractJPGs = true }, shortcut: "j")
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
        if let shortcut = shortcut {
            self.shortcut = .init(KeyEquivalent(shortcut.first ?? "t"), modifiers: [.command])
        } else {
            self.shortcut = nil
        }
    }

    init(_ label: String, action: @escaping () -> Void, shortcut: KeyboardShortcut) {
        self.label = label
        self.action = action
        self.shortcut = shortcut
    }

    var body: some View {
        if let shortcut = shortcut {
            Button(label, action: action).keyboardShortcut(shortcut)
        } else {
            Button(label, action: action)
        }
    }
}

struct TagImage: View {
    @Binding var tagimage: Bool?

    var body: some View {
        Button {
            tagimage = true
        } label: {
            Text("Tag Image")
        }
        .keyboardShortcut("t", modifiers: [.command])
    }
}

struct Abborttask: View {
    @Binding var aborttask: Bool?

    var body: some View {
        Button {
            aborttask = true
        } label: {
            Text("Abort task")
        }
        .keyboardShortcut("k", modifiers: [.command])
    }
}

struct HideInspector: View {
    @Binding var hideInspector: Bool?

    var body: some View {
        Button {
            hideInspector = true
        } label: {
            Text("Hide Inspector")
        }
        .keyboardShortcut("i", modifiers: [.command])
    }
}

// MARK: - Focused Value Keys

struct FocusedTagImage: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedAborttask: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedHideInspector: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedExtractJPGs: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var tagimage: FocusedTagImage.Value? {
        get { self[FocusedTagImage.self] }
        set { self[FocusedTagImage.self] = newValue }
    }

    var aborttask: FocusedAborttask.Value? {
        get { self[FocusedAborttask.self] }
        set { self[FocusedAborttask.self] = newValue }
    }

    var hideInspector: FocusedHideInspector.Value? {
        get { self[FocusedHideInspector.self] }
        set { self[FocusedHideInspector.self] = newValue }
    }

    var extractJPGs: FocusedExtractJPGs.Value? {
        get { self[FocusedExtractJPGs.self] }
        set { self[FocusedExtractJPGs.self] = newValue }
    }
}
