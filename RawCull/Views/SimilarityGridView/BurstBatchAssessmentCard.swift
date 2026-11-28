import OSLog
import SwiftUI

/// Burst list card that runs the local Qwen assessment on the top two frames
/// of every burst, or only of the close calls, with progress and Cancel.
struct BurstBatchAssessmentCard: View {
    let batch: BurstBatchAssessment
    /// Why Start is disabled, or nil when every burst list is ready.
    let disabledReason: String?
    let hasResults: Bool
    /// Low- and medium-confidence bursts with two distinct top frames.
    let closestCallCount: Int
    let start: (BurstBatchAssessment.Scope) -> Void
    let viewResults: () -> Void

    /// The scope waiting for the user to confirm clearing the present results.
    @State private var pendingScope: BurstBatchAssessment.Scope?

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
                        "Assess the recommended and alternate frame with the local Qwen model: only the close calls, "
                            + "where the analysis is unsure between them, or every burst. "
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
                        assessButton(.closestCalls)
                        assessButton(.all)
                    }
                    .confirmationDialog(
                        "Clear the current AI assessments and assess again?",
                        isPresented: Binding(get: { pendingScope != nil }, set: { if !$0 { pendingScope = nil } }),
                        presenting: pendingScope,
                    ) { scope in
                        Button("Clear and Reassess", role: .destructive) { start(scope) }
                        Button("Cancel", role: .cancel) {}
                    } message: { scope in
                        Text(scope == .closestCalls
                            ? "The present results are removed and the close calls are assessed with the local Qwen model."
                            : "The present results are removed and every burst is assessed again with the local Qwen model.")
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

    /// Closest calls is the prominent action until results exist; then both
    /// are secondary and ask before clearing the present results.
    @ViewBuilder
    private func assessButton(_ scope: BurstBatchAssessment.Scope) -> some View {
        let closest = scope == .closestCalls
        let reason = disabledReason
            ?? (closest && closestCallCount == 0 ? String(localized: "Every burst has a clear pick.") : nil)
        let button = Button {
            if hasResults {
                pendingScope = scope
            } else {
                start(scope)
            }
        } label: {
            if closest {
                Label("Assess Closest Calls (\(closestCallCount))", systemImage: "sparkles")
            } else {
                Label("Assess All Bursts", systemImage: "square.stack.3d.up")
            }
        }
        .controlSize(.large)
        .disabled(reason != nil)
        .help(reason ?? (closest
                ? "Assess the top two frames of the low- and medium-confidence bursts, lowest first"
                : "Assess the top two frames of every burst"))

        if closest, !hasResults {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
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
