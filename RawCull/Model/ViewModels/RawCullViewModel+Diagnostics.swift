import Foundation

extension RawCullViewModel {
    func presentRawDiagnostics(for file: FileItem) {
        Task { @concurrent [file] in
            let log = RawFileDiagnostics.log(for: file)
            await MainActor.run {
                self.rawDiagnosticsPresentation = RawDiagnosticsPresentation(log: log)
            }
        }
    }
}
