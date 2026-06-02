import AVFoundation
import SwiftUI

struct SliceTrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let accent: Color
    let stepGridWorkspaceModel: TrackStepGridWorkspaceModel

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

    private var selectedPatternAddress: PatternSlotAddress {
        PatternSlotAddress(trackID: track.id, slotIndex: selectedPatternIndex)
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
        .onAppear {
            syncStepGridCoordinator()
        }
        .onChange(of: currentClip?.id) { _, _ in
            syncStepGridCoordinator()
        }
        .onChange(of: selectedLayer) { _, _ in
            syncStepGridCoordinator()
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
            waveformShell(sample: sample, sliceSet: sliceSet)

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.amber)
            }
        }
    }

    private func waveformShell(sample: AudioSample, sliceSet: SliceSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text(sample.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
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
                layerRow
            }

            sliceStepEditor
        }
    }

    @ViewBuilder
    private var layerRow: some View {
        if let coordinator = stepGridCoordinator,
           coordinator.shouldShowRotaryRow,
           let currentClip {
            StepLayerRotaryRow(
                controls: coordinator.rotaryControls(in: currentClip, track: track),
                activeLayer: selectedLayer.stepGridLayer,
                suppressActiveLayerHighlight: selectedLayer == .steps,
                accent: accent,
                onSelectLayer: selectRotaryLayer,
                onWriteValue: { layer, value in
                    writeRotaryValue(value, layer: layer, coordinator: coordinator)
                }
            )
        } else if stepGridCoordinator?.isSelectionActive == true {
            StepLayerRotaryEmptyState()
        } else {
            SliceLayerTabRow(selectedLayer: selectedLayer, accent: accent) { layer in
                selectedLayer = layer
            }
        }
    }

    @ViewBuilder
    private var sliceStepEditor: some View {
        switch sliceTriggerSteps {
        case let .some(steps):
            let coordinator = stepGridCoordinator
            VStack(alignment: .leading, spacing: 12) {
                SliceStepStrip(
                    stepStates: visibleStepStates(steps: steps),
                    indexOffset: selectedPage * 16,
                    playingStepIndex: playingClipStepIndex,
                    selectedStepIndex: selectedStepIndex,
                    selectedStepIndexes: coordinator?.selection.selectedStepIndexes ?? [],
                    activeLayer: selectedLayer,
                    contentProvider: { stepIndex, state in
                        sliceStepContent(stepIndex: stepIndex, state: state, coordinator: coordinator)
                    },
                    onValueDrag: { stepIndex, value in
                        writeSliceStepValue(value, at: stepIndex, coordinator: coordinator)
                    },
                    onSelect: { stepIndex in
                        selectedStepIndex = min(max(stepIndex, 0), steps.count - 1)
                        coordinator?.toggleSelection(at: stepIndex)
                    }
                ) { stepIndex in
                    selectedStepIndex = min(max(stepIndex, 0), steps.count - 1)
                    if selectedLayer == .steps {
                        toggleStep(at: selectedStepIndex, steps: steps)
                    }
                }

                SliceStepBatchActionBar(
                    isVisible: coordinator?.shouldShowBatchActionBar ?? false,
                    canPaste: coordinator?.clipboard != nil,
                    onClear: {
                        _ = coordinator?.clearSelectedSteps(track: track)
                    },
                    onCopy: {
                        guard let clip = currentClip else { return }
                        coordinator?.copySelectedSteps(from: clip, track: track)
                    },
                    onPaste: {
                        _ = coordinator?.pasteClipboard(track: track)
                    }
                )

                if pageCount(for: steps.count) > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<pageCount(for: steps.count), id: \.self) { page in
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
    var stepGridCoordinator: StepGridCoordinator? {
        stepGridWorkspaceModel.coordinator
    }

    var sliceTriggerSteps: SliceTriggerSteps? {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = clipContent else {
            return nil
        }
        return SliceTriggerSteps(
            stepPattern: stepPattern,
            sliceIndexes: sliceIndexes,
            stepModes: stepModes,
            stepParameters: stepParameters,
            defaultSliceIndex: defaultSliceIndex
        )
    }

    var selectedMarker: SliceMarker? {
        guard let steps = sliceTriggerSteps,
              let sliceSet = displayedSliceSet
        else {
            return currentSliceSet?.markers.first
        }
        return sliceSet.marker(at: selectedSliceIndex(steps: steps))
    }

    var selectedAssignedMarker: SliceMarker? {
        guard let steps = sliceTriggerSteps,
              let step = steps[selectedStepIndex],
              step.isOn,
              let sliceSet = currentSliceSet
        else {
            return nil
        }
        return sliceSet.marker(at: selectedSliceIndex(steps: steps))
    }

    var selectedStepTitle: String {
        "Step \(selectedStepIndex + 1)"
    }

    var selectedStepMode: SliceTriggerStepMode {
        sliceTriggerSteps?[selectedStepIndex]?.mode ?? .single
    }

    var selectedStepParameters: SliceTriggerStepParameters {
        sliceTriggerSteps?[selectedStepIndex]?.parameters ?? .default
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
        let playhead = PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex)
        guard playhead.patternIndex(for: track.id, patternLayer: session.store.patternLayer) == selectedPatternIndex else {
            return nil
        }
        return playhead.clipStepIndex(clipStepCount: clip.content.stepCount)
    }

    func visibleStepStates(steps: SliceTriggerSteps) -> [SliceStepStrip.State] {
        let pageStart = selectedPage * 16
        let pageEnd = min(pageStart + 16, steps.count)
        guard pageStart < pageEnd else {
            return []
        }
        return (pageStart..<pageEnd).map { index in
            guard let step = steps[index], step.isOn else { return .off }
            return .on(sliceIndex: step.sliceIndex, mode: step.mode)
        }
    }

    func sliceStepContent(
        stepIndex: Int,
        state: SliceStepStrip.State,
        coordinator: StepGridCoordinator?
    ) -> StepCellContent {
        switch selectedLayer {
        case .steps:
            guard case let .on(sliceIndex, _) = state else {
                return .optionLabel(text: "")
            }
            return .sliceLabel(index: sliceIndex, label: sliceIndex == 0 ? "All" : "S\(sliceIndex)")

        case .velocity, .chance:
            guard let currentClip, let coordinator else {
                return .valueBar(fraction: 0)
            }
            return coordinator.cellContent(
                for: stepIndex,
                in: currentClip,
                layer: selectedLayer.stepGridLayer,
                track: track
            )
        }
    }

    func writeSliceStepValue(_ value: Double, at stepIndex: Int, coordinator: StepGridCoordinator?) {
        guard let coordinator else {
            return
        }
        selectedStepIndex = min(max(stepIndex, 0), max(0, clipContent.stepCount - 1))
        _ = coordinator.writeAbsoluteValue(
            value,
            stepIndex: stepIndex,
            layer: selectedLayer.stepGridLayer,
            track: track
        )
    }

    func writeRotaryValue(_ value: Double, layer: StepGridLayer, coordinator: StepGridCoordinator) {
        guard let seedStepIndex = coordinator.selectedRotarySeedStepIndex else {
            return
        }
        selectedStepIndex = min(max(seedStepIndex, 0), max(0, clipContent.stepCount - 1))
        _ = coordinator.writeAbsoluteValue(
            value,
            stepIndex: seedStepIndex,
            layer: layer,
            track: track
        )
    }

    func selectRotaryLayer(_ layer: StepGridLayer) {
        guard let clipLayer = SliceTrackClipLayer(stepGridLayer: layer) else {
            return
        }
        selectedLayer = clipLayer
    }

    func syncStepGridCoordinator() {
        guard let clipID = currentClip?.id else {
            stepGridWorkspaceModel.reset()
            return
        }
        let coordinator = stepGridWorkspaceModel.coordinator(
            for: clipID,
            clipMutator: session,
            editableLayers: [.velocity, .chance]
        )
        coordinator.updateActiveLayer(selectedLayer.stepGridLayer)
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

    func selectedSliceIndex(steps: SliceTriggerSteps) -> Int {
        guard let step = steps[selectedStepIndex] else {
            return 0
        }
        return min(max(step.sliceIndex, 0), max(0, (displayedSliceSet?.markers.count ?? 1) - 1))
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
        guard let steps = sliceTriggerSteps else {
            return
        }
        commit(steps: steps.resized(to: stepCount, defaultSliceIndex: defaultSliceIndex))
    }

    func toggleStep(at index: Int, steps: SliceTriggerSteps) {
        var next = steps
        next.toggleStep(at: index, defaultSliceIndex: defaultSliceIndex, selectedSliceIndex: selectedSliceIndex(steps: steps))
        commit(steps: next)
    }

    func assignSliceIndex(_ sliceIndex: Int, steps: SliceTriggerSteps) {
        var next = steps
        next.assignSliceIndex(sliceIndex, at: selectedStepIndex)
        commit(steps: next)
    }

    func assignStepMode(_ mode: SliceTriggerStepMode) {
        guard var steps = sliceTriggerSteps else {
            return
        }
        steps.assignMode(mode, at: selectedStepIndex)
        commit(steps: steps)
    }

    func assignStepParameters(_ parameters: SliceTriggerStepParameters) {
        guard var steps = sliceTriggerSteps else {
            return
        }
        steps.assignParameters(parameters, at: selectedStepIndex)
        commit(steps: steps)
    }

    func commit(steps: SliceTriggerSteps) {
        session.ensureClipAndMutate(at: selectedPatternAddress) { _, entry in
            entry.content = .sliceTriggers(
                stepPattern: steps.stepPattern,
                sliceIndexes: steps.sliceIndexes,
                stepModes: steps.stepModes,
                stepParameters: steps.stepParameters
            )
            entry.macroLanes = entry.macroLanes.mapValues { $0.synced(stepCount: steps.count) }
        }
    }

    func selectMarker(_ markerID: UUID) {
        guard let index = SliceMarkerSelectionPolicy.assignableMarkerIndex(
            markerID: markerID,
            currentSliceSet: currentSliceSet,
            analysisDraft: analysisDraft
        ),
              let steps = sliceTriggerSteps
        else {
            return
        }
        assignSliceIndex(index, steps: steps)
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
            SliceBoundaryEditing.moveSharedBoundary(
                markerID: markerID,
                to: frame,
                in: &set,
                sampleLengthFrames: sampleLengthFrames(sample: sample)
            )
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

}

private extension SliceTrackClipLayer {
    init?(stepGridLayer: StepGridLayer) {
        switch stepGridLayer {
        case .trigger:
            self = .steps
        case .velocity:
            self = .velocity
        case .chance:
            self = .chance
        case .macro, .sliceIndex, .sliceMode, .chord:
            return nil
        }
    }

    var stepGridLayer: StepGridLayer {
        switch self {
        case .steps:
            return .trigger
        case .velocity:
            return .velocity
        case .chance:
            return .chance
        }
    }
}
