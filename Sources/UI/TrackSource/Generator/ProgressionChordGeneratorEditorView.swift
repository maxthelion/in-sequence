import SwiftUI

struct ProgressionChordGeneratorEditorView: View {
    let params: ProgressionChordGeneratorParams
    let accent: Color
    var showsPanel = true
    let onUpdate: (GeneratorParams) -> Void

    @State private var selectedChordStep: Int?
    @State private var selectedStep = 0
    @State private var selectedPage = 0
    @State private var selectedLayer: ChordStepLayer = .position
    @State private var isLoadingPreset = false
    @State private var presetSeed: ProgressionChordSeed = .minorDescending
    @State private var presetRootMIDI = 60
    @State private var presetMode: ProgressionChordMode = .minor

    private var normalized: ProgressionChordGeneratorParams {
        params.normalized
    }

    private var selectedChord: ProgressionChord? {
        guard let selectedChordStep,
              normalized.chords.indices.contains(selectedChordStep)
        else {
            return nil
        }
        return normalized.chords[selectedChordStep]
    }

    private var chordTriggers: [(step: Int, chord: ProgressionChord)] {
        normalized.chords.enumerated().compactMap { step, chord in
            chord.map { (step, $0) }
        }
    }

    var body: some View {
        Group {
            if showsPanel {
                StudioPanel(title: "Progression Chords", eyebrow: "Chord generator source", accent: accent) {
                    editorContent
                }
            } else {
                editorContent
            }
        }
        .onAppear {
            syncSelection()
            presetRootMIDI = normalized.rootMIDI
            presetMode = normalized.mode
        }
        .onChange(of: params) {
            syncSelection()
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            clipSetup
            chordsSection
            selectedChordControls
            layerSection
            stepPageSection
        }
    }

    private var clipSetup: some View {
        HStack(alignment: .top, spacing: 16) {
            controlGroup(title: "Clip Length") {
                HStack(spacing: 8) {
                    ForEach([16, 32, 64, 128], id: \.self) { length in
                        chipButton(
                            title: "\(length)",
                            isSelected: normalized.lengthSteps == length,
                            action: { update(resizing: length) }
                        )
                    }
                }
            }

            Spacer(minLength: 16)
        }
    }

