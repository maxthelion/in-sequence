import AVFoundation
import SwiftUI

struct SlicerSourceWidget: View {
    @Binding var destination: Destination
    let sliceSet: SliceSet?
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink
    let trackID: UUID
    var onInstallSliceSet: (SliceSet, SlicerSettings) -> Void
    var onUpdateSliceSet: (SliceSet, Int64) -> Void
    var onManageMacros: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var analysisMessage: String?
    @State private var showingWaveformEditor = false

    private let sliceColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    private var currentSliceSetID: UUID {
        if case let .slicer(sliceSetID, _) = destination {
            return sliceSetID
        }
        return SliceSet.emptyID
    }

    private var currentSettings: SlicerSettings {
        if case let .slicer(_, settings) = destination {
            return settings
        }
        return .default
    }

    private var effectiveSliceSet: SliceSet {
        sliceSet ?? SliceSet.empty
    }

    private var currentSample: AudioSample? {
        guard let sampleID = effectiveSliceSet.sampleID else {
            return nil
        }
        return library.sample(id: sampleID)
    }

    private var sampleChoices: [AudioSample] {
        library.samples.sorted { lhs, rhs in
            if lhs.category.displayName == rhs.category.displayName {
                return lhs.name < rhs.name
            }
            return lhs.category.displayName < rhs.category.displayName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider

            if let sample = currentSample {
                waveformSection(sample: sample)
                divider
                sliceGrid(sample: sample)
                divider
                settingsSection
            } else {
                emptyState
            }
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .sheet(isPresented: $showingWaveformEditor) {
            if let sample = currentSample {
                SlicerWaveformWindow(
                    sliceSet: effectiveSliceSet,
                    sample: sample,
                    library: library,
                    onCommit: commitEditedSliceSet
                )
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StudioTheme.cyan)
                .frame(width: 28, height: 28)
                .background(StudioTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(currentSample?.name ?? "Choose a loop")
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(headerDetail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(sampleChoices) { sample in
                    Button("\(sample.category.displayName) • \(sample.name)") {
                        install(sample: sample, mode: .grid)
                    }
                }
            } label: {
                Label("Choose", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .help("Choose sample")
            .disabled(sampleChoices.isEmpty)

            compactIconButton(systemName: "slider.horizontal.3", help: "View built-in slicer macros", action: onManageMacros)
            compactIconButton(systemName: "xmark", help: "Remove this slicer destination", action: onRemove)
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a sample to create a slice set for this track.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)

            if sampleChoices.isEmpty {
                Text("The sample library is empty.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(sampleChoices.prefix(12)) { sample in
                        Button {
                            install(sample: sample, mode: .grid)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.name)
                                    .studioText(.labelBold)
                                    .foregroundStyle(StudioTheme.text)
                                    .lineLimit(1)
                                Text(sample.category.displayName)
                                    .studioText(.label)
                                    .foregroundStyle(StudioTheme.mutedText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip)
                                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .padding(12)
    }

    private func waveformSection(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SlicerWaveformView(
                buckets: waveformBuckets(sample: sample),
                sliceSet: effectiveSliceSet,
                sampleLengthFrames: sampleLengthFrames(sample: sample),
                selectedMarkerID: nil,
                onBoundaryMove: nil
            )
            .frame(height: 72)
            .padding(8)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
            )

            HStack(spacing: 8) {
                modeButton(.grid, title: "Grid") {
                    reanalyze(sample: sample, mode: .grid)
                }
                modeButton(.transient, title: "Transient") {
                    reanalyze(sample: sample, mode: .transient)
                }

                Spacer()

                Button {
                    showingWaveformEditor = true
                } label: {
                    Label("Edit", systemImage: "waveform")
                }
                .buttonStyle(.bordered)
            }

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .padding(12)
    }

    private func sliceGrid(sample: AudioSample) -> some View {
        LazyVGrid(columns: sliceColumns, alignment: .leading, spacing: 8) {
            ForEach(Array(effectiveSliceSet.markers.enumerated()), id: \.element.id) { index, marker in
                Button {
                    audition(marker: marker, sample: sample)
                } label: {
                    VStack(spacing: 5) {
                        Text(index == 0 ? "All" : "\(index)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                        Text(sliceDurationLabel(marker: marker, sample: sample))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(index == 0 ? StudioTheme.violet.opacity(0.18) : StudioTheme.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(index == 0 ? StudioTheme.violet.opacity(0.65) : StudioTheme.cyan.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Audition slice \(index)")
            }
        }
        .padding(12)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SlicerControlField(title: "Gain") {
                    Slider(
                        value: Binding(
                            get: { currentSettings.gain },
                            set: { value in updateSettings { $0.gain = value } }
                        ),
                        in: -60...12
                    )
                    Text(String(format: "%+.1f dB", currentSettings.gain))
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                }

                SlicerControlField(title: "Transpose") {
                    Stepper(value: Binding(
                        get: { currentSettings.transpose },
                        set: { value in updateSettings { $0.transpose = value } }
                    ), in: -48...48) {
                        Text("\(currentSettings.transpose > 0 ? "+" : "")\(currentSettings.transpose) st")
                            .studioText(.bodyEmphasis)
                            .foregroundStyle(StudioTheme.text)
                    }
                }

                SlicerControlField(title: "Voice") {
                    Picker("Voice", selection: Binding(
                        get: { currentSettings.voiceMode },
                        set: { value in updateSettings { $0.voiceMode = value } }
                    )) {
                        Text("Mono").tag(SlicerVoiceMode.mono)
                        Text("Poly").tag(SlicerVoiceMode.polyphonic)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(12)
    }

    private var headerDetail: String {
        guard let sample = currentSample else {
            return "Slicer destination"
        }
        let length = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        return "\(sample.category.displayName) • \(length) • \(max(0, effectiveSliceSet.markers.count - 1)) slices"
    }

    private var divider: some View {
        Divider().overlay(StudioTheme.border.opacity(0.7))
    }

    private func modeButton(_ mode: SliceMode, title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(effectiveSliceSet.mode == mode ? StudioTheme.text : StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(effectiveSliceSet.mode == mode ? StudioTheme.cyan.opacity(0.18) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(effectiveSliceSet.mode == mode ? StudioTheme.cyan.opacity(0.7) : StudioTheme.border.opacity(0.8), lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    private func compactIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(Circle().stroke(StudioTheme.border.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func install(sample: AudioSample, mode: SliceMode) {
        guard let set = analyzedSliceSet(sample: sample, mode: mode) else {
            analysisMessage = "Could not analyse \(sample.name)."
            return
        }
        analysisMessage = nil
        onInstallSliceSet(set, currentSettings)
    }

    private func reanalyze(sample: AudioSample, mode: SliceMode) {
        guard var set = analyzedSliceSet(sample: sample, mode: mode) else {
            analysisMessage = "Could not analyse \(sample.name)."
            return
        }
        set.id = currentSliceSetID == SliceSet.emptyID ? set.id : currentSliceSetID
        analysisMessage = nil
        onUpdateSliceSet(set, sampleLengthFrames(sample: sample))
    }

    private func analyzedSliceSet(sample: AudioSample, mode: SliceMode) -> SliceSet? {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return nil
        }
        let markers: [SliceMarker]
        switch mode {
        case .grid:
            markers = SliceAnalyzer.gridSlices(file: file, divisions: 16)
        case .transient:
            markers = SliceAnalyzer.transientSlices(file: file)
        case .manual:
            markers = [SliceMarker(startFrame: 0, endFrame: file.length)]
        }
        var set = SliceSet(sampleID: sample.id, markers: markers, mode: mode, bars: 1)
        set.normalize(sampleLengthFrames: file.length)
        return set
    }

    private func commitEditedSliceSet(_ next: SliceSet) {
        guard let sample = currentSample else { return }
        onUpdateSliceSet(next, sampleLengthFrames(sample: sample))
    }

    private func waveformBuckets(sample: AudioSample) -> [Float] {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else {
            return Array(repeating: 0, count: 96)
        }
        return WaveformDownsampler.downsample(url: url, bucketCount: 96)
    }

    private func sampleLengthFrames(sample: AudioSample) -> Int64 {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return effectiveSliceSet.markers.first?.endFrame ?? 0
        }
        return file.length
    }

    private func sliceDurationLabel(marker: SliceMarker, sample: AudioSample) -> String {
        let frameRate = sampleFrameRate(sample: sample)
        guard frameRate > 0 else { return "--" }
        let seconds = Double(max(0, marker.endFrame - marker.startFrame)) / frameRate
        return String(format: "%.2fs", seconds)
    }

    private func sampleFrameRate(sample: AudioSample) -> Double {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return 44_100
        }
        return file.processingFormat.sampleRate
    }

    private func audition(marker: SliceMarker, sample: AudioSample) {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              marker.endFrame > marker.startFrame
        else {
            return
        }
        _ = sampleEngine.playSlice(
            sampleURL: url,
            startFrame: AVAudioFramePosition(marker.startFrame),
            endFrame: AVAudioFramePosition(marker.endFrame),
            settings: SlicerSettings(
                gain: currentSettings.gain + marker.gain,
                transpose: currentSettings.transpose,
                voiceMode: currentSettings.voiceMode
            ).clamped,
            trackID: trackID,
            at: nil,
            reverse: marker.reverse
        )
    }

    private func updateSettings(_ mutate: (inout SlicerSettings) -> Void) {
        guard case let .slicer(sliceSetID, settings) = destination else { return }
        var next = settings
        mutate(&next)
        destination = .slicer(sliceSetID: sliceSetID, settings: next.clamped)
    }
}
