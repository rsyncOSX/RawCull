import SwiftUI

enum SheetType {
    case copytasksview
    case detailsview
}

struct CopyARWFilesView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var sheetType: SheetType?
    @Binding var remotedatanumbers: RemoteDataNumbers?
    @Binding var showcopytask: Bool

    var body: some View {
        switch sheetType {
        case .copytasksview:
            CopyFilesView(
                viewModel: viewModel,
                remotedatanumbers: $remotedatanumbers,
                sheetType: $sheetType,
                showcopytask: $showcopytask,
            )

        case .detailsview:
            if let remotedatanumbers {
                DetailsView(remotedatanumbers: remotedatanumbers)
            }

        case nil:
            EmptyView()
        }
    }
}
