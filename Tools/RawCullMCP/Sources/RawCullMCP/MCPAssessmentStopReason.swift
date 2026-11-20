import Foundation

/// Why a photo-assessment follow-up stopped or was refused. The raw values
/// are the `errorCode` strings sent across the app/helper boundary, so they
/// must not change.
nonisolated enum MCPAssessmentStopReason: String, Codable, Sendable, CaseIterable {
    case busy
    case executionTimeout
    case modelChanged
    case modelUnavailable
    case reauthorizationRequired
    case assessmentFailed
    case allPhotosFailed
}
