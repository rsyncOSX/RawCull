//
//  CopyFilesView.swift
//  RsyncUI
//
//  Created by Thomas Evensen on 11/12/2023.
//

import OSLog
import SwiftUI

struct CopyFilesView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var viewModel: RawCullViewModel

    @Binding var selectedSource: ARWSourceCatalog?
    @Binding var remotedatanumbers: RemoteDataNumbers?
    @Binding var sheetType: SheetType?
    @Binding var showcopytask: Bool

    @State var sourcecatalog: String = ""
    @State var destinationcatalog: String = ""

    @State private var executionManager: ExecuteCopyFiles?
    @State var dryrun: Bool = true
    @State var copytaggedfiles: Bool = true
    @State var copyratedfiles: Int = 1

    @State private var copyFilesinProgress: Bool = false
    @State private var showResult: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CopyOptionsSection(
                copytaggedfiles: $copytaggedfiles,
                copyratedfiles: $copyratedfiles,
                dryrun: $dryrun,
            )

            Divider()

            SourceAndDestinationSection(
                viewModel: viewModel,
                sourcecatalog: $sourcecatalog,
                destinationcatalog: $destinationcatalog,
                copytaggedfiles: $copytaggedfiles,
                copyratedfiles: $copyratedfiles,
            )

            if copyFilesinProgress {
                ProgressView("Copying files…")
                    .padding(.vertical, 4)
            }

            if showResult, let numbers = remotedatanumbers {
                copyResultView(numbers)
            }

            Spacer()
        }
        .padding()
        .frame(width: 560, height: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Copy") {
                    guard !sourcecatalog.isEmpty,
                          !destinationcatalog.isEmpty else { return }
                    showResult = false
                    copyFilesinProgress = true
                    executeCopyFiles()
                }
                .disabled(copyFilesinProgress || sourcecatalog.isEmpty || destinationcatalog.isEmpty)
            }
        }
        .task(id: selectedSource) {
            guard let selectedSource else { return }
            sourcecatalog = selectedSource.url.path
        }
    }

    private func copyResultView(_ numbers: RemoteDataNumbers) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(dryrun ? "Dry run complete" : "Copy complete")
                    .fontWeight(.medium)
                if numbers.datatosynchronize {
                    Text("\(numbers.filestransferredInt) files · \(numbers.totaltransferredfilessize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing to copy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("View rsync output") {
                sheetType = .detailsview
                showcopytask = true
            }
            .font(.caption)
        }
        .padding()
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func executeCopyFiles() {
        let configuration = SynchronizeConfiguration()

        executionManager = ExecuteCopyFiles(
            configuration: configuration,
            dryrun: dryrun,
            rating: copyratedfiles,
            copytaggedfiles: copytaggedfiles,
            sidebarRawCullViewModel: viewModel,
        )

        executionManager?.onCompletion = { result in
            handleCompletion(result: result)
        }

        executionManager?.startcopyfiles(
            fallbacksource: sourcecatalog,
            fallbackdest: destinationcatalog,
        )
    }

    private func handleCompletion(result: CopyDataResult) {
        var configuration = SynchronizeConfiguration()
        configuration.localCatalog = sourcecatalog
        configuration.offsiteCatalog = destinationcatalog

        copyFilesinProgress = false

        remotedatanumbers = RemoteDataNumbers(
            stringoutputfromrsync: result.output,
            config: configuration,
        )

        if let viewOutput = result.viewOutput {
            remotedatanumbers?.outputfromrsync = viewOutput
        }

        executionManager = nil
        showResult = true
    }
}
