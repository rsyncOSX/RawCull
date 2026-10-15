import AppKit
@testable import RawCull
import Testing

@MainActor
struct ThumbnailPresentationModelTests {
    private func request(size: Int = 200, style: ThumbnailStyle = .grid) -> ThumbnailRequest {
        ThumbnailRequest(url: URL(filePath: "/test/photo.ARW"), targetSize: size, style: style)
    }

    @Test
    func `request identity includes representation and source revision`() {
        let original = request()
        #expect(original != request(size: 300))
        #expect(original != request(style: .list))
        var changed = original
        changed.fileSize = 12
        #expect(original != changed)
        changed = original
        changed.modificationDate = Date(timeIntervalSince1970: 1)
        #expect(original != changed)
    }

    @Test
    func `late old load cannot overwrite a newer image or its binding`() async {
        let model = ThumbnailPresentationModel()
        let oldImage = NSImage(size: NSSize(width: 1, height: 1))
        let newImage = NSImage(size: NSSize(width: 2, height: 2))
        var binding: NSImage?
        var finishOld: CheckedContinuation<NSImage?, Never>?
        var oldTask: Task<Void, Never>?
        await withCheckedContinuation { started in
            oldTask = Task {
                await model.load(request: request(), imageLoader: {
                    await withCheckedContinuation { continuation in
                        finishOld = continuation
                        started.resume()
                    }
                }, publish: { binding = $0 })
            }
        }
        await model.load(request: request(size: 300), imageLoader: { newImage }, publish: { binding = $0 })
        finishOld?.resume(returning: oldImage)
        await oldTask?.value
        #expect(model.image === newImage)
        #expect(binding === newImage)
        #expect(!model.isLoading)
    }

    @Test
    func `cancelled load does not publish its result`() async {
        let model = ThumbnailPresentationModel()
        var published: [NSImage?] = []
        var finish: CheckedContinuation<NSImage?, Never>?
        var task: Task<Void, Never>?
        await withCheckedContinuation { started in
            task = Task {
                await model.load(request: request(), imageLoader: {
                    await withCheckedContinuation { continuation in
                        finish = continuation
                        started.resume()
                    }
                }, publish: { published.append($0) })
            }
        }
        task?.cancel()
        finish?.resume(returning: NSImage(size: NSSize(width: 1, height: 1)))
        await task?.value
        #expect(published.count == 1) // Only the current source's initial clear.
        #expect(published.allSatisfy { $0 == nil })
        #expect(model.image == nil)
        #expect(!model.isLoading)
    }
}
