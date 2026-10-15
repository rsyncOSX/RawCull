import AppKit
import SwiftUI

/// Local event monitors are application-wide. This anchor ties each monitor to
/// its actual review window and leaves native controls and sheets their keys.
@MainActor
final class ReviewKeyboardScope {
    weak var window: NSWindow?

    func accepts(_ event: NSEvent) -> Bool {
        guard let window,
              event.window === window,
              window.isKeyWindow,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        let focusedElement = NSApplication.accessibilityFocusedUIElement() as? any NSAccessibilityProtocol
        return !Self.isEditingControl(window.firstResponder)
            && !Self.controlOwnsKeys(role: focusedElement?.accessibilityRole())
    }

    static func controlOwnsKeys(role: NSAccessibility.Role?) -> Bool {
        guard let role else { return false }
        return [.slider, .textField, .textArea, .comboBox, .popUpButton,
                .incrementor].contains(role)
    }

    static func isEditingControl(_ responder: NSResponder?) -> Bool {
        if responder is NSText || responder is NSPopUpButton { return true }
        return responder is NSControl && !(responder is NSButton)
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

    final class Anchor: NSView {
        private let scope: ReviewKeyboardScope

        init(scope: ReviewKeyboardScope) {
            self.scope = scope
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scope.window = window
        }
    }
}

nonisolated enum ThumbnailKeyboardRouting {
    static func reservesBurstCommand(_ characters: String?, showsBurstGroups: Bool) -> Bool {
        showsBurstGroups && ["\r", "b", "B", "2", "u", "U"].contains(characters ?? "")
    }
}
