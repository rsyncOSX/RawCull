import SwiftUI

struct SimilarityDiagnosticsView: View {
    @State private var model = SimilarityDiagnosticsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SimilarityDiagnosticsHeader(model: model)
            Divider()
            SimilarityDiagnosticsContent(model: model)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await model.refresh()
        }
    }
}

private struct SimilarityDiagnosticsHeader: View {
    let model: SimilarityDiagnosticsViewModel

    @State private var isConfirmingClear = false

    var body: some View {
        HStack(spacing: 12) {
            Label("CLIP Recovery Log", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            Text(model.logFilePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.logFilePath)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading similarity diagnostics")
            }

            Button {
                Task {
                    await model.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)

            Button {
                model.copyAllToClipboard()
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .disabled(model.logText.isEmpty)
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Clear Log", systemImage: "trash")
            }
            .disabled(model.logText.isEmpty || model.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert("Clear Similarity Log?", isPresented: $isConfirmingClear) {
            Button("Clear Log", role: .destructive) {
                Task {
                    await model.clear()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved CLIP recovery and exclusion diagnostics.")
        }
    }
}

private struct SimilarityDiagnosticsContent: View {
    let model: SimilarityDiagnosticsViewModel

    var body: some View {
        if model.isLoading, model.logText.isEmpty {
            ProgressView("Loading similarity diagnostics…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("Similarity Log Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
        } else if model.logText.isEmpty {
            ContentUnavailableView {
                Label("No CLIP Failures Logged", systemImage: "checkmark.circle")
            } description: {
                Text("When CLIP recovery cannot produce a validated artifact, the excluded image and failure reason will appear here.")
            }
        } else {
            ScrollView {
                Text(verbatim: model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(.black.opacity(0.04))
        }
    }
}
