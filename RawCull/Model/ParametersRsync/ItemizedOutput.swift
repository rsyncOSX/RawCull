//
//  ItemizedOutput.swift
//  RawCullSAM3
//

import Foundation

enum ItemizedChangeKind: String {
    case added = "Added"
    case updated = "Updated"
    case deleted = "Deleted"
    case metadata = "Metadata"
    case other = "Other"
}

struct ItemizedOutputRecord {
    let kind: ItemizedChangeKind
    let path: String
    let code: String

    init?(_ record: String) {
        let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.hasPrefix("*deleting") {
            kind = .deleted
            path = trimmed.replacingOccurrences(of: "*deleting", with: "")
                .trimmingCharacters(in: .whitespaces)
            code = "*deleting"
            return
        }

        guard let prefixLength = Self.prefixLength(in: trimmed) else { return nil }

        code = String(trimmed.prefix(prefixLength))
        guard Self.isValidItemizedCode(code) else { return nil }

        path = String(trimmed.dropFirst(prefixLength))
            .trimmingCharacters(in: .whitespaces)
        guard path.isEmpty == false else { return nil }

        let attributes = code.dropFirst(2)
        kind = if attributes.isEmpty == false, attributes.allSatisfy({ $0 == "+" }) {
            .added
        } else if code.first == "." {
            .metadata
        } else if code.first == ">" || code.first == "<" || code.first == "c" {
            .updated
        } else {
            .other
        }
    }

    private static func prefixLength(in record: String) -> Int? {
        let characters = Array(record)
        if characters.count >= 13, characters[12] == " " {
            return 12
        }
        if characters.count >= 12, characters[11] == " " {
            return 11
        }
        if characters.count >= 10, characters[9] == " " {
            return 9
        }
        return nil
    }

    private static func isValidItemizedCode(_ code: String) -> Bool {
        guard let first = code.first else { return false }
        return first == ">" || first == "<" || first == "c" || first == "h" || first == "."
    }
}
