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

private enum ClipEditorMode: String, CaseIterable, Identifiable {
    case trigger
    case velocity
    case probability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trigger:
            return "Steps"
        case .velocity:
            return "Velocity"
        case .probability:
            return "Chance"
        }
    }
}

private enum ClipEditorLayer: Equatable {
    case mode(ClipEditorMode)
    case macro(index: Int)
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

private struct ClipStepInspectorTarget: Identifiable, Equatable {
    let stepIndex: Int

    var id: Int { stepIndex }
}

struct ClipContentPreview: View {
    let content: ClipContent
    let defaultNote: ClipStepNote
    let macroSlots: [MacroSlot]
    let macroBindings: [TrackMacroBinding]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let onAssignMacroSlot: ((Int) -> Void)?
    let onUpdateMacroLanes: (([UUID: MacroLane]) -> Void)?
    let playingStepIndex: Int?
    let onCommit: ((ClipContent) -> Void)?

    @State private var displayedContent: ClipContent
    @State private var selectedLane: ClipEditorLane = .main
    @State private var selectedLayer: ClipEditorLayer = .mode(.trigger)
    @State private var selectedPage = 0
    @State private var editingStepTarget: ClipStepInspectorTarget?

    init(
        content: ClipContent,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4),
        macroSlots: [MacroSlot] = [],
        macroBindings: [TrackMacroBinding] = [],
        macroLanes: [UUID: MacroLane] = [:],
        macroFallbackValues: [UUID: Double] = [:],
        onAssignMacroSlot: ((Int) -> Void)? = nil,
        onUpdateMacroLanes: (([UUID: MacroLane]) -> Void)? = nil,
        playingStepIndex: Int? = nil,
        onChange: ((ClipContent) -> Void)? = nil
    ) {
        let normalizedContent = content.normalized
        self.content = normalizedContent
        self.defaultNote = defaultNote.normalized
        self.macroSlots = macroSlots.sorted { $0.slotIndex < $1.slotIndex }
        self.macroBindings = macroBindings
        self.macroLanes = macroLanes
        self.macroFallbackValues = macroFallbackValues
        self.onAssignMacroSlot = onAssignMacroSlot
        self.onUpdateMacroLanes = onUpdateMacroLanes
        self.playingStepIndex = playingStepIndex
        self.onCommit = onChange
        self._displayedContent = State(initialValue: normalizedContent)
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
                        var nextPattern = stepPattern
                        guard nextPattern.indices.contains(index) else { return }
                        nextPattern[index].toggle()
                        commit(.sliceTriggers(stepPattern: nextPattern, sliceIndexes: sliceIndexes, stepModes: stepModes, stepParameters: stepParameters))
                    }
                    .allowsHitTesting(onCommit != nil)

