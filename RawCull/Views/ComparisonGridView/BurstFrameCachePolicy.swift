import OSLog
import RawCullCore
import SwiftUI

nonisolated enum BurstFrameCachePolicy {
    static let capacity = 3

    static func indices(around selectedIndex: Int, itemCount: Int) -> [Int] {
        guard itemCount > 0, (0 ..< itemCount).contains(selectedIndex) else { return [] }
        let lowerBound = max(0, selectedIndex - 1)
        let upperBound = min(itemCount - 1, selectedIndex + 1)
        return Array(lowerBound ... upperBound)
    }
}
