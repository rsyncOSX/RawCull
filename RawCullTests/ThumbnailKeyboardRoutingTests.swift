import SwiftUI
@testable import RawCull
import Testing

@MainActor
@Suite("Thumbnail keyboard routing")
struct ThumbnailKeyboardRoutingTests {
    @Test(arguments: ["2", "b", "B", "u", "U", "\r", "\u{1b}"])
    func burstCommandsHaveOneOwner(_ key: String) {
        var commands: [String] = []
        let consumed = ThumbnailKeyboardRouting.handleBurstCommand(
            key, showsBurstGroups: true,
            perform: { commands.append($0); return .handled },
        )
        #expect(consumed)
        #expect(commands == [key])
    }

    @Test
    func unavailableBurstCommandCannotBecomeRatingTwo() {
        var calls = 0
        let consumed = ThumbnailKeyboardRouting.handleBurstCommand(
            "2", showsBurstGroups: true,
            perform: { _ in calls += 1; return .ignored },
        )
        #expect(consumed)
        #expect(calls == 1)
        #expect(ThumbnailKeyboardRouting.handleBurstCommand("2", showsBurstGroups: true, perform: nil))
    }

    @Test(arguments: ["2", "b", "u", "\r", "\u{1b}"])
    func ordinaryGridPreservesExistingShortcuts(_ key: String) {
        var called = false
        #expect(!ThumbnailKeyboardRouting.handleBurstCommand(
            key, showsBurstGroups: false,
            perform: { _ in called = true; return .handled },
        ))
        #expect(!called)
    }

    @Test(arguments: ["r", "R", "1", "3", "4", "5", "x", "p", "t", "z", ""])
    func unrelatedKeysContinueToExistingHandlers(_ key: String) {
        var called = false
        #expect(!ThumbnailKeyboardRouting.handleBurstCommand(
            key, showsBurstGroups: true,
            perform: { _ in called = true; return .handled },
        ))
        #expect(!called)
    }
}
