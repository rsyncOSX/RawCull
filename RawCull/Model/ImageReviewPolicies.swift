import CoreGraphics
import Foundation

nonisolated enum ImagePreviewSource: Hashable, Sendable {
    case thumbnail
    case embeddedJPG
    case developedRAW
}

nonisolated struct ImageSourceSelectionState: Equatable, Sendable {
    var selected: ImagePreviewSource
    private(set) var previous: ImagePreviewSource
    private(set) var rawUnavailable = false

    init(initialSource: ImagePreviewSource = .thumbnail) {
        selected = initialSource
        previous = initialSource
    }

    mutating func select(_ source: ImagePreviewSource) {
        guard source != selected else { return }
        previous = selected
        selected = source
    }

    mutating func toggleExtractionSource(_ source: ImagePreviewSource) {
        guard source != .thumbnail else { return }
        guard source != .developedRAW || !rawUnavailable else { return }
        select(selected == source ? .thumbnail : source)
    }

    mutating func markDevelopedRAWUnavailable() {
        selected = previous == .developedRAW ? .thumbnail : previous
        previous = .developedRAW
        rawUnavailable = true
    }

    mutating func resetForNewImage() {
        previous = selected
        rawUnavailable = false
    }
}

nonisolated enum ImageReviewSourceFailure: Equatable, Sendable {
    case developedRAWUnavailable

    var message: String {
        switch self {
        case .developedRAWUnavailable:
            "Not supported"
        }
    }
}

nonisolated struct ImageReviewSourcePresentation: Equatable, Sendable {
    let selectedSource: ImagePreviewSource
    let isDevelopedRAWAvailable: Bool
    let failure: ImageReviewSourceFailure?

    init(
        selection: ImageSourceSelectionState,
        showsDevelopedRAWFailure: Bool,
    ) {
        selectedSource = selection.selected
        isDevelopedRAWAvailable = !selection.rawUnavailable
        failure = showsDevelopedRAWFailure ? .developedRAWUnavailable : nil
    }
}

nonisolated struct ImageReviewViewportPolicy: Equatable, Sendable {
    static let comparison = ImageReviewViewportPolicy(
        minimumScale: 0.5,
        maximumScale: 5.0,
        step: 0.4,
    )
    static let loupe = ImageReviewViewportPolicy(
        minimumScale: 0.5,
        maximumScale: 4.0,
        step: 0.2,
    )

    let minimumScale: CGFloat
    let maximumScale: CGFloat
    let step: CGFloat

    func zoomedIn(from scale: CGFloat) -> CGFloat {
        min(maximumScale, scale + step)
    }

    func zoomedOut(from scale: CGFloat) -> CGFloat {
        max(minimumScale, scale - step)
    }

    func clamped(_ scale: CGFloat) -> CGFloat {
        min(maximumScale, max(minimumScale, scale))
    }
}

nonisolated struct ComparisonViewportInteractionState: Equatable, Sendable {
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var showFocusMask = false
    var showFocusPoints = false

    mutating func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

nonisolated enum ImageReviewRatingAction: Equatable, Sendable {
    case reject
    case keeper
    case stars(Int)

    static let standardActions: [ImageReviewRatingAction] = [
        .reject,
        .keeper,
        .stars(2),
        .stars(3),
        .stars(4),
        .stars(5)
    ]

    var value: Int {
        switch self {
        case .reject: -1
        case .keeper: 0
        case let .stars(value): value
        }
    }

    var label: String {
        switch self {
        case .reject: "X"
        case .keeper: "P"
        case let .stars(value): "\(value)"
        }
    }

    var help: String {
        switch self {
        case .reject: "Reject selected image"
        case .keeper: "Mark selected image as keeper"
        case let .stars(value): "Set selected image to \(value) stars"
        }
    }
}

nonisolated enum RatingDisplay: Equatable, Sendable {
    case unrated
    case rejected
    case keeper
    case stars(Int)

    init(rating: Int, isExplicit: Bool = true) {
        switch rating {
        case -1:
            self = .rejected

        case 0 where isExplicit:
            self = .keeper

        case 2 ... 5:
            self = .stars(rating)

        default:
            self = .unrated
        }
    }

    var label: String {
        switch self {
        case .unrated: "Unrated"
        case .rejected: "X"
        case .keeper: "P"
        case let .stars(rating): "\(rating)"
        }
    }

    var help: String {
        switch self {
        case .unrated: "Unrated"
        case .rejected: "Rejected"
        case .keeper: "Keeper"
        case let .stars(rating): "\(rating)-star rating"
        }
    }
}

nonisolated enum ImageReviewSemanticAction: Equatable, Sendable {
    case zoomIn
    case zoomOut
    case toggleEmbeddedJPG
    case toggleDevelopedRAW
    case toggleFocusMask
    case toggleSubjectOutline
    case toggleFocusPoints
    case rating(ImageReviewRatingAction)
}

nonisolated enum ImageReviewKeyboardPolicy {
    static func action(for characters: String?) -> ImageReviewSemanticAction? {
        switch characters {
        case "+": .zoomIn
        case "-": .zoomOut
        case "j", "J": .toggleEmbeddedJPG
        case "r", "R": .toggleDevelopedRAW
        case "f", "F": .toggleFocusMask
        case "s", "S": .toggleSubjectOutline
        case "a", "A": .toggleFocusPoints
        case "x", "X": .rating(.reject)
        case "p", "P", "0": .rating(.keeper)
        case "1", "2": .rating(.stars(2))
        case "3", "t", "T": .rating(.stars(3))
        case "4": .rating(.stars(4))
        case "5": .rating(.stars(5))
        default: nil
        }
    }
}

nonisolated struct ImageReviewRequestIdentity<Context: Hashable & Sendable>: Hashable, Sendable {
    let generation: UUID
    let context: Context
}

nonisolated struct ImageReviewRequestTracker<Context: Hashable & Sendable>: Sendable {
    private(set) var current: ImageReviewRequestIdentity<Context>?

    mutating func begin(
        context: Context,
        generation: UUID = UUID(),
    ) -> ImageReviewRequestIdentity<Context> {
        let identity = ImageReviewRequestIdentity(
            generation: generation,
            context: context,
        )
        current = identity
        return identity
    }

    mutating func cancel() {
        current = nil
    }

    mutating func finish(_ identity: ImageReviewRequestIdentity<Context>) {
        if current == identity {
            current = nil
        }
    }

    func accepts(
        _ identity: ImageReviewRequestIdentity<Context>,
        isCancelled: Bool,
        requestRevision: Int? = nil,
        currentRevision: Int? = nil,
    ) -> Bool {
        !isCancelled
            && current == identity
            && requestRevision == currentRevision
    }
}

nonisolated struct ImageReviewFocusRequestContext: Hashable, Sendable {
    let fileIDs: [UUID]
}

nonisolated struct ImageReviewSubjectOutlineRequestContext: Hashable, Sendable {
    let fileID: UUID?
    let prompt: String?
    let isPresented: Bool
}
