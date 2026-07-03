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
    let sourceMode: TrackSourceMode
    let accent: Color
    let layout: LayoutMode
    let onUpdate: (GeneratorParams) -> Void
    let onSwitchKind: ((GeneratorKind) -> Void)?
    let onBakeToClip: (() -> Void)?

    @State private var selectedPolyLane = 0
    @State private var selectedStageTab: StageTab = .trigger

    init(
        generator: GeneratorPoolEntry,
        inputClipChoices: [ClipPoolEntry],
        harmonicSidechainClipChoices: [ClipPoolEntry],
        sourceMode: TrackSourceMode,
        accent: Color,
        layout: LayoutMode = .stacked,
        onUpdate: @escaping (GeneratorParams) -> Void,
        onSwitchKind: ((GeneratorKind) -> Void)? = nil,
        onBakeToClip: (() -> Void)? = nil
    ) {
        self.generator = generator
        self.inputClipChoices = inputClipChoices
        self.harmonicSidechainClipChoices = harmonicSidechainClipChoices
        self.sourceMode = sourceMode
        self.accent = accent
        self.layout = layout
        self.onUpdate = onUpdate
        self.onSwitchKind = onSwitchKind
        self.onBakeToClip = onBakeToClip
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
            GeneratorResultStrip(
                notesByStep: GeneratorResultStrip.barContent(
                    for: generator.params,
                    clipChoices: inputClipChoices
                ),
                accent: accent
            )

            if generator.kind == .progressionChordGenerator {
                sourceSection
            } else {
                // TRIGGER | PITCH stage tabs (prototype 14b) in the inset-track
                // solid-thumb family — never a native segmented picker.
                StudioSegmentedControl(
                    title: nil,
                    selection: $selectedStageTab,
                    segments: StageTab.allCases.map { tab in
                        StudioSegment(
                            title: tab.title,
                            value: tab,
                            accessibilityIdentifier: "generator-stage-\(tab.rawValue)"
                        )
                    },
                    accent: accent
                )

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
        }
    }

    private var generatorHeader: some View {
        HStack(spacing: 10) {
            // Themed generator picker — the stock white native pop-up was a
            // Rule 6 finding (design review 22e).
            StudioMenuPicker(
                title: nil,
                selection: Binding(
                    get: { generator.kind },
                    set: { onSwitchKind?($0) }
                ),
                options: GeneratorKind.allCases
                    .filter { $0.compatibleWith.contains(generator.trackType) }
                    .map { StudioMenuPickerOption(label: $0.label, value: $0) },
                help: "Switch generator mode without replacing this pattern source"
            )
            .disabled(onSwitchKind == nil)

            GeneratorHeaderChip(title: "FOLLOWING", value: followingChipValue, accent: accent)

            Spacer(minLength: 0)

            StudioCircleIconButton(
                systemName: "die.face.5",
                accent: accent,
                isEnabled: onBakeToClip != nil,
                help: "Bake generator result to clip",
                action: { onBakeToClip?() }
            )
        }
    }

    private var followingChipValue: String {
        switch firstPitchStage?.harmonicSidechain {
        case .some(.projectChordContext):
            return "Chord"
        case .some(.clip):
            return "Clip"
        case .some(.none), nil:
            return "None"
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
                    VStack(alignment: .leading, spacing: 16) {
                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
                            onUpdate(.mono(trigger: .native(nextStage), pitch: monoPitchStage, shape: shape))
                        }

                        NoteShapeEditor(shape: shape) { nextShape in
                            onUpdate(.mono(trigger: trigger, pitch: monoPitchNode, shape: nextShape))
                        }
                    }
                }

            case let .poly(trigger, _, shape):
                sourceEditorContainer(title: "Generator Source", eyebrow: stepDisplayLabel(trigger.stepStage)) {
                    VStack(alignment: .leading, spacing: 16) {
                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
                            onUpdate(.poly(trigger: .native(nextStage), pitches: polyPitchNodes, shape: shape))
                        }

                        NoteShapeEditor(shape: shape) { nextShape in
                            onUpdate(.poly(trigger: trigger, pitches: polyPitchNodes, shape: nextShape))
                        }
                    }
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
                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
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

    @ViewBuilder
    private var modifierSection: some View {
        switch generator.params {
        case let .mono(_, pitch, _):
            // No explainer eyebrow: "Runs after the selected source" was a
            // Rule 3 sentence (design review 22f/22h) — the ordering is shape
            // knowledge and lives in the container's hover help.
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: nil) {
                PitchAlgoEditor(
                    stage: pitch.pitchStage,
                    inputClipChoices: inputClipChoices,
                    harmonicSidechainClipChoices: harmonicSidechainClipChoices,
                    accent: accent
                ) { nextStage in
                    onUpdate(.mono(trigger: monoTriggerNode, pitch: .native(nextStage), shape: monoShape))
                }
            }

        case let .poly(_, pitches, _):
            // The eyebrow carries the one real fact (lane count) — the old
            // "N lanes over the selected source" line was a Rule 3 sentence
            // with a plural bug ("1 lanes"), design review 22h.
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: "\(pitches.count) lane\(pitches.count == 1 ? "" : "s")") {
                VStack(alignment: .leading, spacing: 16) {
                    PolyLaneSelector(
                        laneCount: pitches.count,
                        selectedLane: $selectedPolyLane,
                        accent: accent,
                        onAddLane: {
                            var nextPitches = pitches
                            nextPitches.append(.native(.defaultMono))
                            selectedPolyLane = nextPitches.count - 1
                            onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                        },
                        onRemoveLane: pitches.count > 1 ? {
                            var nextPitches = pitches
                            nextPitches.remove(at: min(selectedPolyLane, nextPitches.count - 1))
                            selectedPolyLane = min(selectedPolyLane, max(0, nextPitches.count - 1))
                            onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                        } : nil
                    )

                    let laneIndex = min(selectedPolyLane, max(0, pitches.count - 1))
                    PitchAlgoEditor(
                        stage: pitches[laneIndex].pitchStage,
                        inputClipChoices: inputClipChoices,
                        harmonicSidechainClipChoices: harmonicSidechainClipChoices,
                        accent: accent
                    ) { nextStage in
                        var nextPitches = pitches
                        nextPitches[laneIndex] = .native(nextStage)
                        onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                    }
                }
            }

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
            let containedTitle = title == "Generator Source" ? "Generator Controls" : title
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(containedTitle.uppercased())
                        .studioText(.bodyEmphasis)
                        .tracking(1.1)
                        .foregroundStyle(StudioTheme.text)

                    if let eyebrow {
                        Text(eyebrow)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                content()
            }
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
        stepCount: Int = 16
    ) -> [[GeneratedNote]] {
        GeneratedSourceEvaluator.previewNotes(
            for: params,
            clipChoices: clipChoices,
            count: stepCount
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
