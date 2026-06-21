import SwiftUI

struct SliceInspectorView: View {
    let markerIndex: Int
    @Binding var marker: SliceMarker
    let sampleLengthFrames: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(markerIndex == 0 ? "Whole Sample" : "Slice \(markerIndex)")
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)

            HStack(spacing: 12) {
                SlicerControlField(title: "Start") {
                    frameStepper(value: Binding(
                        get: { marker.startFrame },
                        set: { marker.startFrame = min(max($0, 0), max(0, marker.endFrame - 1)) }
                    ))
                }
                SlicerControlField(title: "End") {
                    frameStepper(value: Binding(
                        get: { marker.endFrame },
                        set: { marker.endFrame = min(max($0, marker.startFrame + 1), sampleLengthFrames) }
                    ))
                }
            }

            HStack(spacing: 12) {
                SlicerControlField(title: "Gain") {
                    Slider(value: $marker.gain, in: -60...12)
                    Text(String(format: "%+.1f dB", marker.gain))
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                }
                SlicerControlField(title: "Timing") {
                    Slider(value: $marker.microTimingSteps, in: -0.5...0.5)
                    Text(String(format: "%+.2f step", marker.microTimingSteps))
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                }
            }

            HStack(spacing: 12) {
                Toggle("Reverse", isOn: $marker.reverse)
                    .toggleStyle(.switch)
                TextField("Tag", text: $marker.tag)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func frameStepper(value: Binding<Int64>) -> some View {
        Stepper(value: value, in: 0...max(sampleLengthFrames, 0), step: 128) {
            Text("\(value.wrappedValue)")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
        }
    }
}

struct SliceSamplePlayerParametersView: View {
    let markerIndex: Int
    let sampleName: String
    let sliceDetail: String
    let waveformBuckets: [Float]
    @Binding var mode: SliceTriggerStepMode
    @Binding var parameters: SliceTriggerStepParameters

    private let knobColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            parametersBody
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Side-by-side layout: the waveform sits on the left at a flexible width,
    /// the knob grid and playback controls stack on the right. ViewThatFits
    /// falls back to a vertical column when the row is too narrow.
    private var parametersBody: some View {
        ViewThatFits(in: .horizontal) {
            horizontalBody
            verticalBody
        }
    }

