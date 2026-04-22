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
}