                    TextField(
                        "Comma-separated slice indexes",
                        text: Binding(
                            get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                            set: { newValue in
                                let parsed = newValue
                                    .split(separator: ",")
                                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                                if !parsed.isEmpty {
                                    commit(.sliceTriggers(stepPattern: stepPattern, sliceIndexes: parsed, stepModes: stepModes, stepParameters: stepParameters))
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
            clipHeaderControls(lengthSteps: lengthSteps, steps: steps)

            layerLineControl

            if let selectedMacroLayer {
                let layer = StepGridLayer.macro(index: selectedMacroLayer.macroIndex)
                let previewClip = macroPreviewClip(lengthSteps: lengthSteps, steps: steps)

                StepGridView(
                    stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                    indexOffset: pageStart,
                    playingStepIndex: playingStepIndex,
                    contentProvider: { index, _ in
                        StepGridCoordinator.cellContent(
                            for: index,
                            in: previewClip,
                            layer: layer,
                            macroBindings: macroBindings
                        )
                    },
                    onValueDrag: { index, fraction in
                        updateMacroLaneFraction(
                            fraction,
                            binding: selectedMacroLayer.binding,
                            stepIndex: index,
                            stepCount: lengthSteps
                        )
                    },
                    onDoubleTap: { stepIndex in
                        clearMacroLaneValue(
                            binding: selectedMacroLayer.binding,
                            stepIndex: stepIndex,
                            stepCount: lengthSteps
                        )
                    }
                ) { index in
                    cycleMacroLaneValue(
                        binding: selectedMacroLayer.binding,
                        stepIndex: index,
                        stepCount: lengthSteps
                    )
                }
                .allowsHitTesting(onUpdateMacroLanes != nil)
            } else {
                switch selectedMode {
                case .trigger:
                    StepGridView(
                        stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                        indexOffset: pageStart,
                        playingStepIndex: playingStepIndex,
                        onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
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
                        commit(togglingStep(at: index, lengthSteps: lengthSteps, steps: steps, lane: selectedLane))
                    }
                    .allowsHitTesting(onCommit != nil)

                case .velocity:
                    StepGridView(
                        stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                        indexOffset: pageStart,
                        playingStepIndex: playingStepIndex,
                        contentProvider: { index, _ in
                            guard steps.indices.contains(index) else {
                                return .valueBar(fraction: 0)
                            }
                            return .valueBar(fraction: velocityValue(for: steps[index], lane: selectedLane) / 127.0)
                        },
                        onValueDrag: { index, fraction in
                            commit(
                                ClipNoteGridStepEditing.updatingLaneVelocities(
                                    lane: selectedLane.noteLane,
                                    values: [fraction * 127.0],
                                    visibleIndices: [index],
                                    lengthSteps: lengthSteps,
                                    steps: steps,
                                    defaultNote: defaultNote
                                )
                            )
                        },
                        onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
                    ) { index in
                        guard steps.indices.contains(index) else { return }
                        let nextValue = ClipNoteGridStepEditing.cycledValue(
                            after: velocityValue(for: steps[index], lane: selectedLane),
                            allowedValues: ClipNoteGridStepEditing.velocityCycleValues
                        )
                        commit(
                            ClipNoteGridStepEditing.updatingLaneVelocities(
                                lane: selectedLane.noteLane,
                                values: [nextValue],
                                visibleIndices: [index],
                                lengthSteps: lengthSteps,
                                steps: steps,
                                defaultNote: defaultNote
                            )
                        )
                    }
                    .allowsHitTesting(onCommit != nil)

                case .probability:
                    StepGridView(
                        stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                        indexOffset: pageStart,
                        playingStepIndex: playingStepIndex,
                        contentProvider: { index, _ in
                            guard steps.indices.contains(index) else {
                                return .valueBar(fraction: 0)
                            }
                            return .valueBar(fraction: chanceValue(for: steps[index], lane: selectedLane))
                        },
                        onValueDrag: { index, fraction in
                            commit(
                                ClipNoteGridStepEditing.updatingLaneChances(
                                    lane: selectedLane.noteLane,
                                    values: [fraction],
                                    visibleIndices: [index],
                                    lengthSteps: lengthSteps,
                                    steps: steps,
                                    defaultNote: defaultNote
                                )
                            )
                        },
                        onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
                    ) { index in
                        guard steps.indices.contains(index) else { return }
                        let nextValue = ClipNoteGridStepEditing.cycledValue(
                            after: chanceValue(for: steps[index], lane: selectedLane),
                            allowedValues: ClipNoteGridStepEditing.chanceCycleValues
                        )
                        commit(
                            ClipNoteGridStepEditing.updatingLaneChances(
                                lane: selectedLane.noteLane,
                                values: [nextValue],
                                visibleIndices: [index],
                                lengthSteps: lengthSteps,
                                steps: steps,
                                defaultNote: defaultNote
                            )
                        )
                    }
                    .allowsHitTesting(onCommit != nil)
                }
            }

            clipFooter(lengthSteps: lengthSteps, page: page, pageCount: pageCount, playheadPage: playheadPage, steps: steps)
        }
        .sheet(item: $editingStepTarget) { target in
            Group {
                if steps.indices.contains(target.stepIndex) {
                    ClipStepInspectorSheet(
                        stepIndex: target.stepIndex,
                        step: steps[target.stepIndex],
                        accent: selectedLane.accent
                    )
                } else {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear {
                            editingStepTarget = nil
                        }
                }
            }
            .presentationBackground(.clear)
        }
        .onAppear {
            clampPage(lengthSteps: lengthSteps)
        }
        .onChange(of: lengthSteps) { _, newLength in
            clampPage(lengthSteps: newLength)
            if let editingStepTarget, editingStepTarget.stepIndex >= newLength {
                self.editingStepTarget = nil
            }
        }
        .onChange(of: macroSlots) { _, slots in
            guard case let .macro(index) = selectedLayer else {
                return
            }
            let tabs = ClipMacroLayerTab.tabs(macroSlots: slots, macroBindings: macroBindings)
            if !tabs.contains(where: { $0.macroIndex == index }) {
                selectedLayer = .mode(.trigger)
            }
        }
    }

    private func clipHeaderControls(lengthSteps: Int, steps: [ClipStep]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("CLIP")
                    .studioText(.bodyEmphasis)
                    .tracking(1.1)
                    .foregroundStyle(StudioTheme.text)

                Rectangle()
                    .fill(StudioTheme.violet)
                    .frame(width: 36, height: 2)
            }

            HStack(alignment: .top, spacing: 16) {
                headerControlGroup(title: "Lane") {
                    HStack(spacing: 8) {
                        ForEach(ClipEditorLane.allCases) { lane in
                            chipButton(
                                title: lane.title,
                                accent: lane.accent,
                                isSelected: selectedLane == lane,
                                action: { selectedLane = lane }
                            )
                        }
                    }
                }

                headerControlGroup(title: "Length") {
                    HStack(spacing: 8) {
                        ForEach([16, 32, 64, 128], id: \.self) { option in
                            chipButton(
                                title: "\(option)",
                                accent: StudioTheme.violet,
                                isSelected: lengthSteps == option,
                                isEnabled: onCommit != nil,
                                action: {
                                    commit(resizingNoteGrid(to: option, currentSteps: steps))
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func clipFooter(
        lengthSteps: Int,
        page: Int,
        pageCount: Int,
        playheadPage: Int?,
        steps: [ClipStep]
    ) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("\(noteCount(in: steps)) notes")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .monospacedDigit()

            Spacer(minLength: 12)

            if pageCount > 1 {
                pageSelector(lengthSteps: lengthSteps, page: page, pageCount: pageCount, playheadPage: playheadPage)
            }
        }
    }

    private func pageSelector(lengthSteps: Int, page: Int, pageCount: Int, playheadPage: Int?) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                let start = index * 16 + 1
                let end = min((index + 1) * 16, lengthSteps)
                chipButton(
                    title: "\(start)-\(end)",
                    accent: selectedLane.accent,
                    isSelected: page == index,
                    isPlaying: playheadPage == index,
                    action: { selectedPage = index }
                )
            }
        }
    }

    /// Single-line layer selector: chevrons step through trigger/velocity/
    /// chance and any assigned macro lanes without spending grid rows.
    private var layerLineControl: some View {
        HStack(spacing: 10) {
            StudioStepperButtons(
                symbols: (up: "chevron.up", down: "chevron.down"),
                upHelp: "Previous layer",
                downHelp: "Next layer",
                onUp: { cycleEditorLayer(by: -1) },
                onDown: { cycleEditorLayer(by: 1) }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("LAYER")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                Text(currentLayerTitle)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let firstUnassignedSlot = macroSlots.first(where: { $0.binding == nil }),
               onAssignMacroSlot != nil {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var orderedEditorLayers: [ClipEditorLayer] {
        ClipEditorMode.allCases.map { ClipEditorLayer.mode($0) }
            + macroLayerTabs.map { ClipEditorLayer.macro(index: $0.macroIndex) }
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

    private func syncedMacroLanes(stepCount: Int) -> [UUID: MacroLane] {
        macroLanes.mapValues { $0.synced(stepCount: stepCount) }
    }

    private func updateMacroLaneValue(_ value: Double?, binding: TrackMacroBinding, stepIndex: Int, stepCount: Int) {
        guard let onUpdateMacroLanes else { return }
        var updatedLanes = syncedMacroLanes(stepCount: stepCount)
        var lane = updatedLanes[binding.id] ?? MacroLane(stepCount: stepCount)
        guard lane.values.indices.contains(stepIndex) else { return }
        lane.values[stepIndex] = value.map { clampedMacroValue($0, for: binding) }
        updatedLanes[binding.id] = lane
        onUpdateMacroLanes(updatedLanes)
    }

    private func updateMacroLaneFraction(_ fraction: Double, binding: TrackMacroBinding, stepIndex: Int, stepCount: Int) {
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        let value = binding.descriptor.minValue + (min(max(fraction, 0), 1) * range)
        updateMacroLaneValue(value, binding: binding, stepIndex: stepIndex, stepCount: stepCount)
    }

    private func cycleMacroLaneValue(binding: TrackMacroBinding, stepIndex: Int, stepCount: Int) {
        let values = macroAllowedValues(for: binding)
        let laneValues = macroLanes[binding.id]?.synced(stepCount: stepCount).values
        let current = laneValues?.indices.contains(stepIndex) == true ? laneValues?[stepIndex] ?? nil : nil
        let next = ClipNoteGridStepEditing.cycledValue(after: current ?? macroFallbackValue(for: binding), allowedValues: values)
        updateMacroLaneValue(next, binding: binding, stepIndex: stepIndex, stepCount: stepCount)
    }

    private func clearMacroLaneValue(
        binding: TrackMacroBinding,
        stepIndex: Int,
        stepCount: Int
    ) {
        updateMacroLaneValue(nil, binding: binding, stepIndex: stepIndex, stepCount: stepCount)
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

    private func macroFallbackValue(for binding: TrackMacroBinding) -> Double {
        clampedMacroValue(macroFallbackValues[binding.id] ?? binding.descriptor.defaultValue, for: binding)
    }

    private func clampedMacroValue(_ value: Double, for binding: TrackMacroBinding) -> Double {
        min(max(value, binding.descriptor.minValue), binding.descriptor.maxValue)
    }

    private func macroAllowedValues(for binding: TrackMacroBinding) -> [Double] {
        let descriptor = binding.descriptor
        switch descriptor.valueType {
        case .boolean:
            return [descriptor.minValue, descriptor.maxValue]
        case .patternIndex:
            let lower = Int(descriptor.minValue.rounded(.up))
            let upper = Int(descriptor.maxValue.rounded(.down))
            guard lower <= upper else {
                return [descriptor.minValue]
            }
            return (lower...upper).map(Double.init)
        case .scalar:
            let minValue = descriptor.minValue
            let maxValue = descriptor.maxValue
            guard maxValue > minValue else {
                return [minValue]
            }
            let divisionCount = 8
            return (0...divisionCount).map { index in
                minValue + ((maxValue - minValue) * Double(index) / Double(divisionCount))
            }
        }
    }

    private func headerControlGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            content()
        }
    }

    private func chipButton(
        title: String,
        accent: Color,
        isSelected: Bool,
        isPlaying: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? accent.opacity(StudioOpacity.softStroke) : StudioTheme.border.opacity(StudioOpacity.subtleStroke),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(isPlaying ? StudioTheme.success.opacity(0.95) : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func clampPage(lengthSteps: Int) {
        let pageCount = max(1, (lengthSteps + 15) / 16)
        selectedPage = min(selectedPage, pageCount - 1)
    }

    private func commit(_ nextContent: ClipContent) {
        guard let onCommit else { return }
        let normalized = nextContent.normalized
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
        onCommit(normalized)
        #if DEBUG
        StepGridTapDiagnostics.log(
            "onCommitReturned",
            details: "elapsed=\(StepGridTapDiagnostics.elapsedMilliseconds(since: commitStart)) \(diagnosticSummary(for: normalized))"
        )
        #endif
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
                        var nextModes = stepModes
                        if nextModes.count < stepPattern.count {
                            nextModes.append(contentsOf: Array(repeating: .single, count: stepPattern.count - nextModes.count))
                        }
                        nextModes[index] = mode == .single ? .runFromHere : .single
                        commit(.sliceTriggers(stepPattern: stepPattern, sliceIndexes: sliceIndexes, stepModes: nextModes, stepParameters: stepParameters))
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(index + 1)")
                                .studioText(.micro)
                                .foregroundStyle(StudioTheme.text)
                            Text(mode == .runFromHere ? "Run" : "One")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(stepPattern[index] ? StudioTheme.text : StudioTheme.mutedText.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            mode == .runFromHere ? StudioTheme.violet.opacity(0.2) : Color.white.opacity(StudioOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(mode == .runFromHere ? StudioTheme.violet.opacity(0.7) : StudioTheme.border.opacity(0.8), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!stepPattern[index] || onCommit == nil)
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

    private func togglingStep(
        at index: Int,
        lengthSteps: Int,
        steps: [ClipStep],
        lane: ClipEditorLane
    ) -> ClipContent {
        ClipNoteGridStepEditing.togglingStep(
            at: index,
            lengthSteps: lengthSteps,
            steps: steps,
            lane: lane.noteLane,
            defaultNote: defaultNote
        )
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

private struct ClipStepInspectorSheet: View {
    let stepIndex: Int
    let step: ClipStep
    let accent: Color

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(
                title: "Step \(stepIndex + 1)",
                eyebrow: "Normal and fill lanes summarised together.",
                accent: accent
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    laneSummary(title: "Normal Lane", lane: step.main, accent: ClipEditorLane.main.accent)
                    laneSummary(title: "Fill Lane", lane: step.fill, accent: ClipEditorLane.fill.accent)
                }
            }
            .padding(StudioMetrics.Spacing.page)
            .frame(minWidth: 520, minHeight: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func laneSummary(title: String, lane: ClipLane?, accent: Color) -> some View {
        if let lane {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(title)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)

                    Text("\(Int((lane.chance * 100).rounded()))%")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(StudioOpacity.hoverFill), in: Capsule())
                }

                Text("\(lane.notes.count) \(lane.notes.count == 1 ? "note" : "notes")")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                ForEach(Array(lane.notes.enumerated()), id: \.offset) { index, note in
                    Text("Note \(index + 1): pitch \(note.pitch) • velocity \(note.velocity) • length \(note.lengthSteps) step\(note.lengthSteps == 1 ? "" : "s")")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.softStroke), lineWidth: 1)
            )
        } else {
            StudioPlaceholderTile(
                title: title,
                detail: "This lane is currently off for the selected step.",
                accent: accent
            )
        }
    }
}
