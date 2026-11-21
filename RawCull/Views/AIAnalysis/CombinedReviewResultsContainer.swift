import SwiftUI

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
