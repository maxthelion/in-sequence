import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var showingAddDestinationSheet = false
    @State private var showingMacroPickerSheet = false
    @State private var showingPresetBrowser = false
    @State private var macroSlotPickerRequest: MacroSlotPickerRequest?
    @State private var presetReadoutState: PresetReadout?
    @State private var presetReadoutGeneration: UInt64 = 0
    @State private var presetLoadFailed = false
    @State private var presetStepInFlight = false
    @State private var macroSlotFull = false

    private struct MacroSlotPickerRequest: Identifiable {
        let slotIndex: Int
        var id: Int { slotIndex }
    }

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
        .sheet(item: $macroSlotPickerRequest) { request in
            SingleMacroSlotPickerSheet(
                slotIndex: request.slotIndex,
                currentBindingAddresses: currentAUMacroAddresses,
                readParameters: {
                    engineController.audioInstrumentHost(for: track.id)?.parameterReadout()
                }
            ) { descriptor in
                assignMacro(descriptor, to: request.slotIndex)
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .task(id: presetReadoutRefreshKey) {
            refreshPresetReadout()
        }
        .onChange(of: showingPresetBrowser) { _, isPresented in
            refreshPresetReadout(prepareIfNeeded: isPresented)
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
            switch editedDestination {
            case .inheritGroup:
                VStack(alignment: .leading, spacing: 14) {
                    destinationCard
                    inheritGroupEditor
                }
            case .midi:
                VStack(alignment: .leading, spacing: 14) {
                    destinationCard
                    midiEditor
                }
            case .auInstrument:
                auEditor
            case .internalSampler:
                VStack(alignment: .leading, spacing: 14) {
                    destinationCard
                    internalSamplerEditor
                }
            case .sample:
                samplerEditor
            case .none:
                EmptyView()
            }
        }
    }

    private var destinationCard: some View {
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentAudioInstrumentChoice.displayName)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("AU destination")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 12)

                presetSelectorButton

                compactIconButton(
                    systemName: "slider.horizontal.3",
                    help: "Open plug-in window"
                ) {
                    prepareAndOpenCurrentAudioUnitWindow()
                }

                compactIconButton(
                    systemName: "xmark",
                    help: "Remove this AU destination before choosing another one"
                ) {
                    clearDestination()
                }
            }
            .padding(14)

            Divider()
                .overlay(StudioTheme.border.opacity(0.7))

            // Fixed-width slot row: M1…M8 always occupy the same horizontal position
            // so muscle memory for slot positions is preserved. Scrollable if the
            // inspector column is too narrow.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(auMacroSlots) { slot in
                        AUMacroSlotKnob(
                            slotIndex: slot.slotIndex,
                            binding: slot.binding,
                            value: slot.binding.map { macroValue(for: $0) },
                            onAssign: {
                                prepareAndPresentMacroSlotPicker(slotIndex: slot.slotIndex)
                            },
                            onChange: { newValue in
                                guard let binding = slot.binding else {
                                    return
                                }
                                session.setMacroLayerDefault(
                                    value: newValue,
                                    bindingID: binding.id,
                                    trackID: track.id
                                )
                            },
                            onRemove: slot.binding.map { binding in
                                {
                                    removeMacroSlot(bindingID: binding.id)
                                }
                            }
                        )
                        .frame(width: 68)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 12)

            if macroSlotFull {
                Text("All macro slots are full")
                    .studioText(.label)
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: macroSlotFull)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var presetSelectorButton: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Preset")
                        .studioText(.eyebrow)
                        .tracking(0.7)
                        .foregroundStyle(StudioTheme.mutedText)
                    if presetLoadFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.8))
                            .accessibilityLabel("Preset failed to load")
                    }
                }

                Text(currentPresetDisplayName)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                engineController.prepareAudioUnit(for: track.id)
                showingPresetBrowser = true
            }

            VStack(spacing: 2) {
                presetStepButton(systemName: "chevron.up", direction: .previous)
                presetStepButton(systemName: "chevron.down", direction: .next)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 170, alignment: .leading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
        .overlay(
            Capsule()
                .stroke(presetLoadFailed ? Color.red.opacity(0.5) : StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
        .help(currentPresetSupportingText)
    }

    private func presetStepButton(
        systemName: String,
        direction: PresetStepper.Direction
    ) -> some View {
        Button {
            stepPreset(direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(canStepPreset(direction) ? StudioTheme.text : StudioTheme.mutedText.opacity(0.6))
                .frame(width: 18, height: 12)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStepPreset(direction) || presetStepInFlight)
    }

    private func canStepPreset(_ direction: PresetStepper.Direction) -> Bool {
        guard let readout = currentPresetReadout else {
            return false
        }
        return PresetStepper.target(from: readout, direction: direction) != nil
    }

    private func stepPreset(_ direction: PresetStepper.Direction) {
        guard !presetStepInFlight,
              let readout = currentPresetReadout,
              let descriptor = PresetStepper.target(from: readout, direction: direction)
        else {
            return
        }

        engineController.prepareAudioUnit(for: track.id)
        presetStepInFlight = true
        presetLoadFailed = false

        Task { @MainActor in
            defer { presetStepInFlight = false }
            do {
                let blob = try engineController.loadPreset(descriptor, for: track.id)
                writeStateBlobAndRecord(blob, target: currentWriteTarget)
                presetReadoutState = PresetReadout(
                    factory: readout.factory,
                    user: readout.user,
                    currentID: descriptor.id
                )
                refreshPresetReadout()
            } catch {
                log("stepPreset failed direction=\(direction) error=\(error)")
                presetLoadFailed = true
            }
        }
    }

    private func compactIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(
                    Circle()
                        .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var auMacroBindings: [TrackMacroBinding] {
        track.macros.filter {
            if case .auParameter = $0.source {
                return true
            }
            return false
        }
        .sorted { $0.slotIndex < $1.slotIndex }
    }

    private var auMacroSlots: [AUMacroSlot] {
        (0..<8).map { slotIndex in
            AUMacroSlot(
                slotIndex: slotIndex,
                binding: auMacroBindings.first(where: { $0.slotIndex == slotIndex })
            )
        }
    }

    private var currentAUMacroAddresses: Set<UInt64> {
        Set(auMacroBindings.compactMap { binding in
            if case let .auParameter(address, _) = binding.source {
                return address
            }
            return nil
        })
    }

    private var currentPresetReadout: PresetReadout? {
        presetReadoutState
    }

    private var presetReadoutRefreshKey: String {
        // Use the generation counter (not Data.hashValue which can collide) so
        // every call to refreshPresetReadout() produces a unique key and the
        // .task(id:) block fires reliably.
        switch editedDestination {
        case let .auInstrument(componentID, _):
            return "\(track.id.uuidString):\(componentID):\(presetReadoutGeneration)"
        default:
            return "\(track.id.uuidString):none:\(presetReadoutGeneration)"
        }
    }

    private func refreshPresetReadout(prepareIfNeeded: Bool = false) {
        guard case .auInstrument = editedDestination else {
            presetReadoutGeneration &+= 1
            presetReadoutState = nil
            return
        }

        let trackID = track.id
        let generation = presetReadoutGeneration &+ 1
        presetReadoutGeneration = generation

        if prepareIfNeeded {
            engineController.prepareAudioUnit(for: trackID)
        }

        requestPresetReadout(
            trackID: trackID,
            generation: generation,
            attemptsRemaining: 12
        )
    }

    private func requestPresetReadout(
        trackID: UUID,
        generation: UInt64,
        attemptsRemaining: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let readout = engineController.presetReadout(for: trackID)

            Task { @MainActor in
                guard generation == presetReadoutGeneration else {
                    return
                }

                guard case .auInstrument = editedDestination,
                      track.id == trackID
                else {
                    presetReadoutState = nil
                    return
                }

                if let readout {
                    presetReadoutState = readout
                    return
                }

                presetReadoutState = nil

                guard attemptsRemaining > 1 else {
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
                guard generation == presetReadoutGeneration else {
                    return
                }

                requestPresetReadout(
                    trackID: trackID,
                    generation: generation,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
        }
    }

    private var currentPresetDescriptor: AUPresetDescriptor? {
        guard let readout = currentPresetReadout,
              let currentID = readout.currentID
        else {
            return nil
        }

        return (readout.factory + readout.user).first(where: { $0.id == currentID })
    }

    private var currentPresetDisplayName: String {
        if let descriptor = currentPresetDescriptor {
            return descriptor.name
        }
        if let readout = currentPresetReadout {
            return readout.currentID == nil ? "No preset loaded" : "Current preset"
        }
        return "Preparing preset browser…"
    }

    private var currentPresetSupportingText: String {
        guard let readout = currentPresetReadout else {
            return "The plug-in is still preparing its preset list."
        }

        if let descriptor = currentPresetDescriptor {
            switch descriptor.kind {
            case .factory:
                return "Factory preset"
            case .user:
                return "User preset"
            }
        }

        if readout.currentID == nil {
            let presetCount = readout.factory.count + readout.user.count
            return presetCount == 0 ? "This plug-in exposes no presets." : "Browse the preset list for this AU."
        }

        return "Browse the preset list for this AU."
    }

    private func macroValue(for binding: TrackMacroBinding) -> Double {
        MacroKnobRowViewModel().currentValue(
            binding: binding,
            trackID: track.id,
            layers: session.store.layers
        )
    }

    private var samplerEditor: some View {
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
            ),
            onManageMacros: {
                showingMacroPickerSheet = true
            },
            onRemove: {
                clearDestination()
            }
        )
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

    private func prepareAndPresentMacroSlotPicker(slotIndex: Int) {
        engineController.prepareAudioUnit(for: track.id)
        macroSlotPickerRequest = MacroSlotPickerRequest(slotIndex: slotIndex)
    }

    private func assignMacro(_ parameter: AUParameterDescriptor, to slotIndex: Int) {
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: parameter.displayName,
            minValue: parameter.minValue,
            maxValue: parameter.maxValue,
            defaultValue: parameter.defaultValue,
            valueType: .scalar,
            source: .auParameter(address: parameter.address, identifier: parameter.identifier)
        )
        let accepted = session.assignAUMacroToSlot(descriptor, to: track.id, slotIndex: slotIndex)
        if !accepted {
            macroSlotFull = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                macroSlotFull = false
            }
        }
    }

    private func removeMacroSlot(bindingID: UUID) {
        session.removeAUMacroSlot(bindingID: bindingID, trackID: track.id)
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

// AUMacroSlot and AUMacroSlotKnob live in Sources/UI/TrackDestination/AUMacroSlotKnob.swift
