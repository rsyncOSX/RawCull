import OSLog
import SwiftUI

/// Burst list card that runs the local Qwen assessment on the top two frames
/// of every burst, with progress and Cancel.
struct BurstBatchAssessmentCard: View {
    let batch: BurstBatchAssessment
    /// Why Start is disabled, or nil when every burst list is ready.
    let disabledReason: String?
    let hasResults: Bool
    let start: () -> Void
    let viewResults: () -> Void

    @State private var confirmReassess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 52, height: 52)
                    .background(Color.purple.opacity(0.13), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI assessment").font(.headline)
                    Text(
                        "Assess the recommended and alternate frame of every burst with the local Qwen model. "
                            + "Findings may be inaccurate; ratings are not changed.",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if batch.isRunning {
                    Button(role: .cancel, action: batch.cancel) {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .controlSize(.large)
                    .disabled(batch.phase == .cancelling)
                    .help("Stop after the photo being assessed")
                } else {
                    HStack(spacing: 8) {
                        if hasResults {
                            Button("View Results", systemImage: "rectangle.on.rectangle", action: viewResults)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .keyboardShortcut(.defaultAction)
                        }
                        assessButton
                    }
                    .confirmationDialog(
                        "Clear the current AI assessments and assess again?",
                        isPresented: $confirmReassess,
                    ) {
                        Button("Clear and Reassess", role: .destructive, action: start)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The present results are removed and every burst is assessed again with the local Qwen model.")
                    }
                }
            }

            if batch.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    if batch.phase == .preparing {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: batch.fractionCompleted)
                            .progressViewStyle(.linear)
                    }
                    HStack {
                        Text(batch.statusText)
                        Spacer()
                        if batch.assessedPhotos + batch.failedPhotos > 0 {
                            Text("\(batch.assessedPhotos) assessed · \(batch.failedPhotos) failed")
                                .monospacedDigit()
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else if batch.phase != .idle {
                HStack(spacing: 8) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                    Text(batch.statusText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss", action: batch.dismissStatus)
                        .buttonStyle(.link)
                }
                .font(.callout)
            } else if let disabledReason {
                Text(disabledReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// Prominent when nothing has been assessed yet; secondary once results
    /// exist, and then it asks before clearing them.
    @ViewBuilder
    private var assessButton: some View {
        let button = Button {
            if hasResults {
                confirmReassess = true
            } else {
                start()
            }
        } label: {
            Label(hasResults ? "Reassess" : "Assess All Bursts", systemImage: "sparkles")
        }
        .controlSize(.large)
        .disabled(disabledReason != nil)
        .help(disabledReason ?? (hasResults
                ? "Clear the current results and assess every burst again"
                : "Assess the top two frames of every burst"))

        if hasResults {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var statusSymbol: String {
        switch batch.phase {
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "stop.circle"
        }
    }

    private var statusColor: Color {
        switch batch.phase {
        case .finished: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
