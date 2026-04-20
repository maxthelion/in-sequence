import Foundation

enum StepAlgoKind: String, CaseIterable, Identifiable, Sendable {
    case manual
    case euclidean
    case randomWeighted
    case perStepProbability
    case fromClipSteps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .euclidean:
            return "Euclidean"
        case .randomWeighted:
            return "Weighted"
        case .perStepProbability:
            return "Probability"
        case .fromClipSteps:
            return "From Clip"
        }
    }

    func defaultAlgo(clipChoices: [ClipPoolEntry], current: StepAlgo) -> StepAlgo {
        switch self {
        case .manual:
            if case let .manual(pattern) = current {
                return .manual(pattern: pattern)
            }
            return .manual(pattern: Array(repeating: false, count: 16))
        case .euclidean:
            return .euclidean(pulses: 4, steps: 16, offset: 0)
        case .randomWeighted:
            return .randomWeighted(density: 0.5)
        case .perStepProbability:
            return .perStepProbability(probs: Array(repeating: 0.5, count: 16))
        case .fromClipSteps:
            if let clipID = clipChoices.first?.id {
                return .fromClipSteps(clipID: clipID)
            }
            return .manual(pattern: Array(repeating: false, count: 16))
        }
    }
}

extension StepAlgo {
    var kind: StepAlgoKind {
        switch self {
        case .manual:
            return .manual
        case .euclidean:
            return .euclidean
        case .randomWeighted:
            return .randomWeighted
        case .perStepProbability:
            return .perStepProbability
        case .fromClipSteps:
            return .fromClipSteps
        }
    }
}
