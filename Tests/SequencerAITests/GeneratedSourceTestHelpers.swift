import Foundation
@testable import SequencerAI

func euclideanAlgo(matching pattern: [Bool]) -> StepAlgo {
    let resolvedPattern = pattern.isEmpty ? [false] : pattern

    for pulses in 0...resolvedPattern.count {
        for offset in -resolvedPattern.count...resolvedPattern.count {
            let candidate = StepAlgo.euclidean(
                pulses: pulses,
                steps: resolvedPattern.count,
                offset: offset
            )
            var rng = PreviewRNG()
            let matches = resolvedPattern.indices.allSatisfy { stepIndex in
                candidate.fires(
                    at: stepIndex,
                    totalSteps: resolvedPattern.count,
                    rng: &rng
                ) == resolvedPattern[stepIndex]
            }

            if matches {
                return candidate
            }
        }
    }

    preconditionFailure("Pattern is not representable as a Euclidean trigger: \(resolvedPattern)")
}
