import SwiftUI

enum TracksBasisPhraseResolver {
    static func resolveID(
        engineBasisPhraseID: UUID?,
        selectedPhraseID: UUID,
        phrases: [PhraseModel]
    ) -> UUID? {
        if let engineBasisPhraseID,
           phrases.contains(where: { $0.id == engineBasisPhraseID })
        {
            return engineBasisPhraseID
        }

        if phrases.contains(where: { $0.id == selectedPhraseID }) {
            return selectedPhraseID
        }

        return phrases.first?.id
    }

    static func resolvePhrase(
        engineBasisPhraseID: UUID?,
        selectedPhraseID: UUID,
        selectedPhrase: PhraseModel,
        phrases: [PhraseModel]
    ) -> PhraseModel {
        guard let resolvedID = resolveID(
            engineBasisPhraseID: engineBasisPhraseID,
            selectedPhraseID: selectedPhraseID,
            phrases: phrases
        ) else {
            return selectedPhrase
        }

        return phrases.first(where: { $0.id == resolvedID }) ?? selectedPhrase
    }
}

enum TracksWorkspaceMode: String, CaseIterable, Identifiable {
    case edit
    case perform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit:
            return "Edit"
        case .perform:
            return "Perform"
        }
    }
}

struct TracksWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var mode: TracksWorkspaceMode
    @Binding var selectedLayerID: String
    let onOpenTrack: () -> Void

    var body: some View {
        TracksMatrixView(
            document: $document,
            selectedLayerID: $selectedLayerID,
            isPerforming: mode == .perform,
            onTogglePerform: {
                mode = mode == .perform ? .edit : .perform
            },
            onOpenTrack: onOpenTrack
        )
        .padding(20)
    }
}

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let isPerforming: Bool
    let onTogglePerform: () -> Void
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var isPresentingAddSliceTrack = false
    @State private var isPresentingAddDrumGroup = false
    @State private var performSelection = TrackPerformSelectionState()
    @State private var performRuntimeOverlay = TrackPerformRuntimeOverlayState()
    @State private var performLayerMode = TrackPerformLayerMode.pattern

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 112, maximum: 190), spacing: 12),
        count: 8
    )

    private var selectedLayer: PhraseLayerDefinition {
        let layers = session.store.layers
        return session.store.layer(id: selectedLayerID)
            ?? session.store.patternLayer
            ?? layers.first!
    }

    private var layers: [PhraseLayerDefinition] {
        session.store.layers
    }

    private var selectedLayerIndex: Int {
        layers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var activeMatrixLayer: PhraseLayerDefinition {
        guard isPerforming, let layerID = performLayerMode.phraseLayerID else {
            return selectedLayer
        }

        return session.store.layer(id: layerID) ?? selectedLayer
    }

    private var editingPhrase: PhraseModel {
        let basisPhrase = TracksBasisPhraseResolver.resolvePhrase(
            engineBasisPhraseID: engineController.basisPhraseID,
            selectedPhraseID: session.store.selectedPhraseID,
            selectedPhrase: session.store.selectedPhrase,
            phrases: session.store.phrases
        )
        return session.phraseWithPerformOverlay(basisPhrase)
    }

    private var editingPhraseID: UUID {
        editingPhrase.id
    }

    private var groupedSections: [GroupedTrackSection] {
        session.store.trackGroups.compactMap { group in
            let members = session.store.tracksInGroup(group.id)
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        session.store.tracks.filter { $0.groupID == nil }
    }

    var body: some View {
        let tracks = session.store.tracks
        let selectedTrackID = session.store.selectedTrackID
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: isPerforming ? StudioTheme.amber : StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    actionBar
                    if session.phrasePerformOverlay.isDirty {
                        performOverlayTransactionStrip
                    }

                    if tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            detail: "Create a mono, poly, slice, or drum-kit bundle to start building the matrix.",
                            accent: StudioTheme.cyan
                        )
                    } else {
                        matrixSections(tracks: tracks, selectedTrackID: selectedTrackID)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(document: $document, onOpenTrack: onOpenTrack)
        }
        .sheet(isPresented: $isPresentingAddSliceTrack) {
            AddSliceTrackSheet(
                library: .shared,
                sampleEngine: engineController.sampleEngineSink,
                onCreate: { sample in
                    _ = session.appendSliceTrack(sample: sample)
                    isPresentingAddSliceTrack = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddSliceTrack = false
                }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $isPresentingAddDrumGroup) {
            AddDrumGroupSheet(
                auInstruments: engineController.availableAudioInstruments,
                onCreate: { plan in
                    _ = session.addDrumGroup(plan: plan)
                    isPresentingAddDrumGroup = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddDrumGroup = false
                }
            )
            .presentationBackground(.clear)
        }
        .onChange(of: tracks.map(\.id)) { _, trackIDs in
            performSelection.reconcile(availableTrackIDs: trackIDs)
            performRuntimeOverlay.reconcile(availableTrackIDs: trackIDs)
        }
        .onChange(of: isPerforming) { _, isNowPerforming in
            if !isNowPerforming {
                cleanupPerformRuntime()
            }
        }
        .onChange(of: performLayerMode) { oldValue, newValue in
            if oldValue == .noteRepeat, newValue != .noteRepeat {
                cleanupNoteRepeatRuntime()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackPerformVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyTrackPerformVisualCommand(command)
        }
        .onDisappear {
            cleanupPerformRuntime()
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                createTrackButtons
                Spacer()
                layerControl
                basisPhrasePill
                if isPerforming {
                    performSelectionSummary
                    if performLayerMode != .noteRepeat {
                        performLatchModeControl
                    }
                }
                performToggleButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    createTrackButtons
                }
                HStack(spacing: 10) {
                    layerControl
                    basisPhrasePill
                    if isPerforming {
                        performSelectionSummary
                        if performLayerMode != .noteRepeat {
                            performLatchModeControl
                        }
                    }
                    performToggleButton
                    Spacer()
                }
            }
        }
    }

    private var createTrackButtons: some View {
        Group {
            Button("Add Mono") {
                session.appendTrack(trackType: .monoMelodic)
                onOpenTrack()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Add Poly") {
                session.appendTrack(trackType: .polyMelodic)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Button("Add Input") {
                session.appendTrack(trackType: .audioInput)
                onOpenTrack()
            }
            .buttonStyle(.bordered)
            .disabled(!session.canAppendAudioInputTrack)
            .help(session.canAppendAudioInputTrack ? "Add audio input track" : "One audio input track is available in this version")

            Button("New Slice Track") {
                isPresentingAddSliceTrack = true
            }
            .buttonStyle(.bordered)

            Button("Add Drum Group") {
                isPresentingAddDrumGroup = true
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var layerControl: some View {
        if isPerforming {
            performLayerControl
        } else {
            phraseLayerControl
        }
    }

    private var phraseLayerControl: some View {
        HStack(spacing: 8) {
            Button {
                cycleLayer(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(selectedLayer.name.uppercased())
                        .studioText(.labelBold)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)

                    Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                        .studioText(.micro)
                        .foregroundStyle(layerAccent(selectedLayer.id))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(layerAccent(selectedLayer.id).opacity(StudioOpacity.hoverFill), in: Capsule())
                }

                Text(layerSubtitle(selectedLayer))
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            Button {
                cycleLayer(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(layerAccent(selectedLayer.id).opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
    }

    private var performLayerControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("PERFORM LAYER")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                Text(performLayerMode.subtitle.uppercased())
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(performLayerMode.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            TrackPerformLayerModePicker(selection: $performLayerMode)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(performLayerMode.accent.opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
    }

    private var basisPhrasePill: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("BASIS PHRASE")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Text(editingPhrase.name)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.violet)
                .lineLimit(1)
        }
        .frame(width: 130, alignment: .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(StudioTheme.violet.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    private var performOverlayTransactionStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.amber)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UNSAVED PERFORM EDITS")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.amber)

                    Text(performOverlayStatusText)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button("Save Back") {
                session.savePhrasePerformOverlayBack()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.amber)
            .disabled(!canSavePhrasePerformOverlay)
            .help(canSavePhrasePerformOverlay ? "Save staged perform edits back to the basis phrase" : "Basis phrase is no longer available")

            Button("Revert") {
                session.revertPhrasePerformOverlay()
            }
            .buttonStyle(.bordered)
            .help("Discard staged perform edits")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
        .accessibilityIdentifier("phrase-perform-overlay-transaction")
    }

    private var canSavePhrasePerformOverlay: Bool {
        guard let phraseID = session.phrasePerformOverlay.basisPhraseID else {
            return false
        }
        return session.store.phrases.contains(where: { $0.id == phraseID })
    }

    private var performOverlayStatusText: String {
        let count = session.phrasePerformOverlay.stagedCellCount
        let phraseName = session.phrasePerformOverlay.basisPhraseID
            .flatMap { phraseID in session.store.phrases.first(where: { $0.id == phraseID })?.name }
            ?? "missing phrase"
        return "\(count) staged cell\(count == 1 ? "" : "s") for \(phraseName)"
    }

    private var performSelectionSummary: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EDIT SET")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(performSelectionSummaryText)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if !performSelection.isEmpty {
                Button {
                    performSelection.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Clear edit set")
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    private var performSelectionSummaryText: String {
        let selectedTracks = session.store.tracks.filter { performSelection.contains($0.id) }
        guard !selectedTracks.isEmpty else {
            return "None selected"
        }

        let names = selectedTracks.prefix(2).map(\.name).joined(separator: ", ")
        if selectedTracks.count <= 2 {
            return "\(selectedTracks.count): \(names)"
        }
        return "\(selectedTracks.count): \(names) +\(selectedTracks.count - 2)"
    }

    private var performLatchModeControl: some View {
        TrackPerformLatchModePicker(selection: $performRuntimeOverlay.latchMode)
    }

    private var performToggleButton: some View {
        Button(action: onTogglePerform) {
            Label("Perform", systemImage: isPerforming ? "record.circle.fill" : "record.circle")
                .studioText(.labelBold)
                .frame(minWidth: 96)
        }
        .buttonStyle(.borderedProminent)
        .tint(isPerforming ? StudioTheme.amber : StudioTheme.cyan)
    }

    private func cycleLayer(by delta: Int) {
        guard !layers.isEmpty else {
            return
        }

        let nextIndex = (selectedLayerIndex + delta + layers.count) % layers.count
        selectedLayerID = layers[nextIndex].id
    }

    private func matrixSections(tracks: [StepSequenceTrack], selectedTrackID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !ungroupedTracks.isEmpty {
                tracksGrid(ungroupedTracks, group: nil, selectedTrackID: selectedTrackID)
            }

            ForEach(groupedSections) { section in
                GroupSectionView(
                    section: section,
                    grid: { tracksGrid(section.members, group: section.group, selectedTrackID: selectedTrackID) }
                )
            }
        }
    }

    @ViewBuilder
    private func tracksGrid(_ tracks: [StepSequenceTrack], group: TrackGroup?, selectedTrackID: UUID) -> some View {
        let layer = activeMatrixLayer
        let activePerformLayer = isPerforming ? performLayerMode : nil
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                let address = phraseCellAddress(for: track.id, layerID: layer.id)
                let cell = editingPhrase.cell(at: address)
                let resolvedValue = editingPhrase.resolvedValue(for: layer, at: address)
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: session.store.selectedPatternIndex(for: track.id),
                    layer: layer,
                    activePerformLayer: activePerformLayer,
                    cell: cell,
                    resolvedValue: resolvedValue,
                    valueSummary: valueLabel(resolvedValue, layer: layer),
                    audioInputRuntimeLabel: audioInputRuntimeLabel(for: track.id),
                    isFocused: track.id == selectedTrackID,
                    isPerformSelected: performSelection.contains(track.id),
                    isPerforming: isPerforming,
                    latchMode: performRuntimeOverlay.latchMode,
                    runtimeControlState: activePerformLayer?.binaryControl.map {
                        runtimeControlState(for: track.id, control: $0)
                    },
                    noteRepeatStoredInterval: track.noteRepeatInterval,
                    noteRepeatActiveSnapshot: engineController.noteRepeatRuntimeSnapshot(for: track.id),
                    onTogglePerformSelection: {
                        performSelection.toggle(track.id)
                    },
                    onActivateRuntimeControl: { control in
                        session.setSelectedTrackID(track.id)
                        activateRuntimeControl(control, sourceTrackID: track.id)
                    },
                    onReleaseRuntimeControl: { control in
                        releaseRuntimeControl(control, sourceTrackID: track.id)
                    },
                    onChangeNoteRepeatInterval: { interval in
                        session.setTrackNoteRepeatInterval(interval, trackID: track.id)
                    }
                ) {
                    session.setSelectedTrackID(track.id)
                    if isPerforming {
                        performPrimaryAction(trackID: track.id)
                    } else {
                        onOpenTrack()
                    }
                }
            }
        }
    }

    private func runtimeControlState(for trackID: UUID, control: TrackPerformBinaryControl) -> TrackPerformRuntimeControlState {
        let isEngineActive = control == .noteRepeat && engineController.noteRepeatRuntimeSnapshot(for: trackID) != nil
        let isAvailable = control == .noteRepeat ? session.isNoteRepeatAvailable(trackID: trackID) : true
        return TrackPerformRuntimeControlState(
            control: control,
            isAvailable: isAvailable,
            isActive: isEngineActive || performRuntimeOverlay.isActive(control, trackID: trackID),
            isLatched: performRuntimeOverlay.isLatched(control, trackID: trackID),
            isMomentaryPressed: performRuntimeOverlay.isMomentaryPressed(control, trackID: trackID)
        )
    }

    private func audioInputRuntimeLabel(for trackID: UUID) -> String? {
        guard let runtime = engineController.audioInputRuntime(for: trackID) else {
            return nil
        }

        switch runtime.armState {
        case .armed:
            return "ARM"
        case .recording:
            return "REC"
        case .idle, .hasLoop:
            return "IN"
        }
    }

    private var currentStepIndexInPhrase: Int {
        PhrasePlayhead(phrase: editingPhrase, transportTickIndex: engineController.transportTickIndex).stepIndex
    }

    private var currentBarIndexInPhrase: Int {
        PhrasePlayhead(phrase: editingPhrase, transportTickIndex: engineController.transportTickIndex).barIndex
    }

    private func performPrimaryAction(trackID: UUID) {
        if isPerforming, let control = performLayerMode.binaryControl {
            if performRuntimeOverlay.latchMode == .latched {
                activateRuntimeControl(control, sourceTrackID: trackID)
            }
            return
        }

        let layer = activeMatrixLayer
        let address = phraseCellAddress(for: trackID, layerID: layer.id)
        let cell = editingPhrase.cell(at: address)
        let recipientTrackIDs = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: trackID,
            orderedTrackIDs: session.store.tracks.map(\.id),
            selection: performSelection
        )

        switch cell {
        case .inheritDefault:
            let seedValue = editingPhrase.resolvedValue(for: layer, at: address)
            session.stagePhrasePerformCell(
                .single(cycledValue(seedValue, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .single(value):
            session.stagePhrasePerformCell(
                .single(cycledValue(value, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .bars(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentBarIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: layer)
            session.stagePhrasePerformCell(
                .bars(nextValues),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .steps(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentStepIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: layer)
            session.stagePhrasePerformCell(
                .steps(nextValues),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case .curve:
            let seedValue = editingPhrase.resolvedValue(for: layer, at: address)
            session.stagePhrasePerformCell(
                .single(cycledValue(seedValue, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        }
    }

    private func phraseCellAddress(for trackID: UUID, layerID: String) -> PhraseCellAddress {
        PhraseCellAddress(
            phraseID: editingPhraseID,
            layerID: layerID,
            trackID: trackID,
            stepIndex: currentStepIndexInPhrase
        )
    }

    private func activateRuntimeControl(_ control: TrackPerformBinaryControl, sourceTrackID: UUID) {
        let orderedTrackIDs = session.store.tracks.map(\.id)
        let recipientTrackIDs = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: orderedTrackIDs,
            selection: performSelection
        )

        switch control {
        case .fill:
            performRuntimeOverlay.activate(
                control: control,
                sourceTrackID: sourceTrackID,
                recipientTrackIDs: recipientTrackIDs
            )
        case .noteRepeat:
            let supportedTrackIDs = recipientTrackIDs.filter { session.isNoteRepeatAvailable(trackID: $0) }
            guard !supportedTrackIDs.isEmpty else {
                return
            }

            performRuntimeOverlay.activate(
                control: control,
                sourceTrackID: sourceTrackID,
                recipientTrackIDs: supportedTrackIDs
            )
            supportedTrackIDs.forEach { session.engageNoteRepeat(trackID: $0) }
        }
    }

    private func releaseRuntimeControl(_ control: TrackPerformBinaryControl, sourceTrackID: UUID) {
        if control == .noteRepeat {
            let activeTrackIDs = performRuntimeOverlay.momentaryRecipientTrackIDs(
                control: control,
                sourceTrackID: sourceTrackID
            )
            activeTrackIDs.forEach { session.releaseNoteRepeat(trackID: $0) }
        }
        performRuntimeOverlay.releaseMomentary(control: control, sourceTrackID: sourceTrackID)
    }

    private func cleanupPerformRuntime() {
        cleanupNoteRepeatRuntime()
        performSelection.clear()
        performRuntimeOverlay.cleanupRuntime()
    }

    private func cleanupNoteRepeatRuntime() {
        let overlayActiveTrackIDs = performRuntimeOverlay
            .activeTrackIDs(.noteRepeat, orderedTrackIDs: session.store.tracks.map(\.id))
        let engineActiveTrackIDs = session.store.tracks.compactMap { track in
            engineController.noteRepeatRuntimeSnapshot(for: track.id) == nil ? nil : track.id
        }
        let activeTrackIDs = Array(Set(overlayActiveTrackIDs + engineActiveTrackIDs))
        activeTrackIDs.forEach { session.releaseNoteRepeat(trackID: $0) }
        performRuntimeOverlay.clearRuntime(control: .noteRepeat, trackIDs: activeTrackIDs)
        performRuntimeOverlay.releaseAllMomentary(control: .noteRepeat)
    }

    private func applyTrackPerformVisualCommand(_ command: String) {
        if let rawMode = command.removingPrefix("layer:"),
           let mode = TrackPerformLayerMode(rawValue: rawMode) {
            performLayerMode = mode
            return
        }

        if let rawTrackID = command.removingPrefix("press:"),
           let trackID = UUID(uuidString: rawTrackID) {
            performLayerMode = .noteRepeat
            activateRuntimeControl(.noteRepeat, sourceTrackID: trackID)
            return
        }

        if let rawTrackID = command.removingPrefix("release:"),
           let trackID = UUID(uuidString: rawTrackID) {
            releaseRuntimeControl(.noteRepeat, sourceTrackID: trackID)
            return
        }

        if command == "clear-note-repeat" {
            cleanupNoteRepeatRuntime()
            performRuntimeOverlay.releaseAllMomentary(control: .noteRepeat)
        }
    }

}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

private struct GroupSectionView<Grid: View>: View {
    let section: GroupedTrackSection
    @ViewBuilder let grid: Grid

    private var accent: Color {
        Color(hex: section.group.color) ?? StudioTheme.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(section.group.name)
                            .studioText(.title)
                            .foregroundStyle(StudioTheme.text)

                        Text("\(section.members.count) tracks")
                            .studioText(.eyebrowBold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                            .foregroundStyle(accent)
                    }

                    Text(section.group.sharedDestination?.summary ?? "Shared destination not assigned")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            grid
        }
        .padding(16)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
        )
    }
}

private struct TrackPerformRuntimeControlState: Equatable, Identifiable {
    let control: TrackPerformBinaryControl
    let isAvailable: Bool
    let isActive: Bool
    let isLatched: Bool
    let isMomentaryPressed: Bool

    var id: TrackPerformBinaryControl { control }
}

private struct TrackPerformLatchModePicker: View {
    @Binding var selection: TrackPerformLatchMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrackPerformLatchMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .bold))

                        Text(mode.actionBarLabel)
                            .studioText(.micro)
                            .tracking(0.8)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == mode ? StudioTheme.text : StudioTheme.text.opacity(0.68))
                    .frame(width: 74, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .fill(selection == mode ? StudioTheme.amber.opacity(StudioOpacity.selectedFill) : Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(selection == mode ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : Color.white.opacity(StudioOpacity.borderFaint), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.label))
                .accessibilityHint(Text(mode.helpText))
                .help(mode.helpText)
            }
        }
        .padding(3)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("track-perform-latch-mode")
        .help("Runtime Fill and Repeat mode")
    }
}

private struct TrackPerformLayerModePicker: View {
    @Binding var selection: TrackPerformLayerMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TrackPerformLayerMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .bold))

                        Text(mode.label.uppercased())
                            .studioText(.micro)
                            .tracking(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selection == mode ? StudioTheme.text : StudioTheme.text.opacity(0.68))
                    .frame(width: 82, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .fill(selection == mode ? mode.accent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(selection == mode ? mode.accent.opacity(StudioOpacity.mediumStroke) : Color.white.opacity(StudioOpacity.borderFaint), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.label))
                .help("\(mode.label) layer")
            }
        }
        .padding(3)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("track-perform-layer-mode")
    }
}

private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
    let patternIndex: Int
    let layer: PhraseLayerDefinition
    let activePerformLayer: TrackPerformLayerMode?
    let cell: PhraseCell
    let resolvedValue: PhraseCellValue
    let valueSummary: String
    let audioInputRuntimeLabel: String?
    let isFocused: Bool
    let isPerformSelected: Bool
    let isPerforming: Bool
    let latchMode: TrackPerformLatchMode
    let runtimeControlState: TrackPerformRuntimeControlState?
    let noteRepeatStoredInterval: NoteRepeatInterval
    let noteRepeatActiveSnapshot: EngineController.NoteRepeatRuntimeSnapshot?
    let onTogglePerformSelection: () -> Void
    let onActivateRuntimeControl: (TrackPerformBinaryControl) -> Void
    let onReleaseRuntimeControl: (TrackPerformBinaryControl) -> Void
    let onChangeNoteRepeatInterval: (NoteRepeatInterval) -> Void
    let onTap: () -> Void

    private var accent: Color {
        if let group {
            return Color(hex: group.color) ?? StudioTheme.cyan
        }
        switch track.trackType {
        case .monoMelodic:
            return StudioTheme.cyan
        case .polyMelodic:
            return StudioTheme.amber
        case .slice:
            return StudioTheme.violet
        case .audioInput:
            return StudioTheme.success
        }
    }

    private var typeLabel: String {
        track.trackType.label.uppercased()
    }

    private var destinationLabel: String {
        if case .inheritGroup = track.destination {
            return group?.sharedDestination?.kindLabel ?? "GROUP"
        }
        return track.destination.kindLabel
    }

    private var pitchOffsetLabel: String? {
        guard let group, let offset = group.noteMapping[track.id], offset != 0 else {
            return nil
        }
        return offset > 0 ? "+\(offset)" : "\(offset)"
    }

    private var layerAccentColor: Color {
        if let activePerformLayer {
            return activePerformLayer.accent
        }
        return layerAccent(layer.id)
    }

    private var isRuntimeLayerCard: Bool {
        activePerformLayer?.binaryControl != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TrackTypeBadge(trackType: track.trackType, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 6) {
                        Text(typeLabel)
                        Text("P\(patternIndex + 1)")
                        Text(destinationLabel)
                        if let pitchOffsetLabel {
                            Text(pitchOffsetLabel)
                        }
                    }
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                if let audioInputRuntimeLabel {
                    Text(audioInputRuntimeLabel)
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                        )
                        .lineLimit(1)
                }

                if isPerforming {
                    Button(action: onTogglePerformSelection) {
                        Image(systemName: isPerformSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isPerformSelected ? StudioTheme.amber : StudioTheme.mutedText)
                            .frame(width: 28, height: 28)
                            .background(
                                (isPerformSelected ? StudioTheme.amber : Color.white)
                                    .opacity(StudioOpacity.subtleFill),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(isPerformSelected ? StudioTheme.amber.opacity(0.7) : StudioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(isPerformSelected ? "Remove from edit set" : "Add to edit set")
                }
            }

            if let group {
                Text(group.name.uppercased())
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(StudioOpacity.faintStroke), in: Capsule())
                    .lineLimit(1)
            } else {
                Text(track.defaultDestination.summary)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            activeLayerContent
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(cardStroke, lineWidth: isFocused || isPerformSelected || isPerforming ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            if !isRuntimeLayerCard {
                onTap()
            }
        }
    }

    @ViewBuilder
    private var activeLayerContent: some View {
        if let activePerformLayer,
           let runtimeControlState,
           let control = activePerformLayer.binaryControl {
            TrackPerformRuntimeLayerControl(
                mode: activePerformLayer,
                state: runtimeControlState,
                latchMode: activePerformLayer == .noteRepeat ? .momentary : latchMode,
                accent: layerAccentColor,
                authoredSummary: activePerformLayer.phraseLayerID == nil ? nil : valueSummary,
                storedInterval: activePerformLayer == .noteRepeat ? noteRepeatStoredInterval : nil,
                activeRepeatSnapshot: activePerformLayer == .noteRepeat ? noteRepeatActiveSnapshot : nil,
                onActivate: { onActivateRuntimeControl(control) },
                onRelease: { onReleaseRuntimeControl(control) },
                onChangeInterval: onChangeNoteRepeatInterval
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(cell.editMode.label.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(layerAccentColor)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isPerforming {
                        Text(isPerformSelected ? "LINKED" : "LIVE")
                            .studioText(.micro)
                            .tracking(0.8)
                            .foregroundStyle(isPerformSelected ? StudioTheme.amber : layerAccentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
                    }
                }

                PhraseCellPreview(
                    layer: layer,
                    cell: cell,
                    resolvedValue: resolvedValue,
                    accent: layerAccentColor,
                    summary: valueSummary,
                    metrics: .matrix
                )
                .opacity(isPerforming ? 1 : 0.82)
            }
        }
    }

    private var cardFill: Color {
        if isPerformSelected {
            return StudioTheme.amber.opacity(StudioOpacity.hoverFill)
        }
        if isFocused {
            return accent.opacity(StudioOpacity.hoverFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var cardStroke: Color {
        if isPerformSelected {
            return StudioTheme.amber.opacity(StudioOpacity.accentFill)
        }
        if isPerforming {
            return layerAccentColor.opacity(StudioOpacity.accentFill)
        }
        if isFocused {
            return accent.opacity(StudioOpacity.accentFill)
        }
        return StudioTheme.border
    }
}

private struct TrackPerformRuntimeLayerControl: View {
    let mode: TrackPerformLayerMode
    let state: TrackPerformRuntimeControlState
    let latchMode: TrackPerformLatchMode
    let accent: Color
    let authoredSummary: String?
    let storedInterval: NoteRepeatInterval?
    let activeRepeatSnapshot: EngineController.NoteRepeatRuntimeSnapshot?
    let onActivate: () -> Void
    let onRelease: () -> Void
    let onChangeInterval: (NoteRepeatInterval) -> Void

    @State private var isTrackingMomentaryPress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            triggerSurface

            if let storedInterval {
                intervalPicker(storedInterval)
            }
        }
        .help(helpText)
    }

    @ViewBuilder
    private var triggerSurface: some View {
        if !state.isAvailable {
            label
                .opacity(0.68)
        } else {
            switch latchMode {
            case .latched:
                Button {
                    onActivate()
                } label: {
                    label
                }
                .buttonStyle(.plain)
            case .momentary:
                GeometryReader { proxy in
                    label
                        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    let isInside = CGRect(origin: .zero, size: proxy.size).contains(value.location)
                                    if isInside, !isTrackingMomentaryPress {
                                        isTrackingMomentaryPress = true
                                        onActivate()
                                    } else if !isInside, isTrackingMomentaryPress {
                                        isTrackingMomentaryPress = false
                                        onRelease()
                                    }
                                }
                                .onEnded { _ in
                                    endMomentaryPressIfNeeded()
                                }
                        )
                }
                .frame(minHeight: 96)
                .onDisappear {
                    endMomentaryPressIfNeeded()
                }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: leadingSymbolName)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(StudioOpacity.selectedFill), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(stateLabel)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(labelForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if let authoredSummary {
                    Text("BASE \(authoredSummary.uppercased())")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Text(mode == .noteRepeat ? noteRepeatModeBadge : latchMode.actionBarLabel)
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(state.isActive ? StudioTheme.text : StudioTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(labelForeground)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(labelBackground, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(labelStroke, lineWidth: state.isMomentaryPressed ? 2 : 1)
        )
    }

    private func intervalPicker(_ storedInterval: NoteRepeatInterval) -> some View {
        HStack(spacing: 6) {
            ForEach(NoteRepeatInterval.allCases, id: \.rawValue) { interval in
                Button {
                    onChangeInterval(interval)
                } label: {
                    Text(interval.rawValue)
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(interval == storedInterval ? StudioTheme.text : StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            interval == storedInterval
                                ? accent.opacity(StudioOpacity.selectedFill)
                                : Color.white.opacity(StudioOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(interval == storedInterval ? accent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(intervalHelp(for: interval, storedInterval: storedInterval))
            }
        }
        .accessibilityIdentifier("note-repeat-interval-picker")
    }

    private var leadingSymbolName: String {
        if state.isMomentaryPressed {
            return "hand.tap.fill"
        }
        if state.isLatched {
            return "lock.fill"
        }
        return state.control.symbolName
    }

    private var stateLabel: String {
        if !state.isAvailable {
            if mode == .noteRepeat {
                return "No Clip"
            }
            return "UNAVAILABLE"
        }
        if state.isMomentaryPressed {
            return "HELD"
        }
        if state.isLatched {
            return "LATCHED"
        }
        if state.isActive {
            return "ACTIVE"
        }
        return "READY"
    }

    private var labelForeground: Color {
        state.isActive && state.isAvailable ? StudioTheme.text : StudioTheme.mutedText
    }

    private var labelBackground: Color {
        if !state.isAvailable {
            return Color.white.opacity(StudioOpacity.subtleFill)
        }
        if state.isMomentaryPressed {
            return StudioTheme.amber.opacity(StudioOpacity.selectedFill)
        }
        if state.isLatched {
            return accent.opacity(StudioOpacity.selectedFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var labelStroke: Color {
        if !state.isAvailable {
            return StudioTheme.border
        }
        if state.isMomentaryPressed {
            return StudioTheme.amber.opacity(0.9)
        }
        if state.isLatched {
            return accent.opacity(0.7)
        }
        return StudioTheme.border
    }

    private var noteRepeatModeBadge: String {
        guard let storedInterval else {
            return "MOM"
        }
        if let activeInterval = activeRepeatSnapshot?.interval, activeInterval != storedInterval {
            return "LIVE \(activeInterval.rawValue)"
        }
        return storedInterval.rawValue
    }

    private var helpText: String {
        if !state.isAvailable {
            return "\(mode.label) is available for clip-backed tracks only in v1."
        }
        guard mode == .noteRepeat, let storedInterval else {
            return "\(mode.label) \(latchMode.label)"
        }
        if let activeInterval = activeRepeatSnapshot?.interval, activeInterval != storedInterval {
            return "Repeat is using \(activeInterval.rawValue). Next engagement will use \(storedInterval.rawValue)."
        }
        return "Hold Repeat. Stored interval \(storedInterval.rawValue)."
    }

    private func intervalHelp(for interval: NoteRepeatInterval, storedInterval: NoteRepeatInterval) -> String {
        if activeRepeatSnapshot != nil, interval != storedInterval {
            return "Set next Repeat engagement to \(interval.rawValue); active Repeat keeps its captured interval."
        }
        return "Set Repeat interval to \(interval.rawValue)."
    }

    private func endMomentaryPressIfNeeded() {
        guard isTrackingMomentaryPress else {
            return
        }

        isTrackingMomentaryPress = false
        onRelease()
    }
}

private extension TrackPerformLatchMode {
    var actionBarLabel: String {
        switch self {
        case .momentary:
            return "MOM"
        case .latched:
            return "LATCH"
        }
    }

    var symbolName: String {
        switch self {
        case .momentary:
            return "hand.tap"
        case .latched:
            return "lock"
        }
    }

    var helpText: String {
        switch self {
        case .momentary:
            return "Momentary runtime controls release on pointer up"
        case .latched:
            return "Latch runtime controls toggle until changed"
        }
    }
}

private extension TrackPerformLayerMode {
    var accent: Color {
        switch self {
        case .pattern:
            return StudioTheme.violet
        case .fill:
            return StudioTheme.success
        case .noteRepeat:
            return StudioTheme.cyan
        }
    }
}

private struct TrackTypeBadge: View {
    let trackType: TrackType
    let accent: Color

    private var icon: String {
        switch trackType {
        case .monoMelodic:
            return "waveform.path"
        case .polyMelodic:
            return "pianokeys"
        case .slice:
            return "waveform"
        case .audioInput:
            return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(StudioTheme.text)
            .frame(width: 30, height: 30)
            .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SequencerDocumentSession.self) private var session
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Track")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text("Choose the kind of track to append to the matrix. You can rename and edit the destination in the Track workspace right after creation.")
                .studioText(.subtitleMuted)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 12) {
                createButton(title: "Mono", detail: "Single melodic lane", type: .monoMelodic, accent: StudioTheme.cyan)
                createButton(title: "Poly", detail: "Chord-capable lane", type: .polyMelodic, accent: StudioTheme.amber)
                createButton(title: "Slice", detail: "Sample/slice trigger lane", type: .slice, accent: StudioTheme.violet)
                createButton(
                    title: "Input",
                    detail: session.canAppendAudioInputTrack ? "Audio input lane" : "Already in project",
                    type: .audioInput,
                    accent: StudioTheme.success
                )
            }
        }
        .padding(24)
        .frame(minWidth: 560)
        .background(StudioTheme.chrome)
    }

    private func createButton(title: String, detail: String, type: TrackType, accent: Color) -> some View {
        Button {
            session.appendTrack(trackType: type)
            dismiss()
            onOpenTrack()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .studioText(.title)
                    .foregroundStyle(StudioTheme.text)
                Text(detail)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(16)
            .background(accent.opacity(StudioOpacity.mutedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(type == .audioInput && !session.canAppendAudioInputTrack)
        .help(type == .audioInput && !session.canAppendAudioInputTrack ? "One audio input track is available in this version" : "")
    }
}

private struct AddSliceTrackSheet: View {
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink
    let onCreate: (AudioSample) -> Void
    let onCancel: () -> Void

    @State private var previewingSampleID: UUID?

    private var samples: [AudioSample] {
        library.samples(in: .breaks).sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)]
    }

    private var breaksFolderPath: String {
        library.libraryRoot.appendingPathComponent("breaks", isDirectory: true).path
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: "New Slice Track", eyebrow: "Choose a loop. Slices are detected after the track opens.", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 16) {
                    if samples.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Break Loops Found",
                            detail: "Add WAV loops to \(breaksFolderPath).",
                            accent: StudioTheme.violet
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(samples) { sample in
                                    sampleCard(sample)
                                }
                            }
                        }
                        .frame(maxHeight: 440)
                    }
                }
            }
            .padding(24)
            .frame(minWidth: 760, minHeight: 520)

            Button {
                sampleEngine.stopAudition()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(30)
        }
        .onDisappear {
            sampleEngine.stopAudition()
        }
        .onAppear {
            library.reload()
        }
    }

    private func sampleCard(_ sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sample.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(sampleDetail(sample))
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    togglePreview(sample)
                } label: {
                    Image(systemName: previewingSampleID == sample.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 28, height: 28)
                        .background(StudioTheme.violet.opacity(StudioOpacity.selectedFill), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(previewingSampleID == sample.id ? "Stop preview" : "Preview loop")
            }

            Button {
                sampleEngine.stopAudition()
                onCreate(sample)
            } label: {
                Text("Use Loop")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.violet.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                            .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func togglePreview(_ sample: AudioSample) {
        if previewingSampleID == sample.id {
            sampleEngine.stopAudition()
            previewingSampleID = nil
            return
        }

        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else {
            return
        }

        sampleEngine.stopAudition()
        sampleEngine.audition(sampleURL: url)
        previewingSampleID = sample.id
    }

    private func sampleDetail(_ sample: AudioSample) -> String {
        let length = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        let rate = sample.sampleRate.map { String(format: "%.1fk", $0 / 1_000) } ?? "--"
        return "\(sample.category.displayName) • \(length) • \(rate)"
    }

}

private extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}
