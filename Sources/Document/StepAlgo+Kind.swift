import Foundation

enum StepAlgoKind: String, CaseIterable, Identifiable, Sendable {
    case euclidean
    case manual
    case weighted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .euclidean:
            return "Euclidean"
        case .manual:
            return "Manual"
        case .weighted:
            return "Weighted"
        }
    }

    func defaultAlgo(current: StepAlgo) -> StepAlgo {
        switch self {
        case .euclidean:
            if case let .euclidean(pulses, steps, offset) = current {
                return .euclidean(pulses: pulses, steps: steps, offset: offset)
            }
            return .euclidean(pulses: 4, steps: 16, offset: 0)
        case .manual:
            if case let .manual(pattern) = current {
                return .manual(pattern: pattern)
            }
            return .manual(pattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false])
        case .weighted:
            if case let .weighted(weights, steps, cluster) = current {
                return .weighted(weights: weights, steps: steps, cluster: cluster)
            }
            return .weighted(weights: [1, 0, 0.25, 0, 0.75, 0, 0.25, 0, 1, 0, 0.25, 0, 0.75, 0, 0.25, 0], steps: 16, cluster: 0)
        }
    }
}

extension StepAlgo {
    var kind: StepAlgoKind {
        switch self {
        case .euclidean:
            return .euclidean
        case .manual:
            return .manual
        case .weighted:
            return .weighted
        }
    }
}
