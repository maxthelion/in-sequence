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

enum ChordTrackStepLayer: String, CaseIterable, Equatable, Hashable {
    case chord
    case length
    case inversion
    case chordType

    var title: String {
        switch self {
        case .chord: return "Chord"
        case .length: return "Length"
        case .inversion: return "Inversion"
        case .chordType: return "Chord Type"
        }
    }
}

struct ChordTrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let accent: Color
    let displayedPatternIndex: Int
    let stepGridWorkspaceModel: TrackStepGridWorkspaceModel

    @State private var selectedTab: ChordTrackTab = .steps
    @State private var selectedLayer: ChordTrackStepLayer = .chord
    @State private var selectedStepIndex = 0
    @State private var selectedPage = 0
    @State private var selectedPaletteSlotID: UUID?
    @State private var isLayerSwitcherOpen = false
    @State private var isConfigPresented = false
    @State private var isProgressionChooserPresented = false
    @State private var isAddFXPresented = false
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

    private struct ProgressionTemplate: Identifiable {
        let id: String
        let title: String
        let degrees: [Int]
        let qualities: [ChordID]

        var preview: String {
            degrees.map { ChordTrackWorkspaceView.romanDegreeLabel(for: $0) }.joined(separator: " ")
        }
    }

    private let macroSlotColumns = MacroSlotPresentation.workspaceColumns

    private let configScaleIDs: [ScaleID] = [
        .major,
        .naturalMinor,
        .dorian,
        .mixolydian,
        .minorPentatonic
    ]

    private let progressionTemplates: [ProgressionTemplate] = [
        ProgressionTemplate(
            id: "one-four-five-six",
            title: "I IV V vi",
            degrees: [0, 3, 4, 5],
            qualities: [.majorTriad, .majorTriad, .majorTriad, .minorTriad]
        ),
        ProgressionTemplate(
            id: "one-five-six-four",
            title: "I V vi IV",
            degrees: [0, 4, 5, 3],
            qualities: [.majorTriad, .majorTriad, .minorTriad, .majorTriad]
        ),
        ProgressionTemplate(
            id: "two-five-one",
            title: "ii V I",
            degrees: [1, 4, 0],
            qualities: [.minor7th, .dominant7th, .major7th]
        ),
        ProgressionTemplate(
            id: "six-four-one-five",
            title: "vi IV I V",
            degrees: [5, 3, 0, 4],
            qualities: [.minorTriad, .majorTriad, .majorTriad, .majorTriad]
        )
    ]

    private var track: StepSequenceTrack {
        session.store.selectedTrack
    }

    private var selectedPatternIndex: Int {
        min(max(displayedPatternIndex, 0), TrackPatternBank.slotCount - 1)
    }

    private var selectedPattern: TrackPatternSlot {
        session.store.patternBank(for: track.id).slot(at: selectedPatternIndex)
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
            if isConfigPresented {
                progressionConfigPanel
            }
            if isProgressionChooserPresented {
                progressionChooserPanel
            }
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
                isConfigPresented.toggle()
                if isConfigPresented {
                    isProgressionChooserPresented = false
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isConfigPresented ? StudioTheme.background : StudioTheme.text)
            .background(
                isConfigPresented ? accent : StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isConfigPresented ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .help("Chord config")

            Button {
                isProgressionChooserPresented.toggle()
                if isProgressionChooserPresented {
                    isConfigPresented = false
                }
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isProgressionChooserPresented ? StudioTheme.background : StudioTheme.text)
            .background(
                isProgressionChooserPresented ? accent : StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isProgressionChooserPresented ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .help("Choose progression")

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

    private var progressionConfigPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChordRootKeyboard(
                selectedRoot: palette.progressionRoot,
                progressionRoot: palette.progressionRoot,
                scaleID: palette.progressionScaleID,
                accent: accent
            ) { root in
                updateProgressionRoot(root)
            }

            StudioSegmentedControl(
                title: "Scale",
                selection: Binding(
                    get: { palette.progressionScaleID },
                    set: { updateProgressionScale($0) }
                ),
                segments: configScaleIDs.map { scaleID in
                    StudioSegment(title: Scale.for(id: scaleID)?.name ?? scaleID.rawValue, value: scaleID)
                },
                accent: accent,
                layout: .init(fillsWidth: false, minWidth: 88)
            )
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(
            StudioTheme.panelFill,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var progressionChooserPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(progressionTemplates) { template in
                Button {
                    applyProgressionTemplate(template)
                    isProgressionChooserPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Text(template.title)
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(template.preview)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        StudioTheme.subtleFill,
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            StudioTheme.panelFill,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
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
            HStack(spacing: 12) {
                lengthSelector
                layerChip
                if chordPageCount > 1 {
                    pageSelector
                }
                Spacer(minLength: 0)
            }
            if isLayerSwitcherOpen {
                layerOptions
            }
            chordStepGrid
        }
    }

    private var lengthSelector: some View {
        StudioSegmentedControl(
            title: "Length",
            selection: Binding(
                get: { chordContent.stepCount },
                set: { resizeChordClip(to: $0) }
            ),
            segments: [16, 32, 64, 128].map { length in
                StudioSegment(title: "\(length)", value: length)
            },
            accent: accent,
            layout: .init(fillsWidth: false, minWidth: 44)
        )
    }

    private var layerChip: some View {
        StepLayerQuickSwitchChip(
            title: "Layer",
            selection: $selectedLayer,
            isOpen: $isLayerSwitcherOpen,
            options: layerQuickSwitchOptions,
            accent: accent
        )
    }

    private var layerOptions: some View {
        StepLayerQuickSwitchOptions(
            selection: $selectedLayer,
            isOpen: $isLayerSwitcherOpen,
            options: layerQuickSwitchOptions,
            accent: accent
        )
    }

    private var layerQuickSwitchOptions: [StepLayerQuickSwitchOption<ChordTrackStepLayer>] {
        ChordTrackStepLayer.allCases.map { layer in
            StepLayerQuickSwitchOption(id: layer.rawValue, title: layer.title, value: layer)
        }
    }

    private var chordPageCount: Int {
        max(1, Int(ceil(Double(chordContent.stepCount) / 16.0)))
    }

    private var chordPageStart: Int {
        min(max(selectedPage, 0), chordPageCount - 1) * 16
    }

    private var pageSelector: some View {
        StudioSegmentedControl(
            title: nil,
            selection: Binding(
                get: { min(selectedPage, chordPageCount - 1) },
                set: { selectedPage = min(max($0, 0), chordPageCount - 1) }
            ),
            segments: (0..<chordPageCount).map { index in
                let start = index * 16 + 1
                let end = min((index + 1) * 16, chordContent.stepCount)
                return StudioSegment(title: "\(start)-\(end)", value: index)
            },
            accent: accent,
            layout: .init(fillsWidth: false, minWidth: 44)
        )
    }

    private var chordStepGrid: some View {
        let states = visibleStepStates()
        return StepGridView(
            stepStates: states,
            indexOffset: chordPageStart,
            playingStepIndex: nil,
            selectedStepIndexes: [selectedStepIndex],
            accent: accent,
            contentProvider: { index, state in
                switch selectedLayer {
                case .chord:
                    return .chordLabel(name: stepSlotName(at: index))
                case .length:
                    return .optionLabel(text: stepLengthDisplayValue(at: index))
                case .inversion:
                    return .optionLabel(text: "I\(selectedStepInversion(at: index))")
                case .chordType:
                    guard state != .off else { return .toggle }
                    return .optionLabel(text: stepChordTypeName(at: index))
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
            case .length:
                cycleStepLength(at: index)
            case .inversion:
                incrementInversion(at: index)
            case .chordType:
                cycleChordType(at: index)
            }
        }
    }

    private var fxTab: some View {
        TrackFXChainView(
            trackID: track.id,
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
            accent: accent,
            knobSize: MacroSlotPresentation.workspaceKnobSize,
            showSlotLabel: false,
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
                ChordRootKeyboard(
                    selectedRoot: selectedSlot.root,
                    progressionRoot: palette.progressionRoot,
                    scaleID: palette.progressionScaleID,
                    accent: accent
                ) { root in
                    updateSelectedSlot { $0.root = root }
                }

                qualityGrid(selectedSlot: selectedSlot)

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

    private func visibleStepStates() -> [StepVisualState] {
        Array(stepStates().dropFirst(chordPageStart).prefix(16))
    }

    private func stepStates() -> [StepVisualState] {
        guard case let .chordReferences(stepPattern, _, inversions, chordIDs, _, _) = chordContent else {
            return Array(repeating: .off, count: 16)
        }
        return stepPattern.indices.map { index in
            guard stepPattern[index] else { return .off }
            if selectedLayer == .inversion, (inversions.value(at: index) ?? 0) != 0 {
                return .accented
            }
            if selectedLayer == .chordType, chordIDs.value(at: index) != nil {
                return .accented
            }
            return .on
        }
    }

    private func stepSlotName(at stepIndex: Int) -> String {
        guard case let .chordReferences(_, slotIDs, _, _, _, _) = chordContent else {
            return "-"
        }
        let slotID = slotIDs.value(at: stepIndex) ?? nil
        return palette.slot(id: slotID)?.name ?? "-"
    }

    private func selectedStepInversion() -> Int {
        selectedStepInversion(at: selectedStepIndex)
    }

    private func selectedStepInversion(at stepIndex: Int) -> Int {
        guard case let .chordReferences(_, _, inversions, _, _, _) = chordContent else {
            return 0
        }
        return inversions.value(at: stepIndex) ?? 0
    }

    private func stepChordTypeName(at stepIndex: Int) -> String {
        guard case let .chordReferences(_, slotIDs, _, chordIDs, _, _) = chordContent else {
            return "-"
        }
        let slotID = slotIDs.value(at: stepIndex) ?? nil
        let fallback = palette.slot(id: slotID)?.chordID ?? selectedSlot?.chordID ?? .majorTriad
        let chordID = (chordIDs.value(at: stepIndex) ?? nil) ?? fallback
        return shortChordName(for: chordID)
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

    private func updateProgressionRoot(_ root: Int) {
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.progressionRoot = root
            track.chordPalette = track.chordPalette.normalized
        }
    }

    private func updateProgressionScale(_ scaleID: ScaleID) {
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.progressionScaleID = scaleID
            track.chordPalette = track.chordPalette.normalized
        }
    }

    private func applyProgressionTemplate(_ template: ProgressionTemplate) {
        let root = palette.progressionRoot
        let intervals = Scale.for(id: palette.progressionScaleID)?.intervals ?? [0, 2, 4, 5, 7, 9, 11]
        let currentSlots = palette.slots
        let slots = template.degrees.enumerated().map { index, degree -> ChordPaletteSlot in
            let existing = currentSlots.value(at: index)
            let interval = intervals.value(at: degree % max(intervals.count, 1)) ?? 0
            let octaveOffset = (degree / max(intervals.count, 1)) * 12
            let quality = template.qualities.value(at: index) ?? .majorTriad
            return ChordPaletteSlot(
                id: existing?.id ?? UUID(),
                name: Self.romanDegreeLabel(for: degree),
                root: min(max(root + interval + octaveOffset, 0), 127),
                chordID: quality,
                scaleID: palette.progressionScaleID
            )
        }
        guard !slots.isEmpty else { return }
        selectedPaletteSlotID = slots.first?.id
        session.mutateTrack(id: track.id) { track in
            track.chordPalette.slots = slots
            track.chordPalette.selectedSlotID = slots.first?.id
            track.chordPalette = track.chordPalette.normalized
        }
    }

    private func assignSelectedSlot(to stepIndex: Int) {
        guard let slotID = selectedPaletteSlotID ?? palette.selectedSlotID else { return }
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps) = content.normalized else {
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
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    private func stepLengthDisplayValue(at stepIndex: Int) -> String {
        guard case let .chordReferences(stepPattern, _, _, _, _, lengthSteps) = chordContent.normalized,
              stepPattern.value(at: stepIndex) == true
        else {
            return ""
        }
        return String(lengthSteps.value(at: stepIndex) ?? 4)
    }

    private func cycleStepLength(at stepIndex: Int) {
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps) = content.normalized else {
                return
            }
            var nextPattern = stepPattern
            var nextLengths = lengthSteps
            guard nextPattern.indices.contains(stepIndex), nextLengths.indices.contains(stepIndex) else { return }
            nextPattern[stepIndex] = true
            nextLengths[stepIndex] = ClipNoteGridStepEditing.nextLength(
                after: nextLengths[stepIndex],
                allowsNatural: false
            ) ?? 1
            content = .chordReferences(
                stepPattern: nextPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: nextLengths
            )
        }
    }

    private func incrementInversion(at stepIndex: Int) {
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps) = content.normalized else {
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
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    private func cycleChordType(at stepIndex: Int) {
        mutateChordClip { content in
            guard case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps) = content.normalized else {
                return
            }
            var nextPattern = stepPattern
            var nextChordIDs = chordIDs
            guard nextPattern.indices.contains(stepIndex), nextChordIDs.indices.contains(stepIndex) else { return }
            nextPattern[stepIndex] = true
            let slotID = slotIDs.value(at: stepIndex) ?? nil
            let fallback = palette.slot(id: slotID)?.chordID ?? .majorTriad
            let current = nextChordIDs[stepIndex] ?? fallback
            let all = ChordID.allCases
            let nextIndex = ((all.firstIndex(of: current) ?? 0) + 1) % all.count
            let nextID = all[nextIndex]
            nextChordIDs[stepIndex] = nextID == fallback ? nil : nextID
            content = .chordReferences(
                stepPattern: nextPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: nextChordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    private func resizeChordClip(to newLength: Int) {
        let resolvedLength = min(max(newLength, 1), 128)
        mutateChordClip { content in
            let normalized = content.normalized
            guard case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps) = normalized else {
                content = .emptyChordReferences(lengthSteps: resolvedLength, defaultSlotID: palette.selectedSlotID)
                return
            }
            content = .chordReferences(
                stepPattern: resized(stepPattern, to: resolvedLength, fill: false),
                slotIDs: resized(slotIDs, to: resolvedLength, fill: palette.selectedSlotID),
                inversions: resized(inversions, to: resolvedLength, fill: 0),
                chordIDs: resized(chordIDs, to: resolvedLength, fill: nil),
                velocities: resized(velocities, to: resolvedLength, fill: 96),
                lengthSteps: resized(lengthSteps, to: resolvedLength, fill: 4)
            )
            .normalized
        }
        selectedPage = min(selectedPage, max(0, (resolvedLength - 1) / 16))
        selectedStepIndex = min(selectedStepIndex, resolvedLength - 1)
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

    private func shortChordName(for chordID: ChordID) -> String {
        switch chordID {
        case .majorTriad: return "Maj"
        case .minorTriad: return "Min"
        case .augmentedTriad: return "Aug"
        case .diminishedTriad: return "Dim"
        case .major7th: return "Maj7"
        case .minor7th: return "Min7"
        case .dominant7th: return "7"
        case .diminished7th: return "Dim7"
        case .augmented7th: return "Aug7"
        case .halfDiminished7th: return "m7b5"
        case .major6th: return "Maj6"
        case .minor6th: return "Min6"
        case .major9th: return "Maj9"
        case .minor9th: return "Min9"
        case .major11th: return "Maj11"
        case .minor11th: return "Min11"
        }
    }

    fileprivate static func romanDegreeLabel(for degree: Int) -> String {
        let labels = ["i", "ii", "iii", "iv", "v", "vi", "vii"]
        guard labels.indices.contains(degree) else {
            return "\(degree + 1)"
        }
        return labels[degree]
    }

    private func resized<Value>(_ values: [Value], to count: Int, fill: Value) -> [Value] {
        if values.count == count { return values }
        if values.count < count {
            return values + Array(repeating: fill, count: count - values.count)
        }
        return Array(values.prefix(count))
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
        case "config:open":
            isConfigPresented = true
            isProgressionChooserPresented = false
        case "config:close":
            isConfigPresented = false
        case "progression:open":
            isProgressionChooserPresented = true
            isConfigPresented = false
        case "progression:close":
            isProgressionChooserPresented = false
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
                "configVisible": isConfigPresented,
                "progressionChooserVisible": isProgressionChooserPresented,
                "trackID": track.id.uuidString
            ]
        )
    }

    private func chordActiveStepCount() -> Int {
        guard case let .chordReferences(stepPattern, _, _, _, _, _) = chordContent else {
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

private struct ChordRootKeyboard: View {
    let selectedRoot: Int
    let progressionRoot: Int
    let scaleID: ScaleID
    let accent: Color
    let onSelect: (Int) -> Void

    private let whiteKeys: [(name: String, pitchClass: Int)] = [
        ("C", 0),
        ("D", 2),
        ("E", 4),
        ("F", 5),
        ("G", 7),
        ("A", 9),
        ("B", 11)
    ]

    private let blackKeys: [(name: String, pitchClass: Int, x: CGFloat)] = [
        ("C#", 1, 0.118),
        ("D#", 3, 0.261),
        ("F#", 6, 0.547),
        ("G#", 8, 0.69),
        ("A#", 10, 0.833)
    ]

    var body: some View {
        GeometryReader { proxy in
            let blackWidth = max(26, proxy.size.width / 11)
            let blackHeight = max(46, proxy.size.height * 0.58)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 4) {
                    ForEach(whiteKeys, id: \.pitchClass) { key in
                        keyButton(
                            name: key.name,
                            pitchClass: key.pitchClass,
                            isBlack: false
                        )
                    }
                }

                ForEach(blackKeys, id: \.pitchClass) { key in
                    keyButton(
                        name: key.name,
                        pitchClass: key.pitchClass,
                        isBlack: true
                    )
                    .frame(width: blackWidth, height: blackHeight)
                    .offset(x: proxy.size.width * key.x - blackWidth / 2)
                }
            }
        }
        .frame(height: 96)
        .frame(maxWidth: 620)
    }

    private func keyButton(name: String, pitchClass: Int, isBlack: Bool) -> some View {
        let isSelected = pitchClass == pitchClassOf(selectedRoot)
        let isProgressionRoot = pitchClass == pitchClassOf(progressionRoot)
        let degree = degreeLabel(for: pitchClass)
        let baseFill = isBlack ? StudioTheme.background : StudioTheme.subtleFill
        return Button {
            onSelect(midiRoot(for: pitchClass))
        } label: {
            VStack(spacing: isBlack ? 3 : 5) {
                Spacer(minLength: 0)
                Text(name)
                    .studioText(.labelBold)
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                    .lineLimit(1)
                Text(degree)
                    .studioText(.micro)
                    .foregroundStyle(isSelected ? StudioTheme.background.opacity(0.8) : StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isProgressionRoot ? "ROOT" : " ")
                    .studioText(.micro)
                    .foregroundStyle(isSelected ? StudioTheme.background : accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, isBlack ? 6 : 8)
            .frame(maxWidth: .infinity)
            .frame(height: isBlack ? nil : 96)
            .background(
                isSelected ? accent : baseFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isProgressionRoot || isSelected ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func degreeLabel(for pitchClass: Int) -> String {
        let relative = pitchClassOf(pitchClass - pitchClassOf(progressionRoot))
        guard let scale = Scale.for(id: scaleID),
              let degree = scale.intervals.firstIndex(of: relative)
        else {
            return ""
        }
        return ChordTrackWorkspaceView.romanDegreeLabel(for: degree)
    }

    private func midiRoot(for pitchClass: Int) -> Int {
        let octaveBase = (selectedRoot / 12) * 12
        var candidate = octaveBase + pitchClass
        if candidate < 24 { candidate += 12 }
        if candidate > 96 { candidate -= 12 }
        return min(max(candidate, 0), 127)
    }

    private func pitchClassOf(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}
