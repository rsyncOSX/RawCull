import AppKit
import SwiftUI

struct ModelLocationButton: View {
    let location: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([location])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        .controlSize(.small)
        .help("Shows the model's current location. Managed model locations can change between app launches.")
        .accessibilityHint("Shows the model's current location in Finder.")
    }
}
