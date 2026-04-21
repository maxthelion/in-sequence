import SwiftUI

struct InspectorView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @StateObject private var levelControl = ThrottledMixValue()
    @StateObject private var panControl = ThrottledMixValue()

    private var track: StepSequenceTrack {
        document.project.selectedTrack
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

                document.project.selectedTrack.pitches = parsed
            }
        )
    }

    var body: some View {
        Form {
            Section("Track") {
                TextField("Name", text: $document.project.selectedTrack.name)
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
                    Slider(
                        value: Binding(
                            get: { levelControl.rendered(committed: track.mix.clampedLevel) },
                            set: { updateLevel($0) }
                        ),
                        in: 0...1,
                        onEditingChanged: handleLevelEditingChanged
                    )
                    Text("\(Int((levelControl.rendered(committed: track.mix.clampedLevel) * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Pan")
                    Slider(
                        value: Binding(
                            get: { panControl.rendered(committed: track.mix.clampedPan) },
                            set: { updatePan($0) }
                        ),
                        in: -1...1,
                        onEditingChanged: handlePanEditingChanged
                    )
                    Text(panLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Toggle("Mute", isOn: $document.project.selectedTrack.mix.isMuted)
            }

            Section("Generator") {
                Stepper(value: $document.project.selectedTrack.velocity, in: 1...127) {
                    HStack {
                        Text("Velocity")
                        Spacer()
                        Text("\(track.velocity)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $document.project.selectedTrack.gateLength, in: 1...16) {
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
        let value = panControl.rendered(committed: track.mix.clampedPan)
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
           let group = document.project.group(for: track.id)
        {
            return group.sharedDestination?.summary ?? "Inherited from group"
        }
        return track.destination.summary
    }

    private func handleLevelEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !levelControl.isDragging {
                levelControl.begin(with: track.mix.clampedLevel)
            }
        } else if let final = levelControl.commit() {
            document.project.selectedTrack.mix.level = min(max(final, 0), 1)
        }
    }

    private func updateLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        if !levelControl.isDragging {
            levelControl.begin(with: track.mix.clampedLevel)
        }
        guard levelControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = clamped
        liveMix.pan = panControl.rendered(committed: track.mix.clampedPan)
        engineController.setMix(trackID: track.id, mix: liveMix)
    }

    private func handlePanEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !panControl.isDragging {
                panControl.begin(with: track.mix.clampedPan)
            }
        } else if let final = panControl.commit() {
            document.project.selectedTrack.mix.pan = min(max(final, -1), 1)
        }
    }

    private func updatePan(_ pan: Double) {
        let clamped = min(max(pan, -1), 1)
        if !panControl.isDragging {
            panControl.begin(with: track.mix.clampedPan)
        }
        guard panControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = levelControl.rendered(committed: track.mix.clampedLevel)
        liveMix.pan = clamped
        engineController.setMix(trackID: track.id, mix: liveMix)
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
