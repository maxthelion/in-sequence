import Foundation

enum StepAlgo: Codable, Equatable, Hashable, Sendable {
    case manual(pattern: [Bool])
    case randomWeighted(density: Double)
    case euclidean(pulses: Int, steps: Int, offset: Int)
    case perStepProbability(probs: [Double])
    case fromClipSteps(clipID: UUID)

    func fires<R: RandomNumberGenerator>(
        at stepIndex: Int,
        totalSteps: Int,
        rng: inout R
    ) -> Bool {
        switch self {
        case let .manual(pattern):
            guard !pattern.isEmpty, stepIndex >= 0 else {
                return false
            }
            return pattern[stepIndex % pattern.count]

        case let .randomWeighted(density):
            let normalizedDensity = min(max(density, 0), 1)
            return Double.random(in: 0..<1, using: &rng) < normalizedDensity

        case let .euclidean(pulses, steps, offset):
            guard stepIndex >= 0 else {
                return false
            }

            let resolvedSteps = max(steps, totalSteps, 1)
            let mask = Euclidean.mask(pulses: pulses, steps: resolvedSteps)
            let normalizedOffset = ((offset % resolvedSteps) + resolvedSteps) % resolvedSteps
            let normalizedStepIndex = stepIndex % resolvedSteps
            let rotatedIndex = ((normalizedStepIndex - normalizedOffset) + resolvedSteps) % resolvedSteps
            return mask[rotatedIndex]

        case let .perStepProbability(probs):
            guard !probs.isEmpty, stepIndex >= 0 else {
                return false
            }

            let normalizedProbability = min(max(probs[stepIndex % probs.count], 0), 1)
            return Double.random(in: 0..<1, using: &rng) < normalizedProbability

        case .fromClipSteps:
            return false
        }
    }
}
