import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    private var track: StepSequenceTrack { document.model.selectedTrack }
    private var phrase: PhraseModel { document.model.selectedPhrase }
    private var selectedPatternIndex: Int { document.model.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { document.model.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(document.model.phrases.map { $0.patternIndex(for: track.id, layers: document.model.layers) })
    }
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.model.compatibleGenerators(for: track) }
    private var compatibleClips: [ClipPoolEntry] { document.model.compatibleClips(for: track) }
    private var currentGenerator: GeneratorPoolEntry? { document.model.generatorEntry(id: selectedPattern.sourceRef.generatorID) }
    private var currentClip: ClipPoolEntry? { document.model.clipEntry(id: selectedPattern.sourceRef.clipID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Source", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots
                    )

                    TrackSourceModePalette(trackType: track.trackType, selectedSource: selectedSourceModeBinding)
                }
            }

            switch selectedSourceMode {
            case .generator:
                generatorPanels
            case .clip:
                clipPanels
            }
        }
    }

    private var generatorPanels: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Generator", eyebrow: currentGenerator?.kind.label ?? "No generator selected", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Generator", selection: generatorIDBinding) {
                        ForEach(compatibleGenerators) { generator in
                            Text(generator.name).tag(Optional(generator.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let generator = currentGenerator {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generator.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)

                            Text(generatorSummary(generator))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                    }
                }
            }

            if let generator = currentGenerator {
                GeneratorParamsEditorView(
                    generator: generator,
                    clipChoices: compatibleClips,
                    accent: accent
                ) { updated in
                    document.model.updateGeneratorEntry(id: generator.id) { entry in
                        entry.params = updated
                    }
                }
            } else {
                StudioPanel(title: "Generator Params", eyebrow: "No source selected", accent: accent) {
                    StudioPlaceholderTile(
                        title: "Choose A Generator",
                        detail: "A generator-backed pattern slot should show its step and pitch parameters here."
                    )
                }
            }
        }
    }

    private var clipPanels: some View {
        VStack(alignment: .leading, spacing: 18) {
            if compatibleClips.isEmpty {
                StudioPanel(title: "Clip", eyebrow: "No clip selected", accent: StudioTheme.violet) {
                    StudioPlaceholderTile(
                        title: "No Clip For This Track Type",
                        detail: "Create or attach a compatible clip to preview its notes here.",
                        accent: StudioTheme.violet
                    )
                }
            } else if let clip = currentClip {
                StudioPanel(title: "Clip Notes", eyebrow: clipPreviewEyebrow(clip), accent: StudioTheme.violet) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Clip", selection: clipIDBinding) {
                            ForEach(compatibleClips) { clip in
                                Text(clip.name).tag(Optional(clip.id))
                            }
                        }
                        .pickerStyle(.menu)

                        ClipContentPreview(content: clip.content) { updated in
                            document.model.updateClipEntry(id: clip.id) { entry in
                                entry.content = updated
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.model.selectedPatternIndex(for: track.id) },
            set: { document.model.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    private var selectedSourceModeBinding: Binding<TrackSourceMode> {
        Binding(
            get: { selectedSourceMode },
            set: { newValue in
                switch newValue {
                case .generator:
                    if let generator = compatibleGenerators.first {
                        document.model.setPatternGeneratorID(generator.id, for: track.id, slotIndex: selectedPatternIndex)
                    } else {
                        document.model.setPatternSourceMode(.generator, for: track.id, slotIndex: selectedPatternIndex)
                    }
                case .clip:
                    if let clip = document.model.ensureCompatibleClip(for: track) {
                        document.model.setPatternClipID(clip.id, for: track.id, slotIndex: selectedPatternIndex)
                    } else {
                        document.model.setPatternSourceMode(.clip, for: track.id, slotIndex: selectedPatternIndex)
                    }
                }
            }
        )
    }

    private var generatorIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPattern.sourceRef.generatorID },
            set: { newValue in
                guard let newValue else { return }
                document.model.setPatternGeneratorID(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
        )
    }

    private var clipIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPattern.sourceRef.clipID },
            set: { newValue in
                guard let newValue else { return }
                document.model.setPatternClipID(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
        )
    }

    private func generatorSummary(_ generator: GeneratorPoolEntry) -> String {
        switch generator.params {
        case let .mono(step, pitch, shape):
            return "\(stepDisplayLabel(step)) steps • \(pitchDisplayLabel(pitch)) pitches • vel \(shape.velocity) • gate \(shape.gateLength)"
        case let .poly(step, pitches, shape):
            return "\(stepDisplayLabel(step)) steps • \(pitches.count) pitch lanes • vel \(shape.velocity) • gate \(shape.gateLength)"
        case let .drum(steps, shape):
            return "\(steps.count) drum lanes • vel \(shape.velocity) • gate \(shape.gateLength)"
        case .template:
            return "Template-driven source"
        case let .slice(step, sliceIndexes):
            return "\(stepDisplayLabel(step)) steps • \(sliceIndexes.count) slice indexes"
        }
    }

    private func clipPreviewEyebrow(_ clip: ClipPoolEntry) -> String {
        switch clip.content {
        case .stepSequence:
            return "Step Sequencer"
        case .pianoRoll:
            return "Piano Roll"
        case .sliceTriggers:
            return "Slice Trigger Grid"
        }
    }
}

private enum GeneratorEditorTab: String, CaseIterable, Identifiable {
    case steps
    case pitches
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:
            return "Steps"
        case .pitches:
            return "Pitches"
        case .notes:
            return "Notes"
        }
    }
}

