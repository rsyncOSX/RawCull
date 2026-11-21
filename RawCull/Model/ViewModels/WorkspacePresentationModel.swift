import Foundation
import Observation

/// Window chrome of the main workspace: sheets, alerts, the catalog picker,
/// the loupe metadata panel, the memory-pressure banner and the menu-command
/// focus flags.
@Observable @MainActor
final class WorkspacePresentationModel {
    var alertType: AlertType?
    var showingAlert = false
    /// Sheet currently presented from the main window toolbar
    /// (Scoring Parameters / Scan Statistics). Nil when no sheet is shown.
    var activeSheet: ActiveSheet?
    var sheetType: SheetType? = .copytasksview
    var showCopyARWFilesView = false
    var isShowingPicker = false
    var operationFailurePresentation: OperationFailurePresentation?
    var showsLoupeMetadataPanel = true
    var memoryPressureWarning = false

    // Menu-command flags published through focused scene values.
    var focusAbortTask = false
    var focusExtractJPGs = false
    var focusCopyTaggedFiles = false

    var alertTitle: String {
        switch alertType {
        case .createJPGDiskCache: "Create JPG Disk Cache"
        case .clearRatedFiles: "Clear Rated Images"
        case .none: ""
        }
    }

    /// The JPG-cache alert names the catalog size, so the caller passes it in.
    func alertMessage(catalogFileCount: Int) -> String {
        switch alertType {
        case .createJPGDiskCache:
            "RawCull will create missing extracted JPG preview cache images for \(catalogFileCount) RAW files in this catalog. Existing cached images will be skipped."

        case .clearRatedFiles: "Are you sure you want to clear all rated images?"

        case .none: ""
        }
    }
}
