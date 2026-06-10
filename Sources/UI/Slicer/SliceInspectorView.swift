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
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
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
    @Binding var mode: SliceTriggerStepMode
    @Binding var parameters: SliceTriggerStepParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Parameters")
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)

                Spacer()

                Text(markerIndex == 0 ? "Whole Sample" : "S\(markerIndex)")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.violet)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Mode")
                        .studioText(.eyebrow)
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(width: 72, alignment: .leading)

                    Picker("Mode", selection: $mode) {
                        Text("Single").tag(SliceTriggerStepMode.single)
                        Text("Run").tag(SliceTriggerStepMode.runFromHere)
                    }
                    .pickerStyle(.segmented)
                }

                parameterRow(title: "Gain", value: gainBinding, range: -24...12) { value in
                    String(format: "%+.1f dB", value)
                }
                parameterRow(title: "Pitch", value: pitchBinding, range: -12...12) { value in
                    String(format: "%+.0f st", value)
                }
                parameterRow(title: "Start", value: startPercent, range: 0...99) { value in
                    "\(Int(value.rounded()))%"
                }
                parameterRow(title: "End", value: endPercent, range: 1...100) { value in
                    "\(Int(value.rounded()))%"
                }
                parameterRow(title: "Pan", value: panBinding, range: -1...1) { value in
                    String(format: "%+.2f", value)
                }
                parameterRow(title: "Filter", value: filterBinding, range: 0...1) { value in
                    "\(Int((value * 100).rounded()))%"
                }
                parameterRow(title: "Attack", value: attackBinding, range: 0...100) { value in
                    "\(Int(value.rounded())) ms"
                }
                parameterRow(title: "Release", value: releaseBinding, range: 0...200) { value in
                    "\(Int(value.rounded())) ms"
                }

                HStack(spacing: 10) {
                    booleanButton(title: "Reverse", isOn: reverseBinding)
                    booleanButton(title: "Choke", isOn: chokeBinding)
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.violet.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
    }

    private var gainBinding: Binding<Double> { parameterBinding(\.gain) }
    private var pitchBinding: Binding<Double> { parameterBinding(\.pitch) }
    private var panBinding: Binding<Double> { parameterBinding(\.pan) }
    private var filterBinding: Binding<Double> { parameterBinding(\.filter) }
    private var attackBinding: Binding<Double> { parameterBinding(\.attackMs) }
    private var releaseBinding: Binding<Double> { parameterBinding(\.releaseMs) }
    private var reverseBinding: Binding<Bool> { parameterBinding(\.reverse) }
    private var chokeBinding: Binding<Bool> { parameterBinding(\.choke) }

    private var startPercent: Binding<Double> {
        Binding(
            get: { parameters.startTrim * 100 },
            set: { value in
                var next = parameters
                let maxStart = max(0, 1 - next.endTrim - 0.01)
                next.startTrim = min(max(value / 100, 0), maxStart)
                parameters = next.clamped
            }
        )
    }

    private var endPercent: Binding<Double> {
        Binding(
            get: { (1 - parameters.endTrim) * 100 },
            set: { value in
                var next = parameters
                let endRatio = min(max(value / 100, next.startTrim + 0.01), 1)
                next.endTrim = min(max(1 - endRatio, 0), 0.99)
                parameters = next.clamped
            }
        )
    }

    private func parameterRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formatter: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 72, alignment: .leading)

            Slider(value: value, in: range)

            Text(formatter(value.wrappedValue))
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .frame(width: 58, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func booleanButton(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(isOn.wrappedValue ? "On" : "Off")
                    .studioText(.labelBold)
                    .foregroundStyle(isOn.wrappedValue ? StudioTheme.text : StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? StudioTheme.violet.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isOn.wrappedValue ? StudioTheme.violet.opacity(0.8) : StudioTheme.border.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func parameterBinding(_ keyPath: WritableKeyPath<SliceTriggerStepParameters, Double>) -> Binding<Double> {
        Binding(
            get: { parameters[keyPath: keyPath] },
            set: { value in
                var next = parameters
                next[keyPath: keyPath] = value
                parameters = next.clamped
            }
        )
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
