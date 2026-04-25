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

    func lane(in step: ClipStep) -> ClipLane? {
        switch self {
        case .main:
            return step.main
        case .fill:
            return step.fill
        }
    }

    func setLane(_ lane: ClipLane?, on step: inout ClipStep) {
        switch self {
        case .main:
            step.main = lane
        case .fill:
            step.fill = lane
        }
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

private struct ClipStepInspectorTarget: Identifiable, Equatable {
    let stepIndex: Int

    var id: Int { stepIndex }
}

struct ClipContentPreview: View {
    let content: ClipContent
    let defaultNote: ClipStepNote
    let onCommit: ((ClipContent) -> Void)?

    @State private var displayedContent: ClipContent
    @State private var selectedLane: ClipEditorLane = .main
    @State private var selectedMode: ClipEditorMode = .trigger
    @State private var selectedPage = 0
    @State private var editingStepTarget: ClipStepInspectorTarget?

    init(
        content: ClipContent,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4),
        onChange: ((ClipContent) -> Void)? = nil
    ) {
        let normalizedContent = content.normalized
        self.content = normalizedContent
        self.defaultNote = defaultNote.normalized
        self.onCommit = onChange
        self._displayedContent = State(initialValue: normalizedContent)
    }

    var body: some View {
        Group {
            switch displayedContent {
            case let .noteGrid(lengthSteps, steps):
                noteGridEditor(lengthSteps: lengthSteps, steps: steps)

            case let .sliceTriggers(stepPattern, sliceIndexes):
                VStack(alignment: .leading, spacing: 14) {
                    StepGridView(stepStates: stepPattern.map { $0 ? .on : .off }) { index in
                        var nextPattern = stepPattern
                        guard nextPattern.indices.contains(index) else { return }
                        nextPattern[index].toggle()
                        commit(.sliceTriggers(stepPattern: nextPattern, sliceIndexes: sliceIndexes))
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
                                    commit(.sliceTriggers(stepPattern: stepPattern, sliceIndexes: parsed))
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onChange(of: content) { _, newContent in
            displayedContent = newContent.normalized
        }
    }

    @ViewBuilder
    private func noteGridEditor(lengthSteps: Int, steps: [ClipStep]) -> some View {
        let pageCount = max(1, (lengthSteps + 15) / 16)
        let page = min(selectedPage, pageCount - 1)
        let pageStart = page * 16
        let pageEnd = min(pageStart + 16, lengthSteps)
        let visibleIndices = Array(pageStart..<pageEnd)
        let visibleSteps = visibleIndices.map { steps[$0] }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                controlGroup(title: "Lane") {
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

                Spacer(minLength: 0)

                controlGroup(title: "Length") {
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

            if pageCount > 1 {
                controlGroup(title: "Page") {
                    HStack(spacing: 8) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            let start = index * 16 + 1
                            let end = min((index + 1) * 16, lengthSteps)
                            chipButton(
                                title: "\(start)-\(end)",
                                accent: selectedLane.accent,
                                isSelected: page == index,
                                action: { selectedPage = index }
                            )
                        }
                    }
                }
            }

            controlGroup(title: "Edit") {
                HStack(spacing: 8) {
                    ForEach(ClipEditorMode.allCases) { mode in
                        chipButton(
                            title: mode.title,
                            accent: selectedLane.accent,
                            isSelected: selectedMode == mode,
                            action: { selectedMode = mode }
                        )
                    }
                }
            }

            switch selectedMode {
            case .trigger:
                StepGridView(
                    stepStates: visibleSteps.map { stepVisualState(for: $0, lane: selectedLane) },
                    indexOffset: pageStart,
                    onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
                ) { index in
                    commit(togglingStep(at: index, lengthSteps: lengthSteps, steps: steps, lane: selectedLane))
                }
                .allowsHitTesting(onCommit != nil)

            case .velocity:
                GridEditor(
                    values: visibleSteps.map { velocityValue(for: $0, lane: selectedLane) },
                    allowedValues: [0, 24, 48, 72, 96, 127],
                    accent: selectedLane.accent,
                    indexOffset: pageStart,
                    onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
                ) { nextValues in
                    commit(
                        updatingLaneVelocities(
                            lane: selectedLane,
                            values: nextValues,
                            visibleIndices: visibleIndices,
                            lengthSteps: lengthSteps,
                            steps: steps
                        )
                    )
                }
                .allowsHitTesting(onCommit != nil)

            case .probability:
                GridEditor(
                    values: visibleSteps.map { chanceValue(for: $0, lane: selectedLane) },
                    allowedValues: [0, 0.25, 0.5, 0.75, 1],
                    accent: selectedLane.accent,
                    indexOffset: pageStart,
                    onDoubleTap: { editingStepTarget = ClipStepInspectorTarget(stepIndex: $0) }
                ) { nextValues in
                    commit(
                        updatingLaneChances(
                            lane: selectedLane,
                            values: nextValues,
                            visibleIndices: visibleIndices,
                            lengthSteps: lengthSteps,
                            steps: steps
                        )
                    )
                }
                .allowsHitTesting(onCommit != nil)
            }

            Text(summaryText(lengthSteps: lengthSteps, page: page, pageCount: pageCount, steps: steps))
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
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
    }

    private func controlGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        displayedContent = normalized
        onCommit(normalized)
    }

    private func summaryText(lengthSteps: Int, page: Int, pageCount: Int, steps: [ClipStep]) -> String {
        let laneLabel = selectedLane == .main ? "Normal lane" : "Fill lane"
        let pageLabel = pageCount > 1 ? "Page \(page + 1) of \(pageCount)" : "Single page"
        return "\(laneLabel) • \(selectedMode.title) view • \(pageLabel) • \(noteCount(in: steps)) notes across \(lengthSteps) steps. Double-click any step to inspect both lanes."
    }

    private func stepVisualState(for step: ClipStep, lane: ClipEditorLane) -> StepVisualState {
        lane.lane(in: step) == nil ? .off : lane.activeState
    }

    private func chanceValue(for step: ClipStep, lane: ClipEditorLane) -> Double {
        lane.lane(in: step)?.chance ?? 0
    }

    private func velocityValue(for step: ClipStep, lane: ClipEditorLane) -> Double {
        Double(lane.lane(in: step)?.notes.first?.velocity ?? 0)
    }

    private func togglingStep(
        at index: Int,
        lengthSteps: Int,
        steps: [ClipStep],
        lane: ClipEditorLane
    ) -> ClipContent {
        var updated = steps
        guard updated.indices.contains(index) else {
            return .noteGrid(lengthSteps: lengthSteps, steps: steps)
        }

        if lane.lane(in: updated[index]) == nil {
            lane.setLane(ClipLane(chance: 1, notes: [defaultNote]), on: &updated[index])
        } else {
            lane.setLane(nil, on: &updated[index])
        }

        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    private func resizingNoteGrid(to newLength: Int, currentSteps: [ClipStep]) -> ClipContent {
        let resolvedLength = max(1, newLength)
        let resizedSteps = (0..<resolvedLength).map { index in
            currentSteps.indices.contains(index) ? currentSteps[index] : .empty
        }
        return .noteGrid(lengthSteps: resolvedLength, steps: resizedSteps)
    }

    private func updatingLaneChances(
        lane: ClipEditorLane,
        values: [Double],
        visibleIndices: [Int],
        lengthSteps: Int,
        steps: [ClipStep]
    ) -> ClipContent {
        var updated = steps
        for (stepIndex, chance) in zip(visibleIndices, values) where updated.indices.contains(stepIndex) {
            if var existingLane = lane.lane(in: updated[stepIndex]) {
                existingLane.chance = min(max(chance, 0), 1)
                lane.setLane(existingLane, on: &updated[stepIndex])
            } else if chance > 0 {
                lane.setLane(ClipLane(chance: min(max(chance, 0), 1), notes: [defaultNote]), on: &updated[stepIndex])
            }
        }
        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    private func updatingLaneVelocities(
        lane: ClipEditorLane,
        values: [Double],
        visibleIndices: [Int],
        lengthSteps: Int,
        steps: [ClipStep]
    ) -> ClipContent {
        var updated = steps
        for (stepIndex, velocity) in zip(visibleIndices, values) where updated.indices.contains(stepIndex) {
            let resolvedVelocity = Int(velocity.rounded())
            guard resolvedVelocity > 0 else {
                lane.setLane(nil, on: &updated[stepIndex])
                continue
            }

            if var existingLane = lane.lane(in: updated[stepIndex]) {
                let notes = existingLane.notes.isEmpty ? [defaultNote] : existingLane.notes
                existingLane.notes = notes.map { note in
                    var updatedNote = note
                    updatedNote.velocity = resolvedVelocity
                    return updatedNote
                }
                lane.setLane(existingLane, on: &updated[stepIndex])
            } else {
                var note = defaultNote
                note.velocity = resolvedVelocity
                lane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[stepIndex])
            }
        }
        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
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
            .padding(24)
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
