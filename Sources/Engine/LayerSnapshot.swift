import Foundation

struct LayerSnapshot: Equatable, Sendable {
    var mute: [UUID: Bool]

    static let empty = LayerSnapshot(mute: [:])

    func isMuted(_ trackID: UUID) -> Bool {
        mute[trackID] ?? false
    }
}
