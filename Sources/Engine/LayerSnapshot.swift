import Foundation

struct LayerSnapshot: Equatable, Sendable {
    let mute: [UUID: Bool]
    let fillEnabled: [UUID: Bool]

    static let empty = LayerSnapshot(mute: [:], fillEnabled: [:])

    func isMuted(_ trackID: UUID) -> Bool {
        mute[trackID] ?? false
    }

    func isFillEnabled(_ trackID: UUID) -> Bool {
        fillEnabled[trackID] ?? false
    }
}