private struct GeneratorParamsEditorView: View {
    let generator: GeneratorPoolEntry
    let clipChoices: [ClipPoolEntry]
    let accent: Color
    let onUpdate: (GeneratorParams) -> Void

    @State private var selectedTab: GeneratorEditorTab = .steps
    @State private var selectedPolyLane = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GeneratorTabBar(selectedTab: $selectedTab)

            switch generator.params {
            case let .mono(step, pitch, shape):
                monoEditor(step: step, pitch: pitch, shape: shape)
            case let .poly(step, pitches, shape):
                polyEditor(step: step, pitches: pitches, shape: shape)
            case let .drum(steps, shape):
                drumEditor(steps: steps, shape: shape)
            case let .template(templateID):
                StudioPanel(title: "Template", eyebrow: "Template source", accent: accent) {
                    Text(templateID.uuidString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            case let .slice(step, sliceIndexes):
                sliceEditor(step: step, sliceIndexes: sliceIndexes)
            }
        }
    }

    @ViewBuilder
    private func monoEditor(step: StepAlgo, pitch: PitchAlgo, shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Step Generator", eyebrow: stepDisplayLabel(step), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(step: step, clipChoices: clipChoices) { nextStep in
                        onUpdate(.mono(step: nextStep, pitch: pitch, shape: shape))
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.mono(step: step, pitch: pitch, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Pitch Generator", eyebrow: pitchDisplayLabel(pitch), accent: StudioTheme.violet) {
                PitchAlgoEditor(pitch: pitch, clipChoices: clipChoices) { nextPitch in
                    onUpdate(.mono(step: step, pitch: nextPitch, shape: shape))
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Preview of the current generator", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .mono(step: step, pitch: pitch, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func polyEditor(step: StepAlgo, pitches: [PitchAlgo], shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Step Generator", eyebrow: stepDisplayLabel(step), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(step: step, clipChoices: clipChoices) { nextStep in
                        onUpdate(.poly(step: nextStep, pitches: pitches, shape: shape))
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.poly(step: step, pitches: pitches, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Pitch Generator", eyebrow: "\(pitches.count) lanes", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 16) {
                    PolyLaneSelector(
                        laneCount: pitches.count,
                        selectedLane: $selectedPolyLane,
                        onAddLane: {
                            var nextPitches = pitches
                            nextPitches.append(.manual(pitches: [60], pickMode: .sequential))
                            selectedPolyLane = nextPitches.count - 1
                            onUpdate(.poly(step: step, pitches: nextPitches, shape: shape))
                        },
                        onRemoveLane: pitches.count > 1 ? {
                            var nextPitches = pitches
                            nextPitches.remove(at: min(selectedPolyLane, nextPitches.count - 1))
                            selectedPolyLane = min(selectedPolyLane, max(0, nextPitches.count - 1))
                            onUpdate(.poly(step: step, pitches: nextPitches, shape: shape))
                        } : nil
                    )

                    let laneIndex = min(selectedPolyLane, max(0, pitches.count - 1))
                    PitchAlgoEditor(pitch: pitches[laneIndex], clipChoices: clipChoices) { nextPitch in
                        var nextPitches = pitches
                        nextPitches[laneIndex] = nextPitch
                        onUpdate(.poly(step: step, pitches: nextPitches, shape: shape))
                    }
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Preview of the current generator", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .poly(step: step, pitches: pitches, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func drumEditor(steps: [VoiceTag: StepAlgo], shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Drum Generators", eyebrow: "\(steps.count) voices", accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(steps.keys.sorted()), id: \.self) { key in
                        if let step = steps[key] {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(key.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(StudioTheme.mutedText)

                                StepAlgoEditor(step: step, clipChoices: clipChoices) { nextStep in
                                    var nextSteps = steps
                                    nextSteps[key] = nextStep
                                    onUpdate(.drum(steps: nextSteps, shape: shape))
                                }
                            }
                        }
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.drum(steps: steps, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Drum Mapping", eyebrow: "Voice tags map to kit notes", accent: StudioTheme.violet) {
                WrapRow(items: steps.keys.sorted())
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Preview of the current generator", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .drum(steps: steps, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func sliceEditor(step: StepAlgo, sliceIndexes: [Int]) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Slice Generator", eyebrow: stepDisplayLabel(step), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(step: step, clipChoices: clipChoices) { nextStep in
                        onUpdate(.slice(step: nextStep, sliceIndexes: sliceIndexes))
                    }

                    SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                        onUpdate(.slice(step: step, sliceIndexes: nextIndexes))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Slices", eyebrow: "\(sliceIndexes.count) active", accent: StudioTheme.violet) {
                SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                    onUpdate(.slice(step: step, sliceIndexes: nextIndexes))
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Preview of the current generator", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .slice(step: step, sliceIndexes: sliceIndexes), clipChoices: clipChoices)
            }
        }
    }
}

private func stepDisplayLabel(_ step: StepAlgo) -> String {
    switch step {
    case .manual:
        return "Manual"
    case .randomWeighted:
        return "Random Weighted"
    case .euclidean:
        return "Euclidean"
    case .perStepProbability:
        return "Per-Step Probability"
    case .fromClipSteps:
        return "From Clip Steps"
    }
}

private func pitchDisplayLabel(_ pitch: PitchAlgo) -> String {
    switch pitch {
    case .manual:
        return "Manual"
    case .randomInScale:
        return "Random In Scale"
    case .randomInChord:
        return "Random In Chord"
    case .intervalProb:
        return "Interval Probability"
    case .markov:
        return "Markov"
    case .fromClipPitches:
        return "From Clip Pitches"
    case .external:
        return "External"
    }
}

private enum StepAlgoKind: String, CaseIterable, Identifiable {
    case manual
    case euclidean
    case randomWeighted
    case perStepProbability
    case fromClipSteps

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .euclidean:
            return "Euclidean"
        case .randomWeighted:
            return "Weighted"
        case .perStepProbability:
            return "Probability"
        case .fromClipSteps:
            return "From Clip"
        }
    }
}

private struct StepAlgoEditor: View {
    let step: StepAlgo
    let clipChoices: [ClipPoolEntry]
    let onChange: (StepAlgo) -> Void

