import Foundation

struct LayerSnapshot: Equatable, Sendable {
    let mute: [UUID: Bool]
    let fillEnabled: [UUID: Bool]
    let macroValues: [UUID: [UUID: Double]]

    init(
        mute: [UUID: Bool],
        fillEnabled: [UUID: Bool] = [:],
        macroValues: [UUID: [UUID: Double]] = [:]
    ) {
        self.mute = mute
        self.fillEnabled = fillEnabled
        self.macroValues = macroValues
    }

    static let empty = LayerSnapshot(mute: [:], fillEnabled: [:], macroValues: [:])

    func isMuted(_ trackID: UUID) -> Bool {
        mute[trackID] ?? false
    }

    func isFillEnabled(_ trackID: UUID) -> Bool {
        fillEnabled[trackID] ?? false
    }

    func macroValue(trackID: UUID, bindingID: UUID) -> Double? {
        macroValues[trackID]?[bindingID]
    }

    /// Quantised perform toggles: committed mute changes override the
    /// compiled layer value until the main-side document staging reinstalls
    /// a snapshot that encodes them. Returns a snapshot every prepare-tick
    /// mute consumer reads consistently.
    func applyingMuteOverrides(_ overrides: [UUID: Bool]) -> LayerSnapshot {
        guard !overrides.isEmpty else {
            return self
        }
        var mergedMute = mute
        for (trackID, muted) in overrides {
            mergedMute[trackID] = muted
        }
        return LayerSnapshot(
            mute: mergedMute,
            fillEnabled: fillEnabled,
            macroValues: macroValues
        )
    }
}
