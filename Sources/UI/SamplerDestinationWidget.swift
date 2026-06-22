import SwiftUI

struct SamplerDestinationWidget: View {
    @Binding var destination: Destination       // precondition: .sample
    let library: AudioSampleLibrary
    /// Kept for audition playback only. Filter writes go through the `filterSettings`
    /// binding so the session can dispatch to the engine via `.scopedRuntime(.filter(...))`.
    let sampleEngine: SamplePlaybackSink
    let trackID: UUID
    @Binding var filterSettings: SamplerFilterSettings
    var onManageMacros: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var isAuditioning = false
    @State private var auditionTask: Task<Void, Never>?

    private let ampKnobColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let filterKnobColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var currentSampleID: UUID? {
        if case let .sample(id, _) = destination { return id }
        return nil
    }

    private var currentSettings: SamplerSettings {
        if case let .sample(_, settings) = destination { return settings }
        return .default
    }

    private var currentSample: AudioSample? {
        guard let id = currentSampleID else { return nil }
        return library.sample(id: id)
    }

    private var peers: [AudioSample] {
        guard let category = currentSample?.category else { return [] }
        return library.samples(in: category)
    }

    var body: some View {
        Group {
            if let sample = currentSample {
                sampleCard(sample: sample)
            } else {
                orphanCard
            }
        }
    }

    private func sampleCard(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(sample: sample)
            divider
            sampleBody(sample: sample)
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Side-by-side layout: the waveform browser sits on the left at a flexible
    /// width, the knob grid and filter controls stack on the right. Wrapping is
    /// handled by ViewThatFits so narrow widths fall back to a vertical column.
    private func sampleBody(sample: AudioSample) -> some View {
        ViewThatFits(in: .horizontal) {
            horizontalBody(sample: sample)
            verticalBody(sample: sample)
        }
    }

    private func horizontalBody(sample: AudioSample) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                waveformSection(sample: sample)
                divider
                ampKnobSection
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)

            verticalDivider

