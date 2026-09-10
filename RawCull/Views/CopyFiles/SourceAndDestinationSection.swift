import SwiftUI

struct SourceAndDestinationSection: View {
    let sourcecatalog: String
    @Binding var destinationcatalog: String

    var body: some View {
        Section("Source and Destination") {
            VStack(alignment: .trailing) {
                HStack {
                    Text(sourcecatalog)
                    Image(systemName: "arrowshape.right.fill")
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                )

                HStack {
                    if destinationcatalog.isEmpty {
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
                            Text(destinationcatalog)
                            Image(systemName: "arrowshape.right.fill")
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                        )
                    }

                    OpencatalogView(
                        selecteditem: $destinationcatalog,
                        catalogs: true,
                        bookmarkKey: "destBookmark",
                    )
                }
            }
        }
    }
}
