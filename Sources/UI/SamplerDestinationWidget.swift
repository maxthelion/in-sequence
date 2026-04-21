import SwiftUI

struct SamplerDestinationWidget: View {
    @Binding var destination: Destination       // precondition: .sample
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink

    @State private var isAuditioning = false
    @State private var auditionTask: Task<Void, Never>?

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
                Text(String(format: "%+.1f dB", currentSettings.gain))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
            }
            Slider(value: gainBinding, in: -60...12) { editing in
                if !editing, abs(currentSettings.gain) < 0.5 {
                    updateGain(0)
                }
            }
        }
    }

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
            get: { currentSettings.gain },
            set: { updateGain($0) }
        )
    }

    private func updateGain(_ value: Double) {
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
