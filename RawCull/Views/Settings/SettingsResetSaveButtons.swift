//
//  SettingsResetSaveButtons.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/03/2026.
//

import SwiftUI

struct SettingsResetSaveButtons<Middle: View>: View {
    @Binding var showResetConfirmation: Bool
    @Binding var showSaveConfirmation: Bool
    let resetMessage: String
    let saveMessage: String
    let onReset: () -> Void
    let onSave: () -> Void
    private let middle: Middle

    init(
        showResetConfirmation: Binding<Bool>,
        showSaveConfirmation: Binding<Bool>,
        resetMessage: String,
        saveMessage: String,
        onReset: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder middle: () -> Middle = { EmptyView() },
    ) {
        _showResetConfirmation = showResetConfirmation
        _showSaveConfirmation = showSaveConfirmation
        self.resetMessage = resetMessage
        self.saveMessage = saveMessage
        self.onReset = onReset
        self.onSave = onSave
        self.middle = middle()
    }

    var body: some View {
        Group {
            Button(
                action: { showResetConfirmation = true },
                label: {
                    Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                },
            )
            .buttonStyle(RefinedGlassButtonStyle())
            .confirmationDialog(
                "Reset Settings",
                isPresented: $showResetConfirmation,
                actions: {
                    Button("Reset", role: .destructive, action: onReset)
                    Button("Cancel", role: .cancel) {}
                },
                message: {
                    Text(resetMessage)
                },
            )

            middle

            Button(
                action: { showSaveConfirmation = true },
                label: {
                    Label("Save Settings", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 12, weight: .medium))
                },
            )
            .buttonStyle(RefinedGlassButtonStyle())
            .confirmationDialog(
                "Save Settings",
                isPresented: $showSaveConfirmation,
                actions: {
                    Button("Save", role: .destructive, action: onSave)
                    Button("Cancel", role: .cancel) {}
                },
                message: {
                    Text(saveMessage)
                },
            )
        }
    }
}
