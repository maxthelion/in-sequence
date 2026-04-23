import SwiftUI

struct TrackDestinationEditor: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
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
                VStack(alignment: .leading, spacing: 14) {
                    destinationCard
                    samplerEditor
                }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("Plug-in Window") {
                    prepareAndOpenCurrentAudioUnitWindow()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)

                Button("Manage Macros") {
                    showingMacroPickerSheet = true
                }
                .buttonStyle(.bordered)
            }

            auInstrumentCard

            VStack(alignment: .leading, spacing: 10) {
                Text("CURRENT PRESET")
                    .studioText(.eyebrow)
                    .tracking(0.9)
                    .foregroundStyle(StudioTheme.mutedText)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentPresetDisplayName)
                            .studioText(.subtitle)
                            .foregroundStyle(StudioTheme.text)

                        Text(currentPresetSupportingText)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }

                    Spacer()

                    Button("Presets…") {
                        engineController.prepareAudioUnit(for: track.id)
                        showingPresetBrowser = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MACROS")
                            .studioText(.eyebrow)
                            .tracking(0.9)
                            .foregroundStyle(StudioTheme.mutedText)

                        Text(auMacroBindings.isEmpty ? "No macros selected yet." : "\(auMacroBindings.count) macros selected")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }

                    Spacer()

                    if auMacroBindings.isEmpty {
                        Button("Choose Macros") {
                            showingMacroPickerSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if auMacroBindings.isEmpty {
                    macroEmptyState
                } else {
                    auMacroGrid
                }
            }
            .padding(14)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
    }

    private var auInstrumentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StudioTheme.success)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("AU Instrument")
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)

                Text(currentAudioInstrumentChoice.displayName)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()

            Button {
                clearDestination()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Remove this AU destination before choosing another one")
        }
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var macroEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose AU parameters to expose as track macros. Once selected, they appear here as live controls.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)

            Button("Choose Macros") {
                showingMacroPickerSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.success)
        }
    }

    private var auMacroGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(auMacroBindings, id: \.id) { binding in
                DestinationMacroKnob(
                    binding: binding,
                    value: macroValue(for: binding)
                ) { newValue in
                    session.setMacroLayerDefault(
                        value: newValue,
                        bindingID: binding.id,
                        trackID: track.id
                    )
                }
            }
        }
    }

    private var auMacroBindings: [TrackMacroBinding] {
        track.macros.filter {
            if case .auParameter = $0.source {
                return true
            }
            return false
        }
    }

    private var currentPresetReadout: PresetReadout? {
        engineController.presetReadout(for: track.id)
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

private struct DestinationMacroKnob: View {
    let binding: TrackMacroBinding
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    private let knobSize: CGFloat = 44
    private let dragSensitivity: Double = 220

    init(binding: TrackMacroBinding, value: Double, onChange: @escaping (Double) -> Void) {
        self.binding = binding
        self.value = value
        self.onChange = onChange
        _displayValue = State(initialValue: value)
    }

    private var normalized: Double {
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        guard range > 0 else { return 0 }
        return (displayValue - binding.descriptor.minValue) / range
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border, lineWidth: 2)
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * normalized)
                    .stroke(StudioTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: knobSize - 6, height: knobSize - 6)
                    .rotationEffect(.degrees(-90))

                Text(shortLabel(displayValue))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = displayValue
                        }
                        let delta = -drag.translation.height / dragSensitivity
                        let range = binding.descriptor.maxValue - binding.descriptor.minValue
                        let nextValue = (dragStartValue ?? displayValue) + delta * range
                        displayValue = min(max(nextValue, binding.descriptor.minValue), binding.descriptor.maxValue)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        onChange(displayValue)
                    }
            )

            Text(binding.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: knobSize + 26)
        }
        .onChange(of: value) { _, newValue in
            if dragStartValue == nil {
                displayValue = newValue
            }
        }
    }

    private func shortLabel(_ value: Double) -> String {
        if binding.descriptor.maxValue > 10 {
            return "\(Int(value.rounded()))"
        }

        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
