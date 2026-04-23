import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var recentVoices: [RecentVoice] = []
    @State private var showingAddDestinationSheet = false
    @State private var showingMacroPickerSheet = false
    @State private var showingPresetBrowser = false

    private var track: StepSequenceTrack {
        session.store.selectedTrack
    }

    private func log(_ message: String) {
        NSLog("[TrackDestinationEditor] \(message)")
    }

    private var currentWriteTarget: Project.DestinationWriteTarget {
        session.store.destinationWriteTarget(for: track.id)
    }

    private var editedDestination: Destination {
        session.store.resolvedDestination(for: track.id)
    }

    private var destinationSummary: DestinationSummary {
        DestinationSummary.make(for: editedDestination, in: session.store, trackID: track.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if editedDestination == .none {
                unsetState
            } else {
                setState
            }
        }
        .task(id: track.id) {
            refreshRecentVoices()
        }
        .sheet(isPresented: $showingAddDestinationSheet) {
            AddDestinationSheet(
                trackHasGroup: track.groupID != nil,
                audioInstrumentChoices: engineController.availableAudioInstruments,
                sampleLibrary: AudioSampleLibrary.shared
            ) { destination in
                applyAddedDestination(destination)
            }
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingMacroPickerSheet) {
            macroPickerSheet
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingPresetBrowser) {
            PresetBrowserSheet(
                auDisplayName: currentAudioInstrumentChoice.displayName,
                viewModel: makePresetBrowserViewModel()
            )
        }
    }

    private var unsetState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OUTPUT")
                .studioText(.eyebrow)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No destination")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Text("Set a destination to route notes for this track.")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Button("Add Destination") {
                    showingAddDestinationSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
            }
            .padding(14)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
    }

    private var setState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: destinationSummary.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StudioTheme.success)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(destinationSummary.typeLabel)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)

                    Text(destinationSummary.detail)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Button("Remove") {
                    clearDestination()
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )

            switch editedDestination {
            case .inheritGroup:
                inheritGroupEditor
            case .midi:
                midiEditor
            case .auInstrument:
                auEditor
            case .internalSampler:
                internalSamplerEditor
            case .sample:
                samplerEditor
            case .none:
                EmptyView()
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
        guard let group = session.store.group(for: track.id) else {
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
                            .studioText(.bodyEmphasis)
                            .foregroundStyle(StudioTheme.text)
                    }
                }

                DestinationField(title: "Transpose") {
                    Stepper(value: midiOffsetBinding, in: -24...24) {
                        Text(midiOffsetLabel)
                            .studioText(.bodyEmphasis)
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

                Button("Macros…") {
                    showingMacroPickerSheet = true
                }
                .buttonStyle(.bordered)

                Button("Presets…") {
                    engineController.prepareAudioUnit(for: track.id)
                    showingPresetBrowser = true
                }
                .buttonStyle(.bordered)

                if let stateBlob = currentAUStateBlob {
                    Text("State \(ByteCountFormatter.string(fromByteCount: Int64(stateBlob.count), countStyle: .file))")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    Text("No saved AU state yet")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Text("AU instruments are routed through the app mixer. Closing the plug-in window writes the latest AU fullState back into the document so reopen uses the tuned sound.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var samplerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SamplerDestinationWidget(
                destination: Binding(
                    get: { editedDestination },
                    set: { newDestination in
                        // .fullEngineApply preserved: sample destination change requires AU teardown.
                        session.setEditedDestination(newDestination, for: track.id)
                    }
                ),
                library: AudioSampleLibrary.shared,
                sampleEngine: engineController.sampleEngineSink,
                trackID: track.id,
                filterSettings: Binding(
                    get: { session.store.tracks.first(where: { $0.id == track.id })?.filter ?? .init() },
                    set: { newFilter in
                        // .scopedRuntime(.filter(...)) preserved: filter is a live scoped update.
                        session.setFilterSettings(newFilter, for: track.id)
                    }
                )
            )

            Button("Macros…") {
                showingMacroPickerSheet = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var internalSamplerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioPlaceholderTile(
                title: "Internal Sampler",
                detail: "This track defaults to the bundled internal sampler destination for its type. The audio-side sampler host is still a later plan.",
                accent: StudioTheme.amber
            )

            Button("Macros…") {
                showingMacroPickerSheet = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func makePresetBrowserViewModel() -> PresetBrowserSheetViewModel {
        let trackID = track.id
        return PresetBrowserSheetViewModel(
            read: { [engineController] in
                engineController.presetReadout(for: trackID)
            },
            load: { [engineController] descriptor in
                try engineController.loadPreset(descriptor, for: trackID)
            },
            commit: { stateBlob in
                let liveTarget = session.store.destinationWriteTarget(for: trackID)
                self.writeStateBlobAndRecord(stateBlob, target: liveTarget)
            }
        )
    }

    private func writeStateBlobAndRecord(_ stateBlob: Data?, target: Project.DestinationWriteTarget) {
        // Write the blob via the session typed method (.scopedRuntime(.auState(...))).
        session.writeStateBlob(stateBlob, target: target)

        // Record voice snapshot after the write (needs the updated destination value).
        switch target {
        case .track(let trackID):
            if let track = session.store.tracks.first(where: { $0.id == trackID }) {
                recordVoiceSnapshot(destination: track.destination.withoutTransientState)
            }
        case .group(let groupID):
            if let group = session.store.trackGroups.first(where: { $0.id == groupID }),
               let destination = group.sharedDestination
            {
                recordVoiceSnapshot(destination: destination.withoutTransientState)
            }
        }
    }

    private func applyAddedDestination(_ destination: Destination) {
        // .fullEngineApply preserved via session.setEditedDestination.
        session.setEditedDestination(destination, for: track.id)
        if case .auInstrument = destination {
            engineController.prepareAudioUnit(for: track.id)
        }
    }

    private func clearDestination() {
        AUWindowHost.shared.close(for: currentAUWindowKey)
        // .fullEngineApply preserved via session.setEditedDestination.
        session.setEditedDestination(.none, for: track.id)
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
            set: { choice in
                // Close any open editor window for this track/group before swapping the
                // component. Mirrors what clearDestination() does; prevents a stale window
                // surviving the AU teardown.
                AUWindowHost.shared.close(for: currentAUWindowKey)
                // .fullEngineApply preserved via session.setEditedDestination.
                session.setEditedDestination(
                    .auInstrument(componentID: choice.audioComponentID, stateBlob: nil),
                    for: track.id
                )
                log("audioInstrumentBinding set track=\(track.name) component=\(choice.audioComponentID.displayKey)")
                engineController.prepareAudioUnit(for: track.id)
                saveCurrentVoiceSnapshot()
            }
        )
    }

    private var midiPortBinding: Binding<MIDIEndpointName?> {
        Binding(
            get: { editedDestination.midiPort },
            set: { port in
                // .fullEngineApply preserved via session.setEditedMIDIPort.
                session.setEditedMIDIPort(port, for: track.id)
            }
        )
    }

    private var midiChannelBinding: Binding<Int> {
        Binding(
            get: { Int(editedDestination.midiChannel) + 1 },
            set: { channel in
                let clampedChannel = UInt8(max(0, min(15, channel - 1)))
                // .fullEngineApply preserved via session.setEditedMIDIChannel.
                session.setEditedMIDIChannel(clampedChannel, for: track.id)
            }
        )
    }

    private var midiOffsetBinding: Binding<Int> {
        Binding(
            get: { editedDestination.midiNoteOffset },
            set: { noteOffset in
                // .fullEngineApply preserved via session.setEditedMIDINoteOffset.
                session.setEditedMIDINoteOffset(noteOffset, for: track.id)
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
           let group = session.store.trackGroups.first(where: { $0.id == groupID })
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
            self.writeStateBlobAndRecord(stateBlob, target: {
                switch windowKey {
                case .group(let groupID):
                    return .group(groupID)
                case .track(let trackID):
                    return .track(trackID)
                }
            }())
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
        if case .auInstrument = voice.destination {
            // Close any open editor window before swapping the AU component. Avoids a
            // stale editor surviving the teardown of the current AU.
            AUWindowHost.shared.close(for: currentAUWindowKey)
        }
        // .fullEngineApply preserved via session.setEditedDestination.
        session.setEditedDestination(voice.destination, for: track.id)
        if case .auInstrument = voice.destination {
            engineController.prepareAudioUnit(for: track.id)
        }
        RecentVoicesStore.shared.touch(id: voice.id)
        refreshRecentVoices()
    }

    private func saveCurrentVoiceSnapshot() {
        guard let destination = session.store.voiceSnapshotDestination(for: track.id) else {
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
        session.store.selectedPhrase.name
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

    // MARK: - Macro picker sheet

    @ViewBuilder
    private var macroPickerSheet: some View {
        let trackID = track.id
        let builtinBindings = track.macros.filter {
            if case .builtin = $0.source { return true }
            return false
        }
        let auBindings = track.macros.filter {
            if case .auParameter = $0.source { return true }
            return false
        }
        let currentAddresses = Set(auBindings.compactMap { binding -> UInt64? in
            if case let .auParameter(address, _) = binding.source { return address }
            return nil
        })

        switch editedDestination {
        case .auInstrument:
            // Read the live parameter tree (main thread, called here in the view).
            let params: [AUParameterDescriptor] = {
                guard let host = engineController.audioInstrumentHost(for: trackID) else { return [] }
                return host.parameterReadout() ?? []
            }()
            MacroPickerSheet(
                mode: .auPicker(params: params),
                currentBindingAddresses: currentAddresses
            ) { added, removed in
                applyMacroDiff(added: added, removed: removed, trackID: trackID)
            }

        case .sample, .internalSampler:
            MacroPickerSheet(
                mode: .builtinReadOnly(bindings: builtinBindings),
                currentBindingAddresses: []
            ) { _, _ in }

        default:
            EmptyView()
        }
    }

    private func applyMacroDiff(added: [AUParameterDescriptor], removed: Set<UInt64>, trackID: UUID) {
        session.applyMacroDiff(added: added, removed: removed, trackID: trackID)
    }
}

private struct DestinationField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
