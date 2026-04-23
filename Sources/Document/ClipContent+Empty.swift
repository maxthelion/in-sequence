import Foundation

func clipIsEmpty(_ content: ClipContent) -> Bool {
    switch content {
    case let .noteGrid(_, steps):
        return steps.allSatisfy(\.isEmpty)
    case let .sliceTriggers(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    }
}
