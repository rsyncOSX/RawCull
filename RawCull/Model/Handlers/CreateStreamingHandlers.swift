//
//  CreateStreamingHandlers.swift
//  RawCull
//
//  Created by Thomas Evensen on 17/12/2025.
//

import Foundation
import RsyncProcessStreaming

@MainActor
struct CreateStreamingHandlers {
    // Create handlers with streaming output support.
    // - Parameters:
    //   - fileHandler: Progress callback (file count)
    //   - processTermination: Called when process completes (receives final output).
    //     The caller is responsible for any cleanup after the termination handler returns.
    // - Returns: ProcessHandlers configured for streaming

    func createHandlers(
        fileHandler: @escaping (Int) -> Void,
        processTermination: @escaping ([String]?, Int?, CopyOutcome) -> Void,
    ) -> ProcessHandlers {
        // The pinned RsyncProcess invokes these callbacks synchronously on
        // MainActor, with propagateError before processTermination.
        var outcome = CopyOutcome.success
        return ProcessHandlers(
            processTermination: { output, hiddenID in
                processTermination(output, hiddenID, outcome)
            },
            fileHandler: fileHandler,
            rsyncPath: "/usr/bin/rsync",
            checkLineForError: { _ in },
            updateProcess: { _ in },
            propagateError: { error in
                if case RsyncProcessError.processCancelled = error {
                    outcome = .cancelled
                } else if outcome != .cancelled {
                    outcome = .failed(message: error.localizedDescription)
                }
            },
            checkForErrorInRsyncOutput: true,
            environment: nil,
        )
    }
}
