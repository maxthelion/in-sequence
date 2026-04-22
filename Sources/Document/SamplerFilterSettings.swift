import Foundation

// MARK: - SamplerFilterType

/// The filter mode for a sampler track's built-in filter.
enum SamplerFilterType: String, Codable, CaseIterable, Sendable {
    case lowpass
    case highpass
    case bandpass
    case notch
}

// MARK: - SamplerFilterPoles

/// Pole count for the sampler filter.
///
/// Note: in v1, poles are approximated via Q/bandwidth manipulation on
/// `AVAudioUnitEQ`, not true slope orders. See `SamplerFilterNode.setPoles`.
enum SamplerFilterPoles: Int, Codable, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case four = 4
}

// MARK: - SamplerFilterSettings

/// Per-track filter configuration. Lives on `StepSequenceTrack`, not on
/// `Destination`, so it survives sample swaps within the same track.
///
/// Default values are bypass-transparent: `.lowpass` at 20 kHz with zero
/// resonance and drive — inaudible to human hearing, so existing documents
/// are bit-identical before a user touches the filter.
struct SamplerFilterSettings: Codable, Equatable, Hashable, Sendable {
    var type: SamplerFilterType = .lowpass
    var poles: SamplerFilterPoles = .two
    /// Cutoff frequency in Hz. Range: 20..20_000. Default 20_000.
    var cutoffHz: Double = 20_000
    /// Normalized resonance. Range: 0..1. Default 0 (no resonant peak).
    var resonance: Double = 0
    /// Normalized drive. Range: 0..1. Default 0 (no gain boost).
    ///
    /// v1: applied as `globalGain += drive * 12 dB`. Not a saturation stage.
    var drive: Double = 0

    // MARK: - Clamping

    /// Returns a copy with all values clamped to their valid ranges.
    func clamped() -> SamplerFilterSettings {
        var s = self
        s.cutoffHz = min(max(s.cutoffHz, 20), 20_000)
        s.resonance = min(max(s.resonance, 0), 1)
        s.drive = min(max(s.drive, 0), 1)
        return s
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case poles
        case cutoffHz
        case resonance
        case drive
    }

    init(
        type: SamplerFilterType = .lowpass,
        poles: SamplerFilterPoles = .two,
        cutoffHz: Double = 20_000,
        resonance: Double = 0,
        drive: Double = 0
    ) {
        self.type = type
        self.poles = poles
        self.cutoffHz = cutoffHz
        self.resonance = resonance
        self.drive = drive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(SamplerFilterType.self, forKey: .type) ?? .lowpass
        poles = try container.decodeIfPresent(SamplerFilterPoles.self, forKey: .poles) ?? .two
        cutoffHz = try container.decodeIfPresent(Double.self, forKey: .cutoffHz) ?? 20_000
        resonance = try container.decodeIfPresent(Double.self, forKey: .resonance) ?? 0
        drive = try container.decodeIfPresent(Double.self, forKey: .drive) ?? 0
    }
}
