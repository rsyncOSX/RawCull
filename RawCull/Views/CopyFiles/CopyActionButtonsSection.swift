import SwiftUI

struct CopyActionButtonsSection: View {
    let dismiss: DismissAction
    let onCopyTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConditionalGlassButton(
                systemImage: "arrowshape.right.fill",
                text: "Start Copy",
                helpText: "Start copying files"
            ) {
                onCopyTapped()
            }

            Spacer()

            Button("Close", role: .close) {
                dismiss()
            }
            .buttonStyle(RefinedGlassButtonStyle())
        }
    }
}
