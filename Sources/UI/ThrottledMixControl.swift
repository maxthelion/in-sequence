import SwiftUI

/// Holds temporary drag state for a live mix control so the engine can receive
/// scoped updates without mutating the document on every drag tick.
@MainActor
final class ThrottledMixValue: ObservableObject {
    @Published private(set) var liveValue: Double?

    func begin(with initial: Double) {
        liveValue = initial
    }

    @discardableResult
    func update(_ value: Double, epsilon: Double = 0.0005) -> Bool {
        guard let current = liveValue else {
            liveValue = value
            return true
        }

        if abs(current - value) < epsilon {
            return false
        }

        liveValue = value
        return true
    }

    func commit() -> Double? {
        let final = liveValue
        liveValue = nil
        return final
    }

    var isDragging: Bool {
        liveValue != nil
    }

    func rendered(committed: Double) -> Double {
        liveValue ?? committed
    }
}
