import SwiftUI

struct RawFileDiagnosticsView: View {
    let log: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RAW Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(verbatim: log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.black.opacity(0.04))
            .clipShape(.rect(cornerRadius: 6))
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
    }
}
