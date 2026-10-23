import AppKit
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Testing

extension ConcurrencyTests {
    struct MemoryViewModelTests {
        @Test
        func `memory stats update populates coherent values`() async {
            let viewModel = await MemoryViewModel()

            await viewModel.updateMemoryStats()

            let totalMemory = await viewModel.totalMemory
            let usedMemory = await viewModel.usedMemory
            let appMemory = await viewModel.appMemory

            #expect(totalMemory > 0)
            #expect(usedMemory > 0)
            #expect(appMemory > 0)
            #expect(usedMemory <= totalMemory)
            #expect(appMemory <= usedMemory)
        }
    }
}