    private var kind: StepAlgoKind {
        switch step {
        case .manual:
            return .manual
        case .euclidean:
            return .euclidean
        case .randomWeighted:
            return .randomWeighted
        case .perStepProbability:
            return .perStepProbability
        case .fromClipSteps:
            return .fromClipSteps
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Step Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange(defaultStepAlgo(for: $0, clipChoices: clipChoices, current: step)) }
                )
            ) {
                ForEach(StepAlgoKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch step {
            case let .manual(pattern):
                let states = pattern.map { $0 ? StepVisualState.on : .off }
                StepGridView(stepStates: states) { index in
                    var nextPattern = pattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(.manual(pattern: nextPattern))
                }
            case let .euclidean(pulses, steps, offset):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Pulses", value: pulses, range: 0...steps) {
                        onChange(.euclidean(pulses: $0, steps: steps, offset: offset))
                    }
                    SourceParameterStepperRow(title: "Steps", value: steps, range: 1...32) { nextSteps in
                        onChange(.euclidean(pulses: min(pulses, nextSteps), steps: nextSteps, offset: offset))
                    }
                    SourceParameterStepperRow(title: "Offset", value: offset, range: -32...32) {
                        onChange(.euclidean(pulses: pulses, steps: steps, offset: $0))
                    }
                }
            case let .randomWeighted(density):
                SourceParameterSliderRow(title: "Density", value: density * 100, range: 0...100, accent: stepAlgoAccentColor(for: .randomWeighted)) {
                    onChange(.randomWeighted(density: $0 / 100))
                }
            case let .perStepProbability(probs):
                ProbabilityGridEditor(values: probs) { next in
                    onChange(.perStepProbability(probs: next))
                }
            case let .fromClipSteps(clipID):
                Picker("Step Clip", selection: Binding(
                    get: { Optional(clipID) },
                    set: { newValue in
                        guard let newValue else { return }
                        onChange(.fromClipSteps(clipID: newValue))
                    }
                )) {
                    ForEach(clipChoices) { clip in
                        Text(clip.name).tag(Optional(clip.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

private struct PitchAlgoEditor: View {
    let pitch: PitchAlgo
    let clipChoices: [ClipPoolEntry]
    let onChange: (PitchAlgo) -> Void
    @State private var manualPitchDraft = ""

    private var kind: PitchAlgoKind {
        switch pitch {
        case .manual:
            return .manual
        case .randomInScale:
            return .randomInScale
        case .randomInChord:
            return .randomInChord
        case .intervalProb:
            return .intervalProb
        case .markov:
            return .markov
        case .fromClipPitches:
            return .fromClipPitches
        case .external:
            return .external
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Pitch Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange(defaultPitchAlgo(for: $0, clipChoices: clipChoices, current: pitch)) }
                )
            ) {
                ForEach(PitchAlgoKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch pitch {
            case let .manual(pitches, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(.manual(pitches: pitches, pickMode: $0)) }
                    )) {
                        Text("Sequential").tag(PickMode.sequential)
                        Text("Random").tag(PickMode.random)
                    }
                    .pickerStyle(.segmented)

                    TextField("Comma-separated MIDI notes", text: Binding(
                        get: {
                            if manualPitchDraft.isEmpty {
                                return pitches.map(String.init).joined(separator: ", ")
                            }
                            return manualPitchDraft
                        },
                        set: { newValue in
                            manualPitchDraft = newValue
                            let parsed = newValue
                                .split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                                .filter { (0...127).contains($0) }

                            if !parsed.isEmpty {
                                onChange(.manual(pitches: parsed, pickMode: pickMode))
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    WrapRow(items: pitches.map(String.init))
                }
            case let .randomInScale(root, scale, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.randomInScale(root: $0, scale: scale, spread: spread))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.randomInScale(root: root, scale: $0, spread: spread)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(.randomInScale(root: root, scale: scale, spread: $0))
                    }
                }
            case let .randomInChord(root, chord, inverted, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.randomInChord(root: $0, chord: chord, inverted: inverted, spread: spread))
                    }
                    Picker("Chord", selection: Binding(
                        get: { chord },
                        set: { onChange(.randomInChord(root: root, chord: $0, inverted: inverted, spread: spread)) }
                    )) {
                        ForEach(ChordID.allCases, id: \.self) { chord in
                            Text(chord.rawValue).tag(chord)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Inverted", isOn: Binding(
                        get: { inverted },
                        set: { onChange(.randomInChord(root: root, chord: chord, inverted: $0, spread: spread)) }
                    ))
                    .toggleStyle(.switch)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(.randomInChord(root: root, chord: chord, inverted: inverted, spread: $0))
                    }
                }
            case let .intervalProb(root, scale, degreeWeights):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.intervalProb(root: $0, scale: scale, degreeWeights: degreeWeights))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.intervalProb(root: root, scale: $0, degreeWeights: degreeWeights)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    WeightGridEditor(values: degreeWeights) { next in
                        onChange(.intervalProb(root: root, scale: scale, degreeWeights: next))
                    }
                }
            case let .markov(root, scale, styleID, leap, color):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.markov(root: $0, scale: scale, styleID: styleID, leap: leap, color: color))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.markov(root: root, scale: $0, styleID: styleID, leap: leap, color: color)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Style", selection: Binding(
                        get: { styleID },
                        set: { onChange(.markov(root: root, scale: scale, styleID: $0, leap: leap, color: color)) }
                    )) {
                        ForEach(StyleProfileID.allCases, id: \.self) { styleID in
                            Text(styleID.rawValue).tag(styleID)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterSliderRow(title: "Leap", value: leap * 100, range: 0...100, accent: StudioTheme.amber) {
                        onChange(.markov(root: root, scale: scale, styleID: styleID, leap: $0 / 100, color: color))
                    }
                    SourceParameterSliderRow(title: "Color", value: color * 100, range: 0...100, accent: StudioTheme.violet) {
                        onChange(.markov(root: root, scale: scale, styleID: styleID, leap: leap, color: $0 / 100))
                    }
                }
            case let .fromClipPitches(clipID, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Clip", selection: Binding(
                        get: { Optional(clipID) },
                        set: { newValue in
                            guard let newValue else { return }
                            onChange(.fromClipPitches(clipID: newValue, pickMode: pickMode))
                        }
                    )) {
                        ForEach(clipChoices) { clip in
                            Text(clip.name).tag(Optional(clip.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(.fromClipPitches(clipID: clipID, pickMode: $0)) }
                    )) {
                        Text("Sequential").tag(PickMode.sequential)
                        Text("Random").tag(PickMode.random)
                    }
                    .pickerStyle(.segmented)
                }
            case let .external(port, channel, holdMode):
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Port", text: Binding(
                        get: { port },
                        set: { onChange(.external(port: $0, channel: channel, holdMode: holdMode)) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    SourceParameterStepperRow(title: "Channel", value: channel + 1, range: 1...16) {
                        onChange(.external(port: port, channel: $0 - 1, holdMode: holdMode))
                    }

                    Picker("Hold Mode", selection: Binding(
                        get: { holdMode },
                        set: { onChange(.external(port: port, channel: channel, holdMode: $0)) }
                    )) {
                        Text("Pool").tag(HoldMode.pool)
                        Text("Latest").tag(HoldMode.latest)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

private struct NoteShapeEditor: View {
    let shape: NoteShape
    let onChange: (NoteShape) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SourceParameterSliderRow(title: "Velocity", value: Double(shape.velocity), range: 1...127, accent: StudioTheme.amber) { newValue in
                onChange(NoteShape(velocity: Int(newValue.rounded()), gateLength: shape.gateLength, accent: shape.accent))
            }

            SourceParameterSliderRow(title: "Gate Length", value: Double(shape.gateLength), range: 1...16, accent: StudioTheme.violet) { newValue in
                onChange(NoteShape(velocity: shape.velocity, gateLength: Int(newValue.rounded()), accent: shape.accent))
            }
        }
    }
}

