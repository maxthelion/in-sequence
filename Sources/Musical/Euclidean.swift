enum Euclidean {
    static func mask(pulses: Int, steps: Int) -> [Bool] {
        guard steps > 0 else {
            return []
        }

        let clampedPulses = min(max(pulses, 0), steps)
        guard clampedPulses > 0 else {
            return Array(repeating: false, count: steps)
        }

        guard clampedPulses < steps else {
            return Array(repeating: true, count: steps)
        }

        return (0..<steps).map { step in
            (step * clampedPulses) % steps < clampedPulses
        }
    }
}
