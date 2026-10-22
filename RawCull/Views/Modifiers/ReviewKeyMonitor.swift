import AppKit
import SwiftUI

/// Owns registration only. Each screen supplies its own event policy and actions.
@MainActor
final class ReviewKeyMonitor {
    private var token: Any?

    func install(handler: @escaping (NSEvent) -> KeyPress.Result) {
        remove()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) == .handled ? nil : event
        }
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }
}
