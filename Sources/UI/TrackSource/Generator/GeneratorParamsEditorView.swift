import SwiftUI

struct GeneratorParamsEditorView: View {
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
            case let .mono(trigger, pitch, shape):
                monoEditor(trigger: trigger, pitch: pitch, shape: shape)
            case let .poly(trigger, pitches, shape):
                polyEditor(trigger: trigger, pitches: pitches, shape: shape)
            case let .drum(triggers, shape):
                drumEditor(triggers: triggers, shape: shape)
            case let .template(templateID):
                StudioPanel(title: "Template", eyebrow: "Template source", accent: accent) {
                    Text(templateID.uuidString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            case let .slice(trigger, sliceIndexes):
                sliceEditor(trigger: trigger, sliceIndexes: sliceIndexes)
            }
        }
    }

    @ViewBuilder
    private func monoEditor(trigger: TriggerStageNode, pitch: PitchStageNode, shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Trigger Stage", eyebrow: stepDisplayLabel(trigger.stepStage), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(stage: trigger.stepStage, clipChoices: clipChoices) { nextStage in
                        onUpdate(.mono(trigger: .native(nextStage), pitch: pitch, shape: shape))
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.mono(trigger: trigger, pitch: pitch, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Pitch Expander", eyebrow: pitchDisplayLabel(pitch.pitchStage), accent: StudioTheme.violet) {
                PitchAlgoEditor(stage: pitch.pitchStage, clipChoices: clipChoices) { nextStage in
                    onUpdate(.mono(trigger: trigger, pitch: .native(nextStage), shape: shape))
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Post-expansion preview", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .mono(trigger: trigger, pitch: pitch, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func polyEditor(trigger: TriggerStageNode, pitches: [PitchStageNode], shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Trigger Stage", eyebrow: stepDisplayLabel(trigger.stepStage), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(stage: trigger.stepStage, clipChoices: clipChoices) { nextStage in
                        onUpdate(.poly(trigger: .native(nextStage), pitches: pitches, shape: shape))
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.poly(trigger: trigger, pitches: pitches, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Pitch Expander", eyebrow: "\(pitches.count) lanes over one trigger stream", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 16) {
                    PolyLaneSelector(
                        laneCount: pitches.count,
                        selectedLane: $selectedPolyLane,
                        onAddLane: {
                            var nextPitches = pitches
                            nextPitches.append(.native(.defaultMono))
                            selectedPolyLane = nextPitches.count - 1
                            onUpdate(.poly(trigger: trigger, pitches: nextPitches, shape: shape))
                        },
                        onRemoveLane: pitches.count > 1 ? {
                            var nextPitches = pitches
                            nextPitches.remove(at: min(selectedPolyLane, nextPitches.count - 1))
                            selectedPolyLane = min(selectedPolyLane, max(0, nextPitches.count - 1))
                            onUpdate(.poly(trigger: trigger, pitches: nextPitches, shape: shape))
                        } : nil
                    )

                    let laneIndex = min(selectedPolyLane, max(0, pitches.count - 1))
                    PitchAlgoEditor(stage: pitches[laneIndex].pitchStage, clipChoices: clipChoices) { nextStage in
                        var nextPitches = pitches
                        nextPitches[laneIndex] = .native(nextStage)
                        onUpdate(.poly(trigger: trigger, pitches: nextPitches, shape: shape))
                    }
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Post-expansion preview", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .poly(trigger: trigger, pitches: pitches, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func drumEditor(triggers: [VoiceTag: TriggerStageNode], shape: NoteShape) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Trigger Stage", eyebrow: "\(triggers.count) drum voices", accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(triggers.keys.sorted()), id: \.self) { key in
                        if let trigger = triggers[key] {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(key.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(StudioTheme.mutedText)

                                StepAlgoEditor(stage: trigger.stepStage, clipChoices: clipChoices) { nextStage in
                                    var nextTriggers = triggers
                                    nextTriggers[key] = .native(nextStage)
                                    onUpdate(.drum(triggers: nextTriggers, shape: shape))
                                }
                            }
                        }
                    }

                    NoteShapeEditor(shape: shape) { nextShape in
                        onUpdate(.drum(triggers: triggers, shape: nextShape))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Pitch Routing", eyebrow: "Drum voices stay trigger-only in v1", accent: StudioTheme.violet) {
                WrapRow(items: triggers.keys.sorted())
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Post-expansion preview", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .drum(triggers: triggers, shape: shape), clipChoices: clipChoices)
            }
        }
    }

    @ViewBuilder
    private func sliceEditor(trigger: TriggerStageNode, sliceIndexes: [Int]) -> some View {
        switch selectedTab {
        case .steps:
            StudioPanel(title: "Trigger Stage", eyebrow: stepDisplayLabel(trigger.stepStage), accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    StepAlgoEditor(stage: trigger.stepStage, clipChoices: clipChoices) { nextStage in
                        onUpdate(.slice(trigger: .native(nextStage), sliceIndexes: sliceIndexes))
                    }

                    SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                        onUpdate(.slice(trigger: trigger, sliceIndexes: nextIndexes))
                    }
                }
            }
        case .pitches:
            StudioPanel(title: "Slices", eyebrow: "\(sliceIndexes.count) active", accent: StudioTheme.violet) {
                SliceIndexEditor(sliceIndexes: sliceIndexes) { nextIndexes in
                    onUpdate(.slice(trigger: trigger, sliceIndexes: nextIndexes))
                }
            }
        case .notes:
            StudioPanel(title: "Generated Notes", eyebrow: "Post-expansion preview", accent: StudioTheme.amber) {
                GeneratedNotesPreview(generatorParams: .slice(trigger: trigger, sliceIndexes: sliceIndexes), clipChoices: clipChoices)
            }
        }
    }
}
