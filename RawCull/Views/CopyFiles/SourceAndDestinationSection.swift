import OSLog
import SwiftUI

struct SourceAndDestinationSection: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var sourcecatalog: String
    @Binding var destinationcatalog: String
    @Binding var copytaggedfiles: Bool
    @Binding var copyratedfiles: Int

    var body: some View {
        Section("Source and Destination") {
            VStack(alignment: .trailing) {
                HStack {
                    HStack {
                        Text(sourcecatalog)
                        Image(systemName: "arrowshape.right.fill")
                    }
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                    )

                    OpencatalogView(
                        selecteditem: $sourcecatalog,
                        catalogs: true,
                        bookmarkKey: "sourceBookmark",
                    )
                }

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
