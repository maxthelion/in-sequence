import AVFoundation
import SwiftUI

struct SliceTrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let accent: Color

    @State private var selectedPage = 0
    @State private var selectedStepIndex = 0
    @State private var selectedLayer: SliceTrackClipLayer = .steps
    @State private var selectedLane: SliceTrackLane = .normal
    @State private var waveformZoom = 1.0
    @State private var waveformScroll = 0.0
    @State private var analysisDraft: SliceSet?
    @State private var analysisMode: SliceMode = .transient
    @State private var analysisSensitivity = 0.35
    @State private var analysisBars = 2
    @State private var analysisMessage: String?

    private var track: StepSequenceTrack {
        session.store.selectedTrack
    }

    private var bank: TrackPatternBank {
        session.store.patternBank(for: track.id)
    }

    private var selectedPatternIndex: Int {
        session.store.selectedPatternIndex(for: track.id)
    }

    private var selectedPattern: TrackPatternSlot {
        session.store.selectedPattern(for: track.id)
    }

    private var currentClip: ClipPoolEntry? {
        session.store.clipEntry(id: selectedPattern.sourceRef.clipID)
    }

    private var clipContent: ClipContent {
        (currentClip?.content ?? .emptySliceTriggers(lengthSteps: 16)).normalized
    }

    private var currentSettings: SlicerSettings {
        guard case let .slicer(_, settings) = session.store.resolvedDestination(for: track.id) else {
            return .default
        }
        return settings
    }

    private var currentSliceSet: SliceSet? {
        guard case let .slicer(sliceSetID, _) = session.store.resolvedDestination(for: track.id) else {
            return nil
        }
        return session.store.sliceSet(id: sliceSetID)
    }

    private var displayedSliceSet: SliceSet? {
        analysisDraft ?? currentSliceSet
    }

    private var currentSample: AudioSample? {
        guard let sampleID = currentSliceSet?.sampleID else {
            return nil
        }
        return AudioSampleLibrary.shared.sample(id: sampleID)
    }

    private var occupiedPatternSlots: Set<Int> {
        Set(bank.slots.compactMap { slot in
            guard let clip = session.store.clipEntry(id: slot.sourceRef.clipID),
                  !clipIsEmpty(clip.content)
            else {
                return nil
            }
            return slot.slotIndex
        })
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { session.store.selectedPatternIndex(for: track.id) },
            set: { session.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            mainColumn
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            rightColumn
                .frame(width: 340, alignment: .topLeading)
        }
        .onChange(of: clipContent.stepCount) { _, stepCount in
            selectedPage = min(selectedPage, pageCount(for: stepCount) - 1)
            selectedStepIndex = min(selectedStepIndex, max(0, stepCount - 1))
        }
        .onChange(of: currentSliceSet?.id) { _, _ in
            analysisDraft = nil
            analysisMessage = nil
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Slice Clip", accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    patternControls

                    if let sample = currentSample, let sliceSet = displayedSliceSet {
                        sampleWaveformSection(sample: sample, sliceSet: sliceSet)
                    } else {
                        missingSampleState
                    }
                }
            }

            StudioPanel(title: "Step Layers", accent: accent) {
                clipControls
            }
        }
    }

    private var patternControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlGroup(title: "Pattern") {
                TrackPatternSlotPalette(
                    selectedSlot: selectedPatternIndexBinding,
                    occupiedSlots: occupiedPatternSlots,
                    bypassState: .notApplicable,
                    onBypassToggle: { _ in }
                )
            }

            HStack(spacing: 18) {
                controlGroup(title: "Lane") {
                    HStack(spacing: 8) {
                        ForEach(SliceTrackLane.allCases) { lane in
                            layerButton(title: lane.title, isSelected: selectedLane == lane, isEnabled: lane == .normal) {
                                selectedLane = lane
                            }
                        }
                    }
                }

                Spacer()

                controlGroup(title: "Length") {
                    HStack(spacing: 8) {
                        ForEach([16, 32, 64, 128], id: \.self) { length in
                            lengthButton(length)
                        }
                    }
                }
            }
        }
    }

    private func sampleWaveformSection(sample: AudioSample, sliceSet: SliceSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sampleHeader(sample: sample, sliceSet: sliceSet)
            waveformShell(sample: sample, sliceSet: sliceSet)

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.amber)
            }
        }
    }

    private func sampleHeader(sample: AudioSample, sliceSet: SliceSet) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(sampleDetail(sample: sample, sliceSet: sliceSet))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func waveformShell(sample: AudioSample, sliceSet: SliceSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(sliceSet.userSliceCount > 0 ? "Whole waveform with slice markers" : "Whole waveform - no slices yet")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text(waveformCaption(sliceSet: sliceSet))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)

                Spacer()

                Button {
                    toggleAnalysis(sample: sample)
                } label: {
                    Label(analysisDraft == nil ? "Auto Detect" : "Hide Detect", systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.violet)
            }

            if analysisDraft != nil {
                autoDetectControls(sample: sample)
            }

            SliceTrackWaveformEditor(
                buckets: waveformBuckets(sample: sample),
                sliceSet: sliceSet,
                sampleLengthFrames: sampleLengthFrames(sample: sample),
                selectedMarkerID: selectedMarker?.id,
                zoom: waveformZoom,
                scroll: waveformScroll,
                onSelectMarker: selectMarker,
                onMoveWholeStart: { moveWholeBoundary(isStart: true, to: $0, sample: sample) },
                onMoveWholeEnd: { moveWholeBoundary(isStart: false, to: $0, sample: sample) },
                onMoveSliceBoundary: { moveSliceBoundary(markerID: $0, to: $1, sample: sample) }
            )
            .frame(height: 188)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Label("Zoom", systemImage: "plus.magnifyingglass")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Slider(value: $waveformZoom, in: 1...8)
                    .frame(maxWidth: 220)
                Label("Scroll", systemImage: "arrow.left.and.right")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Slider(value: $waveformScroll, in: 0...1)
                    .disabled(waveformZoom <= 1.01)
                Spacer()
                Text(sampleRangeLabel(sliceSet: sliceSet, sample: sample))
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var clipControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlGroup(title: "Layer") {
                HStack(spacing: 8) {
                    ForEach(SliceTrackClipLayer.allCases) { layer in
                        layerButton(title: layer.title, isSelected: selectedLayer == layer, isEnabled: layer == .steps) {
                            selectedLayer = layer
                        }
                    }
                }
            }

            sliceStepEditor
        }
    }

    @ViewBuilder
    private var sliceStepEditor: some View {
        switch sliceTriggerParts {
        case let .some(parts):
            VStack(alignment: .leading, spacing: 12) {
                SliceStepStrip(
                    stepStates: visibleStepStates(parts: parts),
                    indexOffset: selectedPage * 16,
                    playingStepIndex: playingClipStepIndex,
                    selectedStepIndex: selectedStepIndex
                ) { stepIndex in
                    selectedStepIndex = min(max(stepIndex, 0), parts.stepPattern.count - 1)
                    if selectedLayer == .steps {
                        toggleStep(at: selectedStepIndex, parts: parts)
                    }
                }

                if pageCount(for: parts.stepPattern.count) > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<pageCount(for: parts.stepPattern.count), id: \.self) { page in
                            Button {
                                selectedPage = page
                            } label: {
                                Text("\(page + 1)")
                                    .studioText(.labelBold)
                                    .foregroundStyle(StudioTheme.text)
                                    .frame(minWidth: 34)
                                    .padding(.vertical, 6)
                                    .background(page == selectedPage ? StudioTheme.violet.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        case .none:
            EmptyView()
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Sample Player", eyebrow: selectedStepTitle, accent: StudioTheme.success) {
                samplePlayerPanel
            }

            if session.store.routesSourced(from: track.id).isEmpty == false {
                StudioPanel(
                    title: "Routing",
                    eyebrow: "\(session.store.routesSourced(from: track.id).count) outbound project route\(session.store.routesSourced(from: track.id).count == 1 ? "" : "s")",
                    accent: StudioTheme.violet
                ) {
                    RoutesListView(document: $document)
                }
            }
        }
    }

    private var samplePlayerPanel: some View {
        selectedStepControls
    }

    @ViewBuilder
    private var selectedStepControls: some View {
        if currentSample == nil {
            samplePlayerEmptyState(title: "No loop assigned", detail: "Create a slice track from a break loop first.")
        } else if currentSliceSet?.userSliceCount ?? 0 == 0 {
            samplePlayerEmptyState(title: "No slices yet", detail: "Run Auto Detect and apply the proposal before step destinations can target sample-player voices.")
        } else if let assigned = selectedAssignedMarker,
                  let markerIndex = currentSliceSet?.markers.firstIndex(where: { $0.id == assigned.id }) {
            SliceSamplePlayerParametersView(
                markerIndex: markerIndex,
                mode: Binding(
                    get: { selectedStepMode },
                    set: { assignStepMode($0) }
                ),
                parameters: Binding(
                    get: { selectedStepParameters },
                    set: { assignStepParameters($0) }
                )
            )
        } else {
            samplePlayerEmptyState(title: "No assigned slice", detail: "Select a step with a slice, or choose a waveform slice for the selected step.")
        }
    }

    private func samplePlayerEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
            Text(detail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var missingSampleState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No loop assigned")
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
            Text("Create a new slice track from Tracks to attach a loop.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
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
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                Text("\(analysisDraft?.userSliceCount ?? 0) slices")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.violet)
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
        .padding(12)
        .background(StudioTheme.violet.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
        .onChange(of: analysisMode) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
        .onChange(of: analysisSensitivity) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
        .onChange(of: analysisBars) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
    }
}

private extension SliceTrackWorkspaceView {
    struct SliceTriggerParts {
        var stepPattern: [Bool]
        var sliceIndexes: [Int]
        var stepModes: [SliceTriggerStepMode]
        var stepParameters: [SliceTriggerStepParameters]
    }

    var sliceTriggerParts: SliceTriggerParts? {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = clipContent else {
            return nil
        }
        let stepCount = max(1, stepPattern.count)
        return SliceTriggerParts(
            stepPattern: stepPattern,
            sliceIndexes: synced(sliceIndexes, stepCount: stepCount, fallback: defaultSliceIndex),
            stepModes: synced(stepModes, stepCount: stepCount, fallback: .single),
            stepParameters: synced(stepParameters, stepCount: stepCount, fallback: .default)
        )
    }

    var selectedMarker: SliceMarker? {
        guard let parts = sliceTriggerParts,
              let sliceSet = displayedSliceSet
        else {
            return currentSliceSet?.markers.first
        }
        return sliceSet.marker(at: selectedSliceIndex(parts: parts))
    }

    var selectedAssignedMarker: SliceMarker? {
        guard let parts = sliceTriggerParts,
              parts.stepPattern.indices.contains(selectedStepIndex),
              parts.stepPattern[selectedStepIndex],
              let sliceSet = currentSliceSet
        else {
            return nil
        }
        return sliceSet.marker(at: selectedSliceIndex(parts: parts))
    }

    var selectedStepTitle: String {
        "Step \(selectedStepIndex + 1)"
    }

    var selectedStepMode: SliceTriggerStepMode {
        guard let parts = sliceTriggerParts,
              parts.stepModes.indices.contains(selectedStepIndex)
        else {
            return .single
        }
        return parts.stepModes[selectedStepIndex]
    }

    var selectedStepParameters: SliceTriggerStepParameters {
        guard let parts = sliceTriggerParts,
              parts.stepParameters.indices.contains(selectedStepIndex)
        else {
            return .default
        }
        return parts.stepParameters[selectedStepIndex]
    }

    var defaultSliceIndex: Int {
        (currentSliceSet?.userSliceCount ?? 0) > 0 ? 1 : 0
    }

    var playingClipStepIndex: Int? {
        guard engineController.isRunning,
              let clip = currentClip,
              selectedPattern.sourceRef.clipID == clip.id
        else {
            return nil
        }
        let phrase = session.store.selectedPhrase
        let phraseStep = Int(engineController.transportTickIndex % UInt64(max(1, phrase.stepCount)))
        guard resolvedPatternIndex(in: phrase, trackID: track.id, stepIndex: phraseStep) == selectedPatternIndex else {
            return nil
        }
        return phraseStep % max(1, clip.content.stepCount)
    }

    func visibleStepStates(parts: SliceTriggerParts) -> [SliceStepStrip.State] {
        let pageStart = selectedPage * 16
        let pageEnd = min(pageStart + 16, parts.stepPattern.count)
        guard pageStart < pageEnd else {
            return []
        }
        return (pageStart..<pageEnd).map { index in
            parts.stepPattern[index] ? .on(sliceIndex: parts.sliceIndexes[index], mode: parts.stepModes[index]) : .off
        }
    }

    func pageCount(for stepCount: Int) -> Int {
        max(1, (max(1, stepCount) + 15) / 16)
    }

    func lengthButton(_ length: Int) -> some View {
        Button {
            resizeClip(to: length)
        } label: {
            Text("\(length)")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .frame(minWidth: 34)
                .padding(.vertical, 7)
                .background(clipContent.stepCount == length ? StudioTheme.violet.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                .overlay(Capsule().stroke(clipContent.stepCount == length ? StudioTheme.violet.opacity(0.8) : StudioTheme.border.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func layerButton(title: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? accent.opacity(0.8) : StudioTheme.border.opacity(0.8), lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    func controlGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)
            content()
        }
    }

    func selectedSliceIndex(parts: SliceTriggerParts) -> Int {
        guard parts.sliceIndexes.indices.contains(selectedStepIndex) else {
            return 0
        }
        return min(max(parts.sliceIndexes[selectedStepIndex], 0), max(0, (displayedSliceSet?.markers.count ?? 1) - 1))
    }

    func sliceLabel(for index: Int) -> String {
        index == 0 ? "Whole Sample" : "S\(index)"
    }

    func sampleDetail(sample: AudioSample, sliceSet: SliceSet) -> String {
        let seconds = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        let bars = sliceSet.bars.map { String(format: "%.0f bars", $0) } ?? "unknown bars"
        let rate = sample.sampleRate.map { String(format: "%.1fk", $0 / 1_000) } ?? "--"
        return "unknown BPM - \(seconds) - \(rate) - \(sliceSet.userSliceCount) slices - \(bars)"
    }

    func waveformCaption(sliceSet: SliceSet) -> String {
        if sliceSet.userSliceCount == 0 {
            return "Run Auto Detect to propose transient slices and clip length."
        }
        guard let parts = sliceTriggerParts else {
            return "\(sliceSet.userSliceCount) slices"
        }
        return "Selected: \(sliceLabel(for: selectedSliceIndex(parts: parts)))"
    }

    func sampleRangeLabel(sliceSet: SliceSet, sample: AudioSample) -> String {
        guard let whole = sliceSet.markers.first else {
            return "Sample start/end: --"
        }
        let length = max(1, Double(sampleLengthFrames(sample: sample)))
        let start = (Double(whole.startFrame) / length) * 100
        let end = (Double(whole.endFrame) / length) * 100
        return String(format: "Sample start/end: %.0f%%-%.0f%%", start, end)
    }

    func waveformBuckets(sample: AudioSample) -> [Float] {
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot) else {
            return Array(repeating: 0, count: 256)
        }
        return WaveformDownsampler.downsample(url: url, bucketCount: 256)
    }

    func sampleLengthFrames(sample: AudioSample) -> Int64 {
        if let lengthFrames = sample.lengthFrames {
            return lengthFrames
        }
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return currentSliceSet?.markers.first?.endFrame ?? 0
        }
        return file.length
    }

    func resizeClip(to stepCount: Int) {
        guard var parts = sliceTriggerParts else {
            return
        }
        parts.stepPattern = synced(parts.stepPattern, stepCount: stepCount, fallback: false)
        parts.sliceIndexes = synced(parts.sliceIndexes, stepCount: stepCount, fallback: defaultSliceIndex)
        parts.stepModes = synced(parts.stepModes, stepCount: stepCount, fallback: .single)
        parts.stepParameters = synced(parts.stepParameters, stepCount: stepCount, fallback: .default)
        commit(parts: parts)
    }

    func toggleStep(at index: Int, parts: SliceTriggerParts) {
        guard parts.stepPattern.indices.contains(index) else {
            return
        }
        var next = parts
        next.stepPattern[index].toggle()
        if next.stepPattern[index] {
            next.sliceIndexes[index] = max(defaultSliceIndex, selectedSliceIndex(parts: parts))
        }
        commit(parts: next)
    }

    func assignSliceIndex(_ sliceIndex: Int, parts: SliceTriggerParts) {
        guard parts.sliceIndexes.indices.contains(selectedStepIndex) else {
            return
        }
        var next = parts
        next.sliceIndexes[selectedStepIndex] = sliceIndex
        next.stepPattern[selectedStepIndex] = true
        commit(parts: next)
    }

    func assignStepMode(_ mode: SliceTriggerStepMode) {
        guard var parts = sliceTriggerParts,
              parts.stepModes.indices.contains(selectedStepIndex)
        else {
            return
        }
        parts.stepModes[selectedStepIndex] = mode
        commit(parts: parts)
    }

    func assignStepParameters(_ parameters: SliceTriggerStepParameters) {
        guard var parts = sliceTriggerParts,
              parts.stepParameters.indices.contains(selectedStepIndex)
        else {
            return
        }
        parts.stepParameters[selectedStepIndex] = parameters.clamped
        commit(parts: parts)
    }

    func commit(parts: SliceTriggerParts) {
        session.ensureClipAndMutate(trackID: track.id) { _, entry in
            entry.content = .sliceTriggers(
                stepPattern: parts.stepPattern,
                sliceIndexes: parts.sliceIndexes,
                stepModes: parts.stepModes,
                stepParameters: parts.stepParameters
            )
            entry.macroLanes = entry.macroLanes.mapValues { $0.synced(stepCount: parts.stepPattern.count) }
        }
    }

    func synced<T>(_ values: [T], stepCount: Int, fallback: T) -> [T] {
        let resolvedCount = max(1, stepCount)
        return (0..<resolvedCount).map { index in
            values.indices.contains(index) ? values[index] : fallback
        }
    }

    func selectMarker(_ markerID: UUID) {
        guard analysisDraft == nil,
              let sliceSet = currentSliceSet,
              let index = sliceSet.markers.firstIndex(where: { $0.id == markerID }),
              let parts = sliceTriggerParts
        else {
            return
        }
        assignSliceIndex(index, parts: parts)
    }

    func moveWholeBoundary(isStart: Bool, to frame: Int64, sample: AudioSample) {
        mutateCurrentSliceSet(sample: sample) { set in
            guard !set.markers.isEmpty else {
                return
            }
            let sampleLength = sampleLengthFrames(sample: sample)
            var whole = set.markers[0]
            if isStart {
                whole.startFrame = min(max(frame, 0), max(0, whole.endFrame - 1))
            } else {
                whole.endFrame = min(max(frame, whole.startFrame + 1), sampleLength)
            }
            set.markers[0] = whole
        }
    }

    func moveSliceBoundary(markerID: UUID, to frame: Int64, sample: AudioSample) {
        mutateCurrentSliceSet(sample: sample) { set in
            guard let index = set.markers.firstIndex(where: { $0.id == markerID }), index > 0 else {
                return
            }
            if index == 1 {
                let wholeStart = set.markers.first?.startFrame ?? 0
                let maxStart = max(wholeStart, set.markers[index].endFrame - 1)
                set.markers[index].startFrame = min(max(frame, wholeStart), maxStart)
                return
            }
            let previousStart = set.markers[index - 1].startFrame
            let currentEnd = set.markers[index].endFrame
            let nextBoundary = index + 1 < set.markers.count
                ? set.markers[index + 1].startFrame
                : currentEnd
            let lowerBound = previousStart + 1
            let upperBound = max(lowerBound, min(currentEnd, nextBoundary) - 1)
            let boundary = min(max(frame, lowerBound), upperBound)
            set.markers[index - 1].endFrame = boundary
            set.markers[index].startFrame = boundary
        }
    }

    func mutateCurrentSliceSet(sample: AudioSample, _ update: @escaping (inout SliceSet) -> Void) {
        guard let sliceSet = currentSliceSet else {
            return
        }
        session.mutateSliceSet(id: sliceSet.id, sampleLengthFrames: sampleLengthFrames(sample: sample), update)
    }

    func proposeAutoSlices(sample: AudioSample) {
        guard var set = analyzedSliceSet(sample: sample) else {
            analysisMessage = "Could not analyse \(sample.name)."
            return
        }
        if let currentSliceSet {
            set.id = currentSliceSet.id
            if let whole = currentSliceSet.markers.first, !set.markers.isEmpty {
                set.markers[0].startFrame = whole.startFrame
                set.markers[0].endFrame = whole.endFrame
                set.normalize(sampleLengthFrames: sampleLengthFrames(sample: sample))
            }
        }
        analysisDraft = set
        analysisMessage = nil
    }

    func toggleAnalysis(sample: AudioSample) {
        if analysisDraft == nil {
            proposeAutoSlices(sample: sample)
        } else {
            analysisDraft = nil
            analysisMessage = nil
        }
    }

    func refreshAutoSlicesIfNeeded(sample: AudioSample) {
        guard analysisDraft != nil else {
            return
        }
        proposeAutoSlices(sample: sample)
    }

    func applyAnalysis(sample: AudioSample) {
        guard var set = analysisDraft else {
            return
        }
        if let currentSliceSet {
            set.id = currentSliceSet.id
        }
        session.applySlicerAnalysis(
            sliceSet: set,
            sampleLengthFrames: sampleLengthFrames(sample: sample),
            clipLengthSteps: analysisBars * 16,
            for: track.id
        )
        selectedPage = 0
        selectedStepIndex = 0
        analysisDraft = nil
        analysisMessage = "\(set.userSliceCount) slices applied"
    }

    func analyzedSliceSet(sample: AudioSample) -> SliceSet? {
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot),
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

    func audition(marker: SliceMarker, sample: AudioSample) {
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot),
              marker.endFrame > marker.startFrame
        else {
            return
        }
        _ = engineController.sampleEngineSink.playSlice(
            sampleURL: url,
            startFrame: AVAudioFramePosition(marker.startFrame),
            endFrame: AVAudioFramePosition(marker.endFrame),
            settings: SlicerSettings(
                gain: currentSettings.gain + marker.gain,
                transpose: currentSettings.transpose,
                voiceMode: currentSettings.voiceMode
            ).clamped,
            trackID: track.id,
            at: nil,
            reverse: marker.reverse,
            stepParameters: nil
        )
    }

    func resolvedPatternIndex(in phrase: PhraseModel, trackID: UUID, stepIndex: Int) -> Int {
        guard let layer = session.store.patternLayer else {
            return 0
        }
        switch phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex) {
        case let .index(index):
            return min(max(index, 0), TrackPatternBank.slotCount - 1)
        case let .scalar(value):
            return min(max(Int(value.rounded()), 0), TrackPatternBank.slotCount - 1)
        case let .bool(isOn):
            return isOn ? 1 : 0
        }
    }
}
