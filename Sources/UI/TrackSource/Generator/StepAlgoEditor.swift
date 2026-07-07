import SwiftUI

struct StepAlgoEditor: View {
    let stage: StepStage
    var accent: Color = StudioTheme.transportAccent
    let onChange: (StepStage) -> Void

    private var visibleStage: StepStage {
        if case .manual = stage.algo {
            return StepStage(
                algo: StepAlgoKind.euclidean.defaultAlgo(current: stage.algo),
                basePitch: stage.basePitch
            )
        }
        return stage
    }

    private var visibleStepAlgoKinds: [StepAlgoKind] { [.euclidean, .weighted] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSegmentedControl(
                title: nil,
                selection: Binding(
                    get: { visibleStage.algo.kind },
                    set: { onChange(StepStage(algo: $0.defaultAlgo(current: visibleStage.algo), basePitch: visibleStage.basePitch)) }
                ),
                segments: visibleStepAlgoKinds.map { kind in
                    StudioSegment(
                        title: kind.title,
                        value: kind,
                        accessibilityIdentifier: "generator-trigger-source-\(kind.rawValue)"
                    )
                },
                accent: accent
            )

            stageControls
        }
    }

    @ViewBuilder
    private var stageControls: some View {
        switch visibleStage.algo {
        case let .euclidean(pulses, steps, offset):
            let safeSteps = max(1, steps)
            let safePulses = min(max(0, pulses), safeSteps)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 56, maximum: 96), spacing: 12, alignment: .top),
                    count: 4
                ),
                alignment: .leading,
                spacing: 12
            ) {
                StudioRotaryKnob(
                    title: "Pulses",
                    value: Double(safePulses),
                    range: 0...Double(safeSteps),
                    accent: accent,
                    size: 56
                ) {
                    onChange(StepStage(algo: .euclidean(pulses: Int($0.rounded()), steps: safeSteps, offset: offset), basePitch: visibleStage.basePitch))
                }

                StudioRotaryKnob(
                    title: "Steps",
                    value: Double(safeSteps),
                    range: 1...32,
                    accent: accent,
                    size: 56
                ) { newValue in
                    let nextSteps = Int(newValue.rounded())
                    onChange(StepStage(algo: .euclidean(pulses: min(safePulses, nextSteps), steps: nextSteps, offset: offset), basePitch: visibleStage.basePitch))
                }

                StudioRotaryKnob(
                    title: "Offset",
                    value: Double(offset),
                    range: -32...32,
                    accent: accent,
                    size: 56
                ) {
                    onChange(StepStage(algo: .euclidean(pulses: safePulses, steps: safeSteps, offset: Int($0.rounded())), basePitch: visibleStage.basePitch))
                }

                StudioRotaryKnob(
                    title: "Pitch",
                    value: Double(visibleStage.basePitch),
                    range: 0...127,
                    accent: accent,
                    size: 56
                ) {
                    onChange(StepStage(algo: visibleStage.algo, basePitch: Int($0.rounded())))
                }
            }
        case let .manual(pattern):
            VStack(alignment: .leading, spacing: 12) {
                GridEditor(
                    values: pattern.map { $0 ? 1.0 : 0.0 },
                    allowedValues: [0, 1],
                    accent: accent
                ) { next in
                    onChange(StepStage(algo: .manual(pattern: next.map { $0 >= 0.5 }), basePitch: stage.basePitch))
                }

                StudioRotaryKnob(
                    title: "Pitch",
                    value: Double(visibleStage.basePitch),
                    range: 0...127,
                    accent: accent,
                    size: 56
                ) {
                    onChange(StepStage(algo: visibleStage.algo, basePitch: Int($0.rounded())))
                }
            }
        case let .weighted(weights, steps, cluster):
            VStack(alignment: .leading, spacing: 14) {
                GridEditor(values: weights, allowedValues: [0, 0.25, 0.5, 0.75, 1], accent: accent) { next in
                    onChange(StepStage(algo: .weighted(weights: next, steps: steps, cluster: cluster), basePitch: stage.basePitch))
                }

                HStack(alignment: .top, spacing: 18) {
                    StudioRotaryKnob(
                        title: "Steps",
                        value: Double(steps),
                        range: 1...32,
                        accent: accent,
                        size: 56
                    ) { newValue in
                        let nextSteps = Int(newValue.rounded())
                        let nextWeights = Array(weights.prefix(nextSteps)) + Array(repeating: 0, count: max(0, nextSteps - weights.count))
                        onChange(StepStage(algo: .weighted(weights: nextWeights, steps: nextSteps, cluster: cluster), basePitch: visibleStage.basePitch))
                    }

                    StudioRotaryKnob(
                        title: "Cluster",
                        value: cluster,
                        range: -1...1,
                        accent: accent,
                        size: 56
                    ) {
                        onChange(StepStage(algo: .weighted(weights: weights, steps: steps, cluster: $0), basePitch: visibleStage.basePitch))
                    }

                    StudioRotaryKnob(
                        title: "Pitch",
                        value: Double(visibleStage.basePitch),
                        range: 0...127,
                        accent: accent,
                        size: 56
                    ) {
                        onChange(StepStage(algo: visibleStage.algo, basePitch: Int($0.rounded())))
                    }
                }
            }
        }
    }
}
