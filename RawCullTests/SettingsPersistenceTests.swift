import Foundation
@testable import RawCull
import Testing

@MainActor
struct SettingsPersistenceTests {
    @Test
    func `save failure preserves edits and retry persists them`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocking file".utf8).write(to: root)
        let url = root.appendingPathComponent("settings.json")
        let settings = SettingsViewModel(settingsFileURL: url, loadOnInit: false)
        settings.thumbnailSizeGrid = 240
        #expect(await !settings.saveSettings())
        #expect(settings.persistenceFailure?.operation == .save)
        #expect(settings.thumbnailSizeGrid == 240)
        try FileManager.default.removeItem(at: root)
        let operation = settings.persistenceFailure?.operation
        settings.persistenceFailure = nil // Alert dismissal must not lose the retry operation.
        await settings.retryPersistence(operation)
        #expect(settings.persistenceFailure == nil)
        let saved = try JSONDecoder().decode(SavedSettings.self, from: Data(contentsOf: url))
        #expect(saved.thumbnailSizeGrid == 240)
    }

    @Test
    func `malformed load is observable and repaired settings can be retried`() async throws {
        let url = makeIsolatedSettingsURL()
        let root = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("malformed JSON".utf8).write(to: url)
        let settings = SettingsViewModel(settingsFileURL: url, loadOnInit: false)
        settings.thumbnailSizeGrid = 220
        await settings.loadSettings()
        #expect(settings.persistenceFailure?.operation == .load)
        #expect(settings.thumbnailSizeGrid == 220)
        let writer = SettingsViewModel(settingsFileURL: url, loadOnInit: false)
        writer.thumbnailSizeGrid = 280
        #expect(await writer.saveSettings())
        await settings.retryPersistence()
        #expect(settings.persistenceFailure == nil)
        #expect(settings.thumbnailSizeGrid == 280)
    }

    @Test
    func `absent settings use defaults without presenting an error`() async {
        let url = makeIsolatedSettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let settings = SettingsViewModel(settingsFileURL: url, loadOnInit: false)
        await settings.loadSettings()
        #expect(settings.persistenceFailure == nil)
    }
}
