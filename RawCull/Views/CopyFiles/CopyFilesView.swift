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

    @State private var sourcecatalog: String = ""
    @State private var destinationcatalog: String = ""

    @State private var executionManager: ExecuteCopyFiles?
    @State private var dryrun: Bool = true
    @State private var copytaggedfiles: Bool = true
    @State private var copyratedfiles: Int = 1

    @State private var copyFilesinProgress: Bool = false
    @State private var showResult: Bool = false
    @State private var startupErrorMessage: String?

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
                Button("Close") {
                    closeExecutionManager()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Copy") {
                    guard !sourcecatalog.isEmpty,
                          !destinationcatalog.isEmpty else { return }
                    showResult = false
                    executeCopyFiles()
                }
                .disabled(copyFilesinProgress || sourcecatalog.isEmpty || destinationcatalog.isEmpty)
            }
        }
        .task(id: selectedSource) {
            guard let selectedSource else { return }
            sourcecatalog = selectedSource.url.path
        }
        .onDisappear {
            closeExecutionManager()
        }
        .alert("Copy Not Started", isPresented: startupErrorIsPresented) {
            Button("OK", role: .cancel) {
                startupErrorMessage = nil
            }
        } message: {
            Text(startupErrorMessage ?? "")
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
        startupErrorMessage = nil

        let configuration = SynchronizeConfiguration()

        executionManager = ExecuteCopyFiles(
            configuration: configuration,
            dryrun: dryrun,
            rating: copyratedfiles,
            copytaggedfiles: copytaggedfiles,
            sidebarRawCullViewModel: viewModel,
            displayedSourceURL: URL(fileURLWithPath: sourcecatalog),
        )

        executionManager?.onCompletion = { result in
            handleCompletion(result: result)
        }

        guard let executionManager else { return }

        switch executionManager.startcopyfiles() {
        case .success:
            copyFilesinProgress = true

        case let .failure(failure):
            copyFilesinProgress = false
            startupErrorMessage = failure.localizedDescription
            self.executionManager = nil
        }
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

    private func closeExecutionManager() {
        executionManager?.close()
        executionManager = nil
        copyFilesinProgress = false
    }

    private var startupErrorIsPresented: Binding<Bool> {
        Binding(
            get: { startupErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    startupErrorMessage = nil
                }
            },
        )
    }
}
