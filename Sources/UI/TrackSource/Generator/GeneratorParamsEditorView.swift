import SwiftUI

struct GeneratorParamsEditorView: View {
    enum LayoutMode {
        case stacked
        case sourceOnly
        case modifierOnly
        case sourceContained
        case modifierContained
    }

    private enum StageTab: String, CaseIterable, Identifiable {
        case trigger
        case pitch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trigger:
                return "Trigger"
            case .pitch:
                return "Pitch"
            }
        }
    }

    let generator: GeneratorPoolEntry
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    let chordPalette: ChordPalette?
    let sourceMode: TrackSourceMode
    let accent: Color
    let layout: LayoutMode
    let onUpdate: (GeneratorParams) -> Void
    let onSwitchKind: ((GeneratorKind) -> Void)?
    let onBakeToClip: (() -> Void)?
    let onRemoveSource: (() -> Void)?

    @State private var selectedStageTab: StageTab = .trigger

    init(
        generator: GeneratorPoolEntry,
        inputClipChoices: [ClipPoolEntry],
        harmonicSidechainClipChoices: [ClipPoolEntry],
        chordPalette: ChordPalette? = nil,
        sourceMode: TrackSourceMode,
        accent: Color,
        layout: LayoutMode = .stacked,
        onUpdate: @escaping (GeneratorParams) -> Void,
        onSwitchKind: ((GeneratorKind) -> Void)? = nil,
        onBakeToClip: (() -> Void)? = nil,
        onRemoveSource: (() -> Void)? = nil
    ) {
        self.generator = generator
        self.inputClipChoices = inputClipChoices
        self.harmonicSidechainClipChoices = harmonicSidechainClipChoices
        self.chordPalette = chordPalette
        self.sourceMode = sourceMode
        self.accent = accent
        self.layout = layout
        self.onUpdate = onUpdate
        self.onSwitchKind = onSwitchKind
        self.onBakeToClip = onBakeToClip
        self.onRemoveSource = onRemoveSource
    }

    var body: some View {
        if usesFoundationEditorShell {
            foundationEditorShell
        } else {
            Group {
                switch layout {
                case .stacked:
                    VStack(alignment: .leading, spacing: 18) {
                        sourceSection
                        modifierSection
                    }
                case .sourceOnly:
                    sourceSection
                case .modifierOnly:
                    modifierSection
                case .sourceContained:
                    sourceSection
                case .modifierContained:
                    modifierSection
                }
            }
        }
    }

    private var usesFoundationEditorShell: Bool {
        sourceMode == .generator && layout != .modifierOnly && layout != .modifierContained
    }

    private var foundationEditorShell: some View {
        VStack(alignment: .leading, spacing: 12) {
            generatorHeader
            if layout != .sourceContained {
                GeneratorResultStrip(
                    notesByStep: GeneratorResultStrip.barContent(
                        for: generator.params,
                        clipChoices: inputClipChoices,
                        chordChoices: resolvedChordChoices
                    ),
                    accent: accent
                )
            }

            if generator.kind == .progressionChordGenerator {
                sourceSection
            } else {
                switch selectedStageTab {
                case .trigger:
                    sourceSection
                case .pitch:
                    modifierSection
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackSourceEditorVisualCommand)) { notification in
            guard let command = notification.object as? String,
                  command.hasPrefix("generator-stage:")
            else { return }
            switch command.dropFirst("generator-stage:".count) {
            case "trigger":
                selectedStageTab = .trigger
            case "pitch":
                selectedStageTab = .pitch
            default:
                break
            }
            postRenderedGeneratorVisualState()
        }
        .onAppear {
            postRenderedGeneratorVisualState()
        }
        .onChange(of: selectedStageTab) { _, _ in
            postRenderedGeneratorVisualState()
        }
    }

    private func postRenderedGeneratorVisualState() {
        NotificationCenter.default.post(
            name: .trackSourceGeneratorRenderedVisualState,
            object: nil,
            userInfo: [
                "stage": selectedStageTab.rawValue,
                "kind": generator.kind.rawValue,
                "sourceMode": "\(sourceMode)"
            ]
        )
    }

    private var generatorHeader: some View {
        HStack(spacing: 10) {
            if generator.kind != .progressionChordGenerator {
                generatorStageSelector
            }

            if let followingChipValue {
                GeneratorHeaderChip(title: "FOLLOWING", value: followingChipValue, accent: accent)
            }

            Spacer(minLength: 0)

            Button {
                onBakeToClip?()
            } label: {
                Label("Bake", systemImage: "die.face.5")
                    .studioText(.labelBold)
                    .foregroundStyle(onBakeToClip == nil ? StudioTheme.mutedText : StudioTheme.background)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        onBakeToClip == nil ? StudioTheme.border : accent,
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(onBakeToClip == nil)
            .help("Bake generator result to clip")

            if let onRemoveSource {
                StudioCircleIconButton(
                    systemName: "xmark",
                    size: StudioMetrics.ControlSize.medium,
                    help: "Remove generator",
                    action: onRemoveSource
                )
                .accessibilityIdentifier("generator-source-remove")
            }
        }
    }

    private var generatorStageSelector: some View {
        StudioSegmentedControl(
            title: nil,
            selection: $selectedStageTab,
            segments: StageTab.allCases.map { tab in
                StudioSegment(
                    title: stageTitle(for: tab),
                    value: tab,
                    accessibilityIdentifier: "generator-stage-\(tab.rawValue)"
                )
            },
            accent: accent,
            layout: StudioSegmentedControl.Layout(
                fillsWidth: false,
                minWidth: 64,
                minHeight: 28,
                horizontalPadding: 10
            )
        )
    }

    private func stageTitle(for tab: StageTab) -> String {
        if tab == .pitch, generator.kind == .chordGenerator {
            return "Chords"
        }
        return tab.title
    }

    private var followingChipValue: String? {
        switch firstPitchStage?.harmonicSidechain {
        case .some(.projectChordContext):
            return "Chord"
        case .some(.clip):
            return "Clip"
        case .some(.none), nil:
            return nil
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        if sourceMode != .generator {
            EmptyView()
        } else {
            switch generator.params {
            case let .mono(trigger, _, shape):
                sourceEditorContainer(title: "Generator Source", eyebrow: stepDisplayLabel(trigger.stepStage)) {
                    triggerAndShapeEditor(
                        stepStage: trigger.stepStage,
                        shape: shape,
                        onStageChange: { nextStage in
                            onUpdate(.mono(trigger: .native(nextStage), pitch: monoPitchStage, shape: shape))
                        },
                        onShapeChange: { nextShape in
                            onUpdate(.mono(trigger: trigger, pitch: monoPitchNode, shape: nextShape))
                        }
                    )
                }

            case let .poly(trigger, _, shape):
                sourceEditorContainer(title: "Generator Source", eyebrow: stepDisplayLabel(trigger.stepStage)) {
                    triggerAndShapeEditor(
                        stepStage: trigger.stepStage,
                        shape: shape,
                        onStageChange: { nextStage in
                            onUpdate(.poly(trigger: .native(nextStage), pitches: polyPitchNodes, shape: shape))
                        },
                        onShapeChange: { nextShape in
                            onUpdate(.poly(trigger: trigger, pitches: polyPitchNodes, shape: nextShape))
                        }
                    )
                }

            case let .chordGenerator(params):
                let normalized = params.normalized
                sourceEditorContainer(title: "Generator Source", eyebrow: stepDisplayLabel(normalized.trigger.stepStage)) {
                    triggerAndShapeEditor(
                        stepStage: normalized.trigger.stepStage,
                        shape: normalized.shape,
                        onStageChange: { nextStage in
                            var next = normalized
                            next.trigger = .native(nextStage)
                            onUpdate(.chordGenerator(next.normalized))
                        },
                        onShapeChange: { nextShape in
                            var next = normalized
                            next.shape = nextShape
                            onUpdate(.chordGenerator(next.normalized))
                        }
                    )
                }

            case let .progressionChords(params):
                ProgressionChordGeneratorEditorView(
                    params: params,
                    accent: accent,
                    showsPanel: layout != .sourceContained,
                    onUpdate: onUpdate
                )

            case let .slice(trigger, sliceIndexes):
                sourceEditorContainer(title: "Generator Source", eyebrow: stepDisplayLabel(trigger.stepStage)) {
                    VStack(alignment: .leading, spacing: 16) {
                        StepAlgoEditor(stage: trigger.stepStage, accent: accent) { nextStage in
                            onUpdate(.slice(trigger: .native(nextStage), sliceIndexes: sliceIndexes))
                        }

                        SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                            onUpdate(.slice(trigger: trigger, sliceIndexes: nextIndexes))
                        }
                    }
                }

            case let .template(templateID):
                sourceEditorContainer(title: "Template Source", eyebrow: "Generator-defined source") {
                    Text(templateID.uuidString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.mutedText)
                }

            case .drum:
                sourceEditorContainer(title: "Generator Source", eyebrow: "Drum voices") {
                    Text("Not editable in this workspace")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .help("Drum generator editing is not exposed in this track workspace")
                }
            }
        }
    }

    private func triggerAndShapeEditor(
        stepStage: StepStage,
        shape: NoteShape,
        onStageChange: @escaping (StepStage) -> Void,
        onShapeChange: @escaping (NoteShape) -> Void
    ) -> some View {
        let visibleStage = visibleTriggerStage(for: stepStage)

        return Group {
            if case let .euclidean(pulses, steps, offset) = visibleStage.algo {
                let safeSteps = max(1, steps)
                let safePulses = min(max(0, pulses), safeSteps)

                VStack(alignment: .leading, spacing: 14) {
                    triggerKindSelector(stage: visibleStage, onStageChange: onStageChange)

                    LazyVGrid(columns: triggerAndShapeColumns, alignment: .leading, spacing: 12) {
                        StudioRotaryKnob(
                            title: "Pulses",
                            value: Double(safePulses),
                            range: 0...Double(safeSteps),
                            accent: accent,
                            size: 56
                        ) {
                            onStageChange(StepStage(algo: .euclidean(pulses: Int($0.rounded()), steps: safeSteps, offset: offset), basePitch: visibleStage.basePitch))
                        }

                        StudioRotaryKnob(
                            title: "Steps",
                            value: Double(safeSteps),
                            range: 1...32,
                            accent: accent,
                            size: 56
                        ) { newValue in
                            let nextSteps = Int(newValue.rounded())
                            onStageChange(StepStage(algo: .euclidean(pulses: min(safePulses, nextSteps), steps: nextSteps, offset: offset), basePitch: visibleStage.basePitch))
                        }

                        StudioRotaryKnob(
                            title: "Offset",
                            value: Double(offset),
                            range: -32...32,
                            accent: accent,
                            size: 56
                        ) {
                            onStageChange(StepStage(algo: .euclidean(pulses: safePulses, steps: safeSteps, offset: Int($0.rounded())), basePitch: visibleStage.basePitch))
                        }

                        StudioRotaryKnob(
                            title: "Pitch",
                            value: Double(visibleStage.basePitch),
                            range: 0...127,
                            accent: accent,
                            size: 56
                        ) {
                            onStageChange(StepStage(algo: visibleStage.algo, basePitch: Int($0.rounded())))
                        }

                        StudioRotaryKnob(
                            title: "Velocity",
                            value: Double(shape.velocity),
                            range: 1...127,
                            accent: accent,
                            size: 56
                        ) { newValue in
                            onShapeChange(NoteShape(velocity: Int(newValue.rounded()), gateLength: shape.gateLength, accent: shape.accent))
                        }

                        StudioRotaryKnob(
                            title: "Gate",
                            value: Double(shape.gateLength),
                            range: 1...16,
                            accent: accent,
                            size: 56
                        ) { newValue in
                            onShapeChange(NoteShape(velocity: shape.velocity, gateLength: Int(newValue.rounded()), accent: shape.accent))
                        }
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 18) {
                        StepAlgoEditor(stage: stepStage, accent: accent, maximumControlColumns: 4) { nextStage in
                            onStageChange(nextStage)
                        }
                            .frame(width: 580, alignment: .leading)
                        NoteShapeEditor(shape: shape, accent: accent, knobSize: 56, spacing: 12) { nextShape in
                            onShapeChange(nextShape)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        StepAlgoEditor(stage: stepStage, accent: accent) { nextStage in
                            onStageChange(nextStage)
                        }

                        NoteShapeEditor(shape: shape, accent: accent) { nextShape in
                            onShapeChange(nextShape)
                        }
                    }
                }
            }
        }
    }

    private var triggerAndShapeColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 56, maximum: 96), spacing: 12, alignment: .top),
            count: 6
        )
    }

    private func visibleTriggerStage(for stage: StepStage) -> StepStage {
        if case .manual = stage.algo {
            return StepStage(
                algo: StepAlgoKind.euclidean.defaultAlgo(current: stage.algo),
                basePitch: stage.basePitch
            )
        }
        return stage
    }

    private func triggerKindSelector(
        stage: StepStage,
        onStageChange: @escaping (StepStage) -> Void
    ) -> some View {
        StudioSegmentedControl(
            title: nil,
            selection: Binding(
                get: { stage.algo.kind },
                set: { onStageChange(StepStage(algo: $0.defaultAlgo(current: stage.algo), basePitch: stage.basePitch)) }
            ),
            segments: [.euclidean, .weighted].map { kind in
                StudioSegment(
                    title: kind.title,
                    value: kind,
                    accessibilityIdentifier: "generator-trigger-source-\(kind.rawValue)"
                )
            },
            accent: accent
        )
    }

    @ViewBuilder
    private var modifierSection: some View {
        switch generator.params {
        case let .mono(_, pitch, _):
            PitchAlgoEditor(
                stage: pitch.pitchStage,
                inputClipChoices: inputClipChoices,
                harmonicSidechainClipChoices: harmonicSidechainClipChoices,
                accent: accent
            ) { nextStage in
                onUpdate(.mono(trigger: monoTriggerNode, pitch: .native(nextStage), shape: monoShape))
            }

        case let .poly(_, pitches, _):
            let sharedStage = pitches.first?.pitchStage ?? .defaultMono
            VStack(alignment: .leading, spacing: 12) {
                SourceParameterStepperRow(title: "Voices", value: max(1, pitches.count), range: 1...8) { nextCount in
                    let nextPitches = Array(repeating: PitchStageNode.native(sharedStage), count: nextCount)
                    onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                }

                PitchAlgoEditor(
                    stage: sharedStage,
                    inputClipChoices: inputClipChoices,
                    harmonicSidechainClipChoices: harmonicSidechainClipChoices,
                    accent: accent
                ) { nextStage in
                    let voiceCount = max(1, pitches.count)
                    let nextPitches = Array(repeating: PitchStageNode.native(nextStage), count: voiceCount)
                    onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                }
            }

        case let .chordGenerator(params):
            ChordGeneratorChordsEditorView(
                params: params,
                palette: chordPalette ?? .default,
                accent: accent,
                onUpdate: onUpdate
            )

        case .progressionChords:
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: "Not available for chord sources") {
                // State, not explanation (canon Rule 3): the "why" lives in
                // the tooltip.
                Text("No modifier stage")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .help("Progression chord generators emit complete chords, so they do not expose a separate modifier stage")
            }

        case .slice:
            if sourceMode == .clip {
                modifierEditorContainer(title: "Generator Modifier", eyebrow: nil) {
                    Text("No modifier stage in clip mode")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .help("Slice tracks have no separate pitch modifier stage yet — choose generator mode on the slot to use the generator as the source")
                }
            }

        case .template:
            EmptyView()

        case .drum:
            EmptyView()
        }
    }

    private func sourceEditorContainer<Content: View>(
        title: String,
        eyebrow: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        editorContainer(
            title: title,
            eyebrow: eyebrow,
            accent: accent,
            isContained: layout == .sourceContained,
            content: content
        )
    }

    private func modifierEditorContainer<Content: View>(
        title: String,
        eyebrow: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        editorContainer(
            title: title,
            eyebrow: eyebrow,
            accent: accent,
            isContained: layout == .modifierContained,
            content: content
        )
        .help("Runs after the selected source")
    }

    @ViewBuilder
    private func editorContainer<Content: View>(
        title: String,
        eyebrow: String?,
        accent: Color,
        isContained: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isContained {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            StudioPanel(title: title, eyebrow: eyebrow, accent: accent) {
                content()
            }
        }
    }

    private var monoTriggerNode: TriggerStageNode {
        guard case let .mono(trigger, _, _) = generator.params else {
            assertionFailure("Expected mono generator params")
            return .native(.defaultMono)
        }
        return trigger
    }

    private var monoPitchNode: PitchStageNode {
        guard case let .mono(_, pitch, _) = generator.params else {
            assertionFailure("Expected mono generator params")
            return .native(.defaultMono)
        }
        return pitch
    }

    private var monoPitchStage: PitchStageNode {
        monoPitchNode
    }

    private var monoShape: NoteShape {
        guard case let .mono(_, _, shape) = generator.params else {
            assertionFailure("Expected mono generator params")
            return .default
        }
        return shape
    }

    private var polyTriggerNode: TriggerStageNode {
        guard case let .poly(trigger, _, _) = generator.params else {
            assertionFailure("Expected poly generator params")
            return .native(.defaultMono)
        }
        return trigger
    }

    private var polyPitchNodes: [PitchStageNode] {
        guard case let .poly(_, pitches, _) = generator.params else {
            assertionFailure("Expected poly generator params")
            return [.native(.defaultMono)]
        }
        return pitches
    }

    private var polyShape: NoteShape {
        guard case let .poly(_, _, shape) = generator.params else {
            assertionFailure("Expected poly generator params")
            return .default
        }
        return shape
    }

    private var firstPitchStage: PitchStage? {
        switch generator.params {
        case let .mono(_, pitch, _):
            return pitch.pitchStage
        case let .poly(_, pitches, _):
            return pitches.first?.pitchStage
        default:
            return nil
        }
    }

    private var resolvedChordChoices: [ResolvedChordGeneratorChoice] {
        guard case let .chordGenerator(params) = generator.params else { return [] }
        return params.resolvedChoices(in: chordPalette ?? .default)
    }
}

