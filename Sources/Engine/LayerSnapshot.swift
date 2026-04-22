import Foundation

struct LayerSnapshot: Equatable, Sendable {
    let mute: [UUID: Bool]
    /// Resolved macro values per step: track ID → binding ID → value.
    /// Populated by `MacroCoordinator.snapshot` from `.macroParam` phrase layers
    /// and clip macro lane overrides.
    let macroValues: [UUID: [UUID: Double]]

    init(mute: [UUID: Bool], macroValues: [UUID: [UUID: Double]] = [:]) {
        self.mute = mute
        self.macroValues = macroValues
    }

    static let empty = LayerSnapshot(mute: [:], macroValues: [:])

    func isMuted(_ trackID: UUID) -> Bool {
        mute[trackID] ?? false
    }

    /// Returns the resolved value for a macro binding on a track, or nil if not set.
    func macroValue(trackID: UUID, bindingID: UUID) -> Double? {
        macroValues[trackID]?[bindingID]
    }
}
