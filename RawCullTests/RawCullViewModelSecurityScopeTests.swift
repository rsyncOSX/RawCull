import Foundation
@testable import RawCull
import Testing

@MainActor
struct RawCullViewModelSecurityScopeTests {
    @Test
    func `starting same active catalog does not duplicate security scoped access`() {
        let viewModel = RawCullViewModel()
        let url = URL(fileURLWithPath: "/tmp/rawcull-catalog-a", isDirectory: true)
        var started: [URL] = []
        var stopped: [URL] = []

        viewModel.startSecurityScopedResource = { url in
            started.append(url)
            return true
        }
        viewModel.stopSecurityScopedResource = { url in
            stopped.append(url)
        }

        #expect(viewModel.startSecurityScopedAccess(for: url))
        #expect(viewModel.startSecurityScopedAccess(for: url))

        #expect(started == [url])
        #expect(stopped.isEmpty)
    }

    @Test
    func `starting another catalog stops previous security scoped access`() {
        let viewModel = RawCullViewModel()
        let firstURL = URL(fileURLWithPath: "/tmp/rawcull-catalog-a", isDirectory: true)
        let secondURL = URL(fileURLWithPath: "/tmp/rawcull-catalog-b", isDirectory: true)
        var started: [URL] = []
        var stopped: [URL] = []

        viewModel.startSecurityScopedResource = { url in
            started.append(url)
            return true
        }
        viewModel.stopSecurityScopedResource = { url in
            stopped.append(url)
        }

        #expect(viewModel.startSecurityScopedAccess(for: firstURL))
        #expect(viewModel.startSecurityScopedAccess(for: secondURL))

        #expect(started == [firstURL, secondURL])
        #expect(stopped == [firstURL])
        #expect(viewModel.hasActiveSecurityScopedAccess(for: secondURL))
    }

    @Test
    func `stopping active catalog is idempotent`() {
        let viewModel = RawCullViewModel()
        let url = URL(fileURLWithPath: "/tmp/rawcull-catalog-a", isDirectory: true)
        var stopped: [URL] = []

        viewModel.startSecurityScopedResource = { _ in true }
        viewModel.stopSecurityScopedResource = { url in
            stopped.append(url)
        }

        #expect(viewModel.startSecurityScopedAccess(for: url))
        viewModel.stopActiveSecurityScopedAccess()
        viewModel.stopActiveSecurityScopedAccess()

        #expect(stopped == [url])
        #expect(!viewModel.hasActiveSecurityScopedAccess(for: url))
    }

    @Test
    func `failed start leaves no active security scoped access`() {
        let viewModel = RawCullViewModel()
        let url = URL(fileURLWithPath: "/tmp/rawcull-catalog-a", isDirectory: true)
        var stopped: [URL] = []

        viewModel.startSecurityScopedResource = { _ in false }
        viewModel.stopSecurityScopedResource = { url in
            stopped.append(url)
        }

        #expect(!viewModel.startSecurityScopedAccess(for: url))
        viewModel.stopActiveSecurityScopedAccess()

        #expect(stopped.isEmpty)
        #expect(!viewModel.hasActiveSecurityScopedAccess(for: url))
    }

    @Test
    func `catalog cancellation stops active security scoped access`() {
        let viewModel = RawCullViewModel()
        let url = URL(fileURLWithPath: "/tmp/rawcull-catalog-a", isDirectory: true)
        var stopped: [URL] = []

        viewModel.startSecurityScopedResource = { _ in true }
        viewModel.stopSecurityScopedResource = { url in
            stopped.append(url)
        }

        #expect(viewModel.startSecurityScopedAccess(for: url))
        viewModel.cancelCatalogLoad()

        #expect(stopped == [url])
        #expect(!viewModel.hasActiveSecurityScopedAccess(for: url))
    }
}
