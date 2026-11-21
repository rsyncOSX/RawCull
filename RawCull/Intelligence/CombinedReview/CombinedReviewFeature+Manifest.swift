import Foundation

extension CombinedReviewFeature {
    /// Only the preset's stages get work items, so a Focus check run never plans Qwen work.
    static func initialManifest(_ snapshot: ReviewRunSnapshot) throws -> CombinedReviewRunV1 {
        var work: [ReviewWorkItem] = []
        let preset = snapshot.effectivePreset
        for file in snapshot.files {
            let source = workID(file.id, "source"), overview = workID(file.id, "overview"), identity = workID(file.id, "identity")
            func item(_ name: String, stage: ReviewStage, parents: [ReviewWorkID], terminal: Bool = false) throws -> ReviewWorkItem {
                try .init(id: workID(file.id, name), imageID: file.id, stage: stage,
                          dependencies: parents.map { .init(id: $0, allowsUnavailable: terminal) },
                          compatibility: ReviewCompatibility.make(snapshot: snapshot, image: file, stage: stage))
            }
            switch preset {
            case .full:
                try work.append(contentsOf: [item("source", stage: .source, parents: []),
                                             item("overview", stage: .overview, parents: [source]),
                                             item("identity", stage: .identity, parents: [source, overview], terminal: true),
                                             item("report", stage: .report, parents: [identity, overview], terminal: true)])

            case .focusCheck:
                try work.append(contentsOf: [item("source", stage: .source, parents: []),
                                             item("identity", stage: .identity, parents: [source], terminal: true)])

            case .describe:
                try work.append(contentsOf: [item("source", stage: .source, parents: []),
                                             item("overview", stage: .overview, parents: [source])])
            }
        }
        if snapshot.files.count > 1, preset.includes(.comparison) {
            let file = snapshot.files[0]
            try work.append(.init(id: workID(file.id, "selection"), imageID: file.id, stage: .comparison,
                                  dependencies: snapshot.files.map { .init(id: workID($0.id, "report"), allowsUnavailable: true) },
                                  compatibility: ReviewCompatibility.make(snapshot: snapshot, image: file, stage: .comparison)))
        }
        return try CombinedReviewRunV1(snapshot: snapshot, work: work, budget: ReviewBudget(depth: snapshot.depth, images: snapshot.files.count))
    }
}
