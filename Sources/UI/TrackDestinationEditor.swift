import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var recentVoices: [RecentVoice] {
        RecentVoicesStore.shared.load().filter {
            if case .none = $0.destination {
                return false
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Output", selection: trackOutputBinding) {
                ForEach(TrackOutputDestination.allCases, id: \.self) { destination in
                    Text(destination.label).tag(destination)
                }
            }
            .pickerStyle(.segmented)

            switch track.output {
            case .midiOut:
                midiEditor
            case .auInstrument:
                auEditor
            case .internalSampler:
                internalSamplerEditor
            case .none:
                noneEditor
            }

            Text(track.defaultDestination.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var midiEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            DestinationField(title: "Destination") {
                Picker("Destination", selection: midiPortBinding) {
                    Text("Unassigned").tag(Optional<MIDIEndpointName>.none)
                    ForEach(engineController.availableMIDIDestinationNames, id: \.self) { endpoint in
                        Text(endpoint.displayName).tag(Optional(endpoint))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                DestinationField(title: "Channel") {
                    Stepper(value: midiChannelBinding, in: 1...16) {
                        Text("Ch \(midiChannelBinding.wrappedValue)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                    }
                }

                DestinationField(title: "Transpose") {
                    Stepper(value: midiOffsetBinding, in: -24...24) {
                        Text(midiOffsetLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                    }
                }
            }
        }
    }

    private var auEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VoicePickerView(
                title: "Voice",
                choices: engineController.availableAudioInstruments,
                recentVoices: recentVoices,
                selectedInstrument: audioInstrumentBinding
            ) { voice in
                recallRecentVoice(voice)
            } onSaveCurrent: {
                saveCurrentVoiceSnapshot()
            }

            HStack(spacing: 10) {
                Button("Edit Plug-in Window") {
                    openCurrentAudioUnitWindow()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
                .disabled(engineController.currentAudioUnit(for: track.id) == nil)

                if let stateBlob = currentAUStateBlob {
                    Text("State \(ByteCountFormatter.string(fromByteCount: Int64(stateBlob.count), countStyle: .file))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    Text("No saved AU state yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Text("AU instruments are routed through the app mixer. Closing the plug-in window writes the latest AU fullState back into the document so reopen uses the tuned sound.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var internalSamplerEditor: some View {
        StudioPlaceholderTile(
            title: "Internal Sampler",
            detail: "This track defaults to the bundled internal sampler destination for its type. The audio-side sampler host is still a later plan.",
            accent: StudioTheme.amber
        )
    }

    private var noneEditor: some View {
        StudioPlaceholderTile(
            title: "Routing-Only Track",
            detail: "This track has no default sink. It will still play if one or more project routes fan its notes to another track, endpoint, or chord-context lane.",
            accent: StudioTheme.violet
        )
    }

    private var trackOutputBinding: Binding<TrackOutputDestination> {
        Binding(
            get: { document.model.selectedTrack.output },
            set: {
                if $0 != .auInstrument {
                    AUWindowHost.shared.close(for: track.id)
                }
                document.model.selectedTrack.output = $0
                if $0 == .auInstrument {
                    recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
                }
            }
        )
    }

    private var audioInstrumentBinding: Binding<AudioInstrumentChoice> {
        Binding(
            get: { document.model.selectedTrack.audioInstrument },
            set: {
                document.model.selectedTrack.audioInstrument = $0
                recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
            }
        )
    }

    private var midiPortBinding: Binding<MIDIEndpointName?> {
        Binding(
            get: { document.model.selectedTrack.midiPortName },
            set: { document.model.selectedTrack.setMIDIPort($0) }
        )
    }

    private var midiChannelBinding: Binding<Int> {
        Binding(
            get: { Int(document.model.selectedTrack.midiChannel) + 1 },
            set: { document.model.selectedTrack.setMIDIChannel(UInt8(max(0, min(15, $0 - 1)))) }
        )
    }

    private var midiOffsetBinding: Binding<Int> {
        Binding(
            get: { document.model.selectedTrack.midiNoteOffset },
            set: { document.model.selectedTrack.setMIDINoteOffset($0) }
        )
    }

    private var midiOffsetLabel: String {
        let value = midiOffsetBinding.wrappedValue
        return value == 0 ? "0 st" : "\(value > 0 ? "+" : "")\(value) st"
    }

    private var currentAUStateBlob: Data? {
        if case let .auInstrument(_, stateBlob) = track.defaultDestination {
            return stateBlob
        }
        return nil
    }

    private func openCurrentAudioUnitWindow() {
        guard let audioUnit = engineController.currentAudioUnit(for: track.id) else {
            return
        }

        AUWindowHost.shared.open(
            for: track.id,
            presenter: audioUnit,
            title: track.name
        ) { stateBlob in
            guard let trackIndex = document.model.tracks.firstIndex(where: { $0.id == track.id }),
                  case let .auInstrument(componentID, _) = document.model.tracks[trackIndex].defaultDestination
            else {
                return
            }

            document.model.tracks[trackIndex].voicing.setDefault(.auInstrument(componentID: componentID, stateBlob: stateBlob))
            recordVoiceSnapshot(destination: document.model.tracks[trackIndex].defaultDestination)
        }
    }

    private func recallRecentVoice(_ voice: RecentVoice) {
        document.model.selectedTrack.voicing.setDefault(voice.destination)
        RecentVoicesStore.shared.touch(id: voice.id)
    }

    private func saveCurrentVoiceSnapshot() {
        recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
    }

    private func recordVoiceSnapshot(destination: Destination) {
        guard destination != .none else {
            return
        }

        let existingID = RecentVoicesStore.shared.load().first(where: { $0.destination == destination })?.id ?? UUID()
        let voice = RecentVoice(
            id: existingID,
            name: track.name,
            destination: destination,
            projectOrigin: phraseSummary
        )
        RecentVoicesStore.shared.record(voice)
        RecentVoicesStore.shared.prune()
    }

    private var phraseSummary: String {
        document.model.selectedPhrase.name
    }
}

private struct DestinationField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
