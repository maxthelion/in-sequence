import Foundation

protocol MasterBusHosting: AnyObject {
    var appliedState: MasterBusState { get }
    var applyCallCount: Int { get }
    func apply(_ state: MasterBusState)
}

final class MasterBusHost: MasterBusHosting {
    private let lock = NSLock()
    private var state: MasterBusState = .default
    private var count: Int = 0

    var appliedState: MasterBusState {
        lock.withLock { state }
    }

    var applyCallCount: Int {
        lock.withLock { count }
    }

    func apply(_ state: MasterBusState) {
        lock.withLock {
            self.state = state.normalized()
            self.count += 1
        }
    }

    var activeScene: MasterBusScene {
        appliedState.liveScene
    }

    var abCrossfadeGains: (a: Double, b: Double)? {
        guard let selection = appliedState.abSelection else { return nil }
        return Self.equalPowerGains(crossfader: selection.crossfader)
    }

    static func equalPowerGains(crossfader: Double) -> (a: Double, b: Double) {
        let clamped = min(max(crossfader, 0), 1)
        return (
            a: cos(clamped * .pi / 2),
            b: sin(clamped * .pi / 2)
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
