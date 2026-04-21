struct SamplerSettings: Codable, Equatable, Hashable, Sendable {
    var gain: Double                  // dB, clamped [-60, +12]; UI-exposed in MVP
    var transpose: Int                // semitones, clamped [-48, +48]; reserved
    var attackMs: Double              // [0, 2000]; reserved
    var releaseMs: Double             // [0, 5000]; reserved

    init(gain: Double = 0, transpose: Int = 0, attackMs: Double = 0, releaseMs: Double = 0) {
        self.gain = gain
        self.transpose = transpose
        self.attackMs = attackMs
        self.releaseMs = releaseMs
    }

    static let `default` = SamplerSettings()

    func clamped() -> SamplerSettings {
        SamplerSettings(
            gain: min(max(gain, -60), 12),
            transpose: min(max(transpose, -48), 48),
            attackMs: min(max(attackMs, 0), 2000),
            releaseMs: min(max(releaseMs, 0), 5000)
        )
    }

    // Custom decoder so that absent keys (legacy documents) fall back to
    // stored-property defaults rather than throwing keyNotFound.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gain      = try c.decodeIfPresent(Double.self, forKey: .gain)      ?? 0
        transpose = try c.decodeIfPresent(Int.self,    forKey: .transpose) ?? 0
        attackMs  = try c.decodeIfPresent(Double.self, forKey: .attackMs)  ?? 0
        releaseMs = try c.decodeIfPresent(Double.self, forKey: .releaseMs) ?? 0
    }
}
