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
        .padding(12)
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
