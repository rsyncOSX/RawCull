import SwiftUI

struct MemoryWarningLabelView: View {
    @Binding var memoryWarningOpacity: Double
    let onAppearAction: () -> Void

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
