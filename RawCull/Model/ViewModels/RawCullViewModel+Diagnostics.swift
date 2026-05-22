import Foundation

extension RawCullViewModel {
    func presentRawDiagnostics(for file: FileItem) {
        rawDiagnosticsPresentation = RawDiagnosticsPresentation(log: RawFileDiagnostics.log(for: file))
    }
}
