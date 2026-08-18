import SwiftUI

struct RAWCatalogSidebarView: View {
    @Binding var sources: [ARWSourceCatalog]
    @Binding var selectedSource: ARWSourceCatalog?

    let cullingModel: CullingModel

    var body: some View {
        List(sources, selection: $selectedSource) { source in
            NavigationLink(value: source) {
                Label(source.name, systemImage: "folder.badge.plus")
                    .badge("(" + String(cullingModel.countSelectedFiles(in: source.url)) + ")")
            }
        }
        .navigationTitle("Catalogs")
    }
}
