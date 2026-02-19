//
//  Params.swift
//  RsyncUI
//
//  Created by Thomas Evensen on 20/11/2025.
//

import Foundation
import RsyncArguments

@MainActor
struct Params {
    func params(
        config: SynchronizeConfiguration
    ) -> Parameters {
        Parameters(
            task: config.task,
            basicParameters: BasicRsyncParameters(
                archiveMode: DefaultRsyncParameters.archiveMode.rawValue,
                verboseOutput: DefaultRsyncParameters.verboseOutput.rawValue,
                compressionEnabled: DefaultRsyncParameters.compressionEnabled.rawValue,
                deleteExtraneous: ""
            ),
            optionalParameters: OptionalRsyncParameters(parameter8: config.parameter8,
                                                        parameter9: config.parameter9,
                                                        parameter10: config.parameter10,
                                                        parameter11: config.parameter11,
                                                        parameter12: config.parameter12,
                                                        parameter13: config.parameter13,
                                                        parameter14: config.parameter14),

            sshParameters: SSHParameters(
                offsiteServer: "",
                offsiteUsername: "",
                sshport: "",
                sshkeypathandidentityfile: "",
                sharedsshport: "",
                sharedsshkeypathandidentityfile: "",
                rsyncversion3: false
            ),
            paths: PathConfiguration(
                localCatalog: config.localCatalog,
                offsiteCatalog: config.offsiteCatalog,
                sharedPathForRestore: ""
            ),
            snapshotNumber: 0,
            isRsyncDaemon: false,
            rsyncVersion3: false
        )
    }
}
