import SwiftUI

struct InspectorView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @StateObject private var levelControl = ThrottledMixValue()
    @StateObject private var panControl = ThrottledMixValue()

    private var track: StepSequenceTrack {
        session.store.selectedTrack
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

                let trackID = track.id
                session.mutateTrack(id: trackID) { $0.pitches = parsed }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { track.name },
            set: { newValue in
                let trackID = track.id
                session.mutateTrack(id: trackID) { $0.name = newValue }
            }
        )
    }

    private var muteBinding: Binding<Bool> {
        Binding(
            get: { track.mix.isMuted },
            set: { newValue in
                // .fullEngineApply preserved: mute requires engine document-model rebuild.
                let trackID = track.id
                session.mutateTrack(id: trackID, impact: .fullEngineApply) { $0.mix.isMuted = newValue }
            }
        )
    }

    private var velocityBinding: Binding<Int> {
        Binding(
            get: { track.velocity },
            set: { newValue in
                let trackID = track.id
                session.mutateTrack(id: trackID) { $0.velocity = newValue }
            }
        )
    }

    private var gateLengthBinding: Binding<Int> {
        Binding(
            get: { track.gateLength },
            set: { newValue in
                let trackID = track.id
                session.mutateTrack(id: trackID) { $0.gateLength = newValue }
            }
        )
    }

    var body: some View {
        Form {
            Section("Track") {
                TextField("Name", text: nameBinding)
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

                Toggle("Mute", isOn: muteBinding)
            }

            Section("Generator") {
                Stepper(value: velocityBinding, in: 1...127) {
                    HStack {
                        Text("Velocity")
                        Spacer()
                        Text("\(track.velocity)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: gateLengthBinding, in: 1...16) {
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
           let group = session.store.group(for: track.id)
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
            var nextMix = track.mix
            nextMix.level = min(max(final, 0), 1)
            session.setTrackMix(trackID: track.id, mix: nextMix)
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
        session.setTrackMix(trackID: track.id, mix: liveMix)
    }

    private func handlePanEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !panControl.isDragging {
                panControl.begin(with: track.mix.clampedPan)
            }
        } else if let final = panControl.commit() {
            var nextMix = track.mix
            nextMix.pan = min(max(final, -1), 1)
            session.setTrackMix(trackID: track.id, mix: nextMix)
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
        session.setTrackMix(trackID: track.id, mix: liveMix)
    }
}

#Preview {
    InspectorPreview()
}

private struct InspectorPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        InspectorPreviewInner(document: $document)
    }
}

private struct InspectorPreviewInner: View {
    @Binding var document: SeqAIDocument
    @State private var session: SequencerDocumentSession

    init(document: Binding<SeqAIDocument>) {
        self._document = document
        self._session = State(initialValue: SequencerDocumentSession(document: document))
    }

    var body: some View {
        InspectorView(document: $document)
            .environment(session.engineController)
            .environment(session)
    }
}
