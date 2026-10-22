import SwiftUI

struct SubjectOutlineControlsView: View {
    @Binding var showSubjectOutline: Bool
    let subjectOutlineAvailable: Bool
    let isLoading: Bool
    var shortcutLabel: String?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        OverlayControlCapsule(density: density, shortcutLabel: shortcutLabel) {
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

        }
        .animation(.spring(duration: 0.3), value: showSubjectOutline)
    }
}
