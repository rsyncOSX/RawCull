import Foundation

/// Markdown escaping shared by the release reports.
nonisolated enum ReleaseAnalysisReport {
    static func text(_ value: String) -> String {
        var value = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        for character in ["\\", "`", "*", "_", "[", "]", "<", ">", "#", "|"] {
            value = value.replacingOccurrences(of: character, with: "\\" + character)
        }
        return value
    }
}
