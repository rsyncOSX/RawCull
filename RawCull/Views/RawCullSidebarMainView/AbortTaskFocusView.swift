import SwiftUI

struct AbortTaskFocusView: View {
    @Binding var focusaborttask: Bool
    let abort: () -> Void

    var body: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                focusaborttask = false
                abort()
            }
    }
}
