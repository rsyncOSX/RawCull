import SwiftUI

extension RawCullAIModelDownloadState {
    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking"
        case .unavailable: "Distribution blocked"
        case .licenceRequired: "Licence required"
        case .notConfigured: "Server pending"
        case .ready: "Ready"
        case .downloading: "Downloading"
        case .validating: "Validating"
        case .installed: "Installed"
        case .removing: "Removing"
        case .failed: "Failed"
        }
    }

    var activityTitle: LocalizedStringResource {
        switch self {
        case .checking: "Checking model service…"
        case .validating: "Validating model…"
        case .removing: "Removing model…"

        case .unavailable, .licenceRequired, .notConfigured, .ready,
             .downloading, .installed, .failed:
            ""
        }
    }

    var iconName: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .unavailable: "exclamationmark.shield"
        case .licenceRequired: "doc.badge.ellipsis"
        case .notConfigured: "network.slash"
        case .ready: "arrow.down.circle"
        case .downloading: "arrow.down.circle.fill"
        case .validating: "checkmark.shield"
        case .installed: "checkmark.circle.fill"
        case .removing: "trash.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .installed: .green
        case .ready, .downloading, .validating: .blue
        case .checking, .removing: .secondary
        case .unavailable, .licenceRequired, .notConfigured: .orange
        case .failed: .red
        }
    }
}