    private var horizontalBody: some View {
        HStack(alignment: .top, spacing: 0) {
            waveformSection
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)

            divider

            VStack(alignment: .leading, spacing: 0) {
                knobSection
                divider
                playbackSection
            }
            .frame(minWidth: 240, maxWidth: 360, alignment: .topLeading)
        }
    }

    private var verticalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            waveformSection
            divider
            knobSection
            divider
            playbackSection
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sampleName)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(markerIndex == 0 ? "Whole Sample" : "S\(markerIndex)") • \(sliceDetail)")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            StudioCircleIconButton(
                systemName: "play.fill",
                size: StudioMetrics.ControlSize.medium,
                help: "Preview slice",
                action: {}
            )
            .disabled(true)
        }
        .padding(StudioMetrics.Spacing.standard)
    }

    private var waveformSection: some View {
        WaveformView(buckets: waveformBuckets)
            .frame(minHeight: 60, maxHeight: .infinity)
            .padding(StudioMetrics.Spacing.snug)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip).stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            .padding(StudioMetrics.Spacing.comfortable)
    }

    private var knobSection: some View {
        LazyVGrid(columns: knobColumns, alignment: .leading, spacing: 16) {
            SamplerParameterKnob(
                label: "Start",
                normalizedValue: parameters.startTrim,
                displayText: percentLabel(parameters.startTrim)
            ) { normalized in
                updateStartTrim(normalized)
            }

            SamplerParameterKnob(
                label: "Length",
                normalizedValue: lengthNormalized,
                displayText: percentLabel(lengthNormalized)
            ) { normalized in
                updateLength(normalized)
            }

            SamplerParameterKnob(
                label: "Gain",
                normalizedValue: normalizedGain,
                displayText: gainLabel(parameters.gain)
            ) { normalized in
                updateDouble(\.gain, value: gainFromNormalized(normalized))
            }

            SamplerParameterKnob(
                label: "Pitch",
                normalizedValue: normalizedPitch,
                displayText: pitchLabel(parameters.pitch)
            ) { normalized in
                updateDouble(\.pitch, value: pitchFromNormalized(normalized))
            }

            SamplerParameterKnob(
                label: "Filter",
                normalizedValue: parameters.filter,
                displayText: percentLabel(parameters.filter)
            ) { normalized in
                updateDouble(\.filter, value: normalized)
            }

            SamplerParameterKnob(
                label: "Pan",
                normalizedValue: normalizedPan,
                displayText: panLabel(parameters.pan)
            ) { normalized in
                updateDouble(\.pan, value: panFromNormalized(normalized))
            }

            SamplerParameterKnob(
                label: "Attack",
                normalizedValue: parameters.attackMs / 100,
                displayText: msLabel(parameters.attackMs)
            ) { normalized in
                updateDouble(\.attackMs, value: Self.clamp(normalized, to: 0...1) * 100)
            }

            SamplerParameterKnob(
                label: "Release",
                normalizedValue: parameters.releaseMs / 200,
                displayText: msLabel(parameters.releaseMs)
            ) { normalized in
                updateDouble(\.releaseMs, value: Self.clamp(normalized, to: 0...1) * 200)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionRow(
                title: "Mode",
                options: SliceTriggerStepMode.allCases,
                selection: mode,
                titleForOption: { option in
                    switch option {
                    case .single: return "Single"
                    case .runFromHere: return "Run"
                    }
                },
                onSelect: { mode = $0 }
            )

            HStack(spacing: 10) {
                booleanButton(title: "Reverse", isOn: reverseBinding)
                booleanButton(title: "Choke", isOn: chokeBinding)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
    }

    private var divider: some View {
        Divider()
            .overlay(StudioTheme.border.opacity(0.7))
    }

    private var reverseBinding: Binding<Bool> { parameterBinding(\.reverse) }
    private var chokeBinding: Binding<Bool> { parameterBinding(\.choke) }

    private var lengthNormalized: Double {
        max(0.01, 1 - parameters.startTrim - parameters.endTrim)
    }

    private var normalizedGain: Double {
        Self.clamp((parameters.gain + 24) / 36, to: 0...1)
    }

    private var normalizedPitch: Double {
        Self.clamp((parameters.pitch + 12) / 24, to: 0...1)
    }

    private var normalizedPan: Double {
        Self.clamp((parameters.pan + 1) / 2, to: 0...1)
    }

    private func optionRow<Option: Hashable & Sendable>(
        title: String,
        options: [Option],
        selection: Option,
        titleForOption: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(titleForOption(option)) {
                        onSelect(option)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selection == option ? StudioTheme.text : StudioTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        (selection == option ? StudioTheme.violet.opacity(0.18) : Color.white.opacity(StudioOpacity.subtleFill)),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(selection == option ? StudioTheme.violet.opacity(0.7) : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                    )
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func booleanButton(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .studioText(.eyebrow)
                    .foregroundStyle(isOn.wrappedValue ? StudioTheme.background : StudioTheme.mutedText)
                Text(isOn.wrappedValue ? "On" : "Off")
                    .studioText(.labelBold)
                    .foregroundStyle(isOn.wrappedValue ? StudioTheme.background : StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isOn.wrappedValue ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func percentLabel(_ normalized: Double) -> String {
        "\(Int((Self.clamp(normalized, to: 0...1) * 100).rounded()))%"
    }

    private func gainLabel(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func pitchLabel(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    private func panLabel(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func msLabel(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func gainFromNormalized(_ normalized: Double) -> Double {
        (Self.clamp(normalized, to: 0...1) * 36) - 24
    }

    private func pitchFromNormalized(_ normalized: Double) -> Double {
        (Self.clamp(normalized, to: 0...1) * 24) - 12
    }

    private func panFromNormalized(_ normalized: Double) -> Double {
        (Self.clamp(normalized, to: 0...1) * 2) - 1
    }

    private func updateStartTrim(_ normalized: Double) {
        var next = parameters
        let maxStart = max(0, 1 - next.endTrim - 0.01)
        next.startTrim = min(max(normalized, 0), maxStart)
        parameters = next.clamped
    }

    private func updateLength(_ normalized: Double) {
        var next = parameters
        let length = Self.clamp(normalized, to: 0.01...1)
        next.endTrim = min(max(1 - next.startTrim - length, 0), 0.99)
        parameters = next.clamped
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func updateDouble(_ keyPath: WritableKeyPath<SliceTriggerStepParameters, Double>, value: Double) {
        var next = parameters
        next[keyPath: keyPath] = value
        parameters = next.clamped
    }

    private func parameterBinding(_ keyPath: WritableKeyPath<SliceTriggerStepParameters, Bool>) -> Binding<Bool> {
        Binding(
            get: { parameters[keyPath: keyPath] },
            set: { value in
                var next = parameters
                next[keyPath: keyPath] = value
                parameters = next.clamped
            }
        )
    }
}
