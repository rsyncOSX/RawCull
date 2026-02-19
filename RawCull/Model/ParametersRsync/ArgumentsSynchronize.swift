//
//  ArgumentsSynchronize.swift
//  RsyncUI
//

import Foundation
import RsyncArguments

@MainActor
final class ArgumentsSynchronize {
    var config: SynchronizeConfiguration?

    func argumentsSynchronize(dryRun: Bool) -> [String]? {
        if let config {
            let params = Params().params(config: config)
            let rsyncparameterssynchronize = RsyncParametersSynchronize(parameters: params)

            do {
                try rsyncparameterssynchronize.argumentsForSynchronize(forDisplay: false,
                                                                       verify: false,
                                                                       dryrun: dryRun)
                var arguments = rsyncparameterssynchronize.computedArguments
                // This is a hack, need to remow the two last empty arguments
                // because we need to add sequrity scoped source and destination later
                let count = arguments.count
                guard count > 2 else { return nil }
                if arguments[count - 1].isEmpty, arguments[count - 2].isEmpty {
                    arguments.removeLast(2)
                }
                return arguments
            } catch {
                return nil
            }
        }
        return nil
    }

    init(config: SynchronizeConfiguration?) {
        self.config = config
    }
}
