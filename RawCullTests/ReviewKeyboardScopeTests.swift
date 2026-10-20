import AppKit
@testable import RawCull
import Testing

@MainActor
@Suite("Review keyboard admission")
struct ReviewKeyboardScopeTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func key(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19,
        ))
    }

    @Test
    func `only anchored key window receives shortcuts`() throws {
        let review = makeWindow()
        let settings = makeWindow()
        defer { review.close(); settings.close() }
        let scope = ReviewKeyboardScope()
        let event = try key(in: review)
        #expect(!scope.accepts(event, keyWindow: review, modalWindow: nil))
        scope.window = review
        #expect(scope.accepts(event, keyWindow: review, modalWindow: nil))
        #expect(!scope.accepts(event, keyWindow: settings, modalWindow: nil))
        #expect(try !scope.accepts(key(in: settings), keyWindow: settings, modalWindow: nil))
        #expect(!scope.accepts(event, keyWindow: nil, modalWindow: nil))
        #expect(!scope.accepts(event, keyWindow: review, modalWindow: settings))
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, .option])
    func `command modifiers are left to app kit`(_ modifiers: NSEvent.ModifierFlags) throws {
        let window = makeWindow()
        defer { window.close() }
        let scope = ReviewKeyboardScope()
        scope.window = window
        #expect(try !scope.accepts(key(in: window, modifiers: modifiers), keyWindow: window, modalWindow: nil))
        #expect(try scope.accepts(key(in: window, modifiers: .shift), keyWindow: window, modalWindow: nil))
    }

    @Test
    func `native controls and text own their input`() throws {
        let window = makeWindow()
        defer { window.close() }
        let scope = ReviewKeyboardScope()
        scope.window = window
        let editor = NSTextView(frame: .zero)
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))
        #expect(try !scope.accepts(key(in: window), keyWindow: window, modalWindow: nil))
        #expect(ReviewKeyboardScope.controlOwnsKeys(NSSlider()))
        #expect(ReviewKeyboardScope.controlOwnsKeys(NSButton()))
        #expect(ReviewKeyboardScope.controlOwnsKeys(NSTextField()))
        let control = NSControl()
        let child = NSView()
        control.addSubview(child)
        #expect(ReviewKeyboardScope.controlOwnsKeys(child))
        #expect(!ReviewKeyboardScope.controlOwnsKeys(NSView()))
        #expect(!ReviewKeyboardScope.controlOwnsKeys(nil))
    }

    @Test
    func `anchor tracks window and detaches`() throws {
        let window = makeWindow()
        defer { window.close() }
        let scope = ReviewKeyboardScope()
        let anchor = ReviewKeyboardScopeReader.Anchor(scope: scope)
        window.contentView = anchor
        #expect(scope.window === window)
        anchor.removeFromSuperview()
        #expect(scope.window == nil)
        window.contentView = anchor
        anchor.detach()
        #expect(try !scope.accepts(key(in: window), keyWindow: window, modalWindow: nil))
    }

    @Test
    func `attached sheet keeps keys`() throws {
        let window = makeWindow()
        let sheet = makeWindow()
        defer { window.endSheet(sheet); sheet.close(); window.close() }
        let scope = ReviewKeyboardScope()
        scope.window = window
        window.beginSheet(sheet)
        #expect(window.attachedSheet === sheet)
        #expect(try !scope.accepts(key(in: window), keyWindow: window, modalWindow: nil))
    }
}
