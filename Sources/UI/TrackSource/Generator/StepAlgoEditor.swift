import SwiftUI

struct StepAlgoEditor: View {
    let stage: StepStage
    let clipChoices: [ClipPoolEntry]
    let onChange: (StepStage) -> Void

    private var kind: StepAlgoKind { stage.algo.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Trigger Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange(StepStage(algo: $0.defaultAlgo(clipChoices: clipChoices, current: stage.algo), basePitch: stage.basePitch)) }
                )
            ) {
                ForEach(StepAlgoKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            SourceParameterStepperRow(title: "Base Pitch", value: stage.basePitch, range: 0...127) {
                onChange(StepStage(algo: stage.algo, basePitch: $0))
            }

            switch stage.algo {
            case let .manual(pattern):
                let states = pattern.map { $0 ? StepVisualState.on : .off }
                StepGridView(stepStates: states) { index in
                    var nextPattern = pattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(StepStage(algo: .manual(pattern: nextPattern), basePitch: stage.basePitch))
                }
            case let .euclidean(pulses, steps, offset):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Pulses", value: pulses, range: 0...steps) {
                        onChange(StepStage(algo: .euclidean(pulses: $0, steps: steps, offset: offset), basePitch: stage.basePitch))
                    }
                    SourceParameterStepperRow(title: "Steps", value: steps, range: 1...32) { nextSteps in
                        onChange(StepStage(algo: .euclidean(pulses: min(pulses, nextSteps), steps: nextSteps, offset: offset), basePitch: stage.basePitch))
                    }
                    SourceParameterStepperRow(title: "Offset", value: offset, range: -32...32) {
                        onChange(StepStage(algo: .euclidean(pulses: pulses, steps: steps, offset: $0), basePitch: stage.basePitch))
                    }
                }
            case let .randomWeighted(density):
                SourceParameterSliderRow(title: "Density", value: density * 100, range: 0...100, accent: stepAlgoAccentColor(for: .randomWeighted)) {
                    onChange(StepStage(algo: .randomWeighted(density: $0 / 100), basePitch: stage.basePitch))
                }
            case let .perStepProbability(probs):
                GridEditor(values: probs, allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0], accent: StudioTheme.cyan) { next in
                    onChange(StepStage(algo: .perStepProbability(probs: next), basePitch: stage.basePitch))
                }
            case let .fromClipSteps(clipID):
                Picker("Step Clip", selection: Binding(
                    get: { Optional(clipID) },
                    set: { newValue in
                        guard let newValue else { return }
                        onChange(StepStage(algo: .fromClipSteps(clipID: newValue), basePitch: stage.basePitch))
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
