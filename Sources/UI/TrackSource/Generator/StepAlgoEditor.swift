import SwiftUI

struct StepAlgoEditor: View {
    let stage: StepStage
    let onChange: (StepStage) -> Void

    private var kind: StepAlgoKind { stage.algo.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Trigger Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange(StepStage(algo: $0.defaultAlgo(current: stage.algo), basePitch: stage.basePitch)) }
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
            }
        }
    }
}
