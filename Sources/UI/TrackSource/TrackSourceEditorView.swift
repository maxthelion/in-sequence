import SwiftUI

enum TrackSourceEditorTab: String, CaseIterable, Identifiable {
    case source
    case modifiers
    case clipHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .modifiers:
            return "Modifier"
        case .clipHistory:
            return "Clip History"
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
    @State private var clipHistoryRequest: ClipHistoryPresentationRequest?
    @State private var clipHistoryToast: String?

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

    private struct ClipHistoryPresentationRequest: Identifiable {
        let id = UUID()
        let trackID: UUID
        let trackName: String
        let snapshot: CaptureSnapshot
        let destinationSlots: [ClipHistoryTransferViewModel.DestinationSlot]
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
    private var canPresentClipHistory: Bool {
        selectedSourceMode == .generator && selectedSourceGenerator != nil
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
                TrackPatternSlotPalette(
                    selectedSlot: selectedPatternIndexBinding,
                    occupiedSlots: occupiedPatternSlots,
                    bypassState: .notApplicable,
                    onBypassToggle: { _ in }
                )
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
                    case .clipHistory:
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
        .sheet(item: $clipHistoryRequest) { request in
            ClipHistoryTransferSheet(
                trackID: request.trackID,
                trackName: request.trackName,
                snapshot: request.snapshot,
                destinationSlots: request.destinationSlots,
                accent: accent,
                setAuditionOverride: { state in
                    engineController.setAuditionOverride(state, for: request.trackID)
                },
                onSave: { slotIndex, content in
                    let clipID = session.saveMaterializedClipToPatternSlot(
                        trackID: request.trackID,
                        slotIndex: slotIndex,
                        content: content,
                        name: "Capture P\(slotIndex + 1)"
                    )
                    if clipID != nil {
                        showClipHistoryToast("Saved capture to P\(slotIndex + 1)")
                    }
                    return clipID != nil
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
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
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .source {
                sourcePickerStep = nil
            }
            if newValue != .modifiers {
                modifierPickerStep = nil
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
            onUpdateGeneratorParams: updateSourceGeneratorParams,
            onPresentClipHistory: presentClipHistory
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

    private var clipHistoryTab: some View {
        TrackSourceClipHistoryTabContent(
            accent: StudioTheme.success,
            isAvailable: canPresentClipHistory,
            onPresentClipHistory: presentClipHistory
        )
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

    private func presentClipHistory() {
        guard canPresentClipHistory else {
            return
        }
        let trackID = track.id
        let frozenBank = bank
        clipHistoryRequest = ClipHistoryPresentationRequest(
            trackID: trackID,
            trackName: track.name,
            snapshot: engineController.captureSnapshot(trackID: trackID),
            destinationSlots: ClipHistoryTransferViewModel.destinationSlots(
                from: frozenBank,
                clipName: { clipID in session.store.clipEntry(id: clipID)?.name }
            )
        )
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
                isOccupied: clipID != nil,
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
        selectedSourceIndex = index
        saveError = nil
        stopAudition()
    }

    func setLengthSteps(_ steps: Int) {
        guard Self.lengthOptions.contains(steps) else {
            return
        }
        lengthSteps = steps
        saveError = nil
        if selectedPseudoClip == nil {
            selectedSourceIndex = nil
        }
        stopAudition()
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

private struct ClipHistoryTransferSheet: View {
    let trackName: String
    let accent: Color
    let onSave: (Int, ClipContent) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var model: ClipHistoryTransferViewModel

    init(
        trackID: UUID,
        trackName: String,
        snapshot: CaptureSnapshot,
        destinationSlots: [ClipHistoryTransferViewModel.DestinationSlot],
        accent: Color,
        setAuditionOverride: @escaping (PseudoClipState?) -> Void,
        onSave: @escaping (Int, ClipContent) -> Bool
    ) {
        self.trackName = trackName
        self.accent = accent
        self.onSave = onSave
        _model = State(
            initialValue: ClipHistoryTransferViewModel(
                trackID: trackID,
                snapshot: snapshot,
                destinationSlots: destinationSlots,
                setAuditionOverride: setAuditionOverride
            )
        )
    }

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: "Clip History", eyebrow: trackName, accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Frozen recent output")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.violet)
                        Spacer()
                        Button("Close") {
                            model.cancel()
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.mutedText)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        matrixPanel(title: "Recent History", subtitle: "Select a captured source") {
                            historyMatrix
                        }

                        matrixPanel(title: "Pattern Slots", subtitle: "Choose where to save") {
                            destinationMatrix
                        }
                    }

                    virtualClipPreview
                    replacementRow
                    footer
                }
            }
            .padding(24)
            .frame(minWidth: 960, minHeight: 680)
        }
        .onDisappear {
            model.cancel()
        }
    }

    private func matrixPanel<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Spacer()
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var matrixColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private var historyMatrix: some View {
        LazyVGrid(columns: matrixColumns, spacing: 8) {
            ForEach(model.sourceCells) { cell in
                ClipHistorySourceCellButton(
                    cell: cell,
                    isSelected: model.selectedSourceIndex == cell.index,
                    isInRange: model.isSourceInSelectedRange(cell.index),
                    accent: accent
                ) {
                    model.selectSource(cell.index)
                }
            }
        }
    }

    private var destinationMatrix: some View {
        LazyVGrid(columns: matrixColumns, spacing: 8) {
            ForEach(model.destinationSlots) { slot in
                ClipHistoryDestinationCellButton(
                    slot: slot,
                    isSelected: model.selectedDestinationIndex == slot.slotIndex,
                    accent: accent
                ) {
                    model.selectDestination(slot.slotIndex)
                }
            }
        }
    }

    private var virtualClipPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Virtual Clip Preview")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                lengthPicker
                Spacer()
                Button(model.isAuditioning ? "Auditioning" : "Audition") {
                    model.audition()
                }
                .buttonStyle(.plain)
                .studioText(.labelBold)
                .foregroundStyle(model.canAudition ? StudioTheme.text : StudioTheme.mutedText)
                .disabled(!model.canAudition)

                Button("Stop") {
                    model.stopAudition()
                }
                .buttonStyle(.plain)
                .studioText(.labelBold)
                .foregroundStyle(model.isAuditioning ? StudioTheme.amber : StudioTheme.mutedText)
                .disabled(!model.isAuditioning)
            }

            ClipHistoryPreviewStrip(content: model.previewContent, accent: accent)
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var lengthPicker: some View {
        HStack(spacing: 6) {
            ForEach(ClipHistoryTransferViewModel.lengthOptions, id: \.self) { option in
                Button {
                    model.setLengthSteps(option)
                } label: {
                    Text(lengthLabel(option))
                        .studioText(.micro)
                        .foregroundStyle(model.lengthSteps == option ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            (model.lengthSteps == option ? accent.opacity(StudioOpacity.selectedFill) : Color.clear),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(model.lengthSteps == option ? accent : StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var replacementRow: some View {
        if model.requiresReplaceConfirmation {
            HStack(spacing: 10) {
                Text("P\(model.selectedDestination!.slotIndex + 1) is occupied.")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
                Spacer()
                Button("Replace") {
                    model.confirmReplace()
                }
                .buttonStyle(.plain)
                .studioText(.labelBold)
                .foregroundStyle(model.replaceConfirmed ? StudioTheme.success : StudioTheme.text)
                Button("Cancel") {
                    model.cancelReplace()
                }
                .buttonStyle(.plain)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(10)
            .background(StudioTheme.amber.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.amber.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let saveError = model.saveError {
                Text(saveError)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.amber)
            }
            Spacer()
            Button("Cancel") {
                model.cancel()
                dismiss()
            }
            .buttonStyle(.plain)
            .studioText(.labelBold)
            .foregroundStyle(StudioTheme.mutedText)

            Button("Save to Slot") {
                guard model.save(using: onSave) else {
                    return
                }
                dismiss()
            }
            .buttonStyle(.plain)
            .studioText(.labelBold)
            .foregroundStyle(model.canSave ? StudioTheme.text : StudioTheme.mutedText)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                (model.canSave ? accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)),
                in: Capsule()
            )
            .overlay(Capsule().stroke(model.canSave ? accent : StudioTheme.border, lineWidth: 1))
            .disabled(!model.canSave)
        }
    }

    private func lengthLabel(_ steps: Int) -> String {
        switch steps {
        case 8:
            return "8 steps"
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
}

private struct ClipHistorySourceCellButton: View {
    let cell: ClipHistoryTransferViewModel.SourceCell
    let isSelected: Bool
    let isInRange: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("B\(cell.index + 1)")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    Text(cell.isEmpty ? "empty" : "\(cell.noteCount)")
                        .studioText(.micro)
                        .foregroundStyle(cell.isEmpty ? StudioTheme.mutedText : StudioTheme.text)
                }

                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule()
                            .fill(blobFill(index: index))
                            .frame(width: 7, height: blobHeight(index: index))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(8)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderFill, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: cell.isEmpty ? [4, 4] : []))
            )
        }
        .buttonStyle(.plain)
        .disabled(cell.isEmpty)
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(StudioOpacity.selectedFill)
        }
        if isInRange {
            return accent.opacity(StudioOpacity.subtleFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var borderFill: Color {
        if isSelected || isInRange {
            return accent
        }
        return StudioTheme.border
    }

    private func blobFill(index: Int) -> Color {
        guard !cell.isEmpty else {
            return StudioTheme.border
        }
        return index < min(cell.noteCount, 8) ? accent : StudioTheme.border
    }

    private func blobHeight(index: Int) -> CGFloat {
        CGFloat(8 + ((cell.index + index) % 4) * 4)
    }
}

private struct ClipHistoryDestinationCellButton: View {
    let slot: ClipHistoryTransferViewModel.DestinationSlot
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("P\(slot.slotIndex + 1)")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    if slot.isOccupied {
                        Text("USED")
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.success)
                    }
                }
                Text(slot.clipName ?? "empty")
                    .studioText(.micro)
                    .foregroundStyle(slot.isOccupied ? StudioTheme.text : StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(8)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderFill, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(StudioOpacity.selectedFill)
        }
        if slot.isOccupied {
            return StudioTheme.success.opacity(StudioOpacity.subtleFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var borderFill: Color {
        if isSelected {
            return accent
        }
        if slot.isOccupied {
            return StudioTheme.success
        }
        return StudioTheme.border
    }
}

private struct ClipHistoryPreviewStrip: View {
    let content: ClipContent?
    let accent: Color

    private var steps: [ClipStep] {
        content?.normalized.noteGridSteps ?? []
    }

    var body: some View {
        if steps.isEmpty {
            Text("Select a recent-history source.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ClipHistoryPreviewStepCell(index: index, step: step, accent: accent)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(30), spacing: 5), count: 16)
    }
}

private struct ClipHistoryPreviewStepCell: View {
    let index: Int
    let step: ClipStep
    let accent: Color

    private var notes: [ClipStepNote] {
        step.main?.notes ?? []
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(index + 1)")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
            Text(notes.first.map { "\($0.pitch)" } ?? "-")
                .studioText(.micro)
                .foregroundStyle(notes.isEmpty ? StudioTheme.mutedText : StudioTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 30, height: 42)
        .background(
            (notes.isEmpty ? Color.white.opacity(StudioOpacity.subtleFill) : accent.opacity(StudioOpacity.selectedFill)),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(notes.isEmpty ? StudioTheme.border : accent, lineWidth: 1)
        )
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
