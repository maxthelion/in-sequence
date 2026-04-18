import SwiftUI

struct InspectorView: View {
    @Binding var document: SeqAIDocument

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var pitchesText: Binding<String> {
        Binding(
            get: {
                track.pitches.map(String.init).joined(separator: ", ")
            },
            set: { newValue in
                let parsed = newValue
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (0...127).contains($0) }

                guard !parsed.isEmpty else {
                    return
                }

                document.model.selectedTrack.pitches = parsed
            }
        )
    }

    var body: some View {
        Form {
            Section("Track") {
                TextField("Name", text: $document.model.selectedTrack.name)
                TextField("Pitches", text: pitchesText)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated MIDI notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generator") {
                Stepper(value: $document.model.selectedTrack.velocity, in: 1...127) {
                    HStack {
                        Text("Velocity")
                        Spacer()
                        Text("\(track.velocity)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $document.model.selectedTrack.gateLength, in: 1...16) {
                    HStack {
                        Text("Gate Length")
                        Spacer()
                        Text("\(track.gateLength) ticks")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Summary") {
                LabeledContent("Active steps", value: "\(track.stepPattern.filter { $0 }.count)")
                LabeledContent("Pitch count", value: "\(track.pitches.count)")
                LabeledContent("Track ID", value: track.id.uuidString.prefix(8).description)
            }

            Spacer()
        }
        .frame(minWidth: 220)
    }
}

#Preview {
    InspectorPreview()
}

private struct InspectorPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        InspectorView(document: $document)
    }
}
