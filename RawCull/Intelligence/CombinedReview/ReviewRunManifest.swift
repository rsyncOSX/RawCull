import Foundation

nonisolated enum ReviewWorkState: String, Codable, Sendable {
    case pending, running, completed, failed, cancelled, skipped
    var terminal: Bool {
        self == .completed || self == .failed || self == .skipped
    }
}

nonisolated struct ReviewWorkDependency: Codable, Equatable, Sendable {
    let id: ReviewWorkID
    /// Reconciliation/report can consume explicitly unavailable outcomes; crop
    /// observation requires completed preparation and does not depend on measurement.
    let allowsUnavailable: Bool
}

nonisolated struct ReviewWorkItem: Codable, Sendable {
    let id: ReviewWorkID
    let imageID: ReviewImageID
    let stage: ReviewStage
    let dependencies: [ReviewWorkDependency]
    var compatibility: ReviewCompatibility
    var state: ReviewWorkState = .pending
    var attempts = 0
    var reason: String?
    var artifactKey: String?
}

nonisolated struct CombinedReviewRunV1: Codable, Sendable {
    let snapshot: ReviewRunSnapshot
    var work: [ReviewWorkItem]
    var budget: ReviewBudget
    var cancelled = false

    func validate() throws {
        try snapshot.validate()
        let ids = Set(work.map(\.id))
        let images = Set(snapshot.files.map(\.id))
        guard ids.count == work.count, images.isSubset(of: Set(work.map(\.imageID))), images.isSubset(of: Set(work.filter { $0.stage == .report }.map(\.imageID))) else { throw ReviewRunError.invalidSnapshot }
        var visited: Set<ReviewWorkID> = []
        var visiting: Set<ReviewWorkID> = []
        func visit(_ item: ReviewWorkItem) throws {
            if visited.contains(item.id) {
                return
            }
            guard visiting.insert(item.id).inserted else { throw ReviewRunError.invalidDependency }
            for dependency in item.dependencies {
                guard let parent = work.first(where: { $0.id == dependency.id }), parent.imageID == item.imageID || item.stage == .comparison else {
                    throw ReviewRunError.invalidDependency
                }
                try visit(parent)
            }
            visiting.remove(item.id)
            visited.insert(item.id)
        }
        for item in work {
            guard images.contains(item.imageID) else { throw ReviewRunError.invalidSnapshot }
            try visit(item)
        }
    }

    /// Rebuild static contract fields; dynamic source/region identities are checked
    /// against the regenerated execution plan before their artifacts are consumed.
    func expectedCompatibility() throws -> [ReviewWorkID: ReviewCompatibility] {
        try Dictionary(uniqueKeysWithValues: work.map { item in
            guard let file = snapshot.files.first(where: { $0.id == item.imageID }),
                  snapshot.stageVersions[item.stage] != nil else { throw ReviewRunError.incompatible }
            return (item.id, try ReviewCompatibility.make(
                snapshot: snapshot, image: file, stage: item.stage,
                sourceRender: item.compatibility.fields["sourceRender"] ?? "",
                region: item.compatibility.fields["region"] ?? ""))
        })
    }

    func ready(_ item: ReviewWorkItem) -> Bool {
        !cancelled && item.state == .pending && item.dependencies.allSatisfy { dependency in
            guard let parent = work.first(where: { $0.id == dependency.id }) else { return false }
            return parent.state == .completed || (dependency.allowsUnavailable && parent.state.terminal)
        }
    }

    mutating func begin(_ id: ReviewWorkID, category: ReviewAttemptCategory? = nil) throws {
        guard let index = work.firstIndex(where: { $0.id == id }), ready(work[index]) else { throw ReviewRunError.invalidTransition }
        let permitted: [ReviewAttemptCategory] = switch work[index].stage {
        case .source, .identity, .measurement: []
        case .overview: [.overview]
        case .segmentation: [.sam]
        case .clip: [.clip]
        case .cropObservation: [.crop, .followup]
        case .reconciliation: [.reconciliation]
        case .report: [.report]
        case .comparison: [.comparison]
        }
        guard category.map(permitted.contains) ?? permitted.isEmpty else { throw ReviewRunError.invalidTransition }
        if let category {
            try budget.consume(category, imageID: category == .comparison ? nil : work[index].imageID)
        }
        work[index].state = .running
        work[index].attempts += 1
        work[index].reason = nil
    }

    mutating func finish(_ id: ReviewWorkID, state: ReviewWorkState, reason: String? = nil, artifactKey: String? = nil) throws {
        guard let index = work.firstIndex(where: { $0.id == id }), work[index].state == .running,
              state.terminal, state != .completed || artifactKey != nil,
              state == .completed || !(reason ?? "").isEmpty else { throw ReviewRunError.invalidTransition }
        work[index].state = state
        work[index].reason = reason
        work[index].artifactKey = artifactKey
    }

    mutating func skip(_ id: ReviewWorkID, reason: String) throws {
        guard let index = work.firstIndex(where: { $0.id == id }), work[index].state == .pending,
              !reason.isEmpty else { throw ReviewRunError.invalidTransition }
        work[index].state = .skipped
        work[index].reason = reason
    }

    mutating func cancel() {
        cancelled = true
        for index in work.indices where work[index].state == .running || work[index].state == .pending {
            work[index].state = .cancelled
            work[index].reason = "Run cancelled; unfinished output discarded"
            work[index].artifactKey = nil
        }
    }

    /// Spend counters survive restore. Invalidations apply transitively, even to
    /// previously completed descendants. Completed independent observations survive.
    mutating func restore(expected: [ReviewWorkID: ReviewCompatibility], validArtifacts: Set<String>, retryFailed: Bool = true) {
        cancelled = false
        var invalid: Set<ReviewWorkID> = []
        for index in work.indices {
            let item = work[index]
            if (retryFailed && item.state == .failed) || expected[item.id] != item.compatibility || (item.state == .completed && !validArtifacts.contains(item.artifactKey ?? "")) {
                invalid.insert(item.id)
            }
        }
        var grew = true
        while grew {
            grew = false
            for item in work where !invalid.contains(item.id) && item.dependencies.contains(where: { invalid.contains($0.id) }) {
                invalid.insert(item.id); grew = true
            }
        }
        for index in work.indices {
            let item = work[index]
            if invalid.contains(item.id) || item.state == .running || item.state == .cancelled || (retryFailed && item.state == .failed) {
                work[index].state = .pending
                work[index].artifactKey = nil
                work[index].reason = nil
            }
            if let compatibility = expected[item.id] {
                work[index].compatibility = compatibility
            }
        }
    }
}