private struct GeneratorHeaderChip: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(accent)
            Text(value)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }
}

/// The always-visible combined RESULT strip (prototype 14b): one bar of
/// resolved triggers with pitch labels, readable from either stage tab.
/// Hit cells are accent-outlined with a solid dot + pitch label; rests are
/// border-dim — the prototype's cell grammar.
struct GeneratorResultStrip: View {
    let notesByStep: [[GeneratedNote]]
    let accent: Color

    /// AC5 seam: the strip renders EXACTLY this function's output — the same
    /// `GeneratedSourceEvaluator` preview evaluation the bake path freezes,
    /// and (for deterministic generators) the same realized bar the
    /// `BarPrecomputeEvaluator` precompute publishes. Exposed so the
    /// acceptance test can pin strip content == precomputed bar with no
    /// separate simulation in between.
    static func barContent(
        for params: GeneratorParams,
        clipChoices: [ClipPoolEntry],
        chordChoices: [ResolvedChordGeneratorChoice] = [],
        stepCount: Int = 16
    ) -> [[GeneratedNote]] {
        GeneratedSourceEvaluator.previewNotes(
            for: params,
            clipChoices: clipChoices,
            count: stepCount,
            chordChoices: chordChoices
        )
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(notesByStep.enumerated()), id: \.offset) { _, notes in
                resultCell(notes: notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Generator result strip")
        .accessibilityIdentifier("generator-result-strip")
    }

    @ViewBuilder
    private func resultCell(notes: [GeneratedNote]) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(notes.isEmpty ? StudioTheme.border : accent)
                .frame(width: 5, height: 5)

            if let first = notes.first {
                Text(Self.pitchLabel(first.pitch) + (notes.count > 1 ? "+" : ""))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("·")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    // ux-canon-allow: rest-cell placeholder glyph — muted
                    // caption token, not stateful chrome.
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(notes.isEmpty ? StudioTheme.border : accent, lineWidth: StudioMetrics.borderWidth)
        )
    }

    static func pitchLabel(_ pitch: Int) -> String {
        let clamped = min(max(pitch, 0), 127)
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[clamped % 12])\(clamped / 12 - 1)"
    }
}
