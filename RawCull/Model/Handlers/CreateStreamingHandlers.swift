//
//  CreateStreamingHandlers.swift
//  RsyncUI
//
//  Created by GitHub Copilot on 17/12/2025.
//

import Foundation
import RsyncProcessStreaming

@MainActor
struct CreateStreamingHandlers {
    // Create handlers with streaming output support
    // - Parameters:
    //   - fileHandler: Progress callback (file count)
    //   - processTermination: Called when process completes (receives final output)
    //   - streamingHandler: Optional handler for line-by-line processing
    // - Returns: ProcessHandlers configured for streaming

    func createHandlersWithCleanup(
        fileHandler: @escaping (Int) -> Void,
        processTermination: @escaping ([String]?, Int?) -> Void,
        cleanup: @escaping () -> Void
    ) -> ProcessHandlers {
        ProcessHandlers(
            processTermination: { output, hiddenID in
                processTermination(output, hiddenID)
                cleanup()
            },
            fileHandler: fileHandler,
            rsyncPath: "/usr/bin/rsync",
            checkLineForError: { _ in },
            updateProcess: { _ in },
            propagateError: { _ in },
            checkForErrorInRsyncOutput: false,
            environment: ["": ""]
        )
    }
}
