import Foundation

enum StepAlgoKind: String, CaseIterable, Identifiable, Sendable {
    case euclidean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .euclidean:
            return "Euclidean"
        }
    }

    func defaultAlgo(current: StepAlgo) -> StepAlgo {
        switch self {
        case .euclidean:
            if case let .euclidean(pulses, steps, offset) = current {
                return .euclidean(pulses: pulses, steps: steps, offset: offset)
            }
            return .euclidean(pulses: 4, steps: 16, offset: 0)
        }
    }
}

extension StepAlgo {
    var kind: StepAlgoKind {
        switch self {
        case .euclidean:
            return .euclidean
        }
    }
}
