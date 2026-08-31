#!/usr/bin/env swift

import Foundation

struct TestEnumeration: Decodable {
    struct Value: Decodable {
        struct Test: Decodable {
            let identifier: String
        }

        let enabledTests: [Test]
    }

    let values: [Value]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Test enumeration error: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: VerifyTestEnumeration.swift <enumeration.json> <expected-count>")
}

let enumerationURL = URL(fileURLWithPath: CommandLine.arguments[1])
defer { try? FileManager.default.removeItem(at: enumerationURL) }
guard let expectedCount = Int(CommandLine.arguments[2]), expectedCount >= 0 else {
    fail("expected count must be a non-negative integer")
}

let enumeration: TestEnumeration
do {
    let data = try Data(contentsOf: enumerationURL)
    enumeration = try JSONDecoder().decode(TestEnumeration.self, from: data)
} catch {
    fail("could not read \(enumerationURL.path): \(error)")
}

let identifiers = enumeration.values.flatMap(\.enabledTests).map(\.identifier)
let duplicates = Dictionary(grouping: identifiers, by: { $0 })
    .filter { $0.value.count > 1 }
    .keys
    .sorted()

guard duplicates.isEmpty else {
    fail("duplicate identifiers: \(duplicates.joined(separator: ", "))")
}

guard identifiers.count == expectedCount else {
    fail("expected \(expectedCount) unique tests, enumerated \(identifiers.count)")
}

print("Verified \(identifiers.count) unique test identifiers in \(enumerationURL.lastPathComponent)")
