import Foundation

enum StepAlgo: Codable, Equatable, Hashable, Sendable {
    case euclidean(pulses: Int, steps: Int, offset: Int)
    case manual(pattern: [Bool])
    case weighted(weights: [Double], steps: Int, cluster: Double)

    func fires<R: RandomNumberGenerator>(
        at stepIndex: Int,
        totalSteps: Int,
        rng: inout R
    ) -> Bool {
        switch self {
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
        case let .manual(pattern):
            guard stepIndex >= 0, !pattern.isEmpty else {
                return false
            }
            return pattern[stepIndex % pattern.count]
        case let .weighted(weights, steps, cluster):
            guard stepIndex >= 0 else {
                return false
            }
            let resolvedSteps = max(steps, totalSteps, 1)
            let normalizedWeights = Self.normalizedWeights(weights, count: resolvedSteps)
            let index = stepIndex % resolvedSteps
            let clusteredWeight = Self.clusteredWeight(
                at: index,
                weights: normalizedWeights,
                cluster: min(max(cluster, -1), 1)
            )
            guard clusteredWeight > 0 else {
                return false
            }
            guard clusteredWeight < 1 else {
                return true
            }
            return Double.random(in: 0..<1, using: &rng) < clusteredWeight
        }
    }

    private static func normalizedWeights(_ weights: [Double], count: Int) -> [Double] {
        let clipped = weights.prefix(count).map { min(max($0, 0), 1) }
        return clipped + Array(repeating: 0, count: max(0, count - clipped.count))
    }

    private static func clusteredWeight(at index: Int, weights: [Double], cluster: Double) -> Double {
        guard !weights.isEmpty else {
            return 0
        }
        let base = weights[index]
        guard cluster != 0 else {
            return base
        }

        let left = weights[(index - 1 + weights.count) % weights.count]
        let right = weights[(index + 1) % weights.count]
        let neighbour = max(left, right)
        if cluster > 0 {
            return min(1, base + (1 - base) * neighbour * cluster)
        }
        let repulsion = (left + right) / 2
        return max(0, base * (1 - repulsion * abs(cluster)))
    }
}