            VStack(alignment: .leading, spacing: 0) {
                filterKnobSection
                divider
                filterSection
            }
            .frame(minWidth: 260, maxWidth: 400, alignment: .topLeading)
        }
    }

    private func verticalBody(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            waveformSection(sample: sample)
            divider
            ampKnobSection
            divider
            filterKnobSection
            divider
            filterSection
        }
    }

    private func header(sample: AudioSample) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(sampleDetail(sample))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            StudioCircleIconButton(
                systemName: "slider.horizontal.3",
                size: StudioMetrics.ControlSize.medium,
                help: "View built-in sampler macros",
                action: onManageMacros
            )

            StudioCircleIconButton(
                systemName: isAuditioning ? "stop.fill" : "play.fill",
                size: StudioMetrics.ControlSize.medium,
                help: isAuditioning ? "Stop audition" : "Audition sample"
            ) {
                toggleAudition(sample: sample)
            }

            StudioCircleIconButton(
                systemName: "xmark",
                size: StudioMetrics.ControlSize.medium,
                help: "Remove this sample destination",
                action: onRemove
            )
        }
        .padding(StudioMetrics.Spacing.standard)
    }

    private func waveformSection(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            waveform(sample: sample)

            HStack(spacing: 8) {
                StudioCircleIconButton(
                    systemName: "chevron.left",
                    isEnabled: peers.count >= 2,
                    help: "Previous sample in category"
                ) {
                    stepSample(-1)
                }

                Spacer()

                Text("Browse \(sample.category.displayName.lowercased())")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                StudioCircleIconButton(
                    systemName: "chevron.right",
                    isEnabled: peers.count >= 2,
                    help: "Next sample in category"
                ) {
                    stepSample(+1)
                }
            }
        }
        .frame(alignment: .top)
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private func waveform(sample: AudioSample) -> some View {
        let url = (try? sample.fileRef.resolve(libraryRoot: library.libraryRoot)) ?? URL(fileURLWithPath: "/dev/null")
        let buckets = WaveformDownsampler.downsample(url: url, bucketCount: 64)
        let start = currentSettings.start.clamped(to: 0...1)
        let stop = (currentSettings.start + currentSettings.length).clamped(to: 0...1)
        return WaveformView(buckets: buckets)
            .frame(height: 120)
            .overlay(
                WaveformRegionMarkers(start: start, stop: stop)
            )
            .padding(StudioMetrics.Spacing.snug)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip).stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
    }

    /// Playback / amp controls laid out as a horizontal row beneath the waveform.
    private var ampKnobSection: some View {
        LazyVGrid(columns: ampKnobColumns, alignment: .leading, spacing: 16) {
            SamplerParameterKnob(
                label: "Start",
                normalizedValue: currentSettings.start,
                displayText: percentLabel(currentSettings.start)
            ) { normalized in
                commitStart(normalized)
            }

            SamplerParameterKnob(
                label: "Length",
                normalizedValue: currentSettings.length,
                displayText: percentLabel(currentSettings.length)
            ) { normalized in
                commitLength(normalized)
            }

            SamplerParameterKnob(
                label: "Gain",
                normalizedValue: normalizedGain,
                displayText: gainLabel(currentSettings.gain)
            ) { normalized in
                commitGain(gainFromNormalized(normalized))
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    /// Filter knobs (Cutoff / Reso / Drive) shown atop the right-hand filter column.
    private var filterKnobSection: some View {
        LazyVGrid(columns: filterKnobColumns, alignment: .leading, spacing: 16) {
            SamplerParameterKnob(
                label: "Cutoff",
                normalizedValue: normalizedCutoff(filterSettings.cutoffHz),
                displayText: cutoffLabel(filterSettings.cutoffHz)
            ) { normalized in
                onCutoffChanged(cutoffFromNormalized(normalized))
            }

            SamplerParameterKnob(
                label: "Reso",
                normalizedValue: filterSettings.resonance,
                displayText: percentLabel(filterSettings.resonance)
            ) { normalized in
                onResoChanged(normalized)
            }

            SamplerParameterKnob(
                label: "Drive",
                normalizedValue: filterSettings.drive,
                displayText: percentLabel(filterSettings.drive)
            ) { normalized in
                onDriveChanged(normalized)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterCurveView(settings: filterSettings)
                .frame(height: 64)
                .padding(StudioMetrics.Spacing.snug)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
                .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip).stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))

            optionRow(
                title: "Filter Type",
                options: SamplerFilterType.allCases,
                selection: filterSettings.type,
                titleForOption: Self.filterTypeLabel,
                onSelect: onTypeChanged
            )

            optionRow(
                title: "Poles",
                options: SamplerFilterPoles.allCases,
                selection: filterSettings.poles,
                titleForOption: { option in
                    switch option {
                    case .one: return "1"
                    case .two: return "2"
                    case .four: return "4"
                    }
                },
                onSelect: onPolesChanged
            )
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var orphanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing sample")
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)

                    Text("Sample \(currentSampleID?.uuidString.prefix(8) ?? "—") is not in the library.")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                StudioCircleIconButton(
                    systemName: "xmark",
                    size: StudioMetrics.ControlSize.medium,
                    help: "Remove this sample destination",
                    action: onRemove
                )
            }
            .padding(StudioMetrics.Spacing.standard)

            divider

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose another sample or remove the destination.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                Button("Replace with first available sample") {
                    replaceWithFirstInCurrentCategory()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
            }
            .padding(StudioMetrics.Spacing.comfortable)
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var divider: some View {
        Divider()
            .overlay(StudioTheme.border.opacity(0.7))
    }

    private var verticalDivider: some View {
        Divider()
            .overlay(StudioTheme.border.opacity(0.7))
    }

    private func sampleDetail(_ sample: AudioSample) -> String {
        let lengthLabel = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "—"
        return "\(sample.category.displayName) • \(lengthLabel)"
    }

    private func optionRow<Option: Hashable & Sendable>(
        title: String,
        options: [Option],
        selection: Option,
        titleForOption: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(titleForOption(option)) {
                        onSelect(option)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selection == option ? StudioTheme.text : StudioTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        (selection == option ? StudioTheme.cyan.opacity(0.18) : Color.white.opacity(StudioOpacity.subtleFill)),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(selection == option ? StudioTheme.cyan.opacity(0.7) : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                    )
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var normalizedGain: Double {
        min(max((currentSettings.gain + 60) / 72, 0), 1)
    }

    private func gainFromNormalized(_ normalized: Double) -> Double {
        (normalized * 72) - 60
    }

    private func normalizedCutoff(_ hz: Double) -> Double {
        let clamped = min(max(hz, 20), 20_000)
        let minLog = log10(20.0)
        let maxLog = log10(20_000.0)
        return (log10(clamped) - minLog) / (maxLog - minLog)
    }

    private func cutoffFromNormalized(_ normalized: Double) -> Double {
        let minLog = log10(20.0)
        let maxLog = log10(20_000.0)
        let value = minLog + min(max(normalized, 0), 1) * (maxLog - minLog)
        return pow(10, value)
    }

    private func percentLabel(_ normalized: Double) -> String {
        "\(Int((min(max(normalized, 0), 1) * 100).rounded()))%"
    }

    private func gainLabel(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func cutoffLabel(_ hz: Double) -> String {
        let clamped = min(max(hz, 20), 20_000)
        if clamped >= 1000 {
            return String(format: "%.1fk", clamped / 1000)
        }
        return "\(Int(clamped.rounded()))"
    }

    private func updateSettings(_ mutate: (inout SamplerSettings) -> Void) {
        guard case let .sample(id, settings) = destination else { return }
        var next = settings
        mutate(&next)
        destination = .sample(sampleID: id, settings: next.clamped())
    }

    // MARK: - Filter type label

    static func filterTypeLabel(_ option: SamplerFilterType) -> String {
        switch option {
        case .lowpass: return "LP"
        case .highpass: return "HP"
        case .bandpass: return "BP"
        case .notch: return "Notch"
        case .peak: return "Peak"
        case .comb: return "Comb"
        case .formant: return "Formant"
        }
    }

    // MARK: - Filter change handlers

    func onCutoffChanged(_ hz: Double) {
        filterSettings.cutoffHz = hz.clamped(to: 20...20_000)
    }

    func onResoChanged(_ value: Double) {
        filterSettings.resonance = value.clamped(to: 0...1)
    }

    func onDriveChanged(_ value: Double) {
        filterSettings.drive = value.clamped(to: 0...1)
    }

    func onTypeChanged(_ type: SamplerFilterType) {
        filterSettings.type = type
    }

    func onPolesChanged(_ poles: SamplerFilterPoles) {
        filterSettings.poles = poles
    }

    private func commitStart(_ value: Double) {
        updateSettings { settings in
            settings.start = value.clamped(to: 0...1)
        }
    }

    private func commitLength(_ value: Double) {
        updateSettings { settings in
            settings.length = value.clamped(to: 0...1)
        }
    }

    private func commitGain(_ value: Double) {
        let snapped = abs(value) < 0.5 ? 0 : value
        updateSettings { settings in
            settings.gain = snapped
        }
    }

    private func stepSample(_ delta: Int) {
        guard let id = currentSampleID else { return }
        let next: AudioSample? = delta > 0 ? library.nextSample(after: id) : library.previousSample(before: id)
        guard let next else { return }
        destination = .sample(sampleID: next.id, settings: currentSettings)
    }

    private func toggleAudition(sample: AudioSample) {
        auditionTask?.cancel()
        if isAuditioning {
            sampleEngine.stopAudition()
            isAuditioning = false
            return
        }
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else { return }
        sampleEngine.audition(sampleURL: url)
        isAuditioning = true
        let duration = sample.lengthSeconds ?? 1.0
        auditionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((duration + 0.05) * 1000)))
            if !Task.isCancelled {
                isAuditioning = false
            }
        }
    }

    private func replaceWithFirstInCurrentCategory() {
        let fallback = library.firstSample(in: .kick) ?? library.samples.first
        guard let replacement = fallback else { return }
        destination = .sample(sampleID: replacement.id, settings: currentSettings)
    }
}

