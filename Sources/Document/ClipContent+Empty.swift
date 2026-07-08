import Foundation

func clipIsEmpty(_ content: ClipContent) -> Bool {
    switch content {
    case let .noteGrid(_, steps):
        return steps.allSatisfy(\.isEmpty)
    case let .chordReferences(stepPattern, _, _, _, _):
        return stepPattern.allSatisfy { !$0 }
    case let .sliceTriggers(stepPattern, _, _, _):
        return stepPattern.allSatisfy { !$0 }
    }
}
