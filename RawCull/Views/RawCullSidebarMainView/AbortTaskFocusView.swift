import SwiftUI

struct AbortTaskFocusView: View {
    @Binding var focusAbortTask: Bool
    let abort: () -> Void

    var body: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                focusAbortTask = false
                abort()
            }
    }
}
