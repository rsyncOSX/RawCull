import SwiftUI

struct SourceAndDestinationSection: View {
    let sourceCatalog: String
    @Binding var destinationCatalog: String

    var body: some View {
        Section("Source and Destination") {
            VStack(alignment: .trailing) {
                HStack {
                    Text(sourceCatalog)
                    Image(systemName: "arrowshape.right.fill")
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                )

                HStack {
                    if destinationCatalog.isEmpty {
                        HStack {
                            Text("Select destination")
                                .foregroundStyle(.red)
                            Image(systemName: "arrowshape.right.fill")
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                        )
                    } else {
                        HStack {
                            Text(destinationCatalog)
                            Image(systemName: "arrowshape.right.fill")
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                        )
                    }

                    OpencatalogView(
                        selectedItem: $destinationCatalog,
                        catalogs: true,
                        bookmarkKey: "destBookmark",
                    )
                }
            }
        }
    }
}
