import SwiftUI

struct HideInspectorFocusView: View {
    @Binding var focushideInspector: Bool
    @Binding var hideInspector: Bool

    var body: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                focushideInspector = false
                hideInspector.toggle()
            }
    }
}
