import AppKit
import SwiftUI

/// Local monitors see every window's events. Keep review shortcuts in the
/// anchored window and let native input controls receive their own keys.
@MainActor
final class ReviewKeyboardScope {
    weak var window: NSWindow?

    func accepts(_ event: NSEvent) -> Bool {
        accepts(event, keyWindow: NSApp.keyWindow, modalWindow: NSApp.modalWindow)
    }

    func accepts(_ event: NSEvent, keyWindow: NSWindow?, modalWindow: NSWindow?) -> Bool {
        guard let window,
              event.window === window,
              keyWindow === window,
              window.attachedSheet == nil,
              modalWindow == nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        return !Self.controlOwnsKeys(window.firstResponder)
    }

    static func controlOwnsKeys(_ responder: NSResponder?) -> Bool {
        if responder is NSText || responder is NSControl {
            return true
        }
        // Some native controls give a nested view keyboard focus.
        var view = (responder as? NSView)?.superview
        while let ancestor = view {
            if ancestor is NSControl {
                return true
            }
            view = ancestor.superview
        }
        return false
    }
}

struct ReviewKeyboardScopeReader: NSViewRepresentable {
    let scope: ReviewKeyboardScope

    func makeNSView(context _: Context) -> Anchor {
        Anchor(scope: scope)
    }

    func updateNSView(_ view: Anchor, context _: Context) {
        scope.window = view.window
    }

    static func dismantleNSView(_ view: Anchor, coordinator _: ()) {
        view.detach()
    }

    final class Anchor: NSView {
        private let scope: ReviewKeyboardScope

        init(scope: ReviewKeyboardScope) {
            self.scope = scope
            super.init(frame: .zero)
        }

        required init?(coder _: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scope.window = window
        }

        func detach() {
            scope.window = nil
        }
    }
}
