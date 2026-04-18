import SwiftUI

struct DetailView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    var body: some View {
        VStack(spacing: 0) {
            TransportBar()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.quaternary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.model.primaryTrack.name)
                                    .font(.title2)
                                Text(engineController.isRunning ? "Engine Running" : "Engine Ready")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: engineController.isRunning ? "waveform.path.ecg" : "metronome")
                                .font(.system(size: 30))
                                .foregroundStyle(engineController.isRunning ? .primary : .secondary)
                        }

                        Text(engineController.statusSummary)
                            .foregroundStyle(.secondary)

                        Text("Transport \(engineController.transportPosition) at \(Int(engineController.currentBPM.rounded())) BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pattern")
                            .font(.headline)

                        StepGridView(steps: document.model.primaryTrack.stepPattern) { index in
                            toggleStep(at: index)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pitch Cycle")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(document.model.primaryTrack.pitches.enumerated()), id: \.offset) { index, pitch in
                                    Text("\(pitch)")
                                        .font(.body.monospacedDigit())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.quaternary, in: Capsule())
                                        .overlay(alignment: .topLeading) {
                                            Text("\(index + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .offset(x: -2, y: -12)
                                        }
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func toggleStep(at index: Int) {
        guard document.model.primaryTrack.stepPattern.indices.contains(index) else {
            return
        }
        document.model.primaryTrack.stepPattern[index].toggle()
    }
}

#Preview {
    DetailPreview()
}

private struct DetailPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        DetailView(document: $document)
            .environment(EngineController(client: nil, endpoint: nil))
    }
}
