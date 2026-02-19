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

    @State var showingAlert: Bool = false
    @State var progress: Double = 0
    @State var max: Double = 0
    @State var copyfilesinprogress: Bool = false

    @State private var executionManager: ExecuteCopyFiles?
    @State private var showprogressview = false

    @State var dryrun: Bool = true
    @State var copytaggedfiles: Bool = true
    @State var copyratedfiles: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            // Header with options
            CopyOptionsSection(
                copytaggedfiles: $copytaggedfiles,
                copyratedfiles: $copyratedfiles,
                dryrun: $dryrun
            )

            Divider()

            if copyfilesinprogress {
                ProgressCount(progress: $progress,
                              estimatedSeconds: $viewModel.estimatedSeconds,
                              max: max,
                              statusText: "Copy files in progress, please wait..")
            }

            // Source and destination catalogs
            sourceanddestination

            Spacer()

            // Action buttons
            CopyActionButtonsSection(
                dismiss: dismiss,
                onCopyTapped: {
                    guard sourcecatalog.isEmpty == false,
                          destinationcatalog.isEmpty == false else { return }
                    showingAlert = true
                }
            )
        }
        .padding()
        .frame(width: 650, height: 500, alignment: .init(horizontal: .center, vertical: .center))
        .task(id: selectedSource) {
            guard let selectedSource else { return }
            sourcecatalog = selectedSource.url.path
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Copy ARW files"),
                message: Text("Are you sure you want to copy all tagged ARW files?"),
                primaryButton: .destructive(Text("Copy")) {
                    copyfilesinprogress = true
                    executeCopyFiles()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func executeCopyFiles() {
        let configuration = SynchronizeConfiguration()

        executionManager = ExecuteCopyFiles(
            configuration: configuration,
            dryrun: dryrun,
            rating: copyratedfiles,
            copytaggedfiles: copytaggedfiles,
            sidebarRawCullViewModel: viewModel
        )

        executionManager?.onProgressUpdate = { newProgress in
            Task { @MainActor in
                progress = newProgress
            }
        }

        executionManager?.onCompletion = { result in
            Task { @MainActor in
                handleCompletion(result: result)
            }
        }

        executionManager?.startcopyfiles(
            fallbacksource: sourcecatalog,
            fallbackdest: destinationcatalog
        )
    }

    private func handleCompletion(result: CopyDataResult) {
        // This is for display and information only
        var configuration = SynchronizeConfiguration()
        configuration.localCatalog = sourcecatalog
        configuration.offsiteCatalog = destinationcatalog

        copyfilesinprogress = false

        remotedatanumbers = RemoteDataNumbers(
            stringoutputfromrsync: result.output,
            config: configuration
        )

        // Set the output for view if available
        if let viewOutput = result.viewOutput {
            remotedatanumbers?.outputfromrsync = viewOutput
        }

        // Clean up
        executionManager = nil

        sheetType = .detailsview
        showcopytask = true
    }
}