private struct ClipContentPreview: View {
    let content: ClipContent
    let onChange: ((ClipContent) -> Void)?

    init(content: ClipContent, onChange: ((ClipContent) -> Void)? = nil) {
        self.content = content
        self.onChange = onChange
    }

    var body: some View {
        switch content {
        case let .stepSequence(stepPattern, pitches):
            VStack(alignment: .leading, spacing: 14) {
                StepGridView(stepStates: stepPattern.map { $0 ? .on : .off }) { index in
                    guard let onChange else { return }
                    var nextPattern = stepPattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(.stepSequence(stepPattern: nextPattern, pitches: pitches))
                }
                .allowsHitTesting(onChange != nil)

                TextField(
                    "Comma-separated MIDI notes",
                    text: Binding(
                        get: { pitches.map(String.init).joined(separator: ", ") },
                        set: { newValue in
                            guard let onChange else { return }
                            let parsed = newValue
                                .split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                                .filter { (0...127).contains($0) }
                            if !parsed.isEmpty {
                                onChange(.stepSequence(stepPattern: stepPattern, pitches: parsed))
                            }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        case let .pianoRoll(lengthBars, stepsPerBar, notes):
            VStack(alignment: .leading, spacing: 14) {
                ClipPianoRollPreview(lengthBars: lengthBars, stepsPerBar: stepsPerBar, notes: notes)
                    .frame(height: 180)
                Text("\(notes.count) notes across \(lengthBars) bars")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        case let .sliceTriggers(stepPattern, sliceIndexes):
            VStack(alignment: .leading, spacing: 14) {
                StepGridView(stepStates: stepPattern.map { $0 ? .on : .off }) { index in
                    guard let onChange else { return }
                    var nextPattern = stepPattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(.sliceTriggers(stepPattern: nextPattern, sliceIndexes: sliceIndexes))
                }
                .allowsHitTesting(onChange != nil)

                TextField(
                    "Comma-separated slice indexes",
                    text: Binding(
                        get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                        set: { newValue in
                            guard let onChange else { return }
                            let parsed = newValue
                                .split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                            if !parsed.isEmpty {
                                onChange(.sliceTriggers(stepPattern: stepPattern, sliceIndexes: parsed))
                            }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private enum PitchAlgoKind: String, CaseIterable, Identifiable {
    case manual
    case randomInScale
    case randomInChord
    case intervalProb
    case markov
    case fromClipPitches
    case external

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .randomInScale:
            return "Scale"
        case .randomInChord:
            return "Chord"
        case .intervalProb:
            return "Intervals"
        case .markov:
            return "Markov"
        case .fromClipPitches:
            return "From Clip"
        case .external:
            return "External"
        }
    }
}

private struct GeneratorTabBar: View {
    @Binding var selectedTab: GeneratorEditorTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GeneratorEditorTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(selectedTab == tab ? StudioTheme.cyan.opacity(0.14) : Color.white.opacity(0.03), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedTab == tab ? StudioTheme.cyan.opacity(0.52) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PolyLaneSelector: View {
    let laneCount: Int
    @Binding var selectedLane: Int
    let onAddLane: () -> Void
    let onRemoveLane: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<laneCount, id: \.self) { laneIndex in
                Button {
                    selectedLane = laneIndex
                } label: {
                    Text("Lane \(laneIndex + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedLane == laneIndex ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(selectedLane == laneIndex ? StudioTheme.violet.opacity(0.16) : Color.white.opacity(0.03), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedLane == laneIndex ? StudioTheme.violet.opacity(0.5) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: onAddLane) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .padding(8)
                    .background(Color.white.opacity(0.03), in: Circle())
            }
            .buttonStyle(.plain)

            if let onRemoveLane {
                Button(action: onRemoveLane) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .padding(8)
                        .background(Color.white.opacity(0.03), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ProbabilityGridEditor: View {
    let values: [Double]
    let onChange: ([Double]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Button {
                    var next = values
                    guard next.indices.contains(index) else { return }
                    let options = [0.0, 0.25, 0.5, 0.75, 1.0]
                    let currentIndex = options.firstIndex(where: { abs($0 - value) < 0.01 }) ?? 0
                    next[index] = options[(currentIndex + 1) % options.count]
                    onChange(next)
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(StudioTheme.cyan.opacity(0.85))
                            .frame(height: max(10, 64 * value))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 96)
    }
}

private struct WeightGridEditor: View {
    let values: [Double]
    let onChange: ([Double]) -> Void

    var body: some View {
        ProbabilityGridEditor(values: values, onChange: onChange)
    }
}

private struct SliceIndexEditor: View {
    let sliceIndexes: [Int]
    let onChange: ([Int]) -> Void

    var body: some View {
        TextField(
            "Comma-separated slice indexes",
            text: Binding(
                get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                set: { newValue in
                    let parsed = newValue
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    if !parsed.isEmpty {
                        onChange(parsed)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
    }
}

private struct SourceParameterStepperRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer()
            Stepper(value: Binding(get: { value }, set: onChange), in: range) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .monospacedDigit()
            }
        }
    }
}

private struct GeneratedNotesPreview: View {
    let generatorParams: GeneratorParams
    let clipChoices: [ClipPoolEntry]

    var body: some View {
        let preview = previewSteps(for: generatorParams, clipChoices: clipChoices)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(preview.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            VStack(alignment: .leading, spacing: 4) {
                                if preview[index].isEmpty {
                                    Text("—")
                                        .foregroundStyle(StudioTheme.mutedText)
                                } else {
                                    ForEach(preview[index], id: \.self) { label in
                                        Text(label)
                                            .foregroundStyle(StudioTheme.text)
                                    }
                                }
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .frame(width: 84, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Text("Preview is generated from the current step and pitch settings.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}

private struct PreviewRNG: RandomNumberGenerator {
    private var state: UInt64 = 0x5EEDC0DE

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}

private func previewSteps(for params: GeneratorParams, clipChoices: [ClipPoolEntry], count: Int = 16) -> [[String]] {
    var rng = PreviewRNG()

    switch params {
    case let .mono(step, pitch, _):
        var lastPitch: Int?
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            let picked = pickPitchPreview(pitch, stepIndex: stepIndex, lastPitch: lastPitch, clipChoices: clipChoices, rng: &rng)
            lastPitch = picked
            return ["\(picked)"]
        }
    case let .poly(step, pitches, _):
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            return pitches.map { "\(pickPitchPreview($0, stepIndex: stepIndex, lastPitch: nil, clipChoices: clipChoices, rng: &rng))" }
        }
    case let .drum(steps, _):
        let keys = steps.keys.sorted()
        return (0..<count).map { stepIndex in
            keys.compactMap { key in
                guard let step = steps[key],
                      stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                    return nil
                }
                return key
            }
        }
    case .template:
        return Array(repeating: ["Template"], count: count)
    case let .slice(step, sliceIndexes):
        let slices = sliceIndexes.isEmpty ? [0] : sliceIndexes
        var nextSlice = 0
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            let label = "S\(slices[nextSlice % slices.count])"
            nextSlice += 1
            return [label]
        }
    }
}

private func stepFiresPreview<R: RandomNumberGenerator>(_ step: StepAlgo, stepIndex: Int, clipChoices: [ClipPoolEntry], rng: inout R) -> Bool {
    switch step {
    case let .fromClipSteps(clipID):
        guard let clip = clipChoices.first(where: { $0.id == clipID }) else { return false }
        switch clip.content {
        case let .stepSequence(stepPattern, _):
            return stepPattern[stepIndex % max(1, stepPattern.count)]
        case let .pianoRoll(_, _, notes):
            return notes.contains(where: { $0.startStep == stepIndex })
        case let .sliceTriggers(stepPattern, _):
            return stepPattern[stepIndex % max(1, stepPattern.count)]
        }
    default:
        return step.fires(at: stepIndex, totalSteps: 16, rng: &rng)
    }
}

private func pickPitchPreview<R: RandomNumberGenerator>(_ pitch: PitchAlgo, stepIndex: Int, lastPitch: Int?, clipChoices: [ClipPoolEntry], rng: inout R) -> Int {
    switch pitch {
    case let .fromClipPitches(clipID, pickMode):
        guard let clip = clipChoices.first(where: { $0.id == clipID }) else { return 60 }
        let pitches = clipPitches(for: clip)
        guard !pitches.isEmpty else { return 60 }
        switch pickMode {
        case .sequential:
            return pitches[stepIndex % pitches.count]
        case .random:
            return pitches.randomElement(using: &rng) ?? 60
        }
    case .external:
        return 60
    default:
        return pitch.pick(
            context: PitchContext(lastPitch: lastPitch, scaleRoot: 60, scaleID: .major, currentChord: nil, stepIndex: stepIndex),
            rng: &rng
        )
    }
}

private func clipPitches(for clip: ClipPoolEntry) -> [Int] {
    switch clip.content {
    case let .stepSequence(_, pitches):
        return pitches
    case let .pianoRoll(_, _, notes):
        return Array(Set(notes.map(\.pitch))).sorted()
    case .sliceTriggers:
        return [60]
    }
}

private func defaultStepAlgo(for kind: StepAlgoKind, clipChoices: [ClipPoolEntry], current: StepAlgo) -> StepAlgo {
    switch kind {
    case .manual:
        if case let .manual(pattern) = current {
            return .manual(pattern: pattern)
        }
        return .manual(pattern: Array(repeating: false, count: 16))
    case .euclidean:
        return .euclidean(pulses: 4, steps: 16, offset: 0)
    case .randomWeighted:
        return .randomWeighted(density: 0.5)
    case .perStepProbability:
        return .perStepProbability(probs: Array(repeating: 0.5, count: 16))
    case .fromClipSteps:
        if let clipID = clipChoices.first?.id {
            return .fromClipSteps(clipID: clipID)
        }
        return .manual(pattern: Array(repeating: false, count: 16))
    }
}

private func defaultPitchAlgo(for kind: PitchAlgoKind, clipChoices: [ClipPoolEntry], current: PitchAlgo) -> PitchAlgo {
    switch kind {
    case .manual:
        if case let .manual(pitches, pickMode) = current {
            return .manual(pitches: pitches, pickMode: pickMode)
        }
        return .manual(pitches: [60, 64, 67], pickMode: .sequential)
    case .randomInScale:
        return .randomInScale(root: 60, scale: .major, spread: 12)
    case .randomInChord:
        return .randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12)
    case .intervalProb:
        return .intervalProb(root: 60, scale: .major, degreeWeights: Array(repeating: 0.5, count: 7))
    case .markov:
        return .markov(root: 60, scale: .major, styleID: .balanced, leap: 0.35, color: 0.2)
    case .fromClipPitches:
        if let clipID = clipChoices.first?.id {
            return .fromClipPitches(clipID: clipID, pickMode: .sequential)
        }
        return .manual(pitches: [60], pickMode: .sequential)
    case .external:
        return .external(port: "External MIDI", channel: 0, holdMode: .pool)
    }
}

private func stepAlgoAccentColor(for kind: StepAlgoKind) -> Color {
    switch kind {
    case .manual:
        return StudioTheme.cyan
    case .euclidean:
        return StudioTheme.success
    case .randomWeighted:
        return StudioTheme.amber
    case .perStepProbability:
        return StudioTheme.violet
    case .fromClipSteps:
        return StudioTheme.violet
    }
}

private struct ClipPianoRollPreview: View {
    let lengthBars: Int
    let stepsPerBar: Int
    let notes: [ClipNote]

    private var totalSteps: Int { max(1, lengthBars * stepsPerBar) }
    private var pitchRange: ClosedRange<Int> {
        let pitches = notes.map(\.pitch)
        return (pitches.min() ?? 48)...(pitches.max() ?? 72)
    }

    var body: some View {
        GeometryReader { geometry in
            let pitchCount = max(1, pitchRange.upperBound - pitchRange.lowerBound + 1)
            let stepWidth = geometry.size.width / CGFloat(totalSteps)
            let noteHeight = geometry.size.height / CGFloat(pitchCount)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.03))

                VStack(spacing: 0) {
                    ForEach(Array(pitchRange.reversed()), id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.03))
                            .frame(height: noteHeight)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 0) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Rectangle()
                            .fill(index % stepsPerBar == 0 ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                            .frame(width: stepWidth)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                ForEach(notes) { note in
                    let yIndex = pitchRange.upperBound - note.pitch
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StudioTheme.violet.opacity(0.82))
                        .frame(
                            width: max(stepWidth * CGFloat(note.lengthSteps) - 2, 6),
                            height: max(noteHeight - 3, 6)
                        )
                        .offset(
                            x: stepWidth * CGFloat(note.startStep) + 1,
                            y: noteHeight * CGFloat(yIndex) + 1.5
                        )
                }
            }
        }
    }
}

private struct AlgorithmSummaryCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

private struct WrapRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04), in: Capsule())
                    .foregroundStyle(StudioTheme.text)
            }
        }
    }
}

private struct TrackSourceModePalette: View {
    let trackType: TrackType
    @Binding var selectedSource: TrackSourceMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TrackSourceMode.available(for: trackType), id: \.self) { source in
                Button {
                    selectedSource = source
                } label: {
                    Text(source.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedSource == source ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(fill(for: source), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(stroke(for: source), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func accent(for source: TrackSourceMode) -> Color {
        switch source {
        case .generator:
            return StudioTheme.cyan
        case .clip:
            return StudioTheme.violet
        }
    }

    private func fill(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.14) : Color.white.opacity(0.03)
    }

    private func stroke(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.52) : StudioTheme.border
    }
}

private struct TrackPatternSlotPalette: View {
    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                Button {
                    selectedSlot = slotIndex
                } label: {
                    HStack(spacing: 6) {
                        Text("\(slotIndex + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        Circle()
                            .fill(indicatorFill(for: slotIndex))
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(backgroundFill(for: slotIndex))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor(for: slotIndex), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func backgroundFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.2)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.08)
        }
        return Color.white.opacity(0.03)
    }

    private func borderColor(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.7)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.28)
        }
        return StudioTheme.border
    }

    private func indicatorFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.6)
        }
        return Color.white.opacity(0.08)
    }
}

private struct SourceParameterSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            .tint(accent)
        }
    }
}
