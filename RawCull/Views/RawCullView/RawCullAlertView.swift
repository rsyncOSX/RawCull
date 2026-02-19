import SwiftUI

enum RawCullAlertView {
    enum AlertType {
        case extractJPGs
        case clearToggledFiles
        case resetSavedFiles
    }

    typealias AlertActions = (
        extractJPGS: () -> Void,
        clearCaches: () -> Void
    )

    static func alert(
        type: AlertType?,
        selectedSource: ARWSourceCatalog?,
        cullingModel: CullingModel,
        actions: AlertActions
    ) -> Alert {
        switch type {
        case .extractJPGs:
            return Alert(
                title: Text("Extract JPGs"),
                message: Text("Are you sure you want to extract JPG images from ARW files?"),
                primaryButton: .destructive(Text("Extract")) {
                    actions.extractJPGS()
                },
                secondaryButton: .cancel()
            )

        case .clearToggledFiles:
            return Alert(
                title: Text("Clear Tagged Files"),
                message: Text("Are you sure you want to clear all tagged files?"),
                primaryButton: .destructive(Text("Clear")) {
                    if let url = selectedSource?.url {
                        cullingModel.resetSavedFiles(in: url)
                    }
                },
                secondaryButton: .cancel()
            )

        case .resetSavedFiles:
            return Alert(
                title: Text("Reset Saved Files"),
                message: Text("Are you sure you want to reset all saved files?"),
                primaryButton: .destructive(Text("Reset")) {
                    cullingModel.savedFiles.removeAll()
                    WriteSavedFilesJSON(cullingModel.savedFiles)
                },
                secondaryButton: .cancel()
            )

        case .none:
            return Alert(title: Text("Unknown Action"))
        }
    }
}
