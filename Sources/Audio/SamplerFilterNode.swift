import AVFoundation

protocol SamplerFilterControlling: AnyObject {
    func apply(_ settings: SamplerFilterSettings)
    func setType(_ type: SamplerFilterType)
    func setPoles(_ poles: SamplerFilterPoles)
    func setCutoff(hz: Double)
    func setResonance(_ normalized: Double)
    func setDrive(_ normalized: Double)
}

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
final class SamplerFilterNode: SamplerFilterControlling {

    // MARK: - Public node

    /// The underlying EQ node to attach to an `AVAudioEngine`.
    let avNode: AVAudioUnitEQ
    private var settings = SamplerFilterSettings()

    // MARK: - Init

    init() {
        avNode = Self.performOnMain {
            AVAudioUnitEQ(numberOfBands: 1)
        }
        Self.performOnMain { [self] in
            applyCurrentSettingsOnMain()
        }
    }

    // MARK: - Apply full settings

    /// Apply all five filter parameters at once.
    /// Use fine-grained setters from `TrackMacroApplier` when only one value changes per step.
    func apply(_ settings: SamplerFilterSettings) {
        let resolved = settings.clamped()
        Self.performOnMain { [self] in
            self.settings = resolved
            applyCurrentSettingsOnMain()
        }
    }

    // MARK: - Fine-grained setters

    func setType(_ type: SamplerFilterType) {
        Self.performOnMain { [self] in
            settings.type = type
            applyCurrentSettingsOnMain()
        }
    }

    /// Approximate pole-count via bandwidth adjustment.
    ///
    /// This is NOT a correct pole count. `AVAudioUnitEQ` does not expose slope
    /// order. Narrower bandwidth → steeper perceived roll-off (perceptual stand-in
    /// only). A custom AUAudioUnit subclass will replace this in a future plan.
    func setPoles(_ poles: SamplerFilterPoles) {
        Self.performOnMain { [self] in
            settings.poles = poles
            applyCurrentSettingsOnMain()
        }
    }

    func setCutoff(hz: Double) {
        let clamped = min(max(hz, 20), 20_000)
        Self.performOnMain { [self] in
            settings.cutoffHz = clamped
            applyCurrentSettingsOnMain()
        }
    }

    /// Map normalized resonance (0..1) to a gain bump on the EQ band.
    ///
    /// For LP/HP/BP a positive gain at the cutoff frequency produces a
    /// resonant peak. For notch (.parametric with gain=-40), resonance narrows
    /// the notch by reducing bandwidth.
    func setResonance(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)
        Self.performOnMain { [self] in
            settings.resonance = clamped
            applyCurrentSettingsOnMain()
        }
    }

    /// Map normalized drive (0..1) to a global output gain boost.
    ///
    /// v1: `globalGain += drive * 12 dB`. Not a saturation stage.
    func setDrive(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)
        Self.performOnMain { [self] in
            settings.drive = clamped
            applyCurrentSettingsOnMain()
        }
    }

    // MARK: - Private

    @MainActor
    private func applyCurrentSettingsOnMain() {
        let resolved = settings.clamped()
        settings = resolved
        let band = avNode.bands[0]

        switch resolved.type {
        case .lowpass:
            band.filterType = .lowPass
            band.gain = Float(resolved.resonance * 18)
            band.bandwidth = bandwidth(for: resolved.poles)
        case .highpass:
            band.filterType = .highPass
            band.gain = Float(resolved.resonance * 18)
            band.bandwidth = bandwidth(for: resolved.poles)
        case .bandpass:
            band.filterType = .bandPass
            band.gain = Float(resolved.resonance * 18)
            band.bandwidth = bandwidth(for: resolved.poles)
        case .notch:
            // Notch is implemented as a very-deep parametric band.
            band.filterType = .parametric
            band.gain = -40
            band.bandwidth = notchBandwidth(for: resolved.resonance)
        }

        band.frequency = Float(resolved.cutoffHz)
        avNode.globalGain = Float(resolved.drive * 12)
        band.bypass = isBypassTransparent(resolved)

        if band.bypass {
            band.filterType = .lowPass
            band.frequency = 20_000
            band.bandwidth = bandwidth(for: .two)
            band.gain = 0
            avNode.globalGain = 0
        }
    }

    private func isBypassTransparent(_ settings: SamplerFilterSettings) -> Bool {
        settings.type == .lowpass &&
        settings.cutoffHz >= 20_000 &&
        settings.resonance == 0 &&
        settings.drive == 0
    }

    private func bandwidth(for poles: SamplerFilterPoles) -> Float {
        switch poles {
        case .one:
            return 1.0
        case .two:
            return 0.5
        case .four:
            return 0.15
        }
    }

    private func notchBandwidth(for resonance: Double) -> Float {
        Float(0.5 - resonance * 0.45)
    }

    private static func performOnMain<T>(_ work: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                work()
            }
        }

        var result: T?
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                work()
            }
        }
        return result!
    }
}
