import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private func log(_ message: String) {
        NSLog("[TrackDestinationEditor] \(message)")
    }

    private var recentVoices: [RecentVoice] {
        RecentVoicesStore.shared.load().filter {
            switch $0.destination {
            case .none, .inheritGroup:
                return false
            case .midi, .auInstrument, .internalSampler:
                return true
            }
        }
    }

    private var currentChoice: TrackDestinationChoice {
        switch track.destination {
        case .inheritGroup:
            return .inheritGroup
        case .midi:
            return .midiOut
        case .auInstrument:
            return .auInstrument
        case .internalSampler:
            return .internalSampler
        case .none:
            return .none
        }
    }

    private var availableChoices: [TrackDestinationChoice] {
        var choices: [TrackDestinationChoice] = [.midiOut, .auInstrument, .internalSampler, .none]
        if track.groupID != nil {
            choices.insert(.inheritGroup, at: 0)
        }
        return choices
    }

    private var resolvedDestination: Destination {
        if case .inheritGroup = track.destination,
           let group = document.model.group(for: track.id),
           let sharedDestination = group.sharedDestination
        {
            return sharedDestination
        }

        return track.destination
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
            case .none:
                noneEditor
            }

            Text(resolvedDestination.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
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
        guard let group = document.model.group(for: track.id) else {
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
            document.model.selectedTrack.destination = .inheritGroup
        case .midiOut:
            let port: MIDIEndpointName?
            let channel: UInt8
            let noteOffset: Int
            if case let .midi(existingPort, existingChannel, existingOffset) = track.destination {
                port = existingPort
                channel = existingChannel
                noteOffset = existingOffset
            } else {
                port = .sequencerAIOut
                channel = 0
                noteOffset = 0
            }
            document.model.selectedTrack.destination = .midi(port: port, channel: channel, noteOffset: noteOffset)
        case .auInstrument:
            document.model.selectedTrack.destination = .auInstrument(componentID: currentAudioInstrumentChoice.audioComponentID, stateBlob: nil)
            recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
        case .internalSampler:
            let defaultDestination = SeqAIDocumentModel.defaultDestination(for: document.model.selectedTrack.trackType)
            if case .internalSampler = defaultDestination {
                document.model.selectedTrack.destination = defaultDestination
            } else {
                document.model.selectedTrack.destination = .none
            }
        case .none:
            document.model.selectedTrack.destination = .none
        }
    }

    private var currentAudioInstrumentChoice: AudioInstrumentChoice {
        switch resolvedDestination {
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
                document.model.selectedTrack.destination = .auInstrument(componentID: $0.audioComponentID, stateBlob: nil)
                recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
            }
        )
    }

    private var midiPortBinding: Binding<MIDIEndpointName?> {
        Binding(
            get: {
                if case let .midi(port, _, _) = document.model.selectedTrack.destination {
                    return port
                }
                return nil
            },
            set: { port in
                let channel = UInt8(max(0, min(15, midiChannelBinding.wrappedValue - 1)))
                let offset = midiOffsetBinding.wrappedValue
                document.model.selectedTrack.destination = .midi(port: port, channel: channel, noteOffset: offset)
            }
        )
    }

    private var midiChannelBinding: Binding<Int> {
        Binding(
            get: {
                if case let .midi(_, channel, _) = document.model.selectedTrack.destination {
                    return Int(channel) + 1
                }
                return 1
            },
            set: { channel in
                let clampedChannel = UInt8(max(0, min(15, channel - 1)))
                let port = midiPortBinding.wrappedValue
                let offset = midiOffsetBinding.wrappedValue
                document.model.selectedTrack.destination = .midi(port: port, channel: clampedChannel, noteOffset: offset)
            }
        )
    }

    private var midiOffsetBinding: Binding<Int> {
        Binding(
            get: {
                if case let .midi(_, _, noteOffset) = document.model.selectedTrack.destination {
                    return noteOffset
                }
                return 0
            },
            set: { noteOffset in
                let port = midiPortBinding.wrappedValue
                let channel = UInt8(max(0, min(15, midiChannelBinding.wrappedValue - 1)))
                document.model.selectedTrack.destination = .midi(port: port, channel: channel, noteOffset: noteOffset)
            }
        )
    }

    private var midiOffsetLabel: String {
        let value = midiOffsetBinding.wrappedValue
        return value == 0 ? "0 st" : "\(value > 0 ? "+" : "")\(value) st"
    }

    private var currentAUStateBlob: Data? {
        if case let .auInstrument(_, stateBlob) = resolvedDestination {
            return stateBlob
        }
        return nil
    }

    private var currentAUWindowKey: AUWindowHost.WindowKey {
        if case .inheritGroup = track.destination,
           let groupID = track.groupID
        {
            return .group(groupID)
        }
        return .track(track.id)
    }

    private var currentAUWindowTitle: String {
        if case .group(let groupID) = currentAUWindowKey,
           let group = document.model.trackGroups.first(where: { $0.id == groupID })
        {
            return "\(group.name) (Shared)"
        }
        return track.name
    }

    private func openCurrentAudioUnitWindow() {
        guard let audioUnit = engineController.currentAudioUnit(for: track.id) else {
            log("openCurrentAudioUnitWindow no live audio unit track=\(track.name) trackID=\(track.id)")
            return
        }

        log("openCurrentAudioUnitWindow track=\(track.name) trackID=\(track.id) key=\(String(describing: currentAUWindowKey))")

        AUWindowHost.shared.open(
            for: currentAUWindowKey,
            presenter: audioUnit,
            title: currentAUWindowTitle
        ) { stateBlob in
            switch currentAUWindowKey {
            case .group(let groupID):
                guard let groupIndex = document.model.trackGroups.firstIndex(where: { $0.id == groupID }),
                      case let .auInstrument(componentID, _)? = document.model.trackGroups[groupIndex].sharedDestination
                else {
                    return
                }

                document.model.trackGroups[groupIndex].sharedDestination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                if let destination = document.model.trackGroups[groupIndex].sharedDestination {
                    recordVoiceSnapshot(destination: destination)
                }
            case .track(let trackID):
                guard let trackIndex = document.model.tracks.firstIndex(where: { $0.id == trackID }),
                      case let .auInstrument(componentID, _) = document.model.tracks[trackIndex].defaultDestination
                else {
                    return
                }

                document.model.tracks[trackIndex].destination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                recordVoiceSnapshot(destination: document.model.tracks[trackIndex].defaultDestination)
            }
        }
    }

    private func prepareAndOpenCurrentAudioUnitWindow() {
        log("prepareAndOpenCurrentAudioUnitWindow track=\(track.name) trackID=\(track.id) destination=\(track.destination.summary)")
        engineController.prepareAudioUnit(for: track.id)

        Task { @MainActor in
            for _ in 0..<20 {
                if engineController.currentAudioUnit(for: track.id) != nil {
                    log("prepareAndOpenCurrentAudioUnitWindow live audio unit available")
                    openCurrentAudioUnitWindow()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            log("prepareAndOpenCurrentAudioUnitWindow timed out waiting for live audio unit")
        }
    }

    private func recallRecentVoice(_ voice: RecentVoice) {
        document.model.selectedTrack.destination = voice.destination
        RecentVoicesStore.shared.touch(id: voice.id)
    }

    private func saveCurrentVoiceSnapshot() {
        recordVoiceSnapshot(destination: document.model.selectedTrack.defaultDestination)
    }

    private func recordVoiceSnapshot(destination: Destination) {
        switch destination {
        case .none, .inheritGroup:
            return
        case .midi, .auInstrument, .internalSampler:
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
    }

    private var phraseSummary: String {
        document.model.selectedPhrase.name
    }
}

private enum TrackDestinationChoice: String, CaseIterable, Identifiable {
    case inheritGroup
    case midiOut
    case auInstrument
    case internalSampler
    case none

    var id: String { rawValue }

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
