import SwiftUI

struct StepAlgoEditor: View {
    let stage: StepStage
    let onChange: (StepStage) -> Void

    @State private var showsSecondaryParameters = false

    var body: some View {
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

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showsSecondaryParameters.toggle()
                        }
                    } label: {
                        Image(systemName: showsSecondaryParameters ? "chevron.left.2" : "ellipsis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StudioTheme.mutedText)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                            .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(showsSecondaryParameters ? "Hide extra parameters" : "Show steps, offset, and pitch")
                    .accessibilityLabel(showsSecondaryParameters ? "Hide extra parameters" : "Show extra parameters")
                }
            }
        }
    }
}