struct SamplerParameterKnob: View {
    let label: String
    let normalizedValue: Double
    let displayText: String
    let onCommit: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    private let knobSize: CGFloat = 42
    private let dragSensitivity: Double = 220

    init(
        label: String,
        normalizedValue: Double,
        displayText: String,
        onCommit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.normalizedValue = normalizedValue
        self.displayText = displayText
        self.onCommit = onCommit
        _displayValue = State(initialValue: normalizedValue)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border, lineWidth: 2)
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * displayValue.clamped(to: 0...1))
                    .stroke(StudioTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: knobSize - 6, height: knobSize - 6)
                    .rotationEffect(.degrees(-90))

                Text(displayText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = displayValue
                        }
                        let delta = -drag.translation.height / dragSensitivity
                        let nextValue = (dragStartValue ?? displayValue) + delta
                        displayValue = nextValue.clamped(to: 0...1)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        onCommit(displayValue)
                    }
            )

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: knobSize + 26)
        }
        .onChange(of: normalizedValue) { _, newValue in
            if dragStartValue == nil {
                displayValue = newValue.clamped(to: 0...1)
            }
        }
    }
}

/// A simple frequency-response visualization for the sampler filter.
///
/// Draws a normalized magnitude curve across the audible band (20 Hz–20 kHz on
/// a log axis) whose shape reflects the filter type, cutoff and resonance. This
/// is an illustrative response, not a measured one.
private struct FilterCurveView: View {
    let settings: SamplerFilterSettings

