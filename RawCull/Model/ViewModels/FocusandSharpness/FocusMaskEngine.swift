import AppKit
import CoreImage
import Foundation

/// Immutable background engine for focus-mask rendering and sharpness scoring.
/// The engine is `@unchecked Sendable` because Core Image's `CIContext`
/// sendability is not fully expressed in Swift's type system. The invariant is
/// that the engine has no mutable model/UI state; callers pass immutable config
/// snapshots into every operation.
struct FocusMaskEngine: @unchecked Sendable {
    nonisolated let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf
    ])

    struct FocusMaskDiagnostics: Equatable {
        let regionSource: FocusMaskRegionSource
        let visualThreshold: Float?
    }

    struct FocusMaskRegionSelection: Equatable {
        nonisolated let saliencyRect: CGRect?
        nonisolated let afRect: CGRect?

        nonisolated var source: FocusMaskRegionSource {
            switch (saliencyRect, afRect) {
            case (.some, .some): .saliencyAndAF
            case (.some, nil): .saliency
            case (nil, .some): .afPoint
            case (nil, nil): .none
            }
        }
    }

    struct FocusMaskRenderResult {
        let image: CGImage?
        let diagnostics: FocusMaskDiagnostics
        let evidence: FocusEvidence?
    }

    nonisolated init() {}

    nonisolated static func runCancellableWorker<Success: Sendable>(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () -> Success,
    ) async -> Success? {
        let worker = Task.detached(priority: priority, operation: operation)
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                worker.cancel()
                return nil
            }
            return await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
