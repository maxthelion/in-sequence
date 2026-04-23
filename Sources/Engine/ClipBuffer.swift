import Foundation

struct ClipNoteBuffer: Equatable, Sendable {
    let pitch: UInt8
    let velocity: UInt8
    let lengthSteps: UInt16
}

struct ClipLaneBuffer: Equatable, Sendable {
    let chance: Double
    let notes: [ClipNoteBuffer]
}

struct ClipStepBuffer: Equatable, Sendable {
    let main: ClipLaneBuffer?
    let fill: ClipLaneBuffer?
}

struct ClipBuffer: Equatable, Sendable {
    let clipID: UUID
    let lengthSteps: Int
    let steps: [ClipStepBuffer]
    let macroBindingOrder: [UUID]
    let macroOverrideValues: [[Double?]]

    func step(at stepIndex: Int) -> ClipStepBuffer? {
        guard !steps.isEmpty else {
            return nil
        }
        let normalizedIndex = ((stepIndex % lengthSteps) + lengthSteps) % lengthSteps
        return steps[normalizedIndex]
    }

    func macroOverrides(at stepIndex: Int) -> [UUID: Double] {
        guard !macroBindingOrder.isEmpty, !macroOverrideValues.isEmpty else {
            return [:]
        }

        let normalizedIndex = ((stepIndex % lengthSteps) + lengthSteps) % lengthSteps
        let values = macroOverrideValues[normalizedIndex]
        return Dictionary(
            uniqueKeysWithValues: zip(macroBindingOrder, values).compactMap { bindingID, value in
                value.map { (bindingID, $0) }
            }
        )
    }
}
