import Foundation

nonisolated enum ObjectResponseIssue: Error, LocalizedError, Equatable, Sendable {
    case incompleteJSON
    case invalidJSON
    case invalidSchema(String)
    case invalidValue(String)
    case tooManyItems(String)
    case duplicateID(String)
    case unknownID(String)
    case missingID(String)

    var errorDescription: String? {
        switch self {
        case .incompleteJSON: "Qwen's JSON response was incomplete. Retry the assessment."
        case .invalidJSON: "Qwen did not return a complete JSON object. Retry the assessment."
        case let .invalidSchema(field): "Qwen returned a missing or mistyped \(field) field. Retry the assessment."
        case let .invalidValue(field): "Qwen returned an invalid \(field) value. Retry the assessment."
        case let .tooManyItems(field): "Qwen returned too many \(field). Retry the assessment."
        case let .duplicateID(id): "Qwen repeated object ID \(id). Retry the assessment."
        case let .unknownID(id): "Qwen used object ID \(id), which is absent from the board. Retry the assessment."
        case let .missingID(id): "Qwen omitted board object \(id). Retry the assessment."
        }
    }
}

nonisolated enum ObjectJSONEnvelope {
    static func data(in response: String) throws -> Data {
        let characters = Array(response)
        guard let start = characters.firstIndex(of: "{") else { throw ObjectResponseIssue.invalidJSON }
        var depth = 0
        var quoted = false
        var escaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let suffix = String(characters[(index + 1)...])
                    guard !suffix.contains("{") else { throw ObjectResponseIssue.invalidJSON }
                    return Data(String(characters[start...index]).utf8)
                }
            }
        }
        throw ObjectResponseIssue.incompleteJSON
    }

    static func decode<T: Decodable>(_ type: T.Type, from response: String) throws -> T {
        let data = try data(in: response)
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as DecodingError {
            switch error {
            case let .keyNotFound(key, context):
                throw ObjectResponseIssue.invalidSchema((context.codingPath + [key]).map(\.stringValue).joined(separator: "."))
            case let .typeMismatch(_, context), let .valueNotFound(_, context):
                throw ObjectResponseIssue.invalidSchema(context.codingPath.map(\.stringValue).joined(separator: "."))
            case let .dataCorrupted(context):
                if !context.codingPath.isEmpty {
                    throw ObjectResponseIssue.invalidValue(context.codingPath.map(\.stringValue).joined(separator: "."))
                }
                throw ObjectResponseIssue.invalidJSON
            @unknown default: throw ObjectResponseIssue.invalidJSON
            }
        } catch { throw ObjectResponseIssue.invalidJSON }
    }
}
