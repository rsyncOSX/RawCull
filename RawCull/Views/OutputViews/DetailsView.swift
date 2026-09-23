//
//  DetailsView.swift
//  RsyncVerify
//
//  Created by Thomas Evensen on 07/06/2024.
//

import SwiftUI

struct DetailsView: View {
    @Environment(\.dismiss) var dismiss

    let remoteDataNumbers: RemoteDataNumbers

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                leftPanelContent
                    .frame(width: 350)

                Button("Close", role: .close) {
                    dismiss()
                }
                .buttonStyle(RefinedGlassButtonStyle())
            }

            Divider()

            RsyncOutputRowView(remoteDataNumbers: remoteDataNumbers)
        }
        .padding()
        .frame(width: 1000, height: 520)
    }

    // MARK: - Subviews

    private var leftPanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailsViewHeading(remoteDataNumbers: remoteDataNumbers)

            Spacer()

            syncStatusBox
        }
    }

    private var syncStatusBox: some View {
        Group {
            if remoteDataNumbers.datatosynchronize {
                syncDataContent
            } else {
                noSyncDataContent
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.gradient)
        }
        .padding()
    }

    private var syncDataContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let filesChangedText = remoteDataNumbers.filestransferredInt == 1
                ? "1 file changed"
                : "\(remoteDataNumbers.filestransferredInt) files changed"
            Text(filesChangedText)

            let transferSizeText = remoteDataNumbers.totaltransferredfilessizeInt == 1
                ? "byte for transfer"
                : "\(remoteDataNumbers.totaltransferredfilessize) bytes for transfer"
            Text(transferSizeText)
        }
    }

    private var noSyncDataContent: some View {
        Text("No data to synchronize")
            .font(.title2)
    }
}

// MARK: - RsyncOutputRowView

struct RsyncOutputRowView: View {
    let remoteDataNumbers: RemoteDataNumbers

    var body: some View {
        if let originalRecords = remoteDataNumbers.outputfromrsync {
            // Safely drop the last 11 elements if available
            let countToDrop = min(11, originalRecords.count)
            let records = Array(originalRecords.dropLast(countToDrop))

            return AnyView(
                Table(records) {
                    TableColumn("Output from rsync (\(records.count) rows)") { data in
                        ItemizedOutputRow(record: data.record)
                    }
                },
            )
        } else {
            return AnyView(EmptyView())
        }
    }
}
