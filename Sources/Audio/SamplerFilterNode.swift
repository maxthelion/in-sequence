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
    /// Shadow copy of the intended filter settings. Some `AVAudioUnitEQ`
    /// properties are not reliably introspectable before the node is attached,
    /// so tests and higher layers can read the authored state from here.
    private(set) var currentSettings = SamplerFilterSettings()

    // MARK: - Band

    private var band: AVAudioUnitEQFilterParameters {
        MainActor.assumeIsolated {
            avNode.bands[0]
        }
    }

    // MARK: - Init

    init() {
        avNode = MainActor.assumeIsolated {
            AVAudioUnitEQ(numberOfBands: 1)
        }
        configureDefaultBand()
    }

    // MARK: - Apply full settings

    /// Apply all five filter parameters at once.
    /// Use fine-grained setters from `TrackMacroApplier` when only one value changes per step.
    func apply(_ settings: SamplerFilterSettings) {
        currentSettings = settings.clamped()
        syncNodeFromCurrentSettings()
    }

    // MARK: - Fine-grained setters

    func setType(_ type: SamplerFilterType) {
        currentSettings.type = type
        syncNodeFromCurrentSettings()
    }

    /// Approximate pole-count via bandwidth adjustment.
    ///
    /// This is NOT a correct pole count. `AVAudioUnitEQ` does not expose slope
    /// order. Narrower bandwidth → steeper perceived roll-off (perceptual stand-in
    /// only). A custom AUAudioUnit subclass will replace this in a future plan.
    func setPoles(_ poles: SamplerFilterPoles) {
        currentSettings.poles = poles
        syncNodeFromCurrentSettings()
    }

    func setCutoff(hz: Double) {
        currentSettings.cutoffHz = hz
        syncNodeFromCurrentSettings()
    }

    /// Map normalized resonance (0..1) to a gain bump on the EQ band.
    ///
    /// For LP/HP/BP a positive gain at the cutoff frequency produces a
    /// resonant peak. For notch (.parametric with gain=-40), resonance narrows
    /// the notch by reducing bandwidth.
    func setResonance(_ normalized: Double) {
        currentSettings.resonance = normalized
        syncNodeFromCurrentSettings()
    }

    /// Map normalized drive (0..1) to a global output gain boost.
    ///
    /// v1: `globalGain += drive * 12 dB`. Not a saturation stage.
    func setDrive(_ normalized: Double) {
        currentSettings.drive = normalized
        syncNodeFromCurrentSettings()
    }

    // MARK: - Private

    private func configureDefaultBand() {
        currentSettings = .init()
        syncNodeFromCurrentSettings()
    }

    private func syncNodeFromCurrentSettings() {
        currentSettings = currentSettings.clamped()

        switch currentSettings.type {
        case .lowpass:
            band.filterType = .lowPass
        case .highpass:
            band.filterType = .highPass
        case .bandpass:
            band.filterType = .bandPass
        case .notch:
            band.filterType = .parametric
        }

        band.frequency = Float(currentSettings.cutoffHz)

        if currentSettings.type == .notch {
            // Notch is implemented as a very-deep parametric band. Resonance
            // narrows the cut by tightening the bandwidth.
            band.gain = -40
            band.bandwidth = Float(0.5 - currentSettings.resonance * 0.45)
        } else {
            switch currentSettings.poles {
            case .one:
                band.bandwidth = 1.0    // wide — gentle roll-off (≈ 6 dB/oct feel)
            case .two:
                band.bandwidth = 0.5   // default — moderate roll-off (≈ 12 dB/oct feel)
            case .four:
                band.bandwidth = 0.15  // tight — steep roll-off (≈ 24 dB/oct feel)
            }

            // LP/HP/BP: resonance adds a gain bump at the cutoff. Some
            // `AVAudioUnitEQ` filter modes do not reflect this property back
            // reliably until attached to an engine, so `currentSettings`
            // remains the source of truth for tests and UI state.
            band.gain = Float(currentSettings.resonance * 18)
        }

        band.bypass = false

        let isNeutralDefault =
            currentSettings.type == .lowpass &&
            currentSettings.poles == .two &&
            abs(currentSettings.cutoffHz - 20_000) <= 0.001 &&
            abs(currentSettings.resonance) <= 0.000_001 &&
            abs(currentSettings.drive) <= 0.000_001

        MainActor.assumeIsolated {
            avNode.bypass = isNeutralDefault
            avNode.globalGain = Float(currentSettings.drive * 12)  // 0..12 dB
        }
    }
}
