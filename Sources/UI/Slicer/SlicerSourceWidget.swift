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
    var onApplyAnalyzedSliceSet: (SliceSet, Int64, Int) -> Void = { _, _, _ in }
    var onManageMacros: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var analysisMessage: String?
    @State private var showingWaveformEditor = false
    @State private var analysisDraft: SliceSet?
    @State private var analysisMode: SliceMode = .transient
    @State private var analysisSensitivity = 0.35
    @State private var analysisBars = 2

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

    private var displayedSliceSet: SliceSet {
        analysisDraft ?? effectiveSliceSet
    }

    private var hasUserSlices: Bool {
        effectiveSliceSet.userSliceCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider

            if let sample = currentSample {
                waveformSection(sample: sample)
                divider
                if hasUserSlices || analysisDraft != nil {
                    sliceGrid(sample: sample)
                } else {
                    noSlicesState
                }
                divider
                settingsSection
            } else {
                emptyState
            }
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .sheet(isPresented: $showingWaveformEditor) {
            if let sample = currentSample {
                SlicerWaveformWindow(
                    sliceSet: effectiveSliceSet,
                    sample: sample,
                    library: library,
                    onCommit: commitEditedSliceSet
                )
                .presentationBackground(.clear)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: 28, height: 28)
                .background(StudioTheme.cyan, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

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

            if currentSample == nil {
                Menu {
                    ForEach(sampleChoices) { sample in
                        Button("\(sample.category.displayName) • \(sample.name)") {
                            installBlank(sample: sample)
                        }
                    }
                } label: {
                    Label("Choose", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("Choose sample")
                .disabled(sampleChoices.isEmpty)
            }

            StudioCircleIconButton(
                systemName: "slider.horizontal.3",
                size: StudioMetrics.ControlSize.medium,
                help: "View built-in slicer macros",
                action: onManageMacros
            )
            StudioCircleIconButton(
                systemName: "xmark",
                size: StudioMetrics.ControlSize.medium,
                help: "Remove this slicer destination",
                action: onRemove
            )
        }
        .padding(StudioMetrics.Spacing.standard)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Canon Rule 3: no explainer prose — the sample grid below is the
            // affordance; the empty-library case shows terse state only.
            if sampleChoices.isEmpty {
                Text("Sample library empty")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .help("Pick a sample to create a slice set for this track.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(sampleChoices.prefix(12)) { sample in
                        Button {
                            installBlank(sample: sample)
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
                            .padding(StudioMetrics.Spacing.compact)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip)
                                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
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
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private func waveformSection(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SlicerWaveformView(
                buckets: waveformBuckets(sample: sample),
                sliceSet: displayedSliceSet,
                sampleLengthFrames: sampleLengthFrames(sample: sample),
                selectedMarkerID: nil,
                onBoundaryMove: nil
            )
            .frame(height: 72)
            .padding(StudioMetrics.Spacing.snug)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )

            HStack(spacing: 8) {
                Button {
                    proposeAutoSlices(sample: sample)
                } label: {
                    Label(analysisDraft == nil ? "Auto Detect" : "Refresh Detection", systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.violet)

                Spacer()

                if hasUserSlices {
                    Button {
                        showingWaveformEditor = true
                    } label: {
                        Label("Edit Markers", systemImage: "waveform")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if analysisDraft != nil {
                autoDetectControls(sample: sample)
            }

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .onChange(of: analysisMode) { _, _ in
            refreshAutoSlicesIfNeeded(sample: sample)
        }
        .onChange(of: analysisSensitivity) { _, _ in
            refreshAutoSlicesIfNeeded(sample: sample)
        }
        .onChange(of: analysisBars) { _, _ in
            refreshAutoSlicesIfNeeded(sample: sample)
        }
    }

    private func sliceGrid(sample: AudioSample) -> some View {
        LazyVGrid(columns: sliceColumns, alignment: .leading, spacing: 8) {
            ForEach(Array(displayedSliceSet.markers.enumerated()), id: \.element.id) { index, marker in
                Button {
                    audition(marker: marker, sample: sample)
                } label: {
                    VStack(spacing: 5) {
                        Text(index == 0 ? "All" : "\(index)")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                        Text(sliceDurationLabel(marker: marker, sample: sample))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    // Colour identifies, it never floods (ux-canon rule 12):
                    // pads stay neutral; kind reads from the outline colour.
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(index == 0 ? StudioTheme.violet.opacity(0.65) : StudioTheme.cyan.opacity(0.55), lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .help("Audition slice \(index)")
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var noSlicesState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No slices yet")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.comfortable)
        .help("Use Auto Detect above to preview transient markers and apply them to the clip.")
    }

    private func autoDetectControls(sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Method", selection: $analysisMode) {
                    Text("Transients").tag(SliceMode.transient)
                    Text("Grid").tag(SliceMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Bars", selection: $analysisBars) {
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                    Text("4 bars").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                Text(analysisSummary)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.violet)
                    .lineLimit(1)
            }

            if analysisMode == .transient {
                HStack(spacing: 10) {
                    Text("Sensitivity")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                    Slider(value: $analysisSensitivity, in: 0.15...0.75)
                    Text(String(format: "%.2f", analysisSensitivity))
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack(spacing: 10) {
                Button {
                    applyAnalysis(sample: sample)
                } label: {
                    Label("Apply", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)

                Button {
                    analysisDraft = nil
                    analysisMessage = nil
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        // Colour identifies, it never floods (ux-canon rule 12): the panel is
        // neutral; the violet lives in its outline.
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
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
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var headerDetail: String {
        guard let sample = currentSample else {
            return "Slicer destination"
        }
        let length = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        return "\(sample.category.displayName) • \(length) • \(effectiveSliceSet.userSliceCount) slices"
    }

    private var analysisSummary: String {
        guard let analysisDraft else {
            return "\(analysisBars * 16) step clip"
        }
        return "\(analysisDraft.userSliceCount) slices • \(analysisBars * 16) steps"
    }

    private var divider: some View {
        Divider().overlay(StudioTheme.border.opacity(0.7))
    }

    private func modeButton(_ mode: SliceMode, title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(effectiveSliceSet.mode == mode ? StudioTheme.background : StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(effectiveSliceSet.mode == mode ? StudioTheme.cyan : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(effectiveSliceSet.mode == mode ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )
            .buttonStyle(.plain)
    }

    private func installBlank(sample: AudioSample) {
        guard let set = blankSliceSet(sample: sample) else {
            analysisMessage = "Could not load \(sample.name)."
            return
        }
        analysisMessage = nil
        onInstallSliceSet(set, currentSettings)
    }

    private func proposeAutoSlices(sample: AudioSample) {
        guard var set = analyzedSliceSet(sample: sample) else {
            analysisMessage = "Could not analyse \(sample.name)."
            return
        }
        set.id = currentSliceSetID == SliceSet.emptyID ? set.id : currentSliceSetID
        analysisDraft = set
        analysisMessage = nil
    }

    private func refreshAutoSlicesIfNeeded(sample: AudioSample) {
        guard analysisDraft != nil else {
            return
        }
        proposeAutoSlices(sample: sample)
    }

    private func applyAnalysis(sample: AudioSample) {
        guard var set = analysisDraft else {
            return
        }
        set.id = currentSliceSetID == SliceSet.emptyID ? set.id : currentSliceSetID
        onApplyAnalyzedSliceSet(set, sampleLengthFrames(sample: sample), analysisBars * 16)
        analysisDraft = nil
        analysisMessage = "\(set.userSliceCount) slices applied to a \(analysisBars * 16)-step clip."
    }

    private func blankSliceSet(sample: AudioSample) -> SliceSet? {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return nil
        }
        var set = SliceSet(
            sampleID: sample.id,
            markers: [SliceMarker(startFrame: 0, endFrame: file.length)],
            mode: .manual
        )
        set.normalize(sampleLengthFrames: file.length)
        return set
    }

    private func analyzedSliceSet(sample: AudioSample) -> SliceSet? {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return nil
        }
        let markers: [SliceMarker]
        switch analysisMode {
        case .grid:
            markers = SliceAnalyzer.gridSlices(file: file, divisions: max(1, analysisBars * 16))
        case .transient:
            let transientMarkers = SliceAnalyzer.transientSlices(file: file, sensitivity: analysisSensitivity)
            markers = transientMarkers.count > 1
                ? transientMarkers
                : SliceAnalyzer.gridSlices(file: file, divisions: max(1, analysisBars * 16))
        case .manual:
            markers = [SliceMarker(startFrame: 0, endFrame: file.length)]
        }
        var set = SliceSet(sampleID: sample.id, markers: markers, mode: analysisMode, bars: Double(analysisBars))
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
        guard let frameRate = sampleFrameRate(sample: sample), frameRate > 0 else { return "--" }
        let seconds = Double(max(0, marker.endFrame - marker.startFrame)) / frameRate
        return String(format: "%.2fs", seconds)
    }

    /// Source-file sample rate, or nil when the file can't be resolved/opened.
    /// The duration label is the only consumer and renders "--" on nil, so the
    /// failure propagates rather than fabricating a default rate.
    private func sampleFrameRate(sample: AudioSample) -> Double? {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return nil
        }
        return file.processingFormat.sampleRate
    }

    private func audition(marker: SliceMarker, sample: AudioSample) {
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot),
              marker.endFrame > marker.startFrame
        else {
            analysisMessage = "Could not audition \(sample.name)."
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
            reverse: marker.reverse,
            stepParameters: nil
        )
    }

    private func updateSettings(_ mutate: (inout SlicerSettings) -> Void) {
        guard case let .slicer(sliceSetID, settings) = destination else { return }
        var next = settings
        mutate(&next)
        destination = .slicer(sliceSetID: sliceSetID, settings: next.clamped)
    }
}
