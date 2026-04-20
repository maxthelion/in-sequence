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
