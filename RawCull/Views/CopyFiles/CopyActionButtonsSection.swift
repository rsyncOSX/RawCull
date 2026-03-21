import SwiftUI

struct CopyActionButtonsSection: View {
    let dismiss: DismissAction
    let onCopyTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConditionalGlassButton(
                systemImage: "document.on.document",
                text: "Copy",
                helpText: "Copy files to destination",
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
