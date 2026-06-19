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
    @State private var selectedLowerTab: SliceTrackLowerTab = .source
    // Zoom/scroll only live inside the slicing modal now — the default
    // playback waveform is always full-frame (zoom 1, scroll 0).
    @State private var waveformZoom = 1.0
    @State private var waveformScroll = 0.0
    @State private var analysisDraft: SliceSet?
    @State private var analysisMode: SliceMode = .transient
    @State private var analysisSensitivity = 0.35
    @State private var analysisBars = 2
    @State private var analysisMessage: String?
    @State private var isPresentingAddLoop = false
    @State private var isPresentingSliceModal = false
    @State private var isAddFXPresented = false
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

    private let macroSlotColumns = [
        GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 10, alignment: .top)
    ]

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
        VStack(alignment: .leading, spacing: 18) {
            topControlsPanel

            waveformPanel

            stepSequencePanel

            lowerTabs
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPresentingAddLoop) {
            addLoopSheet
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $isPresentingSliceModal) {
            sliceModal
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $isAddFXPresented) {
            addFXSheet
        }
        .sheet(item: $macroSlotPickerRequest) { request in
            SingleMacroSlotPickerSheet(
                slotIndex: request.slotIndex,
                currentBindingAddresses: currentAUMacroAddresses,
                readParameters: {
                    engineController.audioInstrumentHost(for: track.id)?.parameterReadout()
                }
            ) { descriptor in
                assignMacro(descriptor, to: request.slotIndex)
            }
            .presentationBackground(.clear)
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
        .onReceive(NotificationCenter.default.publisher(for: .sliceTrackWorkspaceVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    // MARK: - Top grammar (above the editor)

    // Standard track-detail top grammar: pattern slots, lane (Normal/Fill),
    // clip length. This mirrors `TrackSourceEditorView` rather than the old
    // bespoke slicer split.
    private var topControlsPanel: some View {
        StudioPanel(title: "Pattern", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                TrackPatternSlotPalette(
                    selectedSlot: selectedPatternIndexBinding,
                    occupiedSlots: occupiedPatternSlots,
                    bypassState: .notApplicable,
                    onBypassToggle: { _ in }
                )

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
    }

    // MARK: - Full-width playback waveform (default view)

    @ViewBuilder
    private var waveformPanel: some View {
        if let sample = currentSample, let sliceSet = displayedSliceSet {
            playbackWaveform(sample: sample, sliceSet: sliceSet)
        } else {
            missingSampleState
        }
    }

    private func playbackWaveform(sample: AudioSample, sliceSet: SliceSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(sample.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Spacer()

                Text("Markers selectable · zoom & slicing in Source")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            // Default playback view: the waveform spans the full content width,
            // slice markers render IN it and are selectable. No zoom/scroll —
            // those live in the slicing modal off the Source tab.
            SliceTrackWaveformEditor(
                buckets: waveformBuckets(sample: sample),
                sliceSet: sliceSet,
                sampleLengthFrames: sampleLengthFrames(sample: sample),
                selectedMarkerID: selectedMarker?.id,
                zoom: 1,
                scroll: 0,
                onSelectMarker: selectMarker,
                onMoveWholeStart: { moveWholeBoundary(isStart: true, to: $0, sample: sample) },
                onMoveWholeEnd: { moveWholeBoundary(isStart: false, to: $0, sample: sample) },
                onMoveSliceBoundary: { moveSliceBoundary(markerID: $0, to: $1, sample: sample) }
            )
            .frame(height: 196)
            .frame(maxWidth: .infinity)
            .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )

            if let analysisMessage {
                Text(analysisMessage)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.amber)
            }
        }
    }

    // MARK: - Step sequence (beneath the waveform, above the lower tabs)

    @ViewBuilder
    private var stepSequencePanel: some View {
        if currentSample != nil {
            VStack(alignment: .leading, spacing: 12) {
                sliceLayerSelector
                sliceStepEditor
            }
        }
    }

    // The step-layer selector sits directly above the steps, consistent with
    // other step editors. Slice Index / Velocity / Chance are engine-backed;
    // Direction / Note Repeat / Gate are real selectable layers shown read-only
    // until per-step engine params land (see NOTE in the strip).
    private var sliceLayerSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Step Layer")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                Text("Same step row, different slicer values.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

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
                    onBackgroundTap: {
                        coordinator?.clearSelection()
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
                .background {
                    StepGridEscapeKeyHandler(isEnabled: coordinator?.isSelectionActive ?? false) {
                        coordinator?.clearSelection()
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
                                    .foregroundStyle(page == selectedPage ? StudioTheme.background : StudioTheme.text)
                                    .frame(minWidth: 34)
                                    .padding(.vertical, 6)
                                    .background(page == selectedPage ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
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

    // MARK: - Lower tabs (Source · Slice · FX · Macros · Mixer)

    private var lowerTabs: some View {
        VStack(alignment: .leading, spacing: 0) {
            SliceLowerTabBar(selectedTab: selectedLowerTab, accent: accent) { tab in
                selectedLowerTab = tab
            }

            Group {
                switch selectedLowerTab {
                case .source:
                    sourceTabBody
                case .slice:
                    sliceTabBody
                case .fx:
                    fxTabBody
                case .macros:
                    macrosTabBody
                case .mixer:
                    mixerTabBody
                }
            }
            .padding(StudioMetrics.Spacing.roomy)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(StudioOpacity.subtleFill))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accent)
                    .frame(height: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        }
    }

    // MARK: Source tab (sample + markers + slicing modal entry)

    @ViewBuilder
    private var sourceTabBody: some View {
        SliceSourceTabContent(
            state: sourceState,
            sampleName: currentSample?.name,
            sliceCount: currentSliceSet?.userSliceCount ?? 0,
            detectionLabel: currentSliceSet.map { Self.detectionLabel(for: $0.mode) } ?? "—",
            accent: accent,
            onChooseSample: { isPresentingAddLoop = true },
            onRemoveSample: removeSample,
            onOpenSliceModal: { isPresentingSliceModal = true }
        )
    }

    private var sourceState: SliceSourceState {
        guard currentSample != nil else { return .empty }
        return (currentSliceSet?.userSliceCount ?? 0) > 0 ? .sliced : .unsliced
    }

    // MARK: Slice tab (drum-part sampler grammar for the selected slice)

    @ViewBuilder
    private var sliceTabBody: some View {
        if currentSample == nil {
            sliceTabPlaceholder("No sample", "Choose a sample in the Source tab first.")
        } else if (currentSliceSet?.userSliceCount ?? 0) == 0 {
            sliceTabPlaceholder("No slices yet", "Open the slicing modal from Source to create slices.")
        } else if let assigned = selectedAssignedMarker,
                  let markerIndex = currentSliceSet?.markers.firstIndex(where: { $0.id == assigned.id }) {
            SliceSamplerCard(
                sampleName: currentSample?.name ?? "Slice",
                markerIndex: markerIndex,
                buckets: currentSample.map { waveformBuckets(sample: $0) } ?? [],
                marker: assigned,
                sampleLengthFrames: currentSample.map { sampleLengthFrames(sample: $0) } ?? 0,
                voiceMode: voiceModeBinding,
                mode: Binding(get: { selectedStepMode }, set: { assignStepMode($0) }),
                parameters: Binding(get: { selectedStepParameters }, set: { assignStepParameters($0) }),
                onAudition: { auditionSelectedSlice() },
                onBrowse: { delta in browseSlice(delta) }
            )
        } else {
            sliceTabPlaceholder(
                "No assigned slice",
                "Select a step with a slice, or tap a marker in the waveform."
            )
        }
    }

    private func sliceTabPlaceholder(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
            Text(help)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: FX / Macros / Mixer (reuse the broader track-detail surfaces)

    @ViewBuilder
    private var fxTabBody: some View {
        // ENGINE TODO (shared with melodic track detail): the chain persists and
        // is fully editable, but inserts do not yet process slicer audio.
        TrackFXChainView(
            inserts: track.fxInserts,
            accent: StudioTheme.violet,
            onAddFX: { isAddFXPresented = true },
            onRemove: { insertID in
                session.removeFXInsert(trackID: track.id, insertID: insertID)
            },
            onMove: { source, destination in
                session.moveFXInsert(trackID: track.id, from: source, to: destination)
            },
            onSetBypassed: { insertID, bypassed in
                session.setFXInsertBypassed(trackID: track.id, insertID: insertID, bypassed: bypassed)
            }
        )
    }

    @ViewBuilder
    private var macrosTabBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macros")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
            Text("M1–M8 slot assignments. Drag to set, right-click to change or remove.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
            LazyVGrid(columns: macroSlotColumns, alignment: .leading, spacing: 12) {
                ForEach(clipMacroSlots) { slot in
                    macroSlotKnob(for: slot)
                }
            }
        }
    }

    @ViewBuilder
    private var mixerTabBody: some View {
        TrackRoutingTabContent(
            document: $document,
            summary: routingPathSummary,
            mode: .mixer,
            accent: accent
        )

        if session.store.routesSourced(from: track.id).isEmpty == false {
            RoutesListView(document: $document)
                .padding(.top, StudioMetrics.Spacing.standard)
        }
    }

    // MARK: - Slicing modal (zoom / scroll / normalize / detection / markers)

    private var sliceModal: some View {
        StudioModal(
            title: "Slice Source",
            subtitle: "Zoom, scroll, normalize, detection, and detailed marker edits.",
            accent: StudioTheme.violet,
            minWidth: 760,
            onClose: { isPresentingSliceModal = false }
        ) {
            if let sample = currentSample, let sliceSet = displayedSliceSet {
                ScrollView {
                    sliceModalBody(sample: sample, sliceSet: sliceSet)
                }
                .frame(maxHeight: 560)
            } else {
                StudioPlaceholderTile(
                    title: "No Sample",
                    detail: "Choose a sample before slicing.",
                    accent: StudioTheme.violet
                )
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func sliceModalBody(sample: AudioSample, sliceSet: SliceSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )

            SlicerControlField(title: "View") {
                HStack(spacing: 12) {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                    Slider(value: $waveformZoom, in: 1...8)
                    Label("Scroll", systemImage: "arrow.left.and.right")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                    Slider(value: $waveformScroll, in: 0...1)
                        .disabled(waveformZoom <= 1.01)
                }
            }

            SlicerControlField(title: "Detection") {
                autoDetectControls(sample: sample)
            }

            SlicerControlField(title: "Sample") {
                HStack(spacing: 10) {
                    Button {
                        normalizeWhole(sample: sample)
                    } label: {
                        Label("Normalize", systemImage: "waveform.path")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        removeSample()
                        isPresentingSliceModal = false
                    } label: {
                        Label("Remove Sample", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Slice browsing / voice mode / audition / remove

    private var voiceModeBinding: Binding<SlicerVoiceMode> {
        Binding(
            get: { currentSettings.voiceMode },
            set: { newMode in
                var next = currentSettings
                next.voiceMode = newMode
                if let sliceSet = currentSliceSet {
                    session.setSlicerDestination(sliceSet: sliceSet, settings: next, for: track.id)
                }
            }
        )
    }

    private func browseSlice(_ delta: Int) {
        guard let steps = sliceTriggerSteps,
              let sliceCount = currentSliceSet?.userSliceCount,
              sliceCount > 0
        else {
            return
        }
        let current = selectedSliceIndex(steps: steps)
        // Slice indices: 0 == whole; 1...sliceCount are the user slices.
        let next = min(max(current + delta, 1), sliceCount)
        assignSliceIndex(next, steps: steps)
    }

    private func auditionSelectedSlice() {
        guard let sample = currentSample,
              let marker = selectedAssignedMarker
        else {
            return
        }
        audition(marker: marker, sample: sample)
    }

    private func removeSample() {
        session.setSlicerDestination(
            sliceSet: SliceSet(sampleID: nil, markers: [], mode: .manual),
            settings: currentSettings,
            for: track.id
        )
        analysisDraft = nil
        analysisMessage = nil
    }

    private func normalizeWhole(sample: AudioSample) {
        mutateCurrentSliceSet(sample: sample) { set in
            set.normalize(sampleLengthFrames: sampleLengthFrames(sample: sample))
        }
        analysisMessage = "Markers normalized"
    }

    static func detectionLabel(for mode: SliceMode) -> String {
        switch mode {
        case .transient: return "Transient detection"
        case .grid: return "Grid detection"
        case .manual: return "Manual markers"
        }
    }

    // An empty slicer is just a plus card; choosing a loop attaches it in
    // place (ux-canon rules 3/4).
    private var missingSampleState: some View {
        StudioAddCard(
            label: "Add Loop",
            accent: accent,
            minHeight: 180,
            help: "Choose a break loop to slice"
        ) {
            isPresentingAddLoop = true
        }
    }

    private var addLoopSheet: some View {
        StudioModal(
            title: "Add Loop",
            subtitle: "Choose the break loop this track slices.",
            minWidth: 440,
            onClose: { isPresentingAddLoop = false }
        ) {
            let loops = AudioSampleLibrary.shared.samples(in: .breaks).sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            if loops.isEmpty {
                StudioPlaceholderTile(
                    title: "No Break Loops",
                    detail: "Add WAV loops to the library's breaks folder.",
                    accent: accent
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(loops) { sample in
                            StudioOptionButton(title: sample.name) {
                                attachLoop(sample)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private func applyVisualCommand(_ command: String) {
        let layerPrefix = "layer:"
        if command.hasPrefix(layerPrefix),
           let layer = SliceTrackClipLayer(rawValue: String(command.dropFirst(layerPrefix.count))) {
            selectedLayer = layer
        }
    }

    private func attachLoop(_ sample: AudioSample) {
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            analysisMessage = "Could not load \(sample.name)."
            return
        }

        var set = SliceSet(
            sampleID: sample.id,
            markers: [SliceMarker(startFrame: 0, endFrame: file.length)],
            mode: .manual
        )
        set.normalize(sampleLengthFrames: file.length)
        session.setSlicerDestination(sliceSet: set, settings: currentSettings, for: track.id)
        isPresentingAddLoop = false
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
        .padding(StudioMetrics.Spacing.comfortable)
        // Colour identifies, it never floods (ux-canon rule 12): the panel is
        // neutral; the violet lives in its outline.
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .onChange(of: analysisMode) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
        .onChange(of: analysisSensitivity) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
        .onChange(of: analysisBars) { _, _ in refreshAutoSlicesIfNeeded(sample: sample) }
    }

    // MARK: - Routing / macros / FX support (reused from the melodic detail)

    private var routingPathSummary: TrackRoutingPathSummary {
        TrackRoutingPathSummary.make(
            destinationSummary: DestinationSummary.make(
                for: session.store.resolvedDestination(for: track.id),
                in: session.store,
                trackID: track.id
            ),
            outputTitle: MixerRoutingDisplayModel.outputTitle(for: track, buses: session.store.buses),
            mix: track.mix
        )
    }

    private var orderedMacros: [TrackMacroBinding] {
        track.macros.sorted { $0.slotIndex < $1.slotIndex }
    }

    private var macroFallbackValues: [UUID: Double] {
        var result: [UUID: Double] = [:]
        let trackID = track.id
        let layers = session.store.layers
        for binding in orderedMacros {
            let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
            if let layer = layers.first(where: { $0.id == layerID }),
               case let .scalar(value) = layer.defaults[trackID] {
                result[binding.id] = value
            } else {
                result[binding.id] = binding.descriptor.defaultValue
            }
        }
        return result
    }

    private var clipMacroSlots: [MacroSlot] {
        (0..<8).map { slotIndex in
            MacroSlot(
                slotIndex: slotIndex,
                binding: orderedMacros.first(where: { $0.slotIndex == slotIndex })
            )
        }
    }

    private var currentAUMacroAddresses: Set<UInt64> {
        Set(orderedMacros.compactMap { binding in
            if case let .auParameter(address, _) = binding.source {
                return address
            }
            return nil
        })
    }

    private var canAssignAUMacros: Bool {
        if case .auInstrument = session.store.resolvedDestination(for: track.id).withoutTransientState {
            return true
        }
        return false
    }

    @ViewBuilder
    func macroSlotKnob(for slot: MacroSlot) -> some View {
        let binding = slot.binding
        let slotValue = binding.flatMap { macroFallbackValues[$0.id] }
        AUMacroSlotKnob(
            slotIndex: slot.slotIndex,
            binding: binding,
            value: slotValue,
            onAssign: { prepareAndPresentMacroSlotPicker(slotIndex: slot.slotIndex) },
            onChange: { newValue in
                guard let binding else { return }
                session.setMacroLayerDefault(
                    value: newValue,
                    bindingID: binding.id,
                    trackID: track.id
                )
            },
            onRemove: binding.map { binding in
                { session.removeAUMacroSlot(bindingID: binding.id, trackID: track.id) }
            }
        )
    }

    private func prepareAndPresentMacroSlotPicker(slotIndex: Int) {
        guard canAssignAUMacros else { return }
        engineController.prepareAudioUnit(for: track.id)
        macroSlotPickerRequest = MacroSlotPickerRequest(slotIndex: slotIndex)
    }

    private func assignMacro(_ parameter: AUParameterDescriptor, to slotIndex: Int) {
        let descriptor = TrackMacroDescriptor(auParameter: parameter)
        _ = session.assignAUMacroToSlot(descriptor, to: track.id, slotIndex: slotIndex)
    }

    var addFXSheet: some View {
        let effects = engineController.availableAudioEffects
        let trackID = track.id
        return StudioModal(
            title: "Add FX",
            accent: StudioTheme.violet,
            minWidth: 360,
            onClose: { isAddFXPresented = false }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                addFXOptionButton(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                    session.addFXInsert(trackID: trackID, insert: .filter())
                    isAddFXPresented = false
                }
                addFXOptionButton(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                    session.addFXInsert(trackID: trackID, insert: .bitcrusher())
                    isAddFXPresented = false
                }
            }

            Divider()
                .overlay(StudioTheme.border)

            Text("AU Effect")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            AUEffectPickerList(effects: effects) { effect in
                addFXOptionButton(title: effect.displayName, systemName: "slider.horizontal.3") {
                    session.addFXInsert(trackID: trackID, insert: .auEffect(effect))
                    isAddFXPresented = false
                }
            }
        }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
    }

    private func addFXOptionButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioTheme.violet)
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
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

        case .direction, .noteRepeat, .gate:
            // Real selectable layers in the step grammar, but not yet backed by
            // a per-step engine parameter. Show the on/off state read-only so
            // the layer row + step strip stay consistent with other layers.
            guard case .on = state else {
                return .optionLabel(text: "")
            }
            return .optionLabel(text: placeholderLayerLabel(for: selectedLayer))
        }
    }

    func placeholderLayerLabel(for layer: SliceTrackClipLayer) -> String {
        switch layer {
        case .direction: return "Fwd"
        case .noteRepeat: return "1x"
        case .gate: return "100%"
        default: return ""
        }
    }

    func writeSliceStepValue(_ value: Double, at stepIndex: Int, coordinator: StepGridCoordinator?) {
        // Only engine-backed layers accept value writes; the others are
        // read-only previews until their per-step params land.
        guard selectedLayer.isEngineBacked, let coordinator else {
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
                .foregroundStyle(clipContent.stepCount == length ? StudioTheme.background : StudioTheme.text)
                .frame(minWidth: 34)
                .padding(.vertical, 7)
                .background(clipContent.stepCount == length ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                .overlay(Capsule().stroke(clipContent.stepCount == length ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
    }

    func layerButton(title: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : (isEnabled ? StudioTheme.text : StudioTheme.mutedText))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? accent : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth))
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
            analysisMessage = "Could not audition \(sample.name)."
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
        // Non-engine-backed layers have no step-grid counterpart yet; they map
        // to `.trigger` for display only (writes are gated by `isEngineBacked`).
        case .direction, .noteRepeat, .gate:
            return .trigger
        }
    }
}
