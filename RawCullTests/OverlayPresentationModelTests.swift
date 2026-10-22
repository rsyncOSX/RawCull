@testable import RawCull
import AppKit
import Testing

@MainActor
@Suite("Overlay presentation")
struct OverlayPresentationModelTests {
    @Test
    func cancelledFocusRequestCannotReplaceTheNewSource() async throws {
        let model = LoupeFocusPresentationModel()
        model.isPresented = true
        let oldImage = NSImage(size: NSSize(width: 1, height: 1))
        let newImage = NSImage(size: NSSize(width: 2, height: 2))
        let (events, started) = AsyncStream.makeStream(of: Void.self)
        var resume: CheckedContinuation<NSImage?, Never>?
        let old = model.request(url: URL(filePath: "/old"), source: .embeddedJPG) {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.yield()
            }
        }
        for await _ in events { break }
        model.reset()
        let latest = model.request(url: URL(filePath: "/new"), source: .developedRAW) { newImage }
        await latest?.value
        resume?.resume(returning: oldImage)
        await old?.value
        #expect(model.image === newImage)
        #expect(!model.isLoading)
        // A completed source is reused rather than generated again.
        let cached = model.request(url: URL(filePath: "/new"), source: .developedRAW) { oldImage }
        #expect(cached == nil)
    }

    @Test
    func cancellingDebouncePreventsFocusWork() async {
        let model = LoupeFocusPresentationModel()
        model.isPresented = true
        var didGenerate = false
        let pending = model.request(url: URL(filePath: "/image"), source: .thumbnail, delay: .seconds(60)) {
            didGenerate = true
            return nil
        }
        model.cancel()
        await pending?.value
        #expect(!didGenerate)
        #expect(!model.isLoading)
        #expect(model.image == nil)
    }

    @Test
    func obsoleteOutlineCompletionCannotClearANewerImage() async {
        let model = SubjectOutlinePresentationModel()
        model.isPresented = true
        let (events, started) = AsyncStream.makeStream(of: Void.self)
        var resume: CheckedContinuation<CGImage?, Never>?
        let old = Task {
            await model.load {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.yield()
                }
            }
        }
        for await _ in events { break }
        model.reset()
        let pixel = Self.pixel()
        await model.load { pixel }
        resume?.resume(returning: nil)
        await old.value
        #expect(model.image === pixel)
        #expect(!model.isLoading)
    }

    private static func pixel() -> CGImage {
        CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
