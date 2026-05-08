import SwiftUI

private enum TrackSourceEditorTab: String, CaseIterable, Identifiable {
    case source
    case modifiers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .modifiers:
            return "Modifiers"
        }
    }
}

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let accent: Color

    @State private var selectedTab: TrackSourceEditorTab = .source
    @State private var sourcePickerStep: TrackSourceContainedSourcePickerStep?
    @State private var isShowingModifierPicker = false
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?
    @State private var isClipHistoryPresented = false

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

    private var track: StepSequenceTrack { session.store.selectedTrack }
    private var bank: TrackPatternBank { session.store.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { session.store.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { session.store.selectedPattern(for: track.id) }
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
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleClips: [ClipPoolEntry] { session.store.compatibleClips(for: track) }
    private var compatibleSourceGenerators: [GeneratorPoolEntry] { session.store.compatibleGenerators(for: track) }
    private var compatibleModifierGenerators: [GeneratorPoolEntry] { session.store.compatibleModifierGenerators(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { session.store.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { session.store.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { session.store.clipEntry(id: selectedPattern.sourceRef.clipID) }
    private var selectedSourceGenerator: GeneratorPoolEntry? {
        session.store.generatorEntry(id: selectedPattern.sourceRef.generatorID)
    }
    private var selectedModifierGenerator: GeneratorPoolEntry? {
        session.store.generatorEntry(id: selectedPattern.sourceRef.modifierGeneratorID)
    }
    private var previewClipContent: ClipContent {
        currentClip?.content
            ?? .emptyNoteGrid(lengthSteps: 16)
    }
    private var defaultClipNote: ClipStepNote {
        ClipStepNote(
            pitch: track.pitches.first ?? 60,
            velocity: track.velocity,
            lengthSteps: track.gateLength
        ).normalized
    }
    private var playingClipStepIndex: Int? {
        guard engineController.isRunning,
              let clip = currentClip,
              selectedPattern.sourceRef.clipID == clip.id
        else {
            return nil
        }

        let phrase = session.store.selectedPhrase
        let phraseStep = Int(engineController.transportTickIndex % UInt64(max(1, phrase.stepCount)))
        let playingPatternIndex = resolvedPatternIndex(in: phrase, trackID: track.id, stepIndex: phraseStep)
        guard playingPatternIndex == selectedPatternIndex else {
            return nil
        }

        return phraseStep % max(1, clip.content.stepCount)
    }

    private var orderedMacros: [TrackMacroBinding] {
        track.macros.sorted { $0.slotIndex < $1.slotIndex }
    }

    /// Phrase-layer fallback values for each macro binding on this track.
    ///
    /// Reads `layer.defaults[trackID]` for the binding's layer; falls back to the
    /// descriptor default when no layer default has been set.
    private var macroFallbackValues: [UUID: Double] {
        var result: [UUID: Double] = [:]
        let trackID = track.id
        let layers = session.store.layers
        for binding in orderedMacros {
            let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
            if let layer = layers.first(where: { $0.id == layerID }),
               case let .scalar(v) = layer.defaults[trackID] {
                result[binding.id] = v
            } else {
                result[binding.id] = binding.descriptor.defaultValue
            }
        }
        return result
    }

    private var clipMacroSlots: [ClipMacroSlot] {
        (0..<8).map { slotIndex in
            ClipMacroSlot(
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Pattern", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots,
                        bypassState: .notApplicable,
                        onBypassToggle: { _ in }
                    )

                    Picker("Editor Section", selection: $selectedTab) {
                        ForEach(TrackSourceEditorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Group {
                switch selectedTab {
                case .source:
                    sourceTab
                case .modifiers:
                    modifiersTab
                }
            }
        }
        .sheet(isPresented: $isShowingModifierPicker) {
            TrackSourceGeneratorSelectionSheet(
                title: "Select Modifier",
                generators: compatibleModifierGenerators,
                onSelect: { generator in
                    selectModifier(generator)
                    isShowingModifierPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(.clear)
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
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $isClipHistoryPresented) {
            ClipHistoryCaptureSheet(
                trackID: track.id,
                trackName: track.name,
                selectedSlotIndex: selectedPatternIndex,
                occupiedSlots: occupiedPatternSlots,
                accent: accent,
                capturedContent: { lengthSteps in
                    engineController.capturedClipContent(trackID: track.id, lengthSteps: lengthSteps)
                },
                onSave: { slotIndex, lengthSteps in
                    session.saveRollingCaptureToPatternSlot(
                        trackID: track.id,
                        slotIndex: slotIndex,
                        lengthSteps: lengthSteps
                    ) != nil
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .onChange(of: selectedPatternIndex) { _, _ in
            sourcePickerStep = nil
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .source {
                sourcePickerStep = nil
            }
        }
    }

    @ViewBuilder
    private var sourceTab: some View {
        TrackSourceSourceTabContent(
            sourceMode: selectedSourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedSourceGenerator,
            compatibleClips: compatibleClips,
            compatibleGenerators: compatibleSourceGenerators,
            sourcePickerStep: sourcePickerStep,
            accent: accent,
            previewClipContent: previewClipContent,
            defaultClipNote: defaultClipNote,
            clipMacroSlots: clipMacroSlots,
            macroLanes: currentClip?.macroLanes ?? [:],
            macroFallbackValues: macroFallbackValues,
            canAssignAUMacros: canAssignAUMacros,
            playingStepIndex: playingClipStepIndex,
            generatedSourceInputClips: generatedSourceInputClips,
            harmonicSidechainClips: harmonicSidechainClips,
            onAssignMacroSlot: prepareAndPresentMacroSlotPicker(slotIndex:),
            onUpdateMacroLanes: updateClipMacroLanes,
            onUpdateClipContent: updateClipContent,
            onShowSourcePicker: { updateSourcePickerStep(.showRoot) },
            onBackOutSourcePicker: { updateSourcePickerStep(.cancel) },
            onShowSourceGeneratorPool: { updateSourcePickerStep(.showGeneratorPool) },
            onShowSourceClipPool: { updateSourcePickerStep(.showClipPool) },
            onCreateBlankGeneratorSource: createBlankGeneratorSource,
            onAssignGeneratorSource: assignGeneratorSource,
            onCreateBlankClipSource: createBlankClipSource,
            onAssignClipSource: assignClipSource,
            onPresentClipHistory: presentClipHistory,
            onRemoveSource: removeSource,
            onUpdateGeneratorParams: updateSourceGeneratorParams
        )
    }

    private func updateSourcePickerStep(_ action: TrackSourceContainedSourcePickerNavigationAction) {
        sourcePickerStep = TrackSourceContainedSourcePickerNavigation.destination(
            from: sourcePickerStep,
            action: action
        )
    }

    @ViewBuilder
    private var modifiersTab: some View {
        TrackSourceModifierTabContent(
            selectedGenerator: selectedModifierGenerator,
            isBypassed: selectedPattern.sourceRef.modifierBypassed,
            compatibleGenerators: compatibleModifierGenerators,
            sourceMode: selectedSourceMode,
            generatedSourceInputClips: generatedSourceInputClips,
            harmonicSidechainClips: harmonicSidechainClips,
            onShowGeneratorPicker: { isShowingModifierPicker = true },
            onToggleBypassed: {
                session.setPatternModifierBypassed(
                    !selectedPattern.sourceRef.modifierBypassed,
                    for: track.id,
                    slotIndex: selectedPatternIndex
                )
            },
            onRemoveModifier: {
                session.setPatternModifierGeneratorID(
                    nil,
                    for: track.id,
                    slotIndex: selectedPatternIndex
                )
            },
            onUpdateGeneratorParams: updateModifierGeneratorParams
        )
    }

    private func prepareAndPresentMacroSlotPicker(slotIndex: Int) {
        guard canAssignAUMacros else {
            return
        }
        engineController.prepareAudioUnit(for: track.id)
        macroSlotPickerRequest = MacroSlotPickerRequest(slotIndex: slotIndex)
    }

    private func assignMacro(_ parameter: AUParameterDescriptor, to slotIndex: Int) {
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: parameter.displayName,
            minValue: parameter.minValue,
            maxValue: parameter.maxValue,
            defaultValue: parameter.defaultValue,
            valueType: .scalar,
            source: .auParameter(address: parameter.address, identifier: parameter.identifier)
        )
        session.assignAUMacroToSlot(descriptor, to: track.id, slotIndex: slotIndex)
    }

    private func updateClipMacroLanes(_ updatedLanes: [UUID: MacroLane]) {
        let trackID = track.id
        session.ensureClipAndMutate(trackID: trackID) { _, entry in
            entry.macroLanes = updatedLanes
        }
    }

    private func updateClipContent(_ updated: ClipContent) {
        let trackID = track.id
        #if DEBUG
        let mutationStart = StepGridTapDiagnostics.now
        StepGridTapDiagnostics.log(
            "storeMutationStart",
            details: "trackID=\(trackID.uuidString)"
        )
        #endif
        session.ensureClipAndMutate(trackID: trackID) { _, entry in
            entry.content = updated
        }
        #if DEBUG
        StepGridTapDiagnostics.log(
            "storeMutationEnd",
            details: "elapsed=\(StepGridTapDiagnostics.elapsedMilliseconds(since: mutationStart)) trackID=\(trackID.uuidString)"
        )
        #endif
    }

    private func updateSourceGeneratorParams(_ updated: GeneratorParams) {
        guard let generatorID = selectedSourceGenerator?.id else {
            return
        }
        session.mutateGenerator(id: generatorID) { entry in
            entry.params = updated
        }
    }

    private func updateModifierGeneratorParams(_ updated: GeneratorParams) {
        guard let generatorID = selectedModifierGenerator?.id else {
            return
        }
        session.mutateGenerator(id: generatorID) { entry in
            entry.params = updated
        }
    }

    private func presentClipHistory() {
        isClipHistoryPresented = true
    }

    private func createBlankGeneratorSource() {
        _ = session.createBlankGeneratorSource(trackID: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
    }

    private func assignGeneratorSource(_ generator: GeneratorPoolEntry) {
        session.assignGeneratorSource(generator.id, to: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
    }

    private func createBlankClipSource() {
        _ = session.createBlankClipSource(trackID: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
    }

    private func assignClipSource(_ clip: ClipPoolEntry) {
        session.assignClipSource(clip.id, to: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
    }

    private func selectModifier(_ generator: GeneratorPoolEntry) {
        let trackID = track.id
        // For modifier selection, we may need to ensure a clip exists when the slot
        // is in clip mode without a clip ID yet. Use batch to handle both steps atomically.
        let currentPattern = selectedPattern
        let currentSourceMode = selectedSourceMode
        let slotIndex = selectedPatternIndex
        session.batch(impact: .snapshotOnly, changed: .full) { s in
            var p = s.exportToProject()
            var clipID = currentPattern.sourceRef.clipID
            if currentSourceMode == .clip, clipID == nil {
                clipID = p.ensureClipForCurrentPattern(trackID: trackID)
                // Sync new clip into store if created.
                let newClips = p.clipPool.filter { c in
                    s.exportToProject().clipPool.first(where: { $0.id == c.id }) == nil
                }
                for clip in newClips { s.appendClip(clip) }
                for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
            }
            let updated = SourceRef(
                mode: currentSourceMode,
                generatorID: currentPattern.sourceRef.generatorID,
                clipID: clipID,
                modifierGeneratorID: generator.id,
                modifierBypassed: false
            )
            p.setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
            for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
        }
    }

    private func removeSource() {
        session.removeSelectedSlotSource(trackID: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
    }

    private func resolvedPatternIndex(in phrase: PhraseModel, trackID: UUID, stepIndex: Int) -> Int {
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

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { session.store.selectedPatternIndex(for: track.id) },
            set: { newValue in
                let trackID = track.id
                session.setSelectedPatternIndex(newValue, for: trackID)
            }
        )
    }
}

private struct ClipHistoryCaptureSheet: View {
    let trackID: UUID
    let trackName: String
    let selectedSlotIndex: Int
    let occupiedSlots: Set<Int>
    let accent: Color
    let capturedContent: (Int) -> ClipContent?
    let onSave: (Int, Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var lengthSteps = 16
    @State private var destinationSlotIndex: Int
    @State private var saveMessage: String?

    private static let lengthOptions = [16, 32, 64, 128, 256]

    init(
        trackID: UUID,
        trackName: String,
        selectedSlotIndex: Int,
        occupiedSlots: Set<Int>,
        accent: Color,
        capturedContent: @escaping (Int) -> ClipContent?,
        onSave: @escaping (Int, Int) -> Bool
    ) {
        self.trackID = trackID
        self.trackName = trackName
        self.selectedSlotIndex = selectedSlotIndex
        self.occupiedSlots = occupiedSlots
        self.accent = accent
        self.capturedContent = capturedContent
        self.onSave = onSave
        let preferredSlot = (0..<TrackPatternBank.slotCount).first { $0 != selectedSlotIndex } ?? selectedSlotIndex
        _destinationSlotIndex = State(initialValue: preferredSlot)
    }

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: "Clip History", eyebrow: trackName, accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            lengthPicker
                            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                                clipPreview(content: capturedContent(lengthSteps))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Save To Pattern Slot")
                                .studioText(.labelBold)
                                .foregroundStyle(StudioTheme.text)
                            patternSlotGrid
                            saveControls
                        }
                        .frame(width: 280, alignment: .topLeading)
                    }
                }
            }
            .padding(24)
            .frame(minWidth: 840, minHeight: 560)
        }
    }

    private var lengthPicker: some View {
        HStack(spacing: 8) {
            Text("Length")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
            ForEach(Self.lengthOptions, id: \.self) { option in
                Button {
                    lengthSteps = option
                    saveMessage = nil
                } label: {
                    Text("\(option / 16) bar\(option == 16 ? "" : "s")")
                        .studioText(.labelBold)
                        .foregroundStyle(lengthSteps == option ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            (lengthSteps == option ? accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(lengthSteps == option ? accent : StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clipPreview(content: ClipContent?) -> some View {
        let normalized = content?.normalized
        let steps = normalized?.noteGridSteps ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Most Recent \(lengthSteps / 16) Bar\(lengthSteps == 16 ? "" : "s")")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Spacer()
                Text("\(activeStepCount(in: steps)) active / \(lengthSteps) steps")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if steps.isEmpty {
                Text("Play the generator to fill the history buffer.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    LazyVGrid(columns: historyGridColumns, alignment: .leading, spacing: 6) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            ClipHistoryStepCell(step: step, index: index, accent: accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .frame(minHeight: 240, maxHeight: 300)
            }
        }
    }

    private var historyGridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(34), spacing: 6), count: 16)
    }

    private var patternSlotGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private var patternSlotGrid: some View {
        LazyVGrid(columns: patternSlotGridColumns, spacing: 8) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                ClipHistoryPatternSlotButton(
                    slotIndex: slotIndex,
                    subtitle: slotSubtitle(for: slotIndex),
                    isSelected: slotIndex == destinationSlotIndex,
                    accent: accent
                ) {
                    destinationSlotIndex = slotIndex
                    saveMessage = nil
                }
            }
        }
    }

    private var saveControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let saveMessage {
                Text(saveMessage)
                    .studioText(.label)
                    .foregroundStyle(saveMessage == "Saved" ? StudioTheme.success : StudioTheme.amber)
            }

            HStack(spacing: 10) {
                Button {
                    guard onSave(destinationSlotIndex, lengthSteps) else {
                        saveMessage = "No captured notes yet"
                        return
                    }
                    saveMessage = "Saved"
                    dismiss()
                } label: {
                    Text("Save Capture")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                        .overlay(Capsule().stroke(accent, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
            }
        }
    }

    private func activeStepCount(in steps: [ClipStep]) -> Int {
        steps.filter { !($0.main?.notes.isEmpty ?? true) }.count
    }

    private func slotSubtitle(for slotIndex: Int) -> String {
        if slotIndex == selectedSlotIndex {
            return "current"
        }
        if occupiedSlots.contains(slotIndex) {
            return "used"
        }
        return "empty"
    }
}

private struct ClipHistoryPatternSlotButton: View {
    let slotIndex: Int
    let subtitle: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("P\(slotIndex + 1)")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? accent : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundFill: Color {
        isSelected ? accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)
    }
}

private struct ClipHistoryStepCell: View {
    let step: ClipStep
    let index: Int
    let accent: Color

    private var notes: [ClipStepNote] {
        step.main?.notes ?? []
    }

    private var isActive: Bool {
        !notes.isEmpty
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(index + 1)")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
            Text(notes.first.map { "\($0.pitch)" } ?? "-")
                .studioText(.labelBold)
                .foregroundStyle(isActive ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 34, height: 46)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(isActive ? accent : StudioTheme.border, lineWidth: 1)
        )
        .help(notes.map { "pitch \($0.pitch), velocity \($0.velocity)" }.joined(separator: "\n"))
    }

    private var backgroundFill: Color {
        isActive ? accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)
    }
}

private struct GeneratorSelectionSheet: View {
    let title: String
    let generators: [GeneratorPoolEntry]
    let onSelect: (GeneratorPoolEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: title, eyebrow: "Choose a compatible generator for this slot.", accent: StudioTheme.cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    if generators.isEmpty {
                        Text("No compatible generators are available.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(generators) { generator in
                                    Button {
                                        onSelect(generator)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(generator.name)
                                                .studioText(.bodyBold)
                                                .foregroundStyle(StudioTheme.text)
                                            Text(generator.kind.label)
                                                .studioText(.label)
                                                .foregroundStyle(StudioTheme.mutedText)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                                                .stroke(StudioTheme.border, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .padding(24)
            .frame(minWidth: 520, minHeight: 360)
        }
    }
}
