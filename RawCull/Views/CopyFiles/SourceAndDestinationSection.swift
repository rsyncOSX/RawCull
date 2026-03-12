import OSLog
import SwiftUI

struct SourceAndDestinationSection: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var sourcecatalog: String
    @Binding var destinationcatalog: String
    @Binding var copytaggedfiles: Bool
    @Binding var copyratedfiles: Int
    @Binding var max: Double

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
                    .onChange(of: destinationcatalog) { _, _ in
                        updateMax(resetRatingWhenNotTagged: true)
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                    .onChange(of: copytaggedfiles) { _, _ in
                        updateMax(resetRatingWhenNotTagged: true)
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                    .onChange(of: copyratedfiles) { _, _ in
                        max = Double(viewModel.extractRatedfilenames(copyratedfiles).count)
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                }
            }
        }
    }

    private func updateMax(resetRatingWhenNotTagged: Bool) {
        if copytaggedfiles {
            max = Double(viewModel.extractTaggedfilenames().count)
        } else {
            if resetRatingWhenNotTagged {
                copyratedfiles = 3 // default
            }
            max = Double(viewModel.extractRatedfilenames(copyratedfiles).count)
        }
    }
}
