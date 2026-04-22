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
    let trackType: TrackType
    let lengthSteps: Int
    let steps: [ClipStepBuffer]
    let macroBindingOrder: [UUID]
    let macroBindingIndexes: [UUID: Int]
    let macroOverrideValues: [[Double?]]

    func macroOverride(stepIndex: Int, bindingID: UUID) -> Double? {
        guard let bindingIndex = macroBindingIndexes[bindingID],
              macroOverrideValues.indices.contains(stepIndex),
              macroOverrideValues[stepIndex].indices.contains(bindingIndex)
        else {
            return nil
        }
        return macroOverrideValues[stepIndex][bindingIndex]
    }
}
