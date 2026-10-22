import AppKit
import RawCullCore
import SwiftUI

struct BurstComparisonEvidenceView: View {
    let inspectorIsPresented: Bool
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Back To Group", action: onBack)
            // .controlSize(.mini)

            Text(inspectorHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 1)
    }

    private var inspectorHint: String {
        let inspectorAction = inspectorIsPresented ? "Press I to close Inspector" : "Press I to open Inspector"
        return "\(inspectorAction)  ·  P/N frame  ·  G next burst"
    }
}
