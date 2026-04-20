import SwiftUI

struct InspectorView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

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
                LabeledContent("Destination", value: destinationSummary)
                TextField("Pitches", text: pitchesText)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated MIDI notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mixer") {
                HStack {
                    Text("Level")
                    Slider(value: $document.model.selectedTrack.mix.level, in: 0...1)
                    Text("\(Int((track.mix.clampedLevel * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Pan")
                    Slider(value: $document.model.selectedTrack.mix.pan, in: -1...1)
                    Text(panLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Toggle("Mute", isOn: $document.model.selectedTrack.mix.isMuted)
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
                LabeledContent("Active steps", value: "\(track.activeStepCount)")
                LabeledContent("Accented steps", value: "\(track.accentedStepCount)")
                LabeledContent("Pitch count", value: "\(track.pitches.count)")
                LabeledContent("Level", value: "\(Int((track.mix.clampedLevel * 100).rounded()))%")
                LabeledContent("Track ID", value: track.id.uuidString.prefix(8).description)
            }

            Spacer()
        }
        .frame(minWidth: 220)
    }

    private var panLabel: String {
        let value = track.mix.clampedPan
        if value < -0.05 {
            return "L\(Int(abs(value) * 100))"
        }
        if value > 0.05 {
            return "R\(Int(value * 100))"
        }
        return "C"
    }

    private var destinationSummary: String {
        if case .inheritGroup = track.destination,
           let group = document.model.group(for: track.id)
        {
            return group.sharedDestination?.summary ?? "Inherited from group"
        }
        return track.destination.summary
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
