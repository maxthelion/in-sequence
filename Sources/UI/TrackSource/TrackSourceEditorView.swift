import SwiftUI

enum TrackSourceEditorTab: String, CaseIterable, Identifiable {
    case stepsClip = "steps-clip"
    case sound
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stepsClip:
            return "Steps/Clip"
        case .sound:
            return "Sound"
        case .fx:
            return "FX"
        case .macros:
            return "Macros"
        case .mixer:
            return "Mixer"
        }
    }

    static func tab(forVisualCommand rawValue: String) -> TrackSourceEditorTab? {
        switch rawValue {
        case "source":
            return .stepsClip
        case "routing":
            return .mixer
        case "steps", "stepsClip", "steps-clip":
            return .stepsClip
        default:
            return TrackSourceEditorTab(rawValue: rawValue)
        }
    }

    func isAvailable(in mode: WorkspaceMode) -> Bool {
        true
    }
}

struct TrackFillPreviewHeaderPresentation: Equatable {
    enum Availability: Equatable {
        case enabled
        case unavailable
    }

    let availability: Availability
    let isActive: Bool
    let buttonTitle: String
    let statusText: String
    let accessibilityLabel: String

    var isEnabled: Bool {
        availability == .enabled
    }

    static func resolve(
        sourceMode: TrackSourceMode,
        currentClip: ClipPoolEntry?,
        selectedTrackID: UUID,
        previewState: TrackFillPreviewState
    ) -> TrackFillPreviewHeaderPresentation {
        guard sourceMode == .clip, currentClip != nil else {
            return TrackFillPreviewHeaderPresentation(
                availability: .unavailable,
                isActive: false,
                buttonTitle: "Fill Preview",
                statusText: "Fill preview is available for clip-backed tracks only in v1.",
                accessibilityLabel: "Fill preview unavailable"
            )
        }

        let isActive = previewState.isActive(for: selectedTrackID)
        return TrackFillPreviewHeaderPresentation(
            availability: .enabled,
            isActive: isActive,
            buttonTitle: "Fill Preview",
            statusText: isActive
                ? "Hearing the fill lane for this track only."
                : "Hearing phrase-resolved playback for this track.",
            accessibilityLabel: isActive ? "Disable fill preview" : "Enable fill preview"
        )
    }
}

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let accent: Color
    let stepGridWorkspaceModel: TrackStepGridWorkspaceModel

    @State private var selectedTab: TrackSourceEditorTab = .stepsClip
    @State private var sourcePickerStep: TrackSourceContainedSourcePickerStep?
    @State private var modifierPickerStep: TrackSourceContainedModifierPickerStep?
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?
    @State private var clipHistoryModel: ClipHistoryTransferViewModel?
    @State private var clipHistoryToast: String?

    private var clipHistoryDestinationMode: Bool {
        clipHistoryModel?.isSaveArmed == true
    }

    private var pendingClipHistoryReplaceSlot: Int? {
        clipHistoryModel?.pendingReplaceSlotIndex
    }

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

    private var track: StepSequenceTrack { session.store.selectedTrack }
    private var bank: TrackPatternBank { session.store.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { session.store.selectedPatternIndex(for: track.id) }
    private var selectedPatternAddress: PatternSlotAddress {
        PatternSlotAddress(trackID: track.id, slotIndex: selectedPatternIndex)
    }
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
    private var sourceDisplayState: TrackSourceSourceDisplayState {
        TrackSourceSourceDisplayState.resolve(
            sourceMode: selectedSourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedSourceGenerator
        )
    }
    private var modifierDisplayState: TrackSourceModifierDisplayState {
        TrackSourceModifierDisplayState.resolve(
            trackType: track.trackType,
            selectedGenerator: selectedModifierGenerator,
            isBypassed: selectedPattern.sourceRef.modifierBypassed
        )
    }
    private var historyDisplayState: TrackSourceHistoryDisplayState {
        TrackSourceHistoryDisplayState.resolve(
            trackType: track.trackType,
            sourceState: sourceDisplayState
        )
    }

    /// One-glance audio-path summary for the ROUTING tab pill + tab body.
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
        let playhead = PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex)
        guard playhead.patternIndex(for: track.id, patternLayer: session.store.patternLayer) == selectedPatternIndex else {
            return nil
        }

        return playhead.clipStepIndex(clipStepCount: clip.content.stepCount)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Pattern", accent: accent) {
                VStack(alignment: .leading, spacing: 10) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots,
                        bypassState: .notApplicable,
                        onBypassToggle: { _ in },
                        destinationMode: clipHistoryDestinationMode
                            ? TrackPatternSlotPalette.DestinationMode(
                                pendingReplaceSlot: pendingClipHistoryReplaceSlot,
                                accent: StudioTheme.success
                            )
                            : nil,
                        onDestinationSelect: selectClipHistoryDestination
                    )

                    clipHistoryDestinationRow
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                trackSourceHeader

                Group {
                    switch selectedTab {
                    case .stepsClip:
                        sourceTab
                    case .sound:
                        soundTab
                    case .fx:
                        fxTab
                    case .macros:
                        macrosTab
                    case .mixer:
                        mixerTab
                    }
                }
            }
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
        .overlay(alignment: .bottomTrailing) {
            if let clipHistoryToast {
                Text(clipHistoryToast)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(StudioTheme.success, in: Capsule())
                    .padding(StudioMetrics.Spacing.comfortable)
            }
        }
        .onChange(of: selectedPatternIndex) { _, _ in
            sourcePickerStep = nil
            modifierPickerStep = nil
            resetClipHistoryDestinationMode()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .stepsClip {
                sourcePickerStep = nil
            }
            if newValue != .stepsClip {
                modifierPickerStep = nil
            }
            resetClipHistoryModel()
        }
        .onChange(of: track.id) { _, _ in
            session.clearTrackFillPreview(reason: .selectedTrackChanged)
        }
        .onAppear {
            syncStepGridCoordinator()
        }
        .onChange(of: currentClip?.id) { _, _ in
            syncStepGridCoordinator()
        }
        .onDisappear {
            session.clearTrackFillPreview(reason: .editorClosed)
        }
        .onChange(of: session.workspaceMode) { _, newMode in
            if !selectedTab.isAvailable(in: newMode) {
                selectedTab = .stepsClip
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackSourceEditorVisualCommand)) { notification in
            guard let command = notification.object as? String,
                  command.hasPrefix("select-tab:"),
                  let tab = TrackSourceEditorTab.tab(forVisualCommand: String(command.dropFirst("select-tab:".count))),
                  tab.isAvailable(in: session.workspaceMode)
            else { return }
            selectedTab = tab
        }
        .task(id: clipHistoryLiveRefreshKey) {
            await refreshClipHistoryWhileVisible()
        }
    }

    private var trackSourceHeader: some View {
        TrackSourceSlotWellTabBar(
            selectedTab: $selectedTab,
            sourceState: sourceDisplayState,
            modifierState: modifierDisplayState,
            routingState: TrackSourceRoutingDisplayState(
                pillSummary: routingPathSummary.pillSummary,
                soundBadgeTitle: routingPathSummary.instrumentLabel
            ),
            accent: accent
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 10)
        .padding(.bottom, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill))
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
            macroBindings: track.macros,
            macroLanes: currentClip?.macroLanes ?? [:],
            macroFallbackValues: macroFallbackValues,
            canAssignAUMacros: canAssignAUMacros,
            playingStepIndex: playingClipStepIndex,
            stepGridCoordinator: stepGridWorkspaceModel.coordinator,
            generatedSourceInputClips: generatedSourceInputClips,
            harmonicSidechainClips: harmonicSidechainClips,
            onAssignMacroSlot: prepareAndPresentMacroSlotPicker(slotIndex:),
            onShowSourcePicker: { updateSourcePickerStep(.showRoot) },
            onBackOutSourcePicker: { updateSourcePickerStep(.cancel) },
            onShowSourceGeneratorPool: { updateSourcePickerStep(.showGeneratorPool) },
            onShowSourceClipPool: { updateSourcePickerStep(.showClipPool) },
            onCreateBlankGeneratorSource: createBlankGeneratorSource,
            onAssignGeneratorSource: assignGeneratorSource,
            onCreateBlankClipSource: createBlankClipSource,
            onAssignClipSource: assignClipSource,
            onRemoveSource: removeSource,
            onUpdateGeneratorParams: updateSourceGeneratorParams
        )
    }

    /// Mirrors the slicer workspace: the shared step-grid coordinator follows
    /// the clip shown in the Source tab. `ClipContentPreview` refines the
    /// coordinator's editable/active layers from its own layer state.
    private func syncStepGridCoordinator() {
        guard selectedSourceMode == .clip, let clipID = currentClip?.id else {
            stepGridWorkspaceModel.reset()
            return
        }
        _ = stepGridWorkspaceModel.coordinator(
            for: clipID,
            clipMutator: session,
            editableLayers: [.velocity, .chance]
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
            trackType: track.trackType,
            selectedGenerator: selectedModifierGenerator,
            isBypassed: selectedPattern.sourceRef.modifierBypassed,
            compatibleGenerators: compatibleModifierGenerators,
            modifierPickerStep: modifierPickerStep,
            sourceMode: selectedSourceMode,
            generatedSourceInputClips: generatedSourceInputClips,
            harmonicSidechainClips: harmonicSidechainClips,
            onShowGeneratorPicker: { updateModifierPickerStep(.showRoot) },
            onBackOutGeneratorPicker: { updateModifierPickerStep(.cancel) },
            onShowModifierPool: { updateModifierPickerStep(.showModifierPool) },
            onCreateBlankModifier: createBlankModifier,
            onSelectModifier: selectModifier,
            onToggleBypassed: {
                session.setPatternModifierBypassed(
                    !selectedPattern.sourceRef.modifierBypassed,
                    at: selectedPatternAddress
                )
            },
            onRemoveModifier: {
                session.setPatternModifierGeneratorID(
                    nil,
                    at: selectedPatternAddress
                )
            },
            onUpdateGeneratorParams: updateModifierGeneratorParams
        )
    }

    @ViewBuilder
    private var clipHistoryTab: some View {
        if !historyDisplayState.isAvailable {
            TrackSourceSelectedWellBody(accent: StudioTheme.success, isEmpty: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                    Text(clipHistoryUnavailableReason)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StudioMetrics.Spacing.standard)
            }
            .onAppear {
                resetClipHistoryModel()
            }
        } else if let clipHistoryModel {
            TrackSourceClipHistoryTabContent(
                model: clipHistoryModel,
                accent: StudioTheme.success,
                sourceSummary: clipHistorySourceSummary,
                isDestinationMode: clipHistoryDestinationMode,
                isTransportRunning: engineController.isRunning,
                onSaveClip: enterClipHistoryDestinationMode
            )
            .onAppear {
                if clipHistoryModel.trackID != track.id {
                    refreshClipHistoryModel()
                }
            }
        } else {
            TrackSourceSelectedWellBody(accent: StudioTheme.success, isEmpty: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                    Text("Listening to the rolling history buffer.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StudioMetrics.Spacing.standard)
            }
            .onAppear(perform: refreshClipHistoryModel)
        }
    }

    private var clipHistorySourceSummary: String {
        switch sourceDisplayState {
        case .occupiedClip:
            return currentClip.map { "Clip source: \($0.name)" } ?? "Clip source"
        case .occupiedGenerator:
            return selectedSourceGenerator.map { "Generator live history: \($0.name)" } ?? "Generator live history"
        case .empty:
            return "No source assigned"
        }
    }

    private var clipHistoryUnavailableReason: String {
        if case let .unavailable(reason) = historyDisplayState {
            return reason
        }
        return "History is unavailable for this source."
    }

    @ViewBuilder
    private var soundTab: some View {
        TrackRoutingTabContent(
            document: $document,
            summary: routingPathSummary,
            mode: .sound,
            accent: accent
        )
    }

    @ViewBuilder
    private var fxTab: some View {
        TrackSourceSelectedWellBody(accent: StudioTheme.violet, isEmpty: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FX")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                Text("Per-track insert chain arrives in the FX slice.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
        }
    }

    @ViewBuilder
    private var macrosTab: some View {
        TrackSourceSelectedWellBody(accent: StudioTheme.amber, isEmpty: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Macros")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                Text("M1–M8 slot assignments. Drag to set, right-click to change or remove.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                macroSlotGrid
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
        }
    }

    private let macroSlotColumns = [
        GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 10, alignment: .top)
    ]

    @ViewBuilder
    private var macroSlotGrid: some View {
        LazyVGrid(columns: macroSlotColumns, alignment: .leading, spacing: 12) {
            ForEach(clipMacroSlots) { slot in
                macroSlotKnob(for: slot)
            }
        }
    }

    @ViewBuilder
    private func macroSlotKnob(for slot: MacroSlot) -> some View {
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

    @ViewBuilder
    private var mixerTab: some View {
        TrackRoutingTabContent(
            document: $document,
            summary: routingPathSummary,
            mode: .mixer,
            accent: accent
        )
    }

    @ViewBuilder
    private var clipHistoryDestinationRow: some View {
        if clipHistoryDestinationMode {
            HStack(spacing: 10) {
                if let pendingClipHistoryReplaceSlot {
                    Text("P\(pendingClipHistoryReplaceSlot + 1) occupied")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.amber)
                    Spacer(minLength: 0)
                    Button("Replace") {
                        confirmClipHistoryReplace()
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    Button("Cancel") {
                        resetClipHistoryDestinationMode()
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                } else {
                    Text("Save armed · choose a pattern slot")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer(minLength: 0)
                    Button("Cancel") {
                        resetClipHistoryDestinationMode()
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            // Colour identifies, it never floods (ux-canon rule 12): the armed
            // banner stays neutral; the green lives in its outline.
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.success.opacity(StudioOpacity.ghostStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
    }

    private func updateModifierPickerStep(_ action: TrackSourceContainedModifierPickerNavigationAction) {
        modifierPickerStep = TrackSourceContainedModifierPickerNavigation.destination(
            from: modifierPickerStep,
            action: action
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
        let descriptor = TrackMacroDescriptor(auParameter: parameter)
        _ = session.assignAUMacroToSlot(descriptor, to: track.id, slotIndex: slotIndex)
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

    private func refreshClipHistoryModel() {
        let trackID = track.id
        let frozenBank = session.store.patternBank(for: trackID)
        clipHistoryModel?.stopAudition()
        clipHistoryModel = ClipHistoryTransferViewModel(
            trackID: trackID,
            snapshot: engineController.captureSnapshot(trackID: trackID),
            destinationSlots: ClipHistoryTransferViewModel.destinationSlots(
                from: frozenBank,
                clipName: { clipID in session.store.clipEntry(id: clipID)?.name }
            ),
            setAuditionOverride: { state in
                engineController.setAuditionOverride(state, for: trackID)
            }
        )
        resetClipHistoryDestinationMode()
    }

    private var clipHistoryLiveRefreshKey: String {
        "history-inactive"
    }

    @MainActor
    private func refreshClipHistoryWhileVisible() async {
        return
    }

    private func updateClipHistoryLiveSnapshot() {
        guard let model = clipHistoryModel else {
            refreshClipHistoryModel()
            return
        }

        guard model.trackID == track.id else {
            refreshClipHistoryModel()
            return
        }

        guard model.selectedSourceIndex == nil else {
            return
        }

        model.updateLiveSnapshot(engineController.captureSnapshot(trackID: model.trackID))
    }

    private func enterClipHistoryDestinationMode() {
        guard let model = clipHistoryModel else {
            refreshClipHistoryModel()
            clipHistoryModel?.saveError = "Choose a history cell first."
            return
        }
        guard model.trackID == track.id else {
            resetClipHistoryModel()
            refreshClipHistoryModel()
            clipHistoryModel?.saveError = "History reloaded for the selected track."
            return
        }
        model.armSave()
    }

    private func selectClipHistoryDestination(_ slotIndex: Int) {
        guard let model = clipHistoryModel,
              model.isSaveArmed,
              model.trackID == track.id
        else {
            return
        }

        model.selectDestination(slotIndex)
        if model.requiresReplaceConfirmation {
            return
        }

        saveSelectedClipHistory(to: slotIndex)
    }

    private func confirmClipHistoryReplace() {
        guard let model = clipHistoryModel,
              let slotIndex = model.pendingReplaceSlotIndex,
              model.trackID == track.id
        else {
            return
        }
        model.confirmReplace()
        saveSelectedClipHistory(to: slotIndex)
    }

    private func saveSelectedClipHistory(to slotIndex: Int) {
        guard let model = clipHistoryModel,
              model.trackID == track.id,
              let content = model.selectedPseudoClip?.noteGrid
        else {
            clipHistoryModel?.saveError = "Choose a history cell first."
            return
        }

        model.stopAudition()
        let clipID = session.saveMaterializedClipToPatternSlot(
            trackID: model.trackID,
            slotIndex: slotIndex,
            content: content,
            name: "Capture P\(slotIndex + 1)"
        )
        if clipID == nil {
            model.saveError = "Could not save this capture."
            return
        }

        showClipHistoryToast("Saved capture to P\(slotIndex + 1)")
        resetClipHistoryDestinationMode()
        refreshClipHistoryModel()
    }

    private func resetClipHistoryModel() {
        resetClipHistoryDestinationMode()
        clipHistoryModel?.stopAudition()
        clipHistoryModel = nil
    }

    private func resetClipHistoryDestinationMode() {
        clipHistoryModel?.disarmSave()
    }

    private func showClipHistoryToast(_ message: String) {
        clipHistoryToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if clipHistoryToast == message {
                clipHistoryToast = nil
            }
        }
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
        session.assignModifierGenerator(generator.id, to: selectedPatternAddress)
        modifierPickerStep = nil
    }

    private func createBlankModifier() {
        _ = session.createBlankModifierGenerator(at: selectedPatternAddress)
        modifierPickerStep = nil
    }

    private func removeSource() {
        session.removeSelectedSlotSource(trackID: track.id, slotIndex: selectedPatternIndex)
        sourcePickerStep = nil
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

@MainActor
@Observable
final class ClipHistoryTransferViewModel {
    struct DestinationSlot: Equatable, Identifiable {
        let slotIndex: Int
        let isOccupied: Bool
        let clipName: String?

        var id: Int { slotIndex }
    }

    struct SourceCell: Equatable, Identifiable {
        let index: Int
        let startStep: Int
        let noteCount: Int
        let isSelectable: Bool

        var id: Int { index }
        var isEmpty: Bool { noteCount == 0 }
    }

    let trackID: UUID
    var snapshot: CaptureSnapshot
    let destinationSlots: [DestinationSlot]
    var selectedSourceIndex: Int?
    var selectedDestinationIndex: Int?
    var lengthSteps: Int
    var isAuditioning = false
    var isSaveArmed = false
    var replaceConfirmed = false
    var saveError: String?

    private let setAuditionOverride: (PseudoClipState?) -> Void

    static let sourceCellCount = 16
    static let stepsPerCell = 16
    static let lengthOptions = PseudoClipState.supportedLengthSteps

    init(
        trackID: UUID,
        snapshot: CaptureSnapshot,
        destinationSlots: [DestinationSlot],
        setAuditionOverride: @escaping (PseudoClipState?) -> Void
    ) {
        self.trackID = trackID
        self.snapshot = snapshot
        self.destinationSlots = destinationSlots
        self.lengthSteps = 16
        self.setAuditionOverride = setAuditionOverride
    }

    static func destinationSlots(
        from bank: TrackPatternBank,
        clipName: (UUID) -> String?
    ) -> [DestinationSlot] {
        (0..<TrackPatternBank.slotCount).map { index in
            let slot = bank.slot(at: index)
            let clipID = slot.sourceRef.clipID
            return DestinationSlot(
                slotIndex: index,
                isOccupied: !slot.sourceRef.isEmpty,
                clipName: clipID.flatMap(clipName) ?? slot.name
            )
        }
    }

    var sourceCells: [SourceCell] {
        let counts = noteCountsBySnapshotOffset()
        return (0..<Self.sourceCellCount).map { index in
            let start = index * Self.stepsPerCell
            let end = min(start + Self.stepsPerCell, snapshot.maxSteps)
            let noteCount = start < end
                ? (start..<end).reduce(0) { $0 + (counts[$1] ?? 0) }
                : 0
            return SourceCell(
                index: index,
                startStep: start,
                noteCount: noteCount,
                isSelectable: noteCount > 0 && isSelectableSourceRange(startStep: start, lengthSteps: lengthSteps)
            )
        }
    }

    var selectedPseudoClip: PseudoClipState? {
        guard let selectedSourceIndex,
              sourceCells.indices.contains(selectedSourceIndex),
              sourceCells[selectedSourceIndex].isSelectable
        else {
            return nil
        }
        return PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: selectedSourceIndex * Self.stepsPerCell,
            lengthSteps: lengthSteps
        )
    }

    var previewContent: ClipContent? {
        previewPseudoClip?.noteGrid
    }

    var previewLengthSteps: Int {
        previewPseudoClip?.lengthSteps ?? Self.stepsPerCell
    }

    /// Number of horizontal step regions the preview grid divides into.
    ///
    /// Auditioning a history segment divides by the selection's step count
    /// (16 regions for a one-bar selection, 32 for two bars). The live
    /// rolling view always divides by one full bar so the grid stays stable
    /// while the current bar fills.
    var previewGridSteps: Int {
        selectedPseudoClip?.lengthSteps ?? Self.stepsPerCell
    }

    /// Step index of the currently-filling position in the live bar, or nil
    /// while auditioning a selected history segment (or before any capture).
    var liveFillStepIndex: Int? {
        guard selectedPseudoClip == nil else {
            return nil
        }
        guard let livePreviewRange else {
            return nil
        }
        return min(livePreviewRange.lengthSteps - 1, Self.stepsPerCell - 1)
    }

    var previewLengthLabel: String {
        if selectedPseudoClip != nil {
            return selectedLengthLabel
        }
        return Self.lengthLabel(for: Self.stepsPerCell)
    }

    var selectedLengthBars: Int {
        max(1, Int(ceil(Double(lengthSteps) / Double(Self.stepsPerCell))))
    }

    var selectedLengthLabel: String {
        Self.lengthLabel(for: lengthSteps)
    }

    var canAudition: Bool {
        selectedPseudoClip != nil
    }

    var selectedDestination: DestinationSlot? {
        guard let selectedDestinationIndex else {
            return nil
        }
        return destinationSlots.first(where: { $0.slotIndex == selectedDestinationIndex })
    }

    var requiresReplaceConfirmation: Bool {
        selectedDestination?.isOccupied == true && !replaceConfirmed
    }

    /// Slot awaiting an explicit replace confirmation while save is armed.
    var pendingReplaceSlotIndex: Int? {
        guard isSaveArmed, requiresReplaceConfirmation else {
            return nil
        }
        return selectedDestinationIndex
    }

    var canSave: Bool {
        selectedPseudoClip != nil
            && selectedDestination != nil
            && !requiresReplaceConfirmation
    }

    func isSourceInSelectedRange(_ index: Int) -> Bool {
        guard let selectedSourceIndex else {
            return false
        }
        guard selectedPseudoClip != nil else {
            return false
        }
        let coveredCells = max(1, Int(ceil(Double(lengthSteps) / Double(Self.stepsPerCell))))
        return index >= selectedSourceIndex && index < selectedSourceIndex + coveredCells
    }

    func selectSource(_ index: Int) {
        guard let cell = sourceCells.first(where: { $0.index == index }),
              cell.isSelectable
        else {
            selectedSourceIndex = nil
            disarmSave()
            stopAudition()
            return
        }

        if selectedSourceIndex == index {
            selectedSourceIndex = nil
            disarmSave()
            stopAudition()
            return
        }

        selectedSourceIndex = index
        saveError = nil
        audition()
    }

    func setLengthSteps(_ steps: Int) {
        guard Self.lengthOptions.contains(steps) else {
            return
        }
        lengthSteps = steps
        saveError = nil
        if selectedPseudoClip == nil {
            selectedSourceIndex = nil
            disarmSave()
            stopAudition()
        } else {
            audition()
        }
    }

    /// Arms the pattern row as the save-destination chooser. Only valid
    /// while a history segment is selected; pattern slots indicate
    /// pressability exclusively in this state.
    func armSave() {
        guard selectedPseudoClip != nil else {
            saveError = "Choose a history cell first."
            return
        }
        saveError = nil
        selectedDestinationIndex = nil
        replaceConfirmed = false
        isSaveArmed = true
    }

    /// Returns the pattern row to normal selection/navigation.
    func disarmSave() {
        isSaveArmed = false
        selectedDestinationIndex = nil
        replaceConfirmed = false
    }

    func updateLiveSnapshot(_ updatedSnapshot: CaptureSnapshot) {
        guard selectedSourceIndex == nil else {
            return
        }
        guard snapshot != updatedSnapshot else {
            return
        }
        snapshot = updatedSnapshot
    }

    func selectDestination(_ index: Int) {
        guard destinationSlots.contains(where: { $0.slotIndex == index }) else {
            return
        }
        selectedDestinationIndex = index
        replaceConfirmed = false
        saveError = nil
    }

    func confirmReplace() {
        guard selectedDestination?.isOccupied == true else {
            return
        }
        replaceConfirmed = true
    }

    func cancelReplace() {
        selectedDestinationIndex = nil
        replaceConfirmed = false
    }

    func audition() {
        guard let selectedPseudoClip else {
            return
        }
        setAuditionOverride(selectedPseudoClip)
        isAuditioning = true
    }

    func stopAudition() {
        setAuditionOverride(nil)
        isAuditioning = false
    }

    func cancel() {
        stopAudition()
    }

    func save(using saveContent: (Int, ClipContent) -> Bool) -> Bool {
        guard canSave,
              let selectedDestination,
              let content = selectedPseudoClip?.noteGrid
        else {
            saveError = "Choose a source and destination first."
            return false
        }

        stopAudition()
        let didSave = saveContent(selectedDestination.slotIndex, content)
        if !didSave {
            saveError = "Could not save this capture."
        }
        return didSave
    }

    static func lengthLabel(for steps: Int) -> String {
        switch steps {
        case 8:
            return "1/2 bar"
        case 16:
            return "1 bar"
        case 32:
            return "2 bars"
        case 64:
            return "4 bars"
        default:
            return "\(steps) steps"
        }
    }

    private func noteCountsBySnapshotOffset() -> [Int: Int] {
        guard let lastAbsoluteStep = snapshot.steps.last?.absoluteStep else {
            return [:]
        }
        let windowStartAbsoluteStep = lastAbsoluteStep - snapshot.maxSteps + 1
        var result: [Int: Int] = [:]
        for step in snapshot.steps {
            result[step.absoluteStep - windowStartAbsoluteStep] = step.notes.count
        }
        return result
    }

    private var previewPseudoClip: PseudoClipState? {
        selectedPseudoClip ?? livePseudoClip
    }

    private var livePseudoClip: PseudoClipState? {
        guard let livePreviewRange else {
            return nil
        }

        return PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: livePreviewRange.startOffset,
            lengthSteps: livePreviewRange.lengthSteps
        )
    }

    private var livePreviewRange: (startOffset: Int, lengthSteps: Int)? {
        guard let lastAbsoluteStep = snapshot.steps.last?.absoluteStep else {
            return nil
        }

        let currentBarPosition = lastAbsoluteStep % Self.stepsPerCell
        let currentBarStartAbsoluteStep = lastAbsoluteStep - currentBarPosition
        let windowStartAbsoluteStep = lastAbsoluteStep - snapshot.maxSteps + 1
        return (
            startOffset: currentBarStartAbsoluteStep - windowStartAbsoluteStep,
            lengthSteps: currentBarPosition + 1
        )
    }

    private func isSelectableSourceRange(startStep: Int, lengthSteps: Int) -> Bool {
        let endStep = startStep + lengthSteps
        guard endStep <= snapshot.maxSteps else {
            return false
        }
        guard let livePreviewRange else {
            return true
        }

        let liveStart = livePreviewRange.startOffset
        let liveEnd = liveStart + livePreviewRange.lengthSteps
        return endStep <= liveStart || startStep >= liveEnd
    }
}
