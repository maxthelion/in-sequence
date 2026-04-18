import SwiftUI

struct TransportBar: View {
    @Environment(EngineController.self) private var engineController

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
            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 16, height: 16)
            }

            Divider().frame(height: 20)

            Text("BPM").foregroundStyle(.secondary).font(.caption)
            Text(String(format: "%.1f", engineController.currentBPM)).monospacedDigit()

            Divider().frame(height: 20)

            Text(engineController.transportPosition).monospacedDigit().foregroundStyle(.secondary)

            Spacer()
        }
    }
}

#Preview {
    TransportBar()
        .padding()
        .environment(EngineController(client: nil, endpoint: nil))
}
