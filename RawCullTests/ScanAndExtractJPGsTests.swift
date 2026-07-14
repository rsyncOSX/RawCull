//
//  ScanAndExtractJPGsTests.swift
//  RawCullVerifyTests
//

import Foundation
@testable import RawCull
import Testing

@MainActor
private final class ScanAndExtractJPGsProgressRecorder {
    var progressUpdates: [Int] = []
    var maxFiles = 0
    var estimatedSeconds: [Int] = []
}

struct ScanAndExtractJPGsTests {
    @Test
    func `unsupported files are counted as processed`() async {
        let recorder = ScanAndExtractJPGsProgressRecorder()
        let urls = (0 ..< 3).map { index in
            URL(fileURLWithPath: "/tmp/rawcull-scan-extract-\(UUID().uuidString)-\(index).txt")
        }

        let actor = ScanAndExtractJPGs(urls: urls)
        let handlers = await CreateFileHandlers().createFileHandlers(
            fileHandler: { count in
                recorder.progressUpdates.append(count)
            },
            maxfilesHandler: { maxFiles in
                recorder.maxFiles = maxFiles
            },
            estimatedTimeHandler: { seconds in
                recorder.estimatedSeconds.append(seconds)
            },
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )

        await actor.setFileHandlers(handlers)
        let processed = await actor.extractCatalogJPGs()

        try? await Task.sleep(for: .milliseconds(50))
        let snapshot = await MainActor.run {
            (
                maxFiles: recorder.maxFiles,
                progressUpdates: recorder.progressUpdates,
            )
        }

        #expect(processed == urls.count)
        #expect(snapshot.maxFiles == urls.count)
        #expect(snapshot.progressUpdates.contains(urls.count))
    }
}
