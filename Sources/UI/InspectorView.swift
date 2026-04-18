import SwiftUI

struct InspectorView: View {
    @Binding var document: SeqAIDocument

    private var pitchesText: Binding<String> {
        Binding(
            get: {
                document.model.primaryTrack.pitches.map(String.init).joined(separator: ", ")
            },
            set: { newValue in
                let parsed = newValue
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (0...127).contains($0) }

                guard !parsed.isEmpty else {
                    return
                }

                document.model.primaryTrack.pitches = parsed
            }
        )
    }

    var body: some View {
        Form {
            Section("Track") {
                TextField("Name", text: $document.model.primaryTrack.name)
                TextField("Pitches", text: pitchesText)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated MIDI notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generator") {
                Stepper(value: $document.model.primaryTrack.velocity, in: 1...127) {
                    HStack {
                        Text("Velocity")
                        Spacer()
                        Text("\(document.model.primaryTrack.velocity)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $document.model.primaryTrack.gateLength, in: 1...16) {
                    HStack {
                        Text("Gate Length")
                        Spacer()
                        Text("\(document.model.primaryTrack.gateLength) ticks")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Summary") {
                LabeledContent("Active steps", value: "\(document.model.primaryTrack.stepPattern.filter { $0 }.count)")
                LabeledContent("Pitch count", value: "\(document.model.primaryTrack.pitches.count)")
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
