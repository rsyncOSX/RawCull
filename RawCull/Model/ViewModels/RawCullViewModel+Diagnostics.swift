import Foundation

extension RawCullViewModel {
    func presentRawDiagnostics(for file: FileItem) {
        rawDiagnosticsTask?.cancel()
        let generation = UUID()
        rawDiagnosticsGeneration = generation
        rawDiagnosticsTask = Task { @concurrent [file] in
            let log = RawFileDiagnostics.log(for: file)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.rawDiagnosticsGeneration == generation else { return }
                self.rawDiagnosticsPresentation = RawDiagnosticsPresentation(log: log)
                self.rawDiagnosticsTask = nil
                self.rawDiagnosticsGeneration = nil
            }
        }
    }
}
