import Foundation

typealias ClipID = UUID

struct StepSelectionModel: Equatable, Sendable {
    var clipID: ClipID
    var selectedStepIndexes: Set<Int> = []

    mutating func updateActiveClip(_ nextClipID: ClipID) {
        guard nextClipID != clipID else { return }
        clipID = nextClipID
        selectedStepIndexes.removeAll()
    }

    mutating func toggleStep(_ stepIndex: Int) {
        if selectedStepIndexes.contains(stepIndex) {
            selectedStepIndexes.remove(stepIndex)
        } else {
            selectedStepIndexes.insert(stepIndex)
        }
    }

    mutating func clear() {
        selectedStepIndexes.removeAll()
    }
}
