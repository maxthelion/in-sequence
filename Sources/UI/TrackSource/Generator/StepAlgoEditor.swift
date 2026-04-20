import SwiftUI

struct StepAlgoEditor: View {
    let step: StepAlgo
    let clipChoices: [ClipPoolEntry]
    let onChange: (StepAlgo) -> Void

    private var kind: StepAlgoKind { step.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Step Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange($0.defaultAlgo(clipChoices: clipChoices, current: step)) }
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
                GridEditor(values: probs, allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0], accent: StudioTheme.cyan) { next in
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