    private let sampleCount = 96

    var body: some View {
        Canvas { context, size in
            let path = curvePath(in: size)

            // Fill under the curve.
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(StudioTheme.cyan.opacity(0.14)))

            // Stroke the curve.
            context.stroke(
                path,
                with: .color(StudioTheme.cyan),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func curvePath(in size: CGSize) -> Path {
        var path = Path()
        guard size.width > 0, size.height > 0 else { return path }

        for index in 0...sampleCount {
            let fraction = Double(index) / Double(sampleCount)
            let magnitude = magnitude(atNormalizedFrequency: fraction)
            let x = CGFloat(fraction) * size.width
            let y = CGFloat(1 - magnitude) * size.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    /// Normalized response magnitude in 0...1 at a normalized (log) frequency
    /// position `x` (0 = 20 Hz, 1 = 20 kHz).
    private func magnitude(atNormalizedFrequency x: Double) -> Double {
        let cutoffX = normalizedFrequency(settings.cutoffHz)
        let resonance = settings.resonance.clamped(to: 0...1)
        // Steepness of the transition; resonance sharpens the slope.
        let width = 0.10 + (1 - resonance) * 0.18
        let peak = resonance * 0.45 // resonant bump height

        switch settings.type {
        case .lowpass:
            let roll = sigmoid((cutoffX - x) / width)
            let bump = peakBump(x, center: cutoffX, height: peak, width: 0.05)
            return clamp01(roll * 0.85 + bump)
        case .highpass:
            let roll = sigmoid((x - cutoffX) / width)
            let bump = peakBump(x, center: cutoffX, height: peak, width: 0.05)
            return clamp01(roll * 0.85 + bump)
        case .bandpass, .comb, .formant:
            let band = peakBump(x, center: cutoffX, height: 0.85, width: width)
            let bump = peakBump(x, center: cutoffX, height: peak, width: 0.04)
            return clamp01(band + bump)
        case .notch:
            let dip = peakBump(x, center: cutoffX, height: 0.85 - peak * 0.3, width: width * 0.8)
            return clamp01(0.85 - dip)
        case .peak:
            let base = 0.45
            let bump = peakBump(x, center: cutoffX, height: 0.4 + peak, width: width)
            return clamp01(base + bump)
        }
    }

    private func normalizedFrequency(_ hz: Double) -> Double {
        let clamped = min(max(hz, 20), 20_000)
        let minLog = log10(20.0)
        let maxLog = log10(20_000.0)
        return (log10(clamped) - minLog) / (maxLog - minLog)
    }

    private func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value * 6))
    }

    private func peakBump(_ x: Double, center: Double, height: Double, width: Double) -> Double {
        let safeWidth = max(width, 0.0001)
        let d = (x - center) / safeWidth
        return height * exp(-d * d)
    }

    private func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Vertical start / stop markers overlaid on the waveform. `start` and `stop`
/// are fractions (0...1) of the waveform width, driven by the Start and
/// Start+Length sampler settings. The region between them is lightly shaded.
private struct WaveformRegionMarkers: View {
    let start: Double
    let stop: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let startX = CGFloat(min(max(start, 0), 1)) * width
            let stopX = CGFloat(min(max(stop, 0), 1)) * width

            ZStack(alignment: .topLeading) {
                // Shaded active region between start and stop.
                Rectangle()
                    .fill(StudioTheme.cyan.opacity(0.10))
                    .frame(width: max(0, stopX - startX), height: height)
                    .offset(x: startX)

                marker(at: startX, height: height)
                marker(at: stopX, height: height)
            }
        }
    }

    private func marker(at x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(StudioTheme.cyan)
            .frame(width: 2, height: height)
            .offset(x: x - 1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
