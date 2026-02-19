//
//  SynchronizeConfiguration.swift
//  RsyncUI
//

import Foundation

struct SynchronizeConfiguration {
    var id = UUID()
    var hiddenID: Int
    var task: String
    var localCatalog: String
    var offsiteCatalog: String
    var offsiteUsername: String
    var parameter4: String?
    var offsiteServer: String
    var backupID: String
    var dateRun: String?
    var snapshotnum: Int?
    var parameter8: String?
    var parameter9: String?
    var parameter10: String?
    var parameter11: String?
    var parameter12: String?
    var parameter13: String?
    var parameter14: String?
    var rsyncdaemon: Int?
    // SSH parameters
    var sshport: Int?
    var sshkeypathandidentityfile: String?
    // Snapshots, day to save and last = 1 or every last=0
    var snapdayoffweek: String?
    var snaplast: Int?
    /// task is halted
    var halted: Int

    /// Create an empty record with no values
    init() {
        task = "synchronize"
        hiddenID = 0
        localCatalog = ""
        offsiteCatalog = ""
        offsiteUsername = ""
        parameter4 = ""
        offsiteServer = ""
        backupID = ""
        halted = 0
    }
}
