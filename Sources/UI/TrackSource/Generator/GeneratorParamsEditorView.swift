import SwiftUI

struct GeneratorParamsEditorView: View {
    enum LayoutMode {
        case stacked
        case sourceOnly
        case modifierOnly
        case sourceContained
        case modifierContained
    }

    let generator: GeneratorPoolEntry
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    let sourceMode: TrackSourceMode
    let accent: Color
    let layout: LayoutMode
    let onUpdate: (GeneratorParams) -> Void

    @State private var selectedPolyLane = 0

    init(
        generator: GeneratorPoolEntry,
        inputClipChoices: [ClipPoolEntry],
        harmonicSidechainClipChoices: [ClipPoolEntry],
        sourceMode: TrackSourceMode,
        accent: Color,
        layout: LayoutMode = .stacked,
        onUpdate: @escaping (GeneratorParams) -> Void
    ) {
        self.generator = generator
        self.inputClipChoices = inputClipChoices
        self.harmonicSidechainClipChoices = harmonicSidechainClipChoices
        self.sourceMode = sourceMode
        self.accent = accent
        self.layout = layout
        self.onUpdate = onUpdate
    }

    var body: some View {
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
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: "Runs after the selected source") {
                PitchAlgoEditor(
                    stage: pitch.pitchStage,
                    inputClipChoices: inputClipChoices,
                    harmonicSidechainClipChoices: harmonicSidechainClipChoices
                ) { nextStage in
                    onUpdate(.mono(trigger: monoTriggerNode, pitch: .native(nextStage), shape: monoShape))
                }
            }

        case let .poly(_, pitches, _):
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: "Runs after the selected source") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(pitches.count) lanes over the selected source")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)

                    PolyLaneSelector(
                        laneCount: pitches.count,
                        selectedLane: $selectedPolyLane,
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
                        harmonicSidechainClipChoices: harmonicSidechainClipChoices
                    ) { nextStage in
                        var nextPitches = pitches
                        nextPitches[laneIndex] = .native(nextStage)
                        onUpdate(.poly(trigger: polyTriggerNode, pitches: nextPitches, shape: polyShape))
                    }
                }
            }

        case .progressionChords:
            modifierEditorContainer(title: "Pitch Modifier", eyebrow: "Not available for chord sources") {
                Text("Chord sources emit complete chords")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .help("Progression chord generators emit complete chords, so they do not expose a separate modifier stage")
            }

        case .slice:
            if sourceMode == .clip {
                modifierEditorContainer(title: "Generator Modifier", eyebrow: "Runs after the selected source") {
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
        eyebrow: String,
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
        eyebrow: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        editorContainer(
            title: title,
            eyebrow: eyebrow,
            accent: StudioTheme.violet,
            isContained: layout == .modifierContained,
            content: content
        )
    }

    @ViewBuilder
    private func editorContainer<Content: View>(
        title: String,
        eyebrow: String,
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

                    Text(eyebrow)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
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
}
