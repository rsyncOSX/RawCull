import SwiftUI

struct MemoryWarningLabelView: View {
    @Binding var memoryWarningOpacity: Double
    let onAppearAction: () -> Void
    let onClose: (() -> Void)?

    init(
        memoryWarningOpacity: Binding<Double> = .constant(0.8),
        onAppearAction: @escaping () -> Void = {},
        onClose: (() -> Void)? = nil,
    ) {
        self._memoryWarningOpacity = memoryWarningOpacity
        self.onAppearAction = onAppearAction
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Memory Warning")
                    .font(.headline)
                Text("System memory pressure detected. Cache has been reduced.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.headline)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close memory warning")
                .help("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(memoryWarningOpacity))
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 8))
        .padding(12)
        .onAppear {
            onAppearAction()
        }
    }
}