    private var chordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chords")
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Text("These are the chords in the clip. Select one to edit its defaults below.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                chipButton(
                    title: "Load From Preset",
                    isSelected: isLoadingPreset,
                    action: {
                        presetRootMIDI = normalized.rootMIDI
                        presetMode = normalized.mode
                        isLoadingPreset.toggle()
                    }
                )
            }

            if isLoadingPreset {
                presetPanel
            }

            if chordTriggers.isEmpty {
                StudioPlaceholderTile(
                    title: "No Chords",
                    detail: "Load a preset to seed chords.",
                    accent: accent
                )
            } else {
                LazyVGrid(columns: chordColumns, alignment: .leading, spacing: 10) {
                    ForEach(Array(chordTriggers.enumerated()), id: \.element.step) { index, trigger in
                        chordCard(index: index, step: trigger.step, chord: trigger.chord)
                    }
                }
            }
        }
    }

    private var presetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Load From Preset")
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Text("Choose a seed and root, then apply it to the clip.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                chipButton(title: "Cancel", isSelected: false) {
                    isLoadingPreset = false
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                Picker("Seed", selection: $presetSeed) {
                    ForEach(ProgressionChordSeed.allCases) { seed in
                        Text(seed.label).tag(seed)
                    }
                }
                .frame(maxWidth: .infinity)

                SourceParameterStepperRow(
                    title: "Root MIDI",
                    value: presetRootMIDI,
                    range: 0...127
                ) { value in
                    presetRootMIDI = value
                }
                .frame(width: 160)

                Picker("Root Position", selection: $presetMode) {
                    ForEach(ProgressionChordMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                chipButton(title: "Apply Preset", isSelected: true) {
                    let next = ProgressionChordGeneratorParams.seeded(
                        seed: presetSeed,
                        rootMIDI: presetRootMIDI,
                        mode: presetMode,
                        lengthSteps: normalized.lengthSteps
                    )
                    selectedStep = 0
                    selectedPage = 0
                    selectedChordStep = next.chords.firstIndex { $0 != nil }
                    isLoadingPreset = false
                    onUpdate(.progressionChords(next))
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 4]))
        )
    }

    private var selectedChordControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(selectedChord.map { "Selected chord: \(normalized.roman(for: $0))" } ?? "No selected chord")
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(StudioTheme.text)

                Text(selectedChordStep.map { "Chord from step \($0 + 1)." } ?? "Select a chord, or select a step that has a chord trigger.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if let selectedChordStep, let selectedChord {
                LazyVGrid(columns: selectedControlColumns, alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Position", value: selectedChord.position, range: -14...14) { value in
                        updateChord(at: selectedChordStep) { $0.position = value }
                    }

                    Picker("Type", selection: binding(for: selectedChordStep, keyPath: \.quality)) {
                        ForEach(ProgressionChordQuality.allCases, id: \.self) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }

                    SourceParameterStepperRow(title: "Inversion", value: selectedChord.inversion, range: 0...3) { value in
                        updateChord(at: selectedChordStep) { $0.inversion = value }
                    }

                    Picker("Voicing", selection: binding(for: selectedChordStep, keyPath: \.voicing)) {
                        ForEach(ProgressionChordVoicing.allCases, id: \.self) { voicing in
                            Text(voicing.label).tag(voicing)
                        }
                    }

                    SourceParameterStepperRow(title: "Notes", value: selectedChord.noteCount, range: 2...5) { value in
                        updateChord(at: selectedChordStep) { $0.noteCount = value }
                    }

                    Picker("Length", selection: lengthBinding(for: selectedChordStep)) {
                        Text("Until next").tag(ProgressionChordLength.untilNext)
                        Text("4 steps").tag(ProgressionChordLength.steps(4))
                        Text("8 steps").tag(ProgressionChordLength.steps(8))
                        Text("16 steps").tag(ProgressionChordLength.steps(16))
                    }
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var layerSection: some View {
        controlGroup(title: "Layers") {
            LazyVGrid(columns: layerColumns, alignment: .leading, spacing: 8) {
                ForEach(ChordStepLayer.allCases) { layer in
                    layerButton(layer)
                }
            }
        }
    }

    private var stepPageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("16-Step Page")
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Text("Steps \(pageStart + 1)-\(min(pageStart + 16, normalized.lengthSteps)) of \(normalized.lengthSteps).")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                Spacer()
                if pageCount > 1 {
                    pageSelector
                }
            }

            LazyVGrid(columns: stepColumns, spacing: 10) {
                ForEach(pageStart..<min(pageStart + 16, normalized.lengthSteps), id: \.self) { step in
                    stepCell(step)
                }
            }
        }
    }

    private func chordCard(index: Int, step: Int, chord: ProgressionChord) -> some View {
        Button {
            selectedChordStep = step
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1)")
                        .studioText(.eyebrow)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer()
                    Text(normalized.roman(for: chord))
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                }
                Text("Step \(step + 1)")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
            .background(
                selectedChordStep == step ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(selectedChordStep == step ? accent.opacity(StudioOpacity.softStroke) : StudioTheme.border.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func stepCell(_ step: Int) -> some View {
        let chord = normalized.chords.indices.contains(step) ? normalized.chords[step] : nil
        let isSelected = selectedStep == step
        return Button {
            editStep(step)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(step + 1)")
                    .studioText(.eyebrow)
                    .foregroundStyle(chord == nil ? StudioTheme.mutedText : StudioTheme.text)

                Spacer(minLength: 4)

                if let chord {
                    Text(normalized.roman(for: chord))
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Text(layerValue(for: chord))
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                } else {
                    Text("-")
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.mutedText)
                    Text("empty")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(StudioMetrics.Spacing.compact)
            .background(
                isSelected ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(isSelected ? accent.opacity(StudioOpacity.softStroke) : StudioTheme.border.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chord == nil {
                Button("Add Chord Here") {
                    insertChord(at: step)
                }
            }

            if let selectedChord {
                Button(chord == nil ? "Copy Selected Chord Here" : "Replace With Selected Chord") {
                    insertChord(at: step, chord: selectedChord)
                }
            }

            if chord != nil {
                Button("Clear Chord") {
                    clearChord(at: step)
                }
            }
        }
    }

    private func layerButton(_ layer: ChordStepLayer) -> some View {
        Button {
            selectedLayer = layer
        } label: {
            Text(layer.label)
                .studioText(.labelBold)
                .foregroundStyle(selectedLayer == layer ? StudioTheme.text : StudioTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    selectedLayer == layer ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(selectedLayer == layer ? accent.opacity(StudioOpacity.softStroke) : StudioTheme.border.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private var pageSelector: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { page in
                let start = page * 16 + 1
                let end = min((page + 1) * 16, normalized.lengthSteps)
                chipButton(
                    title: "\(start)-\(end)",
                    isSelected: selectedPage == page,
                    action: {
                        selectedPage = page
                        selectedStep = page * 16
                    }
                )
            }
        }
    }

    private func update(_ next: ProgressionChordGeneratorParams) {
        onUpdate(.progressionChords(next.normalized))
    }

    private func update(resizing length: Int) {
        var next = normalized
        let resolvedLength = min(max(length, 16), 128)
        next.lengthSteps = resolvedLength
        if next.chords.count < resolvedLength {
            next.chords += Array(repeating: nil, count: resolvedLength - next.chords.count)
        } else if next.chords.count > resolvedLength {
            next.chords = Array(next.chords.prefix(resolvedLength))
        }
        selectedPage = min(selectedPage, max(0, (resolvedLength - 1) / 16))
        selectedStep = min(selectedStep, resolvedLength - 1)
        if let selectedChordStep, selectedChordStep >= resolvedLength {
            self.selectedChordStep = next.chords.firstIndex { $0 != nil }
        }
        update(next)
    }

    private func updateChord(at step: Int, mutate: (inout ProgressionChord) -> Void) {
        var next = normalized
        guard next.chords.indices.contains(step),
              var chord = next.chords[step]
        else {
            return
        }
        mutate(&chord)
        next.chords[step] = chord.normalized
        selectedChordStep = step
        update(next)
    }

    private func editStep(_ step: Int) {
        selectedStep = step
        guard normalized.chords.indices.contains(step) else {
            return
        }

        guard normalized.chords[step] != nil else {
            insertChord(at: step)
            return
        }

        selectedChordStep = step
        cycleSelectedLayer(at: step)
    }

    private func insertChord(at step: Int, chord: ProgressionChord? = nil) {
        var next = normalized
        guard next.chords.indices.contains(step) else {
            return
        }
        let inserted = chord ?? selectedChord ?? defaultInsertedChord
        next.chords[step] = inserted.normalized
        selectedStep = step
        selectedChordStep = step
        update(next)
    }

    private func clearChord(at step: Int) {
        var next = normalized
        guard next.chords.indices.contains(step) else {
            return
        }
        next.chords[step] = nil
        selectedStep = step
        if selectedChordStep == step {
            selectedChordStep = next.chords.firstIndex { $0 != nil }
        }
        update(next)
    }

    private func cycleSelectedLayer(at step: Int) {
        updateChord(at: step) { chord in
            switch selectedLayer {
            case .position:
                chord.position = chord.position >= 14 ? -14 : chord.position + 1
            case .type:
                chord.quality = nextValue(after: chord.quality, in: ProgressionChordQuality.allCases)
            case .inversion:
                chord.inversion = chord.inversion >= 3 ? 0 : chord.inversion + 1
            case .voicing:
                chord.voicing = nextValue(after: chord.voicing, in: ProgressionChordVoicing.allCases)
            case .notes:
                chord.noteCount = chord.noteCount >= 5 ? 2 : chord.noteCount + 1
            case .length:
                chord.length = nextValue(after: chord.length, in: ProgressionChordLength.quickValues)
            }
        }
    }

    private func nextValue<Value: Equatable>(after value: Value, in values: [Value]) -> Value {
        guard let index = values.firstIndex(of: value) else {
            return values.first ?? value
        }
        return values[(index + 1) % values.count]
    }

    private var defaultInsertedChord: ProgressionChord {
        ProgressionChord(
            position: 0,
            accidental: 0,
            quality: normalized.mode == .major ? .major : .minor,
            inversion: 0,
            voicing: .close,
            noteCount: 3,
            length: .untilNext
        )
    }

    private func binding<Value: Equatable>(
        for step: Int,
        keyPath: WritableKeyPath<ProgressionChord, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                guard normalized.chords.indices.contains(step),
                      let chord = normalized.chords[step]
                else {
                    return ProgressionChord.minorOne[keyPath: keyPath]
                }
                return chord[keyPath: keyPath]
            },
            set: { value in
                updateChord(at: step) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func lengthBinding(for step: Int) -> Binding<ProgressionChordLength> {
        Binding(
            get: {
                guard normalized.chords.indices.contains(step),
                      let chord = normalized.chords[step]
                else {
                    return .untilNext
                }
                return chord.length
            },
            set: { value in
                updateChord(at: step) { $0.length = value }
            }
        )
    }

    private func layerValue(for chord: ProgressionChord) -> String {
        switch selectedLayer {
        case .position:
            return "\(normalized.roman(for: chord)) / \(chord.position >= 0 ? "+" : "")\(chord.position)"
        case .type:
            return chord.quality.label
        case .inversion:
            return ["Root", "1st", "2nd", "3rd"][min(max(chord.inversion, 0), 3)]
        case .voicing:
            return chord.voicing.label
        case .notes:
            return "\(chord.noteCount) notes"
        case .length:
            return chord.length.label
        }
    }

    private func syncSelection() {
        let params = normalized
        selectedPage = min(selectedPage, max(0, (params.lengthSteps - 1) / 16))
        selectedStep = min(max(selectedStep, 0), params.lengthSteps - 1)
        if let selectedChordStep,
           params.chords.indices.contains(selectedChordStep),
           params.chords[selectedChordStep] != nil
        {
            return
        }
        selectedChordStep = params.chords.firstIndex { $0 != nil }
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

    private func chipButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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
                        .stroke(isSelected ? accent.opacity(StudioOpacity.softStroke) : StudioTheme.border.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private var pageStart: Int {
        min(selectedPage, pageCount - 1) * 16
    }

    private var pageCount: Int {
        max(1, (normalized.lengthSteps + 15) / 16)
    }

    private var chordColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 116), spacing: 10, alignment: .topLeading), count: 4)
    }

    private var selectedControlColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 130), spacing: 12, alignment: .topLeading), count: 3)
    }

    private var layerColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 90), spacing: 8, alignment: .topLeading), count: 6)
    }

    private var stepColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 64), spacing: 10), count: 8)
    }
}

private enum ChordStepLayer: String, CaseIterable, Identifiable {
    case position
    case type
    case inversion
    case voicing
    case notes
    case length

    var id: String { rawValue }

    var label: String {
        switch self {
        case .position:
            return "Position"
        case .type:
            return "Type"
        case .inversion:
            return "Inversion"
        case .voicing:
            return "Voicing"
        case .notes:
            return "Notes"
        case .length:
            return "Length"
        }
    }
}
