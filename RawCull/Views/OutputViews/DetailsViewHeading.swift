//
//  DetailsViewHeading.swift
//  RsyncVerify
//
//  Created by Thomas Evensen on 20/11/2024.
//

import SwiftUI

struct DetailsViewHeading: View {
    let remoteDataNumbers: RemoteDataNumbers

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    LabeledContent("Synchronize ID: ") {
                        if remoteDataNumbers.backupID.isEmpty {
                            Text("Synchronize ID")
                                .foregroundColor(.blue)
                        } else {
                            Text(remoteDataNumbers.backupID)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(-3)

                    LabeledContent("Task: ") {
                        Text(remoteDataNumbers.task)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Source folder: ") {
                        Text(remoteDataNumbers.localCatalog)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Destination folder: ") {
                        Text(remoteDataNumbers.offsiteCatalog)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Server: ") {
                        if remoteDataNumbers.offsiteServer.isEmpty {
                            Text("localhost")
                                .foregroundColor(.blue)
                        } else {
                            Text(remoteDataNumbers.offsiteServer)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(-3)
                }
                .padding()

                VStack(alignment: .leading) {
                    LabeledContent("Total number of files: ") {
                        Text(remoteDataNumbers.numberoffiles)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Total number of catalogs: ") {
                        Text(remoteDataNumbers.totaldirectories)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Total numbers: ") {
                        Text(remoteDataNumbers.totalnumbers)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)

                    LabeledContent("Total bytes: ") {
                        Text(remoteDataNumbers.totalfilesize)
                            .foregroundColor(.blue)
                    }
                    .padding(-3)
                }
                .padding()
            }
        }
    }
}
