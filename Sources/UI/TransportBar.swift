import SwiftUI

struct TransportBar: View {
    @Environment(EngineController.self) private var engineController

    private var bpmBinding: Binding<Double> {
        Binding(
            get: { engineController.currentBPM },
            set: { engineController.setBPM($0) }
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if engineController.isRunning {
                    engineController.stop()
                } else {
                    engineController.start()
                }
            } label: {
                Image(systemName: engineController.isRunning ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(TransportButtonStyle(accent: engineController.isRunning ? StudioTheme.amber : StudioTheme.cyan))
            .disabled(!engineController.canStart)

            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(TransportButtonStyle(accent: StudioTheme.amber))
            .disabled(true)

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 26)

            Text("BPM")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Slider(value: bpmBinding, in: 40...300)
                .frame(width: 120)
                .tint(StudioTheme.cyan)

            Text(String(format: "%.0f", engineController.currentBPM))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 26)

            Text(engineController.transportPosition)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)

            Text(engineController.statusSummary)
                .foregroundStyle(StudioTheme.mutedText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035), in: Capsule())
        .overlay(
            Capsule()
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(StudioTheme.text)
            .padding(12)
            .background(accent.opacity(configuration.isPressed ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            )
    }
}

#Preview {
    TransportBar()
        .padding()
        .environment(EngineController(client: nil, endpoint: nil))
}
