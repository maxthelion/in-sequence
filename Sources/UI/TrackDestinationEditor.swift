import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @State private var recentVoices: [RecentVoice] = []

    private var track: StepSequenceTrack {
        document.project.selectedTrack
    }

    private func log(_ message: String) {
        NSLog("[TrackDestinationEditor] \(message)")
    }

    private var currentWriteTarget: Project.DestinationWriteTarget {
        document.project.destinationWriteTarget(for: track.id)
    }

    private var editedDestination: Destination {
        document.project.resolvedDestination(for: track.id)
    }

    private var currentChoice: TrackDestinationChoice {
        TrackDestinationChoice(destination: editedDestination)
    }

    private var supportsInternalSamplerChoice: Bool {
        if editedDestination.kind == .internalSampler {
            return true
        }
        return track.trackType == .slice
    }

    private var availableChoices: [TrackDestinationChoice] {
        var choices: [TrackDestinationChoice] = [.midiOut, .auInstrument, .sample]
        if supportsInternalSamplerChoice {
            choices.append(.internalSampler)
        }
        choices.append(.none)
        if track.groupID != nil {
            choices.insert(.inheritGroup, at: 0)
        }
        // Hide the sampler choice if the library is empty — there would be no sane default to assign.
        if AudioSampleLibrary.shared.samples.isEmpty {
            choices.removeAll(where: { $0 == .sample })
        }
        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            destinationSelector

            switch currentChoice {
            case .inheritGroup:
                inheritGroupEditor
            case .midiOut:
                midiEditor
            case .auInstrument:
                auEditor
            case .internalSampler:
                internalSamplerEditor
            case .sample:
                samplerEditor
            case .none:
                noneEditor
            }

            Text(editedDestination.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
        .task(id: track.id) {
            refreshRecentVoices()
        }
    }

    private var destinationSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OUTPUT")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(availableChoices) { destination in
                    Button {
                        applyDestinationChoice(destination)
                    } label: {
                        DestinationChoiceCard(
                            title: destination.label,
                            detail: destination.detail,
                            isSelected: currentChoice == destination
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inheritGroupEditor: some View {
        StudioPlaceholderTile(
            title: "Inherited from Group",
            detail: groupInheritanceDetail,
            accent: StudioTheme.success
        )
    }

    private var groupInheritanceDetail: String {
        guard let group = document.project.group(for: track.id) else {
            return "This track is marked as inheriting a group destination, but it is no longer attached to a group."
        }
        if let destination = group.sharedDestination {
            return "\(group.name) currently resolves to \(destination.summary)."
        }
        return "\(group.name) does not have a shared destination yet."
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
                    prepareAndOpenCurrentAudioUnitWindow()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)

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

    private var samplerEditor: some View {
        SamplerDestinationWidget(
            destination: Binding(
                get: { editedDestination },
                set: { document.project.setEditedDestination($0, for: track.id) }
            ),
            library: AudioSampleLibrary.shared,
            sampleEngine: engineController.sampleEngineSink
        )
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

    private func applyDestinationChoice(_ choice: TrackDestinationChoice) {
        if choice != .auInstrument {
            AUWindowHost.shared.close(for: currentAUWindowKey)
        }

        switch choice {
        case .inheritGroup:
            document.project.selectedTrack.destination = .inheritGroup
        case .midiOut:
            let nextDestination = editedDestination.kind == .midi
                ? editedDestination
                : Destination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
            document.project.setEditedDestination(nextDestination, for: track.id)
        case .auInstrument:
            document.project.setEditedDestination(
                .auInstrument(componentID: currentAudioInstrumentChoice.audioComponentID, stateBlob: nil),
                for: track.id
            )
            saveCurrentVoiceSnapshot()
        case .internalSampler:
            let defaultDestination = Project.defaultDestination(for: document.project.selectedTrack.trackType)
            if case .internalSampler = defaultDestination {
                document.project.setEditedDestination(defaultDestination, for: track.id)
            }
        case .sample:
            if case .sample = editedDestination {
                return
            }
            guard let seed = AudioSampleLibrary.shared.firstSample(in: .kick) else {
                // Library empty — no default. UI hides the choice in this case, so this branch
                // is defensive.
                return
            }
            document.project.setEditedDestination(
                .sample(sampleID: seed.id, settings: .default),
                for: track.id
            )
        case .none:
            document.project.setEditedDestination(.none, for: track.id)
        }
    }

    private var currentAudioInstrumentChoice: AudioInstrumentChoice {
        switch editedDestination {
        case let .auInstrument(componentID, _):
            return AudioInstrumentChoice.defaultChoices.first(where: { $0.audioComponentID == componentID })
                ?? AudioInstrumentChoice(audioComponentID: componentID)
        default:
            return .builtInSynth
        }
    }

    private var audioInstrumentBinding: Binding<AudioInstrumentChoice> {
        Binding(
            get: { currentAudioInstrumentChoice },
            set: {
                document.project.setEditedDestination(
                    .auInstrument(componentID: $0.audioComponentID, stateBlob: nil),
                    for: track.id
                )
                saveCurrentVoiceSnapshot()
            }
        )
    }

    private var midiPortBinding: Binding<MIDIEndpointName?> {
        Binding(
            get: { editedDestination.midiPort },
            set: { port in
                document.project.setEditedMIDIPort(port, for: track.id)
            }
        )
    }

    private var midiChannelBinding: Binding<Int> {
        Binding(
            get: { Int(editedDestination.midiChannel) + 1 },
            set: { channel in
                let clampedChannel = UInt8(max(0, min(15, channel - 1)))
                document.project.setEditedMIDIChannel(clampedChannel, for: track.id)
            }
        )
    }

    private var midiOffsetBinding: Binding<Int> {
        Binding(
            get: { editedDestination.midiNoteOffset },
            set: { noteOffset in
                document.project.setEditedMIDINoteOffset(noteOffset, for: track.id)
            }
        )
    }

    private var midiOffsetLabel: String {
        let value = midiOffsetBinding.wrappedValue
        return value == 0 ? "0 st" : "\(value > 0 ? "+" : "")\(value) st"
    }

    private var currentAUStateBlob: Data? {
        if case let .auInstrument(_, stateBlob) = editedDestination {
            return stateBlob
        }
        return nil
    }

    private var currentAUWindowKey: AUWindowHost.WindowKey {
        switch currentWriteTarget {
        case .track(let trackID):
            return .track(trackID)
        case .group(let groupID):
            return .group(groupID)
        }
    }

    private var currentAUWindowTitle: String {
        if case .group(let groupID) = currentAUWindowKey,
           let group = document.project.trackGroups.first(where: { $0.id == groupID })
        {
            return "\(group.name) (Shared)"
        }
        return track.name
    }

    private func openCurrentAudioUnitWindow() {
        let trackID = track.id
        let windowKey = currentAUWindowKey
        let windowTitle = currentAUWindowTitle

        guard let audioUnit = engineController.currentAudioUnit(for: trackID) else {
            log("openCurrentAudioUnitWindow no live audio unit track=\(track.name) trackID=\(trackID)")
            return
        }

        log("openCurrentAudioUnitWindow track=\(track.name) trackID=\(trackID) key=\(String(describing: windowKey))")

        AUWindowHost.shared.open(
            for: windowKey,
            presenter: audioUnit,
            title: windowTitle
        ) { stateBlob in
            switch windowKey {
            case .group(let groupID):
                guard let groupIndex = document.project.trackGroups.firstIndex(where: { $0.id == groupID }),
                      case let .auInstrument(componentID, _)? = document.project.trackGroups[groupIndex].sharedDestination
                else {
                    return
                }

                document.project.trackGroups[groupIndex].sharedDestination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                if let destination = document.project.trackGroups[groupIndex].sharedDestination {
                    recordVoiceSnapshot(destination: destination.withoutTransientState)
                }
            case .track(let trackID):
                guard let trackIndex = document.project.tracks.firstIndex(where: { $0.id == trackID }),
                      case let .auInstrument(componentID, _) = document.project.tracks[trackIndex].destination
                else {
                    return
                }

                document.project.tracks[trackIndex].destination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                recordVoiceSnapshot(destination: document.project.tracks[trackIndex].destination.withoutTransientState)
            }
        }
    }

    private func prepareAndOpenCurrentAudioUnitWindow() {
        let trackID = track.id
        let maxPollAttempts = 20
        let pollInterval = Duration.milliseconds(100)

        log("prepareAndOpenCurrentAudioUnitWindow track=\(track.name) trackID=\(trackID) destination=\(track.destination.summary)")
        engineController.prepareAudioUnit(for: trackID)

        Task { @MainActor in
            for _ in 0..<maxPollAttempts {
                if engineController.currentAudioUnit(for: trackID) != nil {
                    log("prepareAndOpenCurrentAudioUnitWindow live audio unit available")
                    openCurrentAudioUnitWindow()
                    return
                }
                try? await Task.sleep(for: pollInterval)
            }
            log("prepareAndOpenCurrentAudioUnitWindow timed out waiting for live audio unit")
        }
    }

    private func recallRecentVoice(_ voice: RecentVoice) {
        document.project.setEditedDestination(voice.destination, for: track.id)
        RecentVoicesStore.shared.touch(id: voice.id)
        refreshRecentVoices()
    }

    private func saveCurrentVoiceSnapshot() {
        guard let destination = document.project.voiceSnapshotDestination(for: track.id) else {
            return
        }
        recordVoiceSnapshot(destination: destination)
    }

    private func recordVoiceSnapshot(destination: Destination) {
        switch destination {
        case .none, .inheritGroup:
            return
        case .midi, .auInstrument, .internalSampler, .sample:
            break
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
        refreshRecentVoices()
    }

    private var phraseSummary: String {
        document.project.selectedPhrase.name
    }

    private func refreshRecentVoices() {
        recentVoices = RecentVoicesStore.shared.load().filter {
            switch $0.destination {
            case .none, .inheritGroup:
                return false
            case .midi, .auInstrument, .internalSampler, .sample:
                return true
            }
        }
    }
}

private enum TrackDestinationChoice: String, CaseIterable, Identifiable {
    case inheritGroup
    case midiOut
    case auInstrument
    case internalSampler
    case sample
    case none

    var id: String { rawValue }

    init(destination: Destination) {
        switch destination {
        case .inheritGroup:
            self = .inheritGroup
        case .midi:
            self = .midiOut
        case .auInstrument:
            self = .auInstrument
        case .internalSampler:
            self = .internalSampler
        case .sample:
            self = .sample
        case .none:
            self = .none
        }
    }

    var label: String {
        switch self {
        case .inheritGroup:
            return "Inherit Group"
        case .midiOut:
            return "Virtual MIDI Out"
        case .auInstrument:
            return "AU Instrument"
        case .internalSampler:
            return "Internal Sampler"
        case .sample:
            return "Sampler"
        case .none:
            return "No Default Output"
        }
    }

    var detail: String {
        switch self {
        case .inheritGroup:
            return "Follow the shared destination owned by this track's group"
        case .midiOut:
            return "Send note data to a MIDI endpoint"
        case .auInstrument:
            return "Host an Audio Unit instrument in-app"
        case .internalSampler:
            return "Play through the built-in sampler path"
        case .sample:
            return "Play one-shot sample files"
        case .none:
            return "No sink unless routes handle the notes"
        }
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

private struct DestinationChoiceCard: View {
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(
            (isSelected ? StudioTheme.success.opacity(0.14) : Color.white.opacity(0.03)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? StudioTheme.success.opacity(0.6) : StudioTheme.border, lineWidth: 1)
        )
    }
}
