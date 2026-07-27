import Foundation
import PhotoAIContracts

public struct SegmentationBuildSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let cached: Int
    public let generated: Int
    public let failed: Int

    public init(total: Int, cached: Int, generated: Int, failed: Int) {
        self.total = total
        self.cached = cached
        self.generated = generated
        self.failed = failed
    }
}

public struct SegmentationBuildEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started, progress, completed, failed
    }

    public let kind: Kind
    public let completed: Int
    public let total: Int
    public let cached: Int
    public let generated: Int
    public let failed: Int
    public let currentSourceName: String?
    public let message: String?

    public static func started(total: Int) -> SegmentationBuildEvent {
        SegmentationBuildEvent(
            kind: .started,
            completed: 0,
            total: total,
            cached: 0,
            generated: 0,
            failed: 0,
            currentSourceName: nil,
            message: nil
        )
    }

    public static func progress(
        _ progress: SubjectMaskPrefetchProgress,
        currentSourceName: String?
    ) -> SegmentationBuildEvent {
        SegmentationBuildEvent(
            kind: .progress,
            completed: progress.completed,
            total: progress.total,
            cached: progress.cached,
            generated: progress.generated,
            failed: progress.failed,
            currentSourceName: currentSourceName,
            message: nil
        )
    }

    public static func completed(_ summary: SegmentationBuildSummary) -> SegmentationBuildEvent {
        SegmentationBuildEvent(
            kind: .completed,
            completed: summary.total,
            total: summary.total,
            cached: summary.cached,
            generated: summary.generated,
            failed: summary.failed,
            currentSourceName: nil,
            message: nil
        )
    }

    public static func failed(_ message: String) -> SegmentationBuildEvent {
        SegmentationBuildEvent(
            kind: .failed,
            completed: 0,
            total: 0,
            cached: 0,
            generated: 0,
            failed: 0,
            currentSourceName: nil,
            message: message
        )
    }
}

/// Stable transport wrapper for helper processes or other JSON-lines clients.
/// Host-only request fields (bookmarks, process IDs, app paths) wrap this value
/// outside PhotoAIKit.
public struct SegmentationBuildTransportEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let event: SegmentationBuildEvent

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        event: SegmentationBuildEvent
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
    }
}

public enum SegmentationBuildTransportCodec {
    public static func encodeLine(_ event: SegmentationBuildEvent) throws -> Data {
        var data = try JSONEncoder().encode(SegmentationBuildTransportEnvelope(
            event: event
        ))
        data.append(0x0A)
        return data
    }

    public static func decodeLine(_ data: Data) throws -> SegmentationBuildEvent {
        let trimmed = Data(data.prefix { $0 != 0x0A && $0 != 0x0D })
        let envelope = try JSONDecoder().decode(
            SegmentationBuildTransportEnvelope.self,
            from: trimmed
        )
        guard envelope.schemaVersion == SegmentationBuildTransportEnvelope.currentSchemaVersion else {
            throw SegmentationBuildTransportError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }
        return envelope.event
    }
}

public enum SegmentationBuildTransportError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

public struct SegmentationBatchPipeline: Sendable {
    public let service: SegmentationService
    public let prompt: SubjectSegmentationPrompt
    public let decoder: any ImageDecoding

    public init(
        service: SegmentationService,
        prompt: SubjectSegmentationPrompt = .subject,
        decoder: any ImageDecoding
    ) {
        self.service = service
        self.prompt = prompt
        self.decoder = decoder
    }

    public func generate(
        sources: [AIImageSource],
        events: (@Sendable (SegmentationBuildEvent) async -> Void)? = nil
    ) async throws -> SegmentationBuildSummary {
        await events?(.started(total: sources.count))
        let partition = try await service.partitionByValidCache(sources: sources, prompt: prompt)
        let initialCached = partition.cached.count
        guard !partition.missing.isEmpty else {
            let summary = SegmentationBuildSummary(
                total: sources.count,
                cached: initialCached,
                generated: 0,
                failed: 0
            )
            await events?(.completed(summary))
            return summary
        }

        let names = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.displayName) })
        let recorder = ProgressRecorder(value: SubjectMaskPrefetchProgress(
            completed: initialCached,
            total: sources.count,
            cached: initialCached,
            generated: 0,
            failed: 0,
            currentSourceID: partition.missing.first?.id
        ))
        try await service.prefetch(
            sources: partition.missing,
            prompt: prompt,
            decoder: decoder
        ) { update in
            let translated = SubjectMaskPrefetchProgress(
                completed: initialCached + update.completed,
                total: sources.count,
                cached: initialCached + update.cached,
                generated: update.generated,
                failed: update.failed,
                currentSourceID: update.currentSourceID
            )
            await recorder.record(translated)
            await events?(.progress(
                translated,
                currentSourceName: translated.currentSourceID.flatMap { names[$0] }
            ))
        }
        let latest = await recorder.latest()
        let summary = SegmentationBuildSummary(
            total: latest.total,
            cached: latest.cached,
            generated: latest.generated,
            failed: latest.failed
        )
        await events?(.completed(summary))
        return summary
    }
}

private actor ProgressRecorder {
    private var value: SubjectMaskPrefetchProgress

    init(value: SubjectMaskPrefetchProgress) { self.value = value }
    func record(_ value: SubjectMaskPrefetchProgress) { self.value = value }
    func latest() -> SubjectMaskPrefetchProgress { value }
}
