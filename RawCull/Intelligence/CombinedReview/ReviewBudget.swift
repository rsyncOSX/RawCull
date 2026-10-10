import Foundation

nonisolated enum ReviewAttemptCategory: String, Codable, CaseIterable, Sendable {
    case overview, crop, followup, reconciliation, report, comparison, sam, clip
}

nonisolated struct ReviewBudgetChange: Codable, Equatable, Sendable {
    let category: ReviewAttemptCategory
    let imageID: ReviewImageID?
    let newLimit: Int
    let reason: String
}

nonisolated struct ReviewBudget: Codable, Equatable, Sendable {
    let limits: [ReviewAttemptCategory: Int]
    let perImageLimits: [ReviewAttemptCategory: Int]
    private(set) var attempts: [ReviewAttemptCategory: Int] = [:]
    private(set) var imageAttempts: [String: Int] = [:]
    private(set) var changes: [ReviewBudgetChange] = []

    init(depth: ReviewDepth, images: Int) throws {
        guard images > 0, images <= 1000 else { throw ReviewRunError.invalidSnapshot }
        let crops = min(images * depth.cropsPerImage, depth.selectionCrops)
        let followups = min(images * depth.followupsPerImage, depth.selectionFollowups)
        limits = [.overview: images, .crop: crops, .followup: followups, .reconciliation: images,
                  .report: images, .comparison: images > 1 ? 1 + depth.pairCap : 0,
                  .sam: 4 * images, .clip: images + crops]
        perImageLimits = [.overview: 1, .crop: depth.cropsPerImage, .followup: depth.followupsPerImage,
                          .reconciliation: 1, .report: 1, .sam: 4, .clip: 1 + depth.cropsPerImage]
    }

    var maximumQwenAttempts: Int {
        ReviewAttemptCategory.allCases.filter { $0 != .sam && $0 != .clip }.reduce(0) { total, category in
            total + (changes.last { $0.category == category && $0.imageID == nil }?.newLimit ?? limits[category] ?? 0)
        }
    }

    mutating func recordChange(_ change: ReviewBudgetChange) throws {
        guard change.newLimit >= 0, !change.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewRunError.invalidSnapshot
        }
        changes.append(change)
    }

    mutating func consume(_ category: ReviewAttemptCategory, imageID: ReviewImageID?) throws {
        let totalLimit = changes.last { $0.category == category && $0.imageID == nil }?.newLimit ?? limits[category] ?? 0
        guard attempts[category, default: 0] < totalLimit else { throw ReviewRunError.budgetExhausted }
        if let imageID {
            let key = "\(category.rawValue):\(imageID.rawValue)"
            let localLimit = changes.last { $0.category == category && $0.imageID == imageID }?.newLimit
                ?? perImageLimits[category] ?? 0
            guard imageAttempts[key, default: 0] < localLimit else { throw ReviewRunError.budgetExhausted }
            imageAttempts[key, default: 0] += 1
        } else if category != .comparison {
            throw ReviewRunError.invalidSnapshot
        }
        attempts[category, default: 0] += 1
    }

    /// Round-robin ordering reserves first crop coverage before later priorities.
    static func cropAllocation(images: [ReviewImageID], counts: [ReviewImageID: Int], depth: ReviewDepth) -> [ReviewImageID] {
        var allocated: [ReviewImageID] = []
        for round in 0 ..< depth.cropsPerImage {
            for image in images where round < counts[image, default: 0] {
                guard allocated.count < depth.selectionCrops else { return allocated }
                allocated.append(image)
            }
        }
        return allocated
    }
}
