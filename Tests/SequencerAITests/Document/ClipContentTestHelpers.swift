import Foundation
@testable import SequencerAI

func noteGridMainStepPattern(_ content: ClipContent) -> [Bool] {
    guard case let .noteGrid(lengthSteps, steps) = content.normalized else {
        return []
    }
    return (0..<lengthSteps).map { index in
        steps.indices.contains(index) && steps[index].main != nil
    }
}

func noteGridFillStepPattern(_ content: ClipContent) -> [Bool] {
    guard case let .noteGrid(lengthSteps, steps) = content.normalized else {
        return []
    }
    return (0..<lengthSteps).map { index in
        steps.indices.contains(index) && steps[index].fill != nil
    }
}

func noteGridPitches(_ content: ClipContent) -> [Int] {
    guard case let .noteGrid(_, steps) = content.normalized else {
        return []
    }
    return Array(
        Set(
            steps.flatMap { step in
                (step.main?.notes ?? []) + (step.fill?.notes ?? [])
            }
            .map(\.pitch)
        )
    )
    .sorted()
}
