import AVFoundation
import SwiftUI

enum ChordTrackTab: String, CaseIterable, Equatable {
    case steps
    case chords
    case sound
    case fx
    case macros
    case mixer

    var title: String {
        switch self {
        case .steps: return "Steps/Clip"
        case .chords: return "Chords"
        case .sound: return "Sound"
        case .fx: return "FX"
        case .macros: return "Macros"
        case .mixer: return "Mixer"
        }
    }
}

enum ChordTrackStepLayer: String, CaseIterable, Equatable {
    case chord
    case inversion

    var title: String {
        switch self {
        case .chord: return "Chord"
        case .inversion: return "Inversion"
        }
    }
}

struct ChordTrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let accent: Color
    let stepGridWorkspaceModel: TrackStepGridWorkspaceModel

    @State private var selectedTab: ChordTrackTab = .steps
    @State private var selectedLayer: ChordTrackStepLayer = .chord
    @State private var selectedStepIndex = 0
    @State private var selectedPaletteSlotID: UUID?
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

    private var selectedPatternIndex: Int {
        session.store.selectedPatternIndex(for: track.id)
    }

    private var selectedPattern: TrackPatternSlot {
        session.store.selectedPattern(for: track.id)
    }

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
        for binding in orderedMacros {
            let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
            if let layer = session.store.layers.first(where: { $0.id == layerID }),
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

    private var recipeClipID: UUID? {
        selectedPattern.sourceRef.sourceClipID ?? selectedPattern.sourceRef.clipID
    }

    private var recipeClip: ClipPoolEntry? {
        session.store.clipEntry(id: recipeClipID)
    }

    private var chordContent: ClipContent {
        guard let recipeClip,
              case .chordReferences = recipeClip.content.normalized
        else {
            return .emptyChordReferences(lengthSteps: 16, defaultSlotID: track.chordPalette.normalized.selectedSlotID)
        }
        return recipeClip.content.normalized
    }

    private var palette: ChordPalette {
        track.chordPalette.normalized
    }

    private var selectedSlot: ChordPaletteSlot? {
        palette.slot(id: selectedPaletteSlotID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            paletteBar
            tabWell
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            selectedPaletteSlotID = selectedPaletteSlotID ?? palette.selectedSlotID
            syncStepGridCoordinator()
            postRenderedVisualState()
        }
        .onChange(of: recipeClip?.id) { _, _ in
            syncStepGridCoordinator()
            postRenderedVisualState()
        }
        .onChange(of: selectedLayer) { _, _ in
            syncStepGridCoordinator()
            postRenderedVisualState()
        }
        .onChange(of: selectedTab) { _, _ in
            postRenderedVisualState()
        }
        .onDisappear {
            postRenderedVisualState(isVisible: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chordTrackWorkspaceVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
            postRenderedVisualState()
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
    }

    private var paletteBar: some View {
        HStack(alignment: .center, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(palette.slots) { slot in
                        paletteSlotButton(slot)
                    }
                }
            }

            Button {
                addPaletteSlot()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.background)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .help("Add chord")

            Button {
                bakeSelectedPattern()
            } label: {
                Label("Bake", systemImage: "square.grid.2x2")
                    .studioText(.labelBold)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.background)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .help("Bake chord references to a clip")

            if selectedPattern.sourceRef.sourceClipID != nil {
                Button {
                    restoreRecipeClip()
                } label: {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.text)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .help("Return to chord editing")
            }
        }
    }

    private func paletteSlotButton(_ slot: ChordPaletteSlot) -> some View {
        let isSelected = selectedPaletteSlotID == slot.id
        return Button {
            selectPaletteSlot(slot.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.name.isEmpty ? ChordPalette.pitchName(for: slot.root) : slot.name)
                    .studioText(.labelBold)
                    .lineLimit(1)
                Text(slot.displayName)
                    .studioText(.micro)
                    .foregroundStyle(isSelected ? StudioTheme.background.opacity(0.72) : StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(minWidth: 86, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? accent : StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var tabWell: some View {
        VStack(alignment: .leading, spacing: StudioTabWellGrammar.pillRowToWellGap) {
            StudioSectionPills(
                pills: ChordTrackTab.allCases.map { tab in
                    StudioSectionPill(
                        section: tab,
                        title: tab.title,
                        accessibilityIdentifier: "chord-track-tab-\(tab.rawValue)"
                    )
                },
                selection: selectedTab,
                accent: accent,
                accessibilityIdentifier: "chord-track-tabs",
                onSelect: { selectedTab = $0 }
            )

            StudioTabWell(accent: accent) {
                switch selectedTab {
                case .steps:
                    stepsTab
                case .chords:
                    chordsTab
                case .sound:
                    TrackRoutingTabContent(
                        document: $document,
                        summary: routingPathSummary,
                        mode: .sound,
                        accent: accent
                    )
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

    private var stepsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSegmentedControl(
                title: nil,
                selection: Binding(get: { selectedLayer }, set: { selectedLayer = $0 }),
                segments: ChordTrackStepLayer.allCases.map { StudioSegment(title: $0.title, value: $0) },
                accent: accent
            )
            chordStepGrid
            selectedStepEditor
        }
    }

    private var chordStepGrid: some View {
        let states = stepStates()
        return StepGridView(
            stepStates: states,
            playingStepIndex: nil,
            selectedStepIndexes: [selectedStepIndex],
            accent: accent,
            contentProvider: { index, _ in
                switch selectedLayer {
                case .chord:
                    return .chordLabel(name: stepSlotName(at: index))
                case .inversion:
                    return .optionLabel(text: "I\(selectedStepInversion(at: index))")
                }
            },
            onSelectStep: { index in
                selectedStepIndex = index
            }
        ) { index in
            selectedStepIndex = index
            switch selectedLayer {
            case .chord:
                assignSelectedSlot(to: index)
            case .inversion:
                incrementInversion(at: index)
            }
        }
    }

    private var selectedStepEditor: some View {
        HStack(spacing: 10) {
            StudioMetricPill(title: "STEP", value: "\(selectedStepIndex + 1)", accent: accent)
            StudioMetricPill(title: "CHORD", value: selectedStepSlotName(), accent: accent)
            StudioMetricPill(title: "INV", value: "\(selectedStepInversion())", accent: accent)
        }
    }

    private var fxTab: some View {
        TrackFXChainView(
            inserts: track.fxInserts,
            accent: accent,
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

    private var macrosTab: some View {
        LazyVGrid(columns: macroSlotColumns, alignment: .leading, spacing: 12) {
            ForEach(clipMacroSlots) { slot in
                macroSlotKnob(for: slot)
            }
        }
        .help("Drag a slot to set its value; right-click to change or remove the assignment.")
    }

    private var mixerTab: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
            TrackRoutingTabContent(
                document: $document,
                summary: routingPathSummary,
                mode: .mixer,
                accent: accent
            )

            if session.store.routesSourced(from: track.id).isEmpty == false {
                RoutesListView(document: $document)
            }
        }
    }

    private func macroSlotKnob(for slot: MacroSlot) -> some View {
        let binding = slot.binding
        let slotValue = binding.flatMap { macroFallbackValues[$0.id] }
        return AUMacroSlotKnob(
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

    private var addFXSheet: some View {
        let effects = engineController.availableAudioEffects
        let trackID = track.id
        return StudioModal(
            title: "Add FX",
            accent: accent,
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

            Text("AU EFFECT")
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
                    .foregroundStyle(accent)
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var chordsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedSlot {
                HStack(spacing: 12) {
                    SourceParameterStepperRow(
                        title: "Root",
                        value: selectedSlot.root,
                        range: 24...96
                    ) { root in
                        updateSelectedSlot { $0.root = root }
                    }
                    qualityGrid(selectedSlot: selectedSlot)
                }

                HStack(spacing: 8) {
                    Button {
                        removeSelectedSlot()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .studioText(.labelBold)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StudioTheme.text)
                    .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    .disabled(palette.slots.count <= 1)
                }
            }
        }
    }

    private func qualityGrid(selectedSlot: ChordPaletteSlot) -> some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(ChordID.allCases, id: \.self) { chordID in
                chordQualityButton(chordID, isSelected: selectedSlot.chordID == chordID)
            }
        }
    }

    private func chordQualityButton(_ chordID: ChordID, isSelected: Bool) -> some View {
        Button {
            updateSelectedSlot { $0.chordID = chordID }
        } label: {
            Text(ChordDefinition.for(id: chordID)?.name ?? chordID.rawValue)
                .studioText(.labelBold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
        .background(
            isSelected ? accent : StudioTheme.subtleFill,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
    }

    private func stepStates() -> [StepVisualState] {
        guard case let .chordReferences(stepPattern, _, inversions, _, _) = chordContent else {
            return Array(repeating: .off, count: 16)
        }
        return stepPattern.indices.map { index in
            guard stepPattern[index] else { return .off }
            if selectedLayer == .inversion, (inversions.value(at: index) ?? 0) != 0 {
                return .accented
            }
            return .on
        }
    }

    private func selectedStepSlotName() -> String {
        stepSlotName(at: selectedStepIndex)
    }

    private func stepSlotName(at stepIndex: Int) -> String {
        guard case let .chordReferences(_, slotIDs, _, _, _) = chordContent else {
            return "-"
        }
        let slotID = slotIDs.value(at: stepIndex) ?? nil
        return palette.slot(id: slotID)?.name ?? "-"
    }

    private func selectedStepInversion() -> Int {
        selectedStepInversion(at: selectedStepIndex)
    }

    private func selectedStepInversion(at stepIndex: Int) -> Int {
        guard case let .chordReferences(_, _, inversions, _, _) = chordContent else {
            return 0
        }
        return inversions.value(at: stepIndex) ?? 0
    }

    private func selectPaletteSlot(_ slotID: UUID) {
        selectedPaletteSlotID = slotID
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.selectedSlotID = slotID
        }
    }

    private func addPaletteSlot() {
        let newSlot = ChordPaletteSlot(name: "\(palette.slots.count + 1)", root: 60, chordID: .majorTriad)
        selectedPaletteSlotID = newSlot.id
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.slots.append(newSlot)
            track.chordPalette.selectedSlotID = newSlot.id
            track.chordPalette = track.chordPalette.normalized
        }
    }

    private func removeSelectedSlot() {
        guard let selectedPaletteSlotID, palette.slots.count > 1 else { return }
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.slots.removeAll { $0.id == selectedPaletteSlotID }
            track.chordPalette = track.chordPalette.normalized
        }
        self.selectedPaletteSlotID = palette.slots.first(where: { $0.id != selectedPaletteSlotID })?.id
    }

    private func updateSelectedSlot(_ update: @escaping (inout ChordPaletteSlot) -> Void) {
        guard let selectedPaletteSlotID else { return }
        session.mutateTrack(id: track.id) { track in
            guard let index = track.chordPalette.slots.firstIndex(where: { $0.id == selectedPaletteSlotID }) else { return }
            update(&track.chordPalette.slots[index])
            track.chordPalette = track.chordPalette.normalized
        }
    }

    private func assignSelectedSlot(to stepIndex: Int) {
        guard let slotID = selectedPaletteSlotID ?? palette.selectedSlotID else { return }
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, velocities, lengthSteps) = content.normalized else {
                return
            }
            var nextPattern = stepPattern
            var nextSlotIDs = slotIDs
            guard nextPattern.indices.contains(stepIndex), nextSlotIDs.indices.contains(stepIndex) else { return }
            nextPattern[stepIndex] = true
            nextSlotIDs[stepIndex] = slotID
            content = .chordReferences(
                stepPattern: nextPattern,
                slotIDs: nextSlotIDs,
                inversions: inversions,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    private func incrementInversion(at stepIndex: Int) {
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, velocities, lengthSteps) = content.normalized else {
                return
            }
            var nextPattern = stepPattern
            var nextInversions = inversions
            guard nextPattern.indices.contains(stepIndex), nextInversions.indices.contains(stepIndex) else { return }
            nextPattern[stepIndex] = true
            nextInversions[stepIndex] = nextInversions[stepIndex] >= 3 ? 0 : nextInversions[stepIndex] + 1
            content = .chordReferences(
                stepPattern: nextPattern,
                slotIDs: slotIDs,
                inversions: nextInversions,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    private func mutateChordClip(_ update: @escaping (inout ClipContent) -> Void) {
        let address = PatternSlotAddress(trackID: track.id, slotIndex: selectedPatternIndex)
        if let recipeClipID = selectedPattern.sourceRef.sourceClipID {
            session.mutateClip(id: recipeClipID) { clip in
                update(&clip.content)
            }
        } else {
            _ = session.ensureClipAndMutate(at: address) { _, clip in
                update(&clip.content)
            }
        }
    }

    private func bakeSelectedPattern() {
        _ = session.bakeChordTrackToClip(trackID: track.id, slotIndex: selectedPatternIndex)
    }

    private func restoreRecipeClip() {
        session.restoreChordSourceClip(trackID: track.id, slotIndex: selectedPatternIndex)
    }

    private func applyVisualCommand(_ command: String) {
        let tabPrefix = "tab:"
        if command.hasPrefix(tabPrefix),
           let tab = ChordTrackTab(rawValue: String(command.dropFirst(tabPrefix.count))) {
            selectedTab = tab
            return
        }

        let layerPrefix = "layer:"
        if command.hasPrefix(layerPrefix),
           let layer = ChordTrackStepLayer(rawValue: String(command.dropFirst(layerPrefix.count))) {
            selectedTab = .steps
            selectedLayer = layer
            return
        }

        let selectStepPrefix = "selectStep:"
        if command.hasPrefix(selectStepPrefix),
           let stepIndex = Int(command.dropFirst(selectStepPrefix.count)) {
            selectedStepIndex = max(0, stepIndex)
            stepGridWorkspaceModel.coordinator?.clearSelection()
            stepGridWorkspaceModel.coordinator?.toggleSelection(at: max(0, stepIndex))
            return
        }

        switch command {
        case "bake":
            bakeSelectedPattern()
        case "restore":
            restoreRecipeClip()
        default:
            break
        }
    }

    private func syncStepGridCoordinator() {
        guard let clipID = recipeClip?.id else {
            stepGridWorkspaceModel.reset()
            return
        }
        _ = stepGridWorkspaceModel.coordinator(
            for: clipID,
            clipMutator: session,
            editableLayers: [.chord]
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

    private func postRenderedVisualState(isVisible: Bool = true) {
        NotificationCenter.default.post(
            name: .chordTrackWorkspaceRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "tab": selectedTab.rawValue,
                "layer": selectedLayer.rawValue,
                "paletteSlotCount": palette.slots.count,
                "activeStepCount": chordActiveStepCount(),
                "baked": selectedPattern.sourceRef.sourceClipID != nil,
                "trackID": track.id.uuidString
            ]
        )
    }

    private func chordActiveStepCount() -> Int {
        guard case let .chordReferences(stepPattern, _, _, _, _) = chordContent else {
            return 0
        }
        return stepPattern.filter { $0 }.count
    }
}

private extension Array {
    func value(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
