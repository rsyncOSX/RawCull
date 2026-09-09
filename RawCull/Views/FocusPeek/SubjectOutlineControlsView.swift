import SwiftUI

struct SubjectOutlineControlsView: View {
    @Binding var showSubjectOutline: Bool
    let subjectOutlineAvailable: Bool
    let isLoading: Bool
    var shortcutLabel: String?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        HStack(spacing: density == .compact ? 5 : 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSubjectOutline.toggle()
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "scope")
                            .font(density == .compact ? .body : .title3)
                            .foregroundStyle(showSubjectOutline ? .orange : .primary)
                            .symbolEffect(.bounce, value: showSubjectOutline)
                    }
                }
                .frame(width: density == .compact ? 16 : 20, height: density == .compact ? 16 : 20)
            }
            .buttonStyle(.plain)
            .disabled(!subjectOutlineAvailable || isLoading)
            .help(showSubjectOutline ? "Hide Deep Review subject outline" : "Show Deep Review subject outline")
            .accessibilityLabel("Deep Review subject outline")
            .accessibilityValue(showSubjectOutline ? "Shown" : "Hidden")
            .accessibilityHint(
                subjectOutlineAvailable
                    ? "Shows or hides the cached subject outline from Deep Review."
                    : "Run Deep Review for this image to create a subject outline.",
            )

            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, density == .compact ? 6 : 10)
        .padding(.vertical, density == .compact ? 5 : 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(density == .compact ? 2 : 10)
        .animation(.spring(duration: 0.3), value: showSubjectOutline)
    }
}
