import SwiftUI

struct ExtractJPGsFocusView: View {
    let selectedSource: ARWSourceCatalog?
    @Binding var alertType: AlertType?
    @Binding var showingAlert: Bool

    var body: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                guard selectedSource != nil else { return }
                alertType = .extractJPGs
                showingAlert = true
            }
    }
}
