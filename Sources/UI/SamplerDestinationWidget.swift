import SwiftUI

struct SamplerDestinationWidget: View {
    @Binding var destination: Destination       // precondition: .sample
    let library: AudioSampleLibrary
    /// Kept for audition playback only. Filter writes go through the `filterSettings`
    /// binding so the session can dispatch to the engine via `.scopedRuntime(.filter(...))`.
    let sampleEngine: SamplePlaybackSink
    let trackID: UUID
    @Binding var filterSettings: SamplerFilterSettings

    @State private var isAuditioning = false
    @State private var auditionTask: Task<Void, Never>?
    @StateObject private var gainControl = ThrottledMixValue()

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
        VStack(alignment: .leading, spacing: 12) {
            if let sample = currentSample {
                header(sample: sample)
                waveform(sample: sample)
                controls(sample: sample)
                gainSlider
                filterRow
            } else {
                orphanTile
            }
        }
    }

    private func header(sample: AudioSample) -> some View {
        HStack {
            Text(sample.name)
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
            Spacer()
            let lengthLabel = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "—"
            Text("\(sample.category.displayName) • \(lengthLabel)")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
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

    private func controls(sample: AudioSample) -> some View {
        HStack(spacing: 12) {
            Button { stepSample(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(peers.count < 2)
            Button {
                toggleAudition(sample: sample)
            } label: {
                Image(systemName: isAuditioning ? "stop.fill" : "play.fill")
                Text(isAuditioning ? "Stop" : "Audition")
            }
            Button { stepSample(+1) } label: { Image(systemName: "chevron.right") }
                .disabled(peers.count < 2)
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private var gainSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Gain")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text(String(format: "%+.1f dB", displayedGain))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
            }
            Slider(value: gainBinding, in: -60...12) { isEditing in
                handleGainEditingChanged(isEditing)
            }
        }
    }

    // MARK: - Filter row

    /// Horizontal row of filter controls: type picker, poles picker, cutoff, resonance, drive.
    ///
    /// Edits `filterSettings` directly. Calls `sampleEngine.applyFilter` on each change
    /// for immediate audio feedback. The per-step macro path keeps them in sync.
    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter")
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)
            HStack(spacing: 12) {
                filterTypePicker
                filterPolesPicker
                Spacer()
            }
            HStack(spacing: 16) {
                filterKnob(
                    label: "Cutoff",
                    value: Binding(
                        get: { filterSettings.cutoffHz / 20_000 },
                        set: { onCutoffChanged($0 * 20_000) }
                    )
                )
                filterKnob(
                    label: "Reso",
                    value: Binding(
                        get: { filterSettings.resonance },
                        set: { onResoChanged($0) }
                    )
                )
                filterKnob(
                    label: "Drive",
                    value: Binding(
                        get: { filterSettings.drive },
                        set: { onDriveChanged($0) }
                    )
                )
                Spacer()
            }
        }
    }

    private var filterTypePicker: some View {
        Picker("", selection: Binding(
            get: { filterSettings.type },
            set: { onTypeChanged($0) }
        )) {
            Text("LP").tag(SamplerFilterType.lowpass)
            Text("HP").tag(SamplerFilterType.highpass)
            Text("BP").tag(SamplerFilterType.bandpass)
            Text("Notch").tag(SamplerFilterType.notch)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
    }

    private var filterPolesPicker: some View {
        Picker("", selection: Binding(
            get: { filterSettings.poles },
            set: { onPolesChanged($0) }
        )) {
            Text("1").tag(SamplerFilterPoles.one)
            Text("2").tag(SamplerFilterPoles.two)
            Text("4").tag(SamplerFilterPoles.four)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 100)
    }

    private func filterKnob(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            Slider(value: value, in: 0...1)
                .frame(width: 80)
            Text(label)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
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

    // MARK: - Orphan

    private var orphanTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Missing sample")
                .studioText(.subtitle)
            Text("Sample \(currentSampleID?.uuidString.prefix(8) ?? "—") not in library.")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
            Button("Replace with first in category") { replaceWithFirstInCurrentCategory() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(StudioTheme.amber.opacity(StudioOpacity.mutedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control))
    }

    // MARK: - Helpers

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

    private var gainBinding: Binding<Double> {
        Binding(
            get: { displayedGain },
            set: { updateGainLive($0) }
        )
    }

    private var displayedGain: Double {
        gainControl.rendered(committed: currentSettings.gain)
    }

    private func handleGainEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !gainControl.isDragging {
                gainControl.begin(with: currentSettings.gain)
            }
            return
        }

        guard let final = gainControl.commit() else { return }
        let snapped = abs(final) < 0.5 ? 0 : final
        commitGain(snapped)
    }

    private func updateGainLive(_ value: Double) {
        if !gainControl.isDragging {
            gainControl.begin(with: currentSettings.gain)
        }
        _ = gainControl.update(value)
    }

    private func commitGain(_ value: Double) {
        guard case let .sample(id, settings) = destination else { return }
        var next = settings
        next.gain = value
        destination = .sample(sampleID: id, settings: next.clamped())
    }

    private func replaceWithFirstInCurrentCategory() {
        let fallback = library.firstSample(in: .kick) ?? library.samples.first
        guard let replacement = fallback else { return }
        destination = .sample(sampleID: replacement.id, settings: currentSettings)
    }
}

// MARK: - Comparable clamping helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
