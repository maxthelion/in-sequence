import SwiftUI

struct DetailView: View {
    @Environment(EngineController.self) private var engineController

    var body: some View {
        VStack(spacing: 0) {
            TransportBar()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.quaternary)

            Divider()

            VStack(spacing: 16) {
                Image(systemName: engineController.isRunning ? "waveform.path.ecg" : "metronome")
                    .font(.system(size: 42))
                    .foregroundStyle(engineController.isRunning ? .primary : .secondary)

                Text(engineController.isRunning ? "Engine Running" : "Engine Ready")
                    .font(.title2)

                Text(engineController.statusSummary)
                    .foregroundStyle(.secondary)

                Text("Transport \(engineController.transportPosition) at \(Int(engineController.currentBPM.rounded())) BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    DetailView()
        .environment(EngineController(client: nil, endpoint: nil))
}
