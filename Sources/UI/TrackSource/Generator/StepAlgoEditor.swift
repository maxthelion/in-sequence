import SwiftUI

struct StepAlgoEditor: View {
    let stage: StepStage
    let onChange: (StepStage) -> Void

    @State private var showsSecondaryParameters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Trigger SOURCE selector (prototype 14b): Euclidean | Weighted |
            // Manual in the inset-track solid-thumb family, never a native
            // segmented picker.
            StudioSegmentedControl(
                title: "Source",
                selection: Binding(
                    get: { stage.algo.kind },
                    set: { onChange(StepStage(algo: $0.defaultAlgo(current: stage.algo), basePitch: stage.basePitch)) }
                ),
                segments: StepAlgoKind.allCases.map { kind in
                    StudioSegment(
                        title: kind.title,
                        value: kind,
                        accessibilityIdentifier: "generator-trigger-source-\(kind.rawValue)"
                    )
                },
                accent: StudioTheme.cyan
            )

            stageControls
        }
    }

    @ViewBuilder
    private var stageControls: some View {
        switch stage.algo {
        case let .euclidean(pulses, steps, offset):
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    StudioRotaryKnob(
                        title: "Pulses",
                        value: Double(pulses),
                        range: 0...Double(steps),
                        accent: StudioTheme.cyan,
                        size: 56
                    ) {
                        onChange(StepStage(algo: .euclidean(pulses: Int($0.rounded()), steps: steps, offset: offset), basePitch: stage.basePitch))
                    }

                    if showsSecondaryParameters {
                        StudioRotaryKnob(
                            title: "Steps",
                            value: Double(steps),
                            range: 1...32,
                            accent: StudioTheme.violet
                        ) { newValue in
                            let nextSteps = Int(newValue.rounded())
                            onChange(StepStage(algo: .euclidean(pulses: min(pulses, nextSteps), steps: nextSteps, offset: offset), basePitch: stage.basePitch))
                        }

                        StudioRotaryKnob(
                            title: "Offset",
                            value: Double(offset),
                            range: -32...32,
                            accent: StudioTheme.violet
                        ) {
                            onChange(StepStage(algo: .euclidean(pulses: pulses, steps: steps, offset: Int($0.rounded())), basePitch: stage.basePitch))
                        }

                        StudioRotaryKnob(
                            title: "Pitch",
                            value: Double(stage.basePitch),
                            range: 0...127,
                            accent: StudioTheme.amber
                        ) {
                            onChange(StepStage(algo: stage.algo, basePitch: Int($0.rounded())))
                        }
                    }

                    Spacer(minLength: 0)

                    StudioCircleIconButton(
                        systemName: showsSecondaryParameters ? "chevron.left.2" : "ellipsis",
                        help: showsSecondaryParameters ? "Hide extra parameters" : "Show steps, offset, and pitch"
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showsSecondaryParameters.toggle()
                        }
                    }
                }
            }
        case let .manual(pattern):
            VStack(alignment: .leading, spacing: 12) {
                GridEditor(
                    values: pattern.map { $0 ? 1.0 : 0.0 },
                    allowedValues: [0, 1],
                    accent: StudioTheme.cyan
                ) { next in
                    onChange(StepStage(algo: .manual(pattern: next.map { $0 >= 0.5 }), basePitch: stage.basePitch))
                }

                StudioRotaryKnob(
                    title: "Pitch",
                    value: Double(stage.basePitch),
                    range: 0...127,
                    accent: StudioTheme.amber,
                    size: 56
                ) {
                    onChange(StepStage(algo: stage.algo, basePitch: Int($0.rounded())))
                }
            }
        case let .weighted(weights, steps, cluster):
            VStack(alignment: .leading, spacing: 14) {
                GridEditor(values: weights, allowedValues: [0, 0.25, 0.5, 0.75, 1], accent: StudioTheme.cyan) { next in
                    onChange(StepStage(algo: .weighted(weights: next, steps: steps, cluster: cluster), basePitch: stage.basePitch))
                }

                HStack(alignment: .top, spacing: 18) {
                    StudioRotaryKnob(
                        title: "Steps",
                        value: Double(steps),
                        range: 1...32,
                        accent: StudioTheme.violet,
                        size: 56
                    ) { newValue in
                        let nextSteps = Int(newValue.rounded())
                        let nextWeights = Array(weights.prefix(nextSteps)) + Array(repeating: 0, count: max(0, nextSteps - weights.count))
                        onChange(StepStage(algo: .weighted(weights: nextWeights, steps: nextSteps, cluster: cluster), basePitch: stage.basePitch))
                    }

                    StudioRotaryKnob(
                        title: "Cluster",
                        value: cluster,
                        range: -1...1,
                        accent: StudioTheme.amber,
                        size: 56
                    ) {
                        onChange(StepStage(algo: .weighted(weights: weights, steps: steps, cluster: $0), basePitch: stage.basePitch))
                    }

                    StudioRotaryKnob(
                        title: "Pitch",
                        value: Double(stage.basePitch),
                        range: 0...127,
                        accent: StudioTheme.amber,
                        size: 56
                    ) {
                        onChange(StepStage(algo: stage.algo, basePitch: Int($0.rounded())))
                    }
                }
            }
        }
    }
}
