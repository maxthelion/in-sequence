import Foundation

func clipIsEmpty(_ content: ClipContent) -> Bool {
    switch content {
    case let .stepSequence(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    case let .sliceTriggers(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    case let .pianoRoll(_, _, notes):
        return notes.isEmpty
    }
}
