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
        HStack(spacing: 12) {
            Button {
                if engineController.isRunning {
                    engineController.stop()
                } else {
                    engineController.start()
                }
            } label: {
                Image(systemName: engineController.isRunning ? "stop.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .disabled(!engineController.canStart)

            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 16, height: 16)
            }
            .disabled(true)

            Divider().frame(height: 20)

            Text("BPM").foregroundStyle(.secondary).font(.caption)
            Stepper(value: bpmBinding, in: 40...300, step: 1) {
                Text(String(format: "%.0f", engineController.currentBPM))
                    .monospacedDigit()
            }
            .labelsHidden()
            Text(String(format: "%.0f", engineController.currentBPM)).monospacedDigit()

            Divider().frame(height: 20)

            Text(engineController.transportPosition).monospacedDigit().foregroundStyle(.secondary)
            Text(engineController.statusSummary)
                .foregroundStyle(.secondary)
                .font(.caption)
                .lineLimit(1)

            Spacer()
        }
    }
}

#Preview {
    TransportBar()
        .padding()
        .environment(EngineController(client: nil, endpoint: nil))
}
