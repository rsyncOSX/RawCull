import Foundation

nonisolated struct RawParserDiagnostics<Value: Sendable> {
    let value: Value?
    let trace: [String]
    let failure: String?

    var succeeded: Bool {
        value != nil && failure == nil
    }
}
