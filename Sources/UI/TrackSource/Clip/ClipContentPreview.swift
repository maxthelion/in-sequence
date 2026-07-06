import SwiftUI

private enum ClipEditorLane: String, CaseIterable, Identifiable {
    case main
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main:
            return "Normal"
        case .fill:
            return "Fill"
        }
    }

    var accent: Color {
        switch self {
        case .main:
            return StudioTheme.cyan
        case .fill:
            return StudioTheme.success
        }
    }

    var activeState: StepVisualState {
        switch self {
        case .main:
            return .on
        case .fill:
            return .accented
        }
    }

    /// The shared step-grid lane this editor lane maps onto.
    var noteLane: StepGridNoteLane {
        switch self {
        case .main:
            return .main
        case .fill:
            return .fill
        }
    }

    func lane(in step: ClipStep) -> ClipLane? {
        noteLane.lane(in: step)
    }
}

enum ClipEditorMode: String, CaseIterable, Identifiable {
    case trigger
    case pitch
    case velocity
    case probability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trigger:
            return "Steps"
        case .pitch:
            return "Pitch"
        case .velocity:
            return "Velocity"
        case .probability:
            return "Chance"
        }
    }
}

enum ClipEditorLayer: Equatable, Hashable {
    case mode(ClipEditorMode)
    case macro(index: Int)

    var id: String {
        switch self {
        case let .mode(mode):
            return mode.rawValue
        case let .macro(index):
            return "macro-\(index)"
        }
    }

    init?(rawValue: String) {
        if let mode = ClipEditorMode(rawValue: rawValue) {
            self = .mode(mode)
            return
        }
        if rawValue.hasPrefix("macro-"),
           let index = Int(rawValue.dropFirst("macro-".count)) {
            self = .macro(index: index)
            return
        }
        return nil
    }

    /// The shared step-grid layer this editor layer maps onto. Macro indexes
    /// are `TrackMacroBinding` array indexes (never visual slot positions).
    var stepGridLayer: StepGridLayer {
        switch self {
        case .mode(.trigger):
            return .trigger
        case .mode(.pitch):
            return .pitch
        case .mode(.velocity):
            return .velocity
        case .mode(.probability):
            return .chance
        case let .macro(index):
            return .macro(index: index)
        }
    }

    init?(stepGridLayer: StepGridLayer) {
        switch stepGridLayer {
        case .trigger:
            self = .mode(.trigger)
        case .pitch:
            self = .mode(.pitch)
        case .velocity:
            self = .mode(.velocity)
        case .chance:
            self = .mode(.probability)
        case let .macro(index):
            self = .macro(index: index)
        case .sliceIndex, .sliceMode, .chord:
            return nil
        }
    }
}

struct ClipMacroLayerTab: Equatable, Identifiable {
    let slotIndex: Int
    let macroIndex: Int
    let binding: TrackMacroBinding

    var id: UUID { binding.id }

    static func tabs(
        macroSlots: [MacroSlot],
        macroBindings: [TrackMacroBinding]
    ) -> [ClipMacroLayerTab] {
        macroSlots.compactMap { slot in
            guard let binding = slot.binding,
                  let macroIndex = macroBindings.firstIndex(where: { $0.id == binding.id })
            else {
                return nil
            }
            return ClipMacroLayerTab(
                slotIndex: slot.slotIndex,
                macroIndex: macroIndex,
                binding: binding
            )
        }
    }
}

struct ClipContentPreview: View {
    let content: ClipContent
    let defaultNote: ClipStepNote
    /// The ONE chrome accent of the surface (track identity colour): thumbs
    /// of the Lane/Length/bar inset-track selectors carry it. Content accents
    /// (step cells, playhead ring) stay free.
    let accent: Color
    let macroSlots: [MacroSlot]
    let macroBindings: [TrackMacroBinding]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let stepGridCoordinator: StepGridCoordinator?
    let onAssignMacroSlot: ((Int) -> Void)?
    let canRandomize: Bool
    let isRandomizePanelVisible: Bool
    let hasSavedRandomizeSettings: Bool
    let randomizePanel: (() -> AnyView)?
    let onRandomize: (() -> Void)?
    let onToggleRandomizePanel: (() -> Void)?
    let playingStepIndex: Int?

