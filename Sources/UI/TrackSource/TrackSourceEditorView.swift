import SwiftUI

enum TrackSourceEditorTab: String, CaseIterable, Identifiable {
    case source
    case modifiers
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .modifiers:
            return "Modifier"
        case .history:
            return "History"
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
    @State private var modifierPickerStep: TrackSourceContainedModifierPickerStep?
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?
    @State private var clipHistoryModel: ClipHistoryTransferViewModel?
    @State private var clipHistoryDestinationMode = false
    @State private var pendingClipHistoryReplaceSlot: Int?
    @State private var clipHistoryToast: String?

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
                TrackSourceSlotWellTabBar(
                    selectedTab: $selectedTab,
                    sourceState: sourceDisplayState,
                    modifierState: modifierDisplayState,
                    accent: accent
                )

                Group {
                    switch selectedTab {
                    case .source:
                        sourceTab
                    case .modifiers:
                        modifiersTab
                    case .history:
                        clipHistoryTab
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
            .presentationBackground(.ultraThinMaterial)
        }
        .overlay(alignment: .bottomTrailing) {
            if let clipHistoryToast {
                Text(clipHistoryToast)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(StudioTheme.success.opacity(StudioOpacity.selectedFill), in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.success.opacity(StudioOpacity.ghostStroke), lineWidth: 1))
                    .padding(12)
            }
        }
        .onChange(of: selectedPatternIndex) { _, _ in
            sourcePickerStep = nil
            modifierPickerStep = nil
            resetClipHistoryDestinationMode()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .source {
                sourcePickerStep = nil
            }
            if newValue != .modifiers {
                modifierPickerStep = nil
            }
            if newValue == .history {
                refreshClipHistoryModel()
            } else {
                resetClipHistoryDestinationMode()
                clipHistoryModel?.stopAudition()
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
        if let clipHistoryModel {
            TrackSourceClipHistoryTabContent(
                model: clipHistoryModel,
                accent: StudioTheme.success,
                sourceSummary: clipHistorySourceSummary,
                isDestinationMode: clipHistoryDestinationMode,
                onRefresh: refreshClipHistoryModel,
                onSaveClip: enterClipHistoryDestinationMode
            )
            .onAppear {
                if clipHistoryModel.trackID != track.id {
                    refreshClipHistoryModel()
                }
            }
        } else {
            TrackSourceSelectedWellBody(accent: StudioTheme.success, isEmpty: false) {
                HStack {
                    Text("History")
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    TrackSourceActionButton(
                        title: "Load History",
                        accent: StudioTheme.success,
                        action: refreshClipHistoryModel
                    )
                }
                .padding(14)
            }
            .onAppear(perform: refreshClipHistoryModel)
        }
    }

    private var clipHistorySourceSummary: String {
        switch sourceDisplayState {
        case .occupiedClip:
            return currentClip.map { "Clip source: \($0.name)" } ?? "Clip source"
        case .occupiedGenerator:
            return selectedSourceGenerator.map { "Generator source: \($0.name)" } ?? "Generator source"
        case .empty:
            return "No source assigned"
        }
    }

    @ViewBuilder
    private var clipHistoryDestinationRow: some View {
        if clipHistoryDestinationMode {
            HStack(spacing: 10) {
                if let pendingClipHistoryReplaceSlot {
                    Text("P\(pendingClipHistoryReplaceSlot + 1) is occupied.")
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
                    Text("Choose a pulsing pattern slot to save the selected history clip.")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
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
            .background(StudioTheme.success.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.success.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
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

    private func updateClipMacroLanes(_ updatedLanes: [UUID: MacroLane]) {
        session.ensureClipAndMutate(at: selectedPatternAddress) { _, entry in
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
        session.ensureClipAndMutate(at: selectedPatternAddress) { _, entry in
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

    private func refreshClipHistoryModel() {
        let trackID = track.id
        let frozenBank = bank
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

    private func enterClipHistoryDestinationMode() {
        guard let model = clipHistoryModel else {
            refreshClipHistoryModel()
            clipHistoryModel?.saveError = "Choose a history cell first."
            return
        }
        guard model.selectedPseudoClip != nil else {
            model.saveError = "Choose a history cell first."
            return
        }
        model.saveError = nil
        pendingClipHistoryReplaceSlot = nil
        clipHistoryDestinationMode = true
    }

    private func selectClipHistoryDestination(_ slotIndex: Int) {
        guard clipHistoryDestinationMode,
              let model = clipHistoryModel
        else {
            return
        }

        model.selectDestination(slotIndex)
        if model.requiresReplaceConfirmation {
            pendingClipHistoryReplaceSlot = slotIndex
            return
        }

        saveSelectedClipHistory(to: slotIndex)
    }

    private func confirmClipHistoryReplace() {
        guard let slotIndex = pendingClipHistoryReplaceSlot,
              let model = clipHistoryModel
        else {
            return
        }
        model.confirmReplace()
        saveSelectedClipHistory(to: slotIndex)
    }

    private func saveSelectedClipHistory(to slotIndex: Int) {
        guard let model = clipHistoryModel,
              let content = model.selectedPseudoClip?.noteGrid
        else {
            clipHistoryModel?.saveError = "Choose a history cell first."
            return
        }

        model.stopAudition()
        let clipID = session.saveMaterializedClipToPatternSlot(
            trackID: track.id,
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

    private func resetClipHistoryDestinationMode() {
        clipHistoryDestinationMode = false
        pendingClipHistoryReplaceSlot = nil
        clipHistoryModel?.cancelReplace()
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

        var id: Int { index }
        var isEmpty: Bool { noteCount == 0 }
    }

    let trackID: UUID
    let snapshot: CaptureSnapshot
    let destinationSlots: [DestinationSlot]
    var selectedSourceIndex: Int?
    var selectedDestinationIndex: Int?
    var lengthSteps: Int
    var isAuditioning = false
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
            return SourceCell(index: index, startStep: start, noteCount: noteCount)
        }
    }

    var selectedPseudoClip: PseudoClipState? {
        guard let selectedSourceIndex,
              sourceCells.indices.contains(selectedSourceIndex),
              !sourceCells[selectedSourceIndex].isEmpty
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
        selectedPseudoClip?.noteGrid
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

    var canSave: Bool {
        selectedPseudoClip != nil
            && selectedDestination != nil
            && !requiresReplaceConfirmation
    }

    func isSourceInSelectedRange(_ index: Int) -> Bool {
        guard let selectedSourceIndex else {
            return false
        }
        let coveredCells = max(1, Int(ceil(Double(lengthSteps) / Double(Self.stepsPerCell))))
        return index >= selectedSourceIndex && index < selectedSourceIndex + coveredCells
    }

    func selectSource(_ index: Int) {
        guard let cell = sourceCells.first(where: { $0.index == index }),
              !cell.isEmpty
        else {
            selectedSourceIndex = nil
            stopAudition()
            return
        }

        if selectedSourceIndex == index {
            selectedSourceIndex = nil
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
            stopAudition()
        } else {
            audition()
        }
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
