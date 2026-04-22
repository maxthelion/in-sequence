import AVFoundation

/// Wraps `AVAudioUnitEQ` (1 band) to expose the five-parameter filter surface
/// used by sampler tracks: type, poles, cutoff, resonance, and drive.
///
/// One filter exists per sampler-shaped track. It sits between the per-track
/// mixer and the main mixer node. Graph lifetime is managed by
/// `SamplePlaybackEngine`.
///
/// DSP note — poles approximation:
///   `AVAudioUnitEQ` does not expose filter slope order. V1 approximates
///   1-pole / 2-pole / 4-pole behaviour by adjusting the EQ band's `bandwidth`
///   parameter (wider → gentler roll-off, tighter → steeper). This is a
///   perceptual stand-in, not acoustically accurate slope orders. A future plan
///   will swap this for a custom `AUAudioUnit` DSP subclass without touching the
///   document model, macros, UI, or wiring.
///
/// Drive note:
///   v1 drive is `globalGain += drive * 12 dB`. This is a level boost, not
///   a saturation stage.
final class SamplerFilterNode {

    // MARK: - Public node

    /// The underlying EQ node to attach to an `AVAudioEngine`.
    let avNode: AVAudioUnitEQ

    // MARK: - Band

    private var band: AVAudioUnitEQFilterParameters { avNode.bands[0] }

    // MARK: - Init

    init() {
        avNode = AVAudioUnitEQ(numberOfBands: 1)
        configureDefaultBand()
    }

    // MARK: - Apply full settings

    /// Apply all five filter parameters at once.
    /// Use fine-grained setters from `TrackMacroApplier` when only one value changes per step.
    func apply(_ settings: SamplerFilterSettings) {
        setType(settings.type)
        setPoles(settings.poles)
        setCutoff(hz: settings.cutoffHz)
        setResonance(settings.resonance)
        setDrive(settings.drive)
    }

    // MARK: - Fine-grained setters

    func setType(_ type: SamplerFilterType) {
        switch type {
        case .lowpass:
            band.filterType = .lowPass
        case .highpass:
            band.filterType = .highPass
        case .bandpass:
            band.filterType = .bandPass
        case .notch:
            // Notch is implemented as a very-deep parametric band.
            // Gain of -40 dB at the centre frequency approximates a notch.
            band.filterType = .parametric
            band.gain = -40
        }
        band.bypass = false
    }

    /// Approximate pole-count via bandwidth adjustment.
    ///
    /// This is NOT a correct pole count. `AVAudioUnitEQ` does not expose slope
    /// order. Narrower bandwidth → steeper perceived roll-off (perceptual stand-in
    /// only). A custom AUAudioUnit subclass will replace this in a future plan.
    func setPoles(_ poles: SamplerFilterPoles) {
        switch poles {
        case .one:
            band.bandwidth = 1.0    // wide — gentle roll-off (≈ 6 dB/oct feel)
        case .two:
            band.bandwidth = 0.5   // default — moderate roll-off (≈ 12 dB/oct feel)
        case .four:
            band.bandwidth = 0.15  // tight — steep roll-off (≈ 24 dB/oct feel)
        }
    }

    func setCutoff(hz: Double) {
        let clamped = min(max(hz, 20), 20_000)
        band.frequency = Float(clamped)
    }

    /// Map normalized resonance (0..1) to a gain bump on the EQ band.
    ///
    /// For LP/HP/BP a positive gain at the cutoff frequency produces a
    /// resonant peak. For notch (.parametric with gain=-40), resonance narrows
    /// the notch by reducing bandwidth.
    func setResonance(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)
        if band.filterType == .parametric {
            // Notch: resonance narrows the band (tighter Q = deeper, narrower notch).
            band.bandwidth = Float(0.5 - clamped * 0.45)  // 0.5 → 0.05 as resonance → 1
        } else {
            // LP/HP/BP: resonance adds a gain bump at the cutoff.
            band.gain = Float(clamped * 18)  // 0..18 dB
        }
    }

    /// Map normalized drive (0..1) to a global output gain boost.
    ///
    /// v1: `globalGain += drive * 12 dB`. Not a saturation stage.
    func setDrive(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)
        avNode.globalGain = Float(clamped * 12)  // 0..12 dB
    }

    // MARK: - Private

    private func configureDefaultBand() {
        // Bypass-transparent defaults: LP at 20 kHz, 0 resonance, 0 drive.
        band.filterType = .lowPass
        band.frequency = 20_000
        band.bandwidth = 0.5
        band.gain = 0
        band.bypass = false
        avNode.globalGain = 0
    }
}
