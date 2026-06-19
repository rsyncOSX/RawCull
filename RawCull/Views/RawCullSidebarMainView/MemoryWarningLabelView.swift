import SwiftUI

struct MemoryWarningLabelView: View {
    enum WarningStyle {
        case soft
        case full
    }

    let style: WarningStyle
    @Binding var memoryWarningOpacity: Double
    let onAppearAction: () -> Void
    let onClose: (() -> Void)?

    init(
        style: WarningStyle = .full,
        memoryWarningOpacity: Binding<Double> = .constant(0.8),
        onAppearAction: @escaping () -> Void = {},
        onClose: (() -> Void)? = nil,
    ) {
        self.style = style
        self._memoryWarningOpacity = memoryWarningOpacity
        self.onAppearAction = onAppearAction
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style == .soft ? "memorychip" : "exclamationmark.triangle.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(style == .soft ? "Memory Pressure" : "Memory Warning")
                    .font(.headline)
                Text(style == .soft
                    ? "Memory usage at 85%+. macOS reports normal."
                    : "System memory pressure detected. Cache has been reduced.")
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
        .background(style == .soft ? Color.orange.opacity(0.7) : Color.red.opacity(memoryWarningOpacity))
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 8))
        .padding(12)
        .onAppear {
            onAppearAction()
        }
    }
}
