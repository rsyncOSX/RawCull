import SwiftUI

enum SheetType {
    case copytasksview
    case detailsview
}

struct CopyARWFilesView: View {
    @Binding var sheetType: SheetType?
    @Binding var remoteDataNumbers: RemoteDataNumbers?
    @Binding var showcopytask: Bool

    var body: some View {
        switch sheetType {
        case .copytasksview:
            CopyFilesView(
                remoteDataNumbers: $remoteDataNumbers,
                sheetType: $sheetType,
                showcopytask: $showcopytask,
            )

        case .detailsview:
            if let remoteDataNumbers {
                DetailsView(remoteDataNumbers: remoteDataNumbers)
            }

        case nil:
            EmptyView()
        }
    }
}
