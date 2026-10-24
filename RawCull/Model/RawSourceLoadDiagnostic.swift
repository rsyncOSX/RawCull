import Foundation

/// Opt-in adapter timing. The parser span includes its private actor/limiter
/// waits, I/O and decode; it must not be reported as pure decode CPU time.
nonisolated struct RawSourceLoadDiagnostic: Codable, Sendable {
    let id: UUID
    let operation: String
    let source: URL
    let requestedPixelSize: Int?
    let submitted: Double
    let accessReady: Double
    let taskStarted: Double
    let parserReturned: Double
    let delivered: Double
    let succeeded: Bool
    let cancelled: Bool
}