    @State private var displayedContent: ClipContent
    @State private var selectedLane: ClipEditorLane = .main
    @State private var selectedLayer: ClipEditorLayer = .mode(.trigger)
    @State private var isLayerSwitcherOpen = false
    @State private var selectedPage = 0

    init(
        content: ClipContent,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4),
        accent: Color,
        macroSlots: [MacroSlot] = [],
        macroBindings: [TrackMacroBinding] = [],
        macroLanes: [UUID: MacroLane] = [:],
        macroFallbackValues: [UUID: Double] = [:],
        stepGridCoordinator: StepGridCoordinator? = nil,
        onAssignMacroSlot: ((Int) -> Void)? = nil,
        canRandomize: Bool = false,
        isRandomizePanelVisible: Bool = false,
        hasSavedRandomizeSettings: Bool = false,
        randomizePanel: (() -> AnyView)? = nil,
        onRandomize: (() -> Void)? = nil,
        onToggleRandomizePanel: (() -> Void)? = nil,
        playingStepIndex: Int? = nil
    ) {
        let normalizedContent = content.normalized
        self.content = normalizedContent
        self.defaultNote = defaultNote.normalized
        self.accent = accent
        self.macroSlots = macroSlots.sorted { $0.slotIndex < $1.slotIndex }
        self.macroBindings = macroBindings
        self.macroLanes = macroLanes
        self.macroFallbackValues = macroFallbackValues
        self.stepGridCoordinator = stepGridCoordinator
        self.onAssignMacroSlot = onAssignMacroSlot
        self.canRandomize = canRandomize
        self.isRandomizePanelVisible = isRandomizePanelVisible
        self.hasSavedRandomizeSettings = hasSavedRandomizeSettings
        self.randomizePanel = randomizePanel
        self.onRandomize = onRandomize
        self.onToggleRandomizePanel = onToggleRandomizePanel
        self.playingStepIndex = playingStepIndex
        self._displayedContent = State(initialValue: normalizedContent)
    }

    /// Edits are enabled exactly when a coordinator is attached: the
    /// coordinator's `commitEdit` is the one clip-write path for every
    /// step-grid surface (audit F1/F3).
    private var isEditable: Bool {
        stepGridCoordinator != nil
    }

    var body: some View {
        Group {
            switch displayedContent {
            case let .noteGrid(lengthSteps, steps):
                noteGridEditor(lengthSteps: lengthSteps, steps: steps)

            case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
                VStack(alignment: .leading, spacing: 14) {
                    StepGridView(
                        stepStates: stepPattern.map { $0 ? .on : .off },
                        playingStepIndex: playingStepIndex
                    ) { index in
                        guard stepPattern.indices.contains(index) else { return }
                        commit { entry in
                            ClipNoteGridStepEditing.toggleActive(
                                at: index,
                                entry: &entry,
                                noteLane: .main,
                                defaultNote: defaultNote
                            )
                        }
                    }
                    .allowsHitTesting(isEditable)

                    TextField(
                        "Comma-separated slice indexes",
                        text: Binding(
                            get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                            set: { newValue in
                                let parsed = newValue
                                    .split(separator: ",")
                                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                                if !parsed.isEmpty {
                                    commit { entry in
                                        guard case let .sliceTriggers(pattern, _, modes, parameters) = entry.content.normalized else { return }
                                        entry.content = .sliceTriggers(
                                            stepPattern: pattern,
                                            sliceIndexes: parsed,
                                            stepModes: modes,
                                            stepParameters: parameters
                                        )
                                    }
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    sliceStepModeEditor(
                        stepPattern: stepPattern,
                        sliceIndexes: sliceIndexes,
                        stepModes: stepModes,
                        stepParameters: stepParameters
                    )
                }
            }
        }
        .onChange(of: content) { _, newContent in
            #if DEBUG
            StepGridTapDiagnostics.log(
                "contentPropChangedFromStore",
                details: diagnosticSummary(for: newContent.normalized)
            )
            #endif
            displayedContent = newContent.normalized
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackSourceEditorVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    private func applyVisualCommand(_ command: String) {
        let layerPrefix = "clip-layer:"
        if command.hasPrefix(layerPrefix),
           let layer = ClipEditorLayer(rawValue: String(command.dropFirst(layerPrefix.count))) {
            selectedLayer = layer
            return
        }

        switch command {
        case "clip-layer-switcher:open":
            isLayerSwitcherOpen = true
        case "clip-layer-switcher:close":
            isLayerSwitcherOpen = false
        default:
            break
        }
    }

    @ViewBuilder
    private func noteGridEditor(lengthSteps: Int, steps: [ClipStep]) -> some View {
        let pageCount = max(1, (lengthSteps + 15) / 16)
        let playheadPage = playingStepIndex.map { min(max($0, 0), lengthSteps - 1) / 16 }
        let page = min(selectedPage, pageCount - 1)
        let pageStart = page * 16
        let pageEnd = min(pageStart + 16, lengthSteps)
        let visibleIndices = Array(pageStart..<pageEnd)
        let visibleSteps = visibleIndices.map { steps[$0] }

        VStack(alignment: .leading, spacing: 12) {
            clipHeaderControls(
                lengthSteps: lengthSteps,
                steps: steps,
                page: page,
                pageCount: pageCount,
                playheadPage: playheadPage
            )

            if isRandomizePanelVisible, let randomizePanel {
                randomizePanel()
            } else {
                layerDisclosureRow(lengthSteps: lengthSteps, steps: steps)

                if let selectedMacroLayer {
                    let layer = StepGridLayer.macro(index: selectedMacroLayer.macroIndex)
                    let previewClip = macroPreviewClip(lengthSteps: lengthSteps, steps: steps)

                    StepGridView(
                        stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                        indexOffset: pageStart,
                        playingStepIndex: playingStepIndex,
                        selectedStepIndexes: selectedStepIndexes,
                        contentProvider: { index, _ in
                            StepGridCoordinator.cellContent(
                                for: index,
                                in: previewClip,
                                layer: layer,
                                macroBindings: macroBindings
                            )
                        },
                        onValueDrag: { index, fraction in
                            writeValueLayer(fraction, layer: layer, tappedIndex: index)
                        },
                        onSelectStep: selectStepAction,
                        onBackgroundTap: clearSelectionAction
                    ) { index in
                        cycleMacroLayerValue(macroIndex: selectedMacroLayer.macroIndex, tappedIndex: index)
                    }
                    .allowsHitTesting(isEditable)
                } else {
                    switch selectedMode {
                    case .trigger:
                        StepGridView(
                            stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                            indexOffset: pageStart,
                            playingStepIndex: playingStepIndex,
                            selectedStepIndexes: selectedStepIndexes,
                            onSelectStep: selectStepAction,
                            onBackgroundTap: clearSelectionAction
                        ) { index in
                            #if DEBUG
                            let beforeState = steps.indices.contains(index)
                                ? stepVisualState(for: steps[index], lane: selectedLane).diagnosticName
                                : "missing"
                            StepGridTapDiagnostics.log(
                                "clipTriggerTapHandler",
                                stepIndex: index,
                                details: "lane=\(selectedLane.rawValue) before=\(beforeState)"
                            )
                            #endif
                            let indexes = affectedStepIndexes(for: index)
                            commit { entry in
                                ClipNoteGridStepEditing.applyTap(
                                    tappedIndex: index,
                                    indexes: indexes,
                                    layer: .trigger,
                                    entry: &entry,
                                    macroBindings: nil,
                                    noteLane: selectedLane.noteLane,
                                    defaultNote: defaultNote
                                )
                            }
                        }
                        .allowsHitTesting(isEditable)

                    case .pitch:
                        StepGridView(
                            stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                            indexOffset: pageStart,
                            playingStepIndex: playingStepIndex,
                            selectedStepIndexes: selectedStepIndexes,
                            contentProvider: { index, _ in
                                StepGridCoordinator.cellContent(
                                    for: index,
                                    in: macroPreviewClip(lengthSteps: lengthSteps, steps: steps),
                                    layer: .pitch,
                                    noteLane: selectedLane.noteLane
                                )
                            },
                            onValueDrag: { index, fraction in
                                writeValueLayer(fraction, layer: .pitch, tappedIndex: index)
                            },
                            onSelectStep: selectStepAction,
                            onBackgroundTap: clearSelectionAction,
                            onOctaveTap: { index in
                                let indexes = affectedStepIndexes(for: index)
                                commit { entry in
                                    ClipNoteGridStepEditing.applyOctaveTap(
                                        tappedIndex: index,
                                        indexes: indexes,
                                        entry: &entry,
                                        noteLane: selectedLane.noteLane,
                                        defaultNote: defaultNote
                                    )
                                }
                            }
                        ) { index in
                            let indexes = affectedStepIndexes(for: index)
                            commit { entry in
                                ClipNoteGridStepEditing.applyTap(
                                    tappedIndex: index,
                                    indexes: indexes,
                                    layer: .pitch,
                                    entry: &entry,
                                    macroBindings: nil,
                                    noteLane: selectedLane.noteLane,
                                    defaultNote: defaultNote
                                )
                            }
                        }
                        .allowsHitTesting(isEditable)

                    case .velocity:
                        StepGridView(
                            stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                            indexOffset: pageStart,
                            playingStepIndex: playingStepIndex,
                            selectedStepIndexes: selectedStepIndexes,
                            contentProvider: { index, _ in
                                guard steps.indices.contains(index) else {
                                    return .valueBar(fraction: 0)
                                }
                                return .valueBar(fraction: velocityValue(for: steps[index], lane: selectedLane) / 127.0)
                            },
                            onValueDrag: { index, fraction in
                                writeValueLayer(fraction, layer: .velocity, tappedIndex: index)
                            },
                            onSelectStep: selectStepAction,
                            onBackgroundTap: clearSelectionAction
                        ) { index in
                            guard steps.indices.contains(index) else { return }
                            let nextValue = ClipNoteGridStepEditing.cycledValue(
                                after: velocityValue(for: steps[index], lane: selectedLane),
                                allowedValues: ClipNoteGridStepEditing.velocityCycleValues
                            )
                            writeValueLayer(nextValue / 127.0, layer: .velocity, tappedIndex: index)
                        }
                        .allowsHitTesting(isEditable)

                    case .probability:
                        StepGridView(
                            stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                            indexOffset: pageStart,
                            playingStepIndex: playingStepIndex,
                            selectedStepIndexes: selectedStepIndexes,
                            contentProvider: { index, _ in
                                guard steps.indices.contains(index) else {
                                    return .valueBar(fraction: 0)
                                }
                                return .valueBar(fraction: chanceValue(for: steps[index], lane: selectedLane))
                            },
                            onValueDrag: { index, fraction in
                                writeValueLayer(fraction, layer: .chance, tappedIndex: index)
                            },
                            onSelectStep: selectStepAction,
                            onBackgroundTap: clearSelectionAction
                        ) { index in
                            guard steps.indices.contains(index) else { return }
                            let nextValue = ClipNoteGridStepEditing.cycledValue(
                                after: chanceValue(for: steps[index], lane: selectedLane),
                                allowedValues: ClipNoteGridStepEditing.chanceCycleValues
                            )
                            writeValueLayer(nextValue, layer: .chance, tappedIndex: index)
                        }
                        .allowsHitTesting(isEditable)
                    }
                }
            }
        }
        .background {
            StepGridEscapeKeyHandler(isEnabled: stepGridCoordinator?.isSelectionActive ?? false) {
                stepGridCoordinator?.clearSelection()
            }
        }
        .onAppear {
            clampPage(lengthSteps: lengthSteps)
            syncCoordinatorLayers()
        }
        .onChange(of: lengthSteps) { _, newLength in
            clampPage(lengthSteps: newLength)
            pruneSelection(lengthSteps: newLength)
        }
        .onChange(of: selectedLayer) { _, _ in
            syncCoordinatorLayers()
        }
        .onChange(of: macroSlots) { _, slots in
            defer { syncCoordinatorLayers() }
            guard case let .macro(index) = selectedLayer else {
                return
            }
            let tabs = ClipMacroLayerTab.tabs(macroSlots: slots, macroBindings: macroBindings)
            if !tabs.contains(where: { $0.macroIndex == index }) {
                selectedLayer = .mode(.trigger)
            }
        }
    }

    /// The layer row above the grid: plain single-line layer selector when no
    /// steps are selected, the shared Variant D rotary row (one arc-dial per
    /// editable layer, writing to every selected step) while a selection is
    /// active. Shared with the slicer workspace — no parallel inspector.
    @ViewBuilder
    private func layerControlRow(lengthSteps: Int, steps: [ClipStep]) -> some View {
        if let stepGridCoordinator, stepGridCoordinator.shouldShowRotaryRow {
            StepLayerRotaryRow(
                controls: stepGridCoordinator.rotaryControls(
                    in: macroPreviewClip(lengthSteps: lengthSteps, steps: steps),
                    macroBindings: macroBindings,
                    noteLane: selectedLane.noteLane
                ),
                activeLayer: selectedLayer.stepGridLayer,
                suppressActiveLayerHighlight: selectedLayer == .mode(.trigger),
                accent: selectedLane.accent,
                onSelectLayer: { layer in
                    if let editorLayer = ClipEditorLayer(stepGridLayer: layer) {
                        selectedLayer = editorLayer
                    }
                },
                onWriteValue: { layer, value in
                    writeRotaryValue(value, layer: layer)
                }
            )
        } else if stepGridCoordinator?.isSelectionActive == true {
            StepLayerRotaryEmptyState()
        } else {
            layerLineControl
        }
    }

    private var selectedStepIndexes: Set<Int> {
        stepGridCoordinator?.selection.selectedStepIndexes ?? []
    }

    private var selectStepAction: ((Int) -> Void)? {
        guard let stepGridCoordinator else { return nil }
        return { stepIndex in
            stepGridCoordinator.toggleSelection(at: stepIndex)
        }
    }

    private var clearSelectionAction: (() -> Void)? {
        guard let stepGridCoordinator else { return nil }
        return { stepGridCoordinator.clearSelection() }
    }

    /// Selection-aware edit targets: editing a selected step applies the same
    /// value to every selected step in one commit; editing an unselected step
    /// only touches that step and leaves the selection alone.
    private func affectedStepIndexes(for stepIndex: Int) -> [Int] {
        guard let stepGridCoordinator,
              stepGridCoordinator.selection.selectedStepIndexes.contains(stepIndex)
        else {
            return [stepIndex]
        }
        return stepGridCoordinator.selection.selectedStepIndexes.sorted()
    }

    private func writeRotaryValue(_ value: Double, layer: StepGridLayer) {
        guard let stepGridCoordinator,
              let seedStepIndex = stepGridCoordinator.selectedRotarySeedStepIndex
        else {
            return
        }
        _ = stepGridCoordinator.writeAbsoluteValue(
            value,
            stepIndex: seedStepIndex,
            layer: layer,
            macroBindings: macroBindings,
            noteLane: selectedLane.noteLane,
            defaultNote: defaultNote
        )
    }

    private func syncCoordinatorLayers() {
        guard let stepGridCoordinator else { return }
        stepGridCoordinator.updateEditableLayers(
            [.pitch, .velocity, .chance] + macroLayerTabs.map { StepGridLayer.macro(index: $0.macroIndex) }
        )
        stepGridCoordinator.updateActiveLayer(selectedLayer.stepGridLayer)
    }

    private func pruneSelection(lengthSteps: Int) {
        guard let stepGridCoordinator else { return }
        let pruned = stepGridCoordinator.selection.selectedStepIndexes.filter { $0 < lengthSteps }
        if pruned != stepGridCoordinator.selection.selectedStepIndexes {
            stepGridCoordinator.selection.selectedStepIndexes = pruned
        }
    }

    // Unified tab grammar (Variant D): the STEPS/CLIP pill already names this
    // panel (no "CLIP" header restating, canon Rule 1), and Lane/Length are
    // VALUE selectors — solid surface-accent thumbs inside darker inset
    // tracks, never bespoke floating capsules or a second chrome accent.
    private func clipHeaderControls(
        lengthSteps: Int,
        steps: [ClipStep],
        page: Int,
        pageCount: Int,
        playheadPage: Int?
    ) -> some View {
        HStack(alignment: .top, spacing: StudioMetrics.Spacing.standard) {
            StudioSegmentedControl(
                title: "Lane",
                selection: $selectedLane,
                segments: ClipEditorLane.allCases.map { lane in
                    StudioSegment(title: lane.title, value: lane)
                },
                accent: accent,
                layout: .init(fillsWidth: false, minWidth: 64)
            )

            StudioSegmentedControl(
                title: "Length",
                selection: Binding(
                    get: { lengthSteps },
                    set: { option in
                        commit { entry in
                            guard case let .noteGrid(_, currentSteps) = entry.content.normalized else { return }
                            entry.content = resizingNoteGrid(to: option, currentSteps: currentSteps)
                        }
                    }
                ),
                segments: [16, 32, 64, 128].map { option in
                    StudioSegment(title: "\(option)", value: option, isEnabled: isEditable)
                },
                accent: accent,
                layout: .init(fillsWidth: false, minWidth: 44)
            )

            if pageCount > 1 {
                pageSelector(lengthSteps: lengthSteps, page: page, pageCount: pageCount, playheadPage: playheadPage)
            }

            StepLayerQuickSwitchChip(
                title: "Layer",
                selection: $selectedLayer,
                isOpen: $isLayerSwitcherOpen,
                options: layerQuickSwitchOptions,
                accent: accent
            )

            randomizeControls

            Text("\(noteCount(in: steps)) notes")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize()

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var randomizeControls: some View {
        if onRandomize != nil || onToggleRandomizePanel != nil {
            HStack(spacing: 6) {
                Button {
                    onRandomize?()
                } label: {
                    Label("Randomize", systemImage: "die.face.5")
                        .studioText(.labelBold)
                        .foregroundStyle(canRandomize ? StudioTheme.background : StudioTheme.mutedText)
                        .lineLimit(1)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            canRandomize ? accent : StudioTheme.border,
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canRandomize)
                .accessibilityLabel("Randomize current clip")

                Button {
                    onToggleRandomizePanel?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canRandomize ? StudioTheme.text : StudioTheme.mutedText)
                        .frame(width: 30, height: 30)
                        .background(
                            isRandomizePanelVisible ? Color.white.opacity(StudioOpacity.subtleFill) : Color.clear,
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                                .stroke(randomizeSettingsStroke, lineWidth: StudioMetrics.borderWidth)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canRandomize)
                .help("Randomize settings")
                .accessibilityLabel("Randomize settings")
                .accessibilityValue(hasSavedRandomizeSettings ? "Saved" : "Default")
            }
            .fixedSize()
        }
    }

    private var randomizeSettingsStroke: Color {
        guard canRandomize else { return StudioTheme.border }
        return isRandomizePanelVisible || hasSavedRandomizeSettings ? accent : StudioTheme.border
    }

    @ViewBuilder
    private func layerDisclosureRow(lengthSteps: Int, steps: [ClipStep]) -> some View {
        if isLayerSwitcherOpen {
            VStack(alignment: .leading, spacing: 8) {
                StepLayerQuickSwitchOptions(
                    selection: $selectedLayer,
                    isOpen: $isLayerSwitcherOpen,
                    options: layerQuickSwitchOptions,
                    accent: accent
                )
                assignMacroButtonRow
            }
        } else {
            layerControlRow(lengthSteps: lengthSteps, steps: steps)
        }
    }

    // BAR-range value selector (inset-track grammar): solid surface-accent
    // thumb; the green ring is the playhead page — content state, not chrome.
    private func pageSelector(lengthSteps: Int, page: Int, pageCount: Int, playheadPage: Int?) -> some View {
        StudioSegmentedControl(
            title: nil,
            selection: Binding(
                get: { page },
                set: { selectedPage = $0 }
            ),
            segments: (0..<pageCount).map { index in
                let start = index * 16 + 1
                let end = min((index + 1) * 16, lengthSteps)
                return StudioSegment(
                    title: "\(start)-\(end)",
                    value: index,
                    indicatorAccent: playheadPage == index ? StudioTheme.success : nil
                )
            },
            accent: accent,
            layout: .init(fillsWidth: false, minWidth: 44)
        )
    }

    /// Single-line layer selector: chevrons step through trigger/velocity/
    /// chance and any assigned macro lanes without spending grid rows.
    private var layerLineControl: some View {
        assignMacroButtonRow
    }

    @ViewBuilder
    private var assignMacroButtonRow: some View {
        if let firstUnassignedSlot = macroSlots.first(where: { $0.binding == nil }),
           onAssignMacroSlot != nil {
            HStack {
                Spacer(minLength: 0)
                Button {
                    onAssignMacroSlot?(firstUnassignedSlot.slotIndex)
                } label: {
                    Label("Assign Macro", systemImage: "plus")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .buttonStyle(.plain)
                .help("Assign macro M\(firstUnassignedSlot.slotIndex + 1)")
            }
        }
    }

    private var layerQuickSwitchOptions: [StepLayerQuickSwitchOption<ClipEditorLayer>] {
        orderedEditorLayers.map { layer in
            StepLayerQuickSwitchOption(
                id: layer.id,
                title: title(for: layer),
                value: layer
            )
        }
    }

    private var orderedEditorLayers: [ClipEditorLayer] {
        ClipEditorMode.allCases.map { ClipEditorLayer.mode($0) }
            + macroLayerTabs.map { ClipEditorLayer.macro(index: $0.macroIndex) }
    }

    private func title(for layer: ClipEditorLayer) -> String {
        switch layer {
        case let .mode(mode):
            return mode.title
        case let .macro(index):
            let tab = macroLayerTabs.first { $0.macroIndex == index }
            return tab.map { "M\($0.slotIndex + 1)" } ?? "Macro"
        }
    }

    private var currentLayerTitle: String {
        switch selectedLayer {
        case let .mode(mode):
            return mode.title
        case let .macro(index):
            let tab = macroLayerTabs.first { $0.macroIndex == index }
            return tab.map { "M\($0.slotIndex + 1) · \($0.binding.displayName)" } ?? "Macro"
        }
    }

    private func cycleEditorLayer(by delta: Int) {
        let layers = orderedEditorLayers
        guard !layers.isEmpty else { return }
        let currentIndex = layers.firstIndex(of: selectedLayer) ?? 0
        selectedLayer = layers[(currentIndex + delta + layers.count) % layers.count]
    }

    private var selectedMode: ClipEditorMode {
        guard case let .mode(mode) = selectedLayer else {
            return .trigger
        }
        return mode
    }

    private var selectedMacroBinding: TrackMacroBinding? {
        selectedMacroLayer?.binding
    }

    private var selectedMacroLayer: ClipMacroLayerTab? {
        guard case let .macro(index) = selectedLayer else {
            return nil
        }
        return macroLayerTabs.first { $0.macroIndex == index }
    }

    private var macroLayerTabs: [ClipMacroLayerTab] {
        ClipMacroLayerTab.tabs(macroSlots: macroSlots, macroBindings: macroBindings)
    }

    private func macroLayerTab(for slot: MacroSlot) -> ClipMacroLayerTab? {
        macroLayerTabs.first { $0.slotIndex == slot.slotIndex }
    }

    /// One value-layer write for drags, tap cycles, and macro lanes: the
    /// shared `applyAbsoluteValue` transform over the selection-aware
    /// affected indexes, committed through the coordinator in one mutation.
    private func writeValueLayer(_ value: Double, layer: StepGridLayer, tappedIndex: Int) {
        let indexes = affectedStepIndexes(for: tappedIndex)
        commit { entry in
            ClipNoteGridStepEditing.applyAbsoluteValue(
                value,
                indexes: indexes,
                layer: layer,
                entry: &entry,
                macroBindings: macroBindings,
                noteLane: selectedLane.noteLane,
                defaultNote: defaultNote
            )
        }
    }

    /// Macro-layer tap: the shared quantized cycle (spec §4c), seeded from
    /// the tapped step's stored value, falling back to the live macro value.
    private func cycleMacroLayerValue(macroIndex: Int, tappedIndex: Int) {
        let indexes = affectedStepIndexes(for: tappedIndex)
        commit { entry in
            ClipNoteGridStepEditing.applyTap(
                tappedIndex: tappedIndex,
                indexes: indexes,
                layer: .macro(index: macroIndex),
                entry: &entry,
                macroBindings: macroBindings,
                noteLane: selectedLane.noteLane,
                defaultNote: defaultNote,
                macroFallbackValues: macroFallbackValues
            )
        }
    }

    private func macroPreviewClip(lengthSteps: Int, steps: [ClipStep]) -> ClipPoolEntry {
        ClipPoolEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: "Preview",
            trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: lengthSteps, steps: steps),
            macroLanes: macroLanes
        )
    }

    private func clampPage(lengthSteps: Int) {
        let pageCount = max(1, (lengthSteps + 15) / 16)
        selectedPage = min(selectedPage, pageCount - 1)
    }

    /// Commit a step edit through the one clip-write path (audit F1/F3).
    ///
    /// The edit is an in-place transform of a `ClipPoolEntry`. It is applied
    /// twice: first to a local copy seeded from `displayedContent` so the
    /// tapped cell repaints in the same frame (optimistic render — this is
    /// the tap-latency path), then to live store truth through
    /// `StepGridCoordinator.commitEdit` → `mutateClip(id:)`. Because the
    /// store application transforms *current* store state instead of
    /// replacing the clip with content built from this view's copy,
    /// interleaved writes from other surfaces (rotary row, slicer) are never
    /// lost. The store's change comes back through `content` and replaces
    /// `displayedContent`, which stays a pure render cache.
    private func commit(_ edit: (inout ClipPoolEntry) -> Void) {
        guard let stepGridCoordinator else { return }
        var optimistic = ClipPoolEntry(
            id: optimisticEntryID,
            name: "Optimistic",
            trackType: .monoMelodic,
            content: displayedContent,
            macroLanes: macroLanes
        )
        edit(&optimistic)
        let normalized = optimistic.content.normalized
        #if DEBUG
        StepGridTapDiagnostics.log(
            "optimisticContentAssignStart",
            details: diagnosticSummary(for: normalized)
        )
        #endif
        displayedContent = normalized
        #if DEBUG
        StepGridTapDiagnostics.log(
            "optimisticContentAssignEnd",
            details: diagnosticSummary(for: normalized)
        )
        let commitStart = StepGridTapDiagnostics.now
        #endif
        _ = stepGridCoordinator.commitEdit(edit)
        #if DEBUG
        StepGridTapDiagnostics.log(
            "onCommitReturned",
            details: "elapsed=\(StepGridTapDiagnostics.elapsedMilliseconds(since: commitStart)) \(diagnosticSummary(for: normalized))"
        )
        #endif
    }

    private var optimisticEntryID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    }

    #if DEBUG
    private func diagnosticSummary(for content: ClipContent) -> String {
        switch content {
        case let .noteGrid(lengthSteps, steps):
            return "noteGrid length=\(lengthSteps) notes=\(noteCount(in: steps))"
        case let .sliceTriggers(stepPattern, _, _, _):
            return "sliceTriggers length=\(stepPattern.count) active=\(stepPattern.filter { $0 }.count)"
        }
    }
    #endif

    private func sliceStepModeEditor(
        stepPattern: [Bool],
        sliceIndexes: [Int],
        stepModes: [SliceTriggerStepMode],
        stepParameters: [SliceTriggerStepParameters]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN MODE")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(stepPattern.indices, id: \.self) { index in
                    let mode = stepModes.indices.contains(index) ? stepModes[index] : .single
                    Button {
                        let target = mode == .single ? 1 : 0
                        commit { entry in
                            ClipNoteGridStepEditing.setSliceMode(target, at: index, entry: &entry)
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(index + 1)")
                                .studioText(.micro)
                                .foregroundStyle(mode == .runFromHere ? StudioTheme.background : StudioTheme.text)
                            Text(mode == .runFromHere ? "Run" : "One")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(mode == .runFromHere ? StudioTheme.background : (stepPattern[index] ? StudioTheme.text : StudioTheme.mutedText.opacity(0.55)))
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        // Colour identifies, it never floods (ux-canon rule
                        // 12): an engaged step cell is fully solid accent with
                        // dark glyphs, never a translucent wash.
                        .background(
                            mode == .runFromHere ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(mode == .runFromHere ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!stepPattern[index] || !isEditable)
                    .opacity(stepPattern[index] ? 1 : 0.45)
                }
            }
        }
    }


    private func stepVisualState(for step: ClipStep, lane: ClipEditorLane) -> StepVisualState {
        ClipNoteGridStepEditing.visualState(for: step, lane: lane.noteLane, activeState: lane.activeState)
    }

    private func chanceValue(for step: ClipStep, lane: ClipEditorLane) -> Double {
        ClipNoteGridStepEditing.chanceValue(for: step, lane: lane.noteLane)
    }

    private func velocityValue(for step: ClipStep, lane: ClipEditorLane) -> Double {
        ClipNoteGridStepEditing.velocityValue(for: step, lane: lane.noteLane)
    }

    private func resizingNoteGrid(to newLength: Int, currentSteps: [ClipStep]) -> ClipContent {
        let resolvedLength = max(1, newLength)
        let resizedSteps = (0..<resolvedLength).map { index in
            currentSteps.indices.contains(index) ? currentSteps[index] : .empty
        }
        return .noteGrid(lengthSteps: resolvedLength, steps: resizedSteps)
    }

    private func noteCount(in steps: [ClipStep]) -> Int {
        steps.reduce(0) { partial, step in
            partial + (step.main?.notes.count ?? 0) + (step.fill?.notes.count ?? 0)
        }
    }
}
