import Foundation

nonisolated struct RawParserDiagnostics<Value: Sendable>: Sendable {
    let value: Value?
    let trace: [String]
    let failure: String?

    var succeeded: Bool {
        value != nil && failure == nil
    }

    nonisolated init(value: Value?, trace: [String], failure: String?) {
        self.value = value
        self.trace = trace
        self.failure = failure
    }
}
