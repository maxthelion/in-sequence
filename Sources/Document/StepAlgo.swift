import Foundation

enum StepAlgo: Codable, Equatable, Hashable, Sendable {
    case euclidean(pulses: Int, steps: Int, offset: Int)

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
        }
    }
}
