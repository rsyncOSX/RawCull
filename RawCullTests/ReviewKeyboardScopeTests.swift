import AppKit
@testable import RawCull
import Testing

@MainActor
struct ReviewKeyboardScopeTests {
    @Test
    func `unattached review scopes reject keyboard events`() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2",
            isARepeat: false, keyCode: 19,
        ))
        #expect(!ReviewKeyboardScope().accepts(event))
    }

    @Test
    func `native editors and controls retain their keyboard input`() {
        #expect(ReviewKeyboardScope.isEditingControl(NSTextView()))
        #expect(ReviewKeyboardScope.isEditingControl(NSSlider()))
        #expect(!ReviewKeyboardScope.isEditingControl(NSButton()))
        #expect(ReviewKeyboardScope.isEditingControl(NSPopUpButton()))
        #expect(!ReviewKeyboardScope.isEditingControl(NSView()))
    }

    @Test
    func `SwiftUI accessibility controls retain their keys`() {
        for role: NSAccessibility.Role in [.slider, .textField, .textArea, .comboBox, .popUpButton,
                                           .incrementor] {
            #expect(ReviewKeyboardScope.controlOwnsKeys(role: role))
        }
        for role: NSAccessibility.Role in [.button, .checkBox, .radioButton, .tabGroup, .image] {
            #expect(!ReviewKeyboardScope.controlOwnsKeys(role: role))
        }
        #expect(!ReviewKeyboardScope.controlOwnsKeys(role: nil))
    }

    @Test(arguments: ["2", "b", "B", "u", "U", "\r"])
    func `burst keys belong to the burst handler before ratings`(_ key: String) {
        #expect(ThumbnailKeyboardRouting.reservesBurstCommand(key, showsBurstGroups: true))
        #expect(!ThumbnailKeyboardRouting.reservesBurstCommand(key, showsBurstGroups: false))
    }

    @Test(arguments: ["1", "3", "4", "5", "x", "p", "z"])
    func `ordinary rating and inspection keys remain available`(_ key: String) {
        #expect(!ThumbnailKeyboardRouting.reservesBurstCommand(key, showsBurstGroups: true))
    }
}
