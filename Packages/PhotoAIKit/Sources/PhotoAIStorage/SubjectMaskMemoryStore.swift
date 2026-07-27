import PhotoAIContracts

public actor SubjectMaskMemoryStore: SubjectMaskStoring {
    private var entries: [SubjectMaskStorageKey: SubjectSegmentationResult] = [:]

    public init() {}

    public func load(for key: SubjectMaskStorageKey) -> SubjectSegmentationResult? {
        entries[key]
    }

    public func contains(_ key: SubjectMaskStorageKey) -> Bool {
        entries[key] != nil
    }

    public func save(
        _ result: SubjectSegmentationResult,
        for key: SubjectMaskStorageKey
    ) {
        entries[key] = result
    }

    public func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }
}
