import SwiftUI

/// Shared layout keeps tool-specific inputs separate from consistent run controls.
struct AIAnalysisControlBar<Inputs: View, Actions: View, Status: View>: View {
    @ViewBuilder let inputs: () -> Inputs
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let status: () -> Status

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    inputs()
                    Spacer(minLength: 12)
                    actions()
                }
                VStack(alignment: .leading, spacing: 8) {
                    inputs()
                    HStack { Spacer(); actions() }
                }
            }
            status()
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AIAnalysisProgressView: View {
    let completedCount: Int
    let totalCount: Int
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message).lineLimit(1).help(message)
                Spacer()
                Text("\(completedCount) / \(totalCount)").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
                .progressViewStyle(.linear)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AIAnalysisErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AIAnalysisStatusBadge: View {
    let title: LocalizedStringResource
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct AIAnalysisFindingsSection: View {
    let title: LocalizedStringResource
    let values: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            if values.isEmpty {
                Text("None detected").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(values, id: \.self) { value in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(value)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension View {
    func aiAnalysisResultsContainer() -> some View {
        background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }
}
