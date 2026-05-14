//
//  CancellableImageIOWorkTests.swift
//  RawCullTests
//
//  Created by Codex on 14/05/2026.
//

import CoreGraphics
import Foundation
import os
@testable import RawCull
import Testing

private final class DecodeProbe: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    nonisolated func markDecoded() {
        lock.withLock { $0 = true }
    }

    nonisolated var didDecode: Bool {
        lock.withLock { $0 }
    }
}

struct CancellableImageIOWorkTests {
    @Test(.tags(.critical))
    func `cancelled ImageIO work resumes without running decode phase`() async throws {
        let probe = DecodeProbe()

        await withTaskGroup(of: Void.self) { group in
            group.cancelAll()
            group.addTask {
                await #expect(throws: CancellationError.self) {
                    try await CancellableImageIOWork.run(qos: .utility) { token in
                        try token.checkCancellation()
                        probe.markDecoded()
                        return 1
                    }
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(!probe.didDecode)
    }

    @Test(.tags(.critical))
    func `cancelled Sony thumbnail extraction throws cancellation`() async {
        await expectCancelledThumbnail {
            try await SonyThumbnailExtractor.extractSonyThumbnail(
                from: missingRawURL(extension: "arw"),
                maxDimension: 512,
            )
        }
    }

    @Test(.tags(.critical))
    func `cancelled Nikon thumbnail extraction throws cancellation`() async {
        await expectCancelledThumbnail {
            try await NikonThumbnailExtractor.extractNikonThumbnail(
                from: missingRawURL(extension: "nef"),
                maxDimension: 512,
            )
        }
    }

    @Test(.tags(.critical))
    func `cancelled Sony JPEG extraction returns nil`() async {
        let image = await runCancelledJPEGExtraction {
            await JPGSonyARWExtractor.jpgSonyARWExtractor(
                from: missingRawURL(extension: "arw"),
                fullSize: false,
            )
        }

        #expect(image == nil)
    }

    @Test(.tags(.critical))
    func `cancelled Nikon JPEG extraction returns nil`() async {
        let image = await runCancelledJPEGExtraction {
            await JPGNikonNEFExtractor.jpgNikonNEFExtractor(
                from: missingRawURL(extension: "nef"),
                fullSize: false,
            )
        }

        #expect(image == nil)
    }

    private func expectCancelledThumbnail(
        _ extraction: @escaping @Sendable () async throws -> CGImage,
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.cancelAll()
            group.addTask {
                await #expect(throws: CancellationError.self) {
                    _ = try await extraction()
                }
            }
        }
    }

    private func runCancelledJPEGExtraction(
        _ extraction: @escaping @Sendable () async -> CGImage?,
    ) async -> CGImage? {
        await withTaskGroup(of: CGImage?.self) { group in
            group.cancelAll()
            group.addTask {
                await extraction()
            }
            return await group.next()
        }
    }

    private func missingRawURL(extension pathExtension: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawcull-cancel-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}
