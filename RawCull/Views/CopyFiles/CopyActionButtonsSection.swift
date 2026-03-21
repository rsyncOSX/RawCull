import SwiftUI

struct CopyActionButtonsSection: View {
    let dismiss: DismissAction
    let onCopyTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConditionalGlassButton(
                systemImage: "document.on.document",
                text: "Start Copy",
                helpText: "Start copying files",
                style: .softCapsule,
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
