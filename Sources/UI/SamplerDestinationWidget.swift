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

    private let knobColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

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
            waveformSection(sample: sample)
            divider
            knobSection
            divider
            filterSection
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
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

            compactIconButton(
                systemName: "slider.horizontal.3",
                help: "View built-in sampler macros",
                action: onManageMacros
            )

            compactIconButton(
                systemName: isAuditioning ? "stop.fill" : "play.fill",
                help: isAuditioning ? "Stop audition" : "Audition sample"
            ) {
                toggleAudition(sample: sample)
            }

            compactIconButton(
                systemName: "xmark",
                help: "Remove this sample destination",
                action: onRemove
            )
        }
        .padding(14)
    }

    private func waveformSection(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            waveform(sample: sample)

            HStack(spacing: 8) {
                browseButton(systemName: "chevron.left", help: "Previous sample in category") {
                    stepSample(-1)
                }
                .disabled(peers.count < 2)

                Spacer()

                Text("Browse \(sample.category.displayName.lowercased())")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                browseButton(systemName: "chevron.right", help: "Next sample in category") {
                    stepSample(+1)
                }
                .disabled(peers.count < 2)
            }
        }
        .padding(12)
    }

    private func waveform(sample: AudioSample) -> some View {
        let url = (try? sample.fileRef.resolve(libraryRoot: library.libraryRoot)) ?? URL(fileURLWithPath: "/dev/null")
        let buckets = WaveformDownsampler.downsample(url: url, bucketCount: 64)
        return WaveformView(buckets: buckets)
            .frame(height: 60)
            .padding(8)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip).stroke(StudioTheme.border, lineWidth: 1))
    }

    private var knobSection: some View {
        LazyVGrid(columns: knobColumns, alignment: .leading, spacing: 16) {
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
        .padding(12)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionRow(
                title: "Filter Type",
                options: SamplerFilterType.allCases,
                selection: filterSettings.type,
                titleForOption: { option in
                    switch option {
                    case .lowpass: return "LP"
                    case .highpass: return "HP"
                    case .bandpass: return "BP"
                    case .notch: return "Notch"
                    }
                },
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
        .padding(12)
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

                compactIconButton(
                    systemName: "xmark",
                    help: "Remove this sample destination",
                    action: onRemove
                )
            }
            .padding(14)

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
            .padding(12)
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var divider: some View {
        Divider()
            .overlay(StudioTheme.border.opacity(0.7))
    }

    private func sampleDetail(_ sample: AudioSample) -> String {
        let lengthLabel = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "—"
        return "\(sample.category.displayName) • \(lengthLabel)"
    }

    private func browseButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(
                    Circle()
                        .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func compactIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(
                    Circle()
                        .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
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
                            .stroke(selection == option ? StudioTheme.cyan.opacity(0.7) : StudioTheme.border.opacity(0.8), lineWidth: 1)
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

private struct SamplerParameterKnob: View {
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
