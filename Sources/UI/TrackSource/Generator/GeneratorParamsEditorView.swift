import SwiftUI

struct GeneratorParamsEditorView: View {
    enum LayoutMode {
        case stacked
        case sourceOnly
        case modifierOnly
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
                StudioPanel(title: "Generator Source", eyebrow: "Used when this slot is set to Generator", accent: accent) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(stepDisplayLabel(trigger.stepStage))
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)

                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
                            onUpdate(.mono(trigger: .native(nextStage), pitch: monoPitchStage, shape: shape))
                        }

                        NoteShapeEditor(shape: shape) { nextShape in
                            onUpdate(.mono(trigger: trigger, pitch: monoPitchNode, shape: nextShape))
                        }
                    }
                }

            case let .poly(trigger, _, shape):
                StudioPanel(title: "Generator Source", eyebrow: "Used when this slot is set to Generator", accent: accent) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(stepDisplayLabel(trigger.stepStage))
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)

                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
                            onUpdate(.poly(trigger: .native(nextStage), pitches: polyPitchNodes, shape: shape))
                        }

                        NoteShapeEditor(shape: shape) { nextShape in
                            onUpdate(.poly(trigger: trigger, pitches: polyPitchNodes, shape: nextShape))
                        }
                    }
                }

            case let .slice(trigger, sliceIndexes):
                StudioPanel(title: "Generator Source", eyebrow: "Used when this slot is set to Generator", accent: accent) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(stepDisplayLabel(trigger.stepStage))
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)

                        StepAlgoEditor(stage: trigger.stepStage) { nextStage in
                            onUpdate(.slice(trigger: .native(nextStage), sliceIndexes: sliceIndexes))
                        }

                        SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                            onUpdate(.slice(trigger: trigger, sliceIndexes: nextIndexes))
                        }
                    }
                }

            case let .template(templateID):
                StudioPanel(title: "Template Source", eyebrow: "Generator-defined source", accent: accent) {
                    Text(templateID.uuidString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.mutedText)
                }

            case .drum:
                StudioPanel(title: "Generator Source", eyebrow: "Drum voices", accent: accent) {
                    Text("Drum generator editing is not exposed in this track workspace.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
        }
    }

    @ViewBuilder
    private var modifierSection: some View {
        switch generator.params {
        case let .mono(_, pitch, _):
            StudioPanel(title: "Pitch Modifier", eyebrow: "Runs after the selected source", accent: StudioTheme.violet) {
                PitchAlgoEditor(
                    stage: pitch.pitchStage,
                    inputClipChoices: inputClipChoices,
                    harmonicSidechainClipChoices: harmonicSidechainClipChoices
                ) { nextStage in
                    onUpdate(.mono(trigger: monoTriggerNode, pitch: .native(nextStage), shape: monoShape))
                }
            }

        case let .poly(_, pitches, _):
            StudioPanel(title: "Pitch Modifier", eyebrow: "Runs after the selected source", accent: StudioTheme.violet) {
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

        case .slice:
            if sourceMode == .clip {
                StudioPanel(title: "Generator Modifier", eyebrow: "Runs after the selected source", accent: StudioTheme.violet) {
                    Text("Slice tracks do not have a separate pitch modifier stage yet. Choose generator mode on the slot to use the generator as the source.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .template:
            EmptyView()

        case .drum:
            EmptyView()
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
