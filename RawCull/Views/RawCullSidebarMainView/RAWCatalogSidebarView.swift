import SwiftUI

struct RAWCatalogSidebarView: View {
    @Binding var sources: [ARWSourceCatalog]
    @Binding var selectedSource: ARWSourceCatalog?
    @Binding var isShowingPicker: Bool

    let cullingModel: CullingModel

    var body: some View {
        List(sources, selection: $selectedSource) { source in
            NavigationLink(value: source) {
                Label(source.name, systemImage: "folder.badge.plus")
                    .badge("(" + String(cullingModel.countSelectedFiles(in: source.url)) + ")")
            }
        }
        .navigationTitle("Catalogs")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: { isShowingPicker = true }, label: {
                    Label("Add Catalog", systemImage: "plus")
                })
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}
