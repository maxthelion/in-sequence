import SwiftUI

// Inline expanded-row accordion for the kit matrix (AC21): the row header,
// mini-tab bar, and the five mini-tabs (Steps/Clip, Sound, FX, Macros, Mixer)
// scoped to a member track. Split out of DrumKitMatrixView.swift as an
// extension; zero behavior change.

extension DrumKitMatrixView {
    // MARK: - Inline expanded-row detail panel (AC21)

    /// The inline detail panel that opens to the RIGHT of the part name when a
    /// row is expanded. Reuses the single-track detail surfaces, scoped to the
    /// member's track id: mini-tab bar + selected tab body.
    /// Kept compact: each tab body is its own helper so the type-checker never
    /// faces one giant view-builder expression.
    @ViewBuilder
    func expandedRowDetail(_ row: DrumKitMatrixModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            expandedRowTabBar
            expandedRowTabBody(row)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $expandedFXTarget) { target in
            expandedFXChooserSheet(memberID: target.memberID)
        }
        .sheet(item: $expandedMacroTarget) { target in
            SingleMacroSlotPickerSheet(
                slotIndex: target.slotIndex,
                currentBindingAddresses: memberAUMacroAddresses(target.memberID),
                readParameters: {
                    engineController.audioInstrumentHost(for: target.memberID)?.parameterReadout()
                }
            ) { descriptor in
                assignMemberMacro(descriptor, memberID: target.memberID, slotIndex: target.slotIndex)
            }
            .presentationBackground(.clear)
        }
    }

    var expandedRowTabBar: some View {
        StudioSegmentedControl(
            title: nil,
            selection: Binding(
                get: { expandedRowTab },
                set: { newValue in
                    expandedRowTab = newValue
                    postRenderedVisualState(isVisible: true)
                }
            ),
            segments: DrumKitRowTab.allCases.map { tab in
                StudioSegment(
                    title: tab.title,
                    value: tab,
                    accessibilityIdentifier: "kit-row-tab-\(tab.rawValue)",
                    accessibilityLabel: "Row tab \(tab.title)"
                )
            },
            accent: accent,
            layout: StudioSegmentedControl.Layout(
                fillsWidth: false,
                minWidth: 64,
                minHeight: 28,
                minimumScaleFactor: nil
            )
        )
    }

    @ViewBuilder
    func expandedRowTabBody(_ row: DrumKitMatrixModel.Row) -> some View {
        switch expandedRowTab {
        case .stepsClip:
            expandedStepsClipTab(row)
        case .sound:
            expandedSoundTab(row)
        case .fx:
            expandedFXTab(row)
        case .macros:
            expandedMacrosTab(row)
        case .mixer:
            expandedMixerTab(row)
        }
    }

    func memberTrack(_ memberID: UUID) -> StepSequenceTrack? {
        session.store.tracks.first { $0.id == memberID }
    }

    // MARK: Steps/Clip mini-tab (Clip ↔ Generator switch + grid / generator)

    /// Steps/Clip mini-tab (AC21). A Clip↔Generator switch for THIS member's
    /// active pattern slot, then the 16-step grid (clip) or a generator picker
    /// (+ modifier affordance) when in generator mode. Editing step content is
    /// allowed and does not change link state (AC19).
    @ViewBuilder
    func expandedStepsClipTab(_ row: DrumKitMatrixModel.Row) -> some View {
        let pageOffset = model.map { clampedPage($0) * Self.stepsPerBar } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            sourceModeSwitch(row)

            switch row.sourceMode {
            case .clip:
                expandedStepGrid(row: row, pageOffset: pageOffset)
            case .generator:
                expandedGeneratorBody(row)
            }
        }
    }

    func sourceModeSwitch(_ row: DrumKitMatrixModel.Row) -> some View {
        HStack(spacing: 8) {
            Text("SOURCE")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            StudioSegmentedControl(
                title: nil,
                selection: Binding(
                    get: { row.sourceMode },
                    set: { setMemberSourceMode(row: row, mode: $0) }
                ),
                segments: [TrackSourceMode.clip, .generator].map { mode in
                    StudioSegment(
                        title: mode.label,
                        value: mode,
                        accessibilityIdentifier: "kit-row-source-\(mode.rawValue)",
                        accessibilityLabel: "Source mode \(mode.label)"
                    )
                },
                accent: accent,
                layout: StudioSegmentedControl.Layout(
                    fillsWidth: false,
                    minWidth: 64,
                    minHeight: 26,
                    minimumScaleFactor: nil
                )
            )

            Spacer(minLength: 0)
        }
    }

    /// Switch THIS member's active pattern slot between clip and generator
    /// sources. Picks the first compatible pool entry; if none exists, the
    /// switch sets the slot's mode via an empty source ref so the UI still
    /// reflects the choice.
    func setMemberSourceMode(row: DrumKitMatrixModel.Row, mode: TrackSourceMode) {
        guard row.sourceMode != mode else { return }
        let slotIndex = row.patternSlotIndex
        guard let track = memberTrack(row.memberID) else { return }
        switch mode {
        case .clip:
            if let clip = session.store.clipPool.first(where: { $0.trackType == track.trackType }) {
                session.assignClipSource(clip.id, to: row.memberID, slotIndex: slotIndex)
            } else if let clip = session.store.clipPool.first {
                session.assignClipSource(clip.id, to: row.memberID, slotIndex: slotIndex)
            }
        case .generator:
            if let generator = session.store.generatorPool.first(where: { $0.trackType == track.trackType }) {
                session.assignGeneratorSource(generator.id, to: row.memberID, slotIndex: slotIndex)
            } else if let generator = session.store.generatorPool.first {
                session.assignGeneratorSource(generator.id, to: row.memberID, slotIndex: slotIndex)
            }
        }
        postRenderedVisualState(isVisible: true)
    }

    @ViewBuilder
    func expandedStepGrid(row: DrumKitMatrixModel.Row, pageOffset: Int) -> some View {
        switch row.content {
        case let .editable(_, _, steps):
            let states = (0..<Self.stepsPerBar).map { local -> StepVisualState in
                let absolute = pageOffset + local
                guard steps.indices.contains(absolute) else { return .off }
                return ClipNoteGridStepEditing.visualState(for: steps[absolute], lane: .main)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let model { barPager(model) }
                StepGridView(
                    stepStates: states,
                    indexOffset: pageOffset,
                    contentProvider: { index, _ in
                        expandedCellContent(steps: steps, index: index)
                    },
                    onValueDrag: selectedLayer == .steps ? nil : { index, fraction in
                        commitDrag(row: row, stepIndex: index, fraction: fraction)
                    },
                    advanceStep: { index in
                        commitTap(row: row, stepIndex: index)
                    }
                )
                .frame(maxWidth: .infinity)
            }
        case let .readOnly(_, detail, _):
            Text(detail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        case .generator:
            EmptyView()
        }
    }

    func expandedCellContent(steps: [ClipStep], index: Int) -> StepCellContent {
        guard steps.indices.contains(index) else {
            return selectedLayer == .steps ? .toggle : .valueBar(fraction: 0)
        }
        switch selectedLayer {
        case .steps:
            return .toggle
        case .velocity:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.velocityValue(for: steps[index], lane: .main) / 127.0
            )
        case .chance:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.chanceValue(for: steps[index], lane: .main)
            )
        }
    }

    @ViewBuilder
    func expandedGeneratorBody(_ row: DrumKitMatrixModel.Row) -> some View {
        let detail: String = {
            if case let .generator(d) = row.content { return d }
            return "Generator"
        }()
        let modifierName = memberModifierName(row.memberID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(detail)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent, in: Capsule())
                Text("generator")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("MODIFIER")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                if let modifierName {
                    Text(modifierName)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    Button {
                        session.setPatternModifierGeneratorID(nil, for: row.memberID, slotIndex: row.patternSlotIndex)
                        postRenderedVisualState(isVisible: true)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Remove modifier")
                    .accessibilityLabel("Remove modifier")
                } else {
                    Button {
                        addMemberModifier(row)
                    } label: {
                        Label("Add modifier", systemImage: "plus")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.text)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                            .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kit-row-add-modifier")
                    .accessibilityLabel("Add generator modifier")
                }

                Spacer(minLength: 0)
            }
        }
    }

    func memberModifierName(_ memberID: UUID) -> String? {
        guard let bank = session.store.patternBanksByTrackID[memberID],
              let track = memberTrack(memberID) else { return nil }
        let slotIndex = session.store.selectedPhrase.patternIndex(for: track.id, layers: session.store.layers)
        guard let modifierID = bank.slot(at: slotIndex).sourceRef.modifierGeneratorID,
              let generator = session.store.generatorPool.first(where: { $0.id == modifierID })
        else { return nil }
        return generator.name
    }

    /// Attach the first modifier-capable generator as a modifier on the member's
    /// active slot (AC21: the generator can carry a modifier).
    func addMemberModifier(_ row: DrumKitMatrixModel.Row) {
        guard let track = memberTrack(row.memberID) else { return }
        let candidate = session.store.generatorPool.first { $0.trackType == track.trackType }
            ?? session.store.generatorPool.first
        guard let modifier = candidate else { return }
        session.setPatternModifierGeneratorID(modifier.id, for: row.memberID, slotIndex: row.patternSlotIndex)
        postRenderedVisualState(isVisible: true)
    }

    // MARK: Sound mini-tab (mini sampler + in-sampler filter for the member)

    /// Sound mini-tab (AC21). Reuses `SamplerDestinationWidget` bound to THIS
    /// member's track id, so the mini sampler + in-sampler filter edit the real
    /// member sound (a drum part's filter stays inside the sampler, not FX).
    @ViewBuilder
    func expandedSoundTab(_ row: DrumKitMatrixModel.Row) -> some View {
        let memberID = row.memberID
        SamplerDestinationWidget(
            destination: Binding(
                get: { memberTrack(memberID)?.destination ?? .none },
                set: { session.setEditedDestination($0, for: memberID) }
            ),
            library: AudioSampleLibrary.shared,
            sampleEngine: engineController.sampleEngineSink,
            trackID: memberID,
            filterSettings: Binding(
                get: { memberTrack(memberID)?.filter ?? .init() },
                set: { session.setFilterSettings($0, for: memberID) }
            ),
            onManageMacros: {
                expandedRowTab = .macros
                postRenderedVisualState(isVisible: true)
            },
            onRemove: {}
        )
    }

    // MARK: FX mini-tab (per-track insert chain for the member)

    /// FX mini-tab (AC21). Reuses `TrackFXChainView` bound to THIS member's
    /// per-track insert chain — real add/remove/reorder/bypass.
    @ViewBuilder
    func expandedFXTab(_ row: DrumKitMatrixModel.Row) -> some View {
        let memberID = row.memberID
        let inserts = memberTrack(memberID)?.fxInserts ?? []
        TrackFXChainView(
            inserts: inserts,
            accent: accent,
            onAddFX: { expandedFXTarget = ExpandedFXTarget(memberID: memberID) },
            onRemove: { insertID in
                session.removeFXInsert(trackID: memberID, insertID: insertID)
            },
            onMove: { source, destination in
                session.moveFXInsert(trackID: memberID, from: source, to: destination)
            },
            onSetBypassed: { insertID, bypassed in
                session.setFXInsertBypassed(trackID: memberID, insertID: insertID, bypassed: bypassed)
            }
        )
    }

    /// "+ FX" picker for an expanded member's per-track chain. Mirrors the
    /// single-track Add FX sheet, committing a `TrackFXInsert` to the member.
    @ViewBuilder
    func expandedFXChooserSheet(memberID: UUID) -> some View {
        let effects = engineController.availableAudioEffects
        StudioModal(
            title: "Add FX",
            accent: accent,
            minWidth: 360,
            onClose: { expandedFXTarget = nil }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                kitFXOptionRow(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                    session.addFXInsert(trackID: memberID, insert: .filter())
                    expandedFXTarget = nil
                }
                kitFXOptionRow(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                    session.addFXInsert(trackID: memberID, insert: .bitcrusher())
                    expandedFXTarget = nil
                }
            }

            Divider()
                .overlay(StudioTheme.border)

            Text("AU Effect")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            AUEffectPickerList(effects: effects) { effect in
                kitFXOptionRow(title: effect.displayName, systemName: "slider.horizontal.3") {
                    session.addFXInsert(trackID: memberID, insert: .auEffect(effect))
                    expandedFXTarget = nil
                }
            }
        }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Macros mini-tab (M1–M8 slots for the member)

    /// Macros mini-tab (AC21). Renders THIS member's real M1–M8 slot bindings
    /// via `AUMacroSlotKnob`. Value changes write through the real session
    /// mutation (`setMacroLayerDefault`); assigning a NEW slot presents the
    /// AU-parameter picker sheet in-place (the same `SingleMacroSlotPickerSheet`
    /// the per-track editor uses), so macro assignment lives entirely inside the
    /// kit view — no dive-in required.
    @ViewBuilder
    func expandedMacrosTab(_ row: DrumKitMatrixModel.Row) -> some View {
        let memberID = row.memberID
        let slots = memberMacroSlots(memberID)
        let fallbacks = memberMacroFallbackValues(memberID)
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Self.macroColumns, alignment: .leading, spacing: 12) {
                ForEach(slots) { slot in
                    AUMacroSlotKnob(
                        slotIndex: slot.slotIndex,
                        binding: slot.binding,
                        value: slot.binding.flatMap { fallbacks[$0.id] },
                        onAssign: { prepareAndPresentMemberMacroPicker(memberID: memberID, slotIndex: slot.slotIndex) },
                        onChange: { newValue in
                            guard let binding = slot.binding else { return }
                            session.setMacroLayerDefault(value: newValue, bindingID: binding.id, trackID: memberID)
                        },
                        onRemove: slot.binding.map { binding in
                            { session.removeAUMacroSlot(bindingID: binding.id, trackID: memberID) }
                        }
                    )
                }
            }
            Text("Drum-part macro defaults. Tap an empty slot to assign an AU parameter.")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    /// Whether the member's resolved destination is an AU instrument (only AU
    /// instruments expose assignable parameters). Mirrors the per-track editor's
    /// `canAssignAUMacros` gate.
    func memberCanAssignAUMacros(_ memberID: UUID) -> Bool {
        if case .auInstrument = session.store.resolvedDestination(for: memberID).withoutTransientState {
            return true
        }
        return false
    }

    /// AU parameter addresses already bound to one of the member's macro slots,
    /// so the picker can hide already-assigned parameters.
    func memberAUMacroAddresses(_ memberID: UUID) -> Set<UInt64> {
        Set((memberTrack(memberID)?.macros ?? []).compactMap { binding in
            if case let .auParameter(address, _) = binding.source {
                return address
            }
            return nil
        })
    }

    /// Prepare the member's AU host then present the AU-parameter picker sheet
    /// for the given slot (mirrors TrackSourceEditorView's
    /// `prepareAndPresentMacroSlotPicker`, scoped to the member).
    func prepareAndPresentMemberMacroPicker(memberID: UUID, slotIndex: Int) {
        guard memberCanAssignAUMacros(memberID) else { return }
        engineController.prepareAudioUnit(for: memberID)
        expandedMacroTarget = ExpandedMacroTarget(memberID: memberID, slotIndex: slotIndex)
    }

    /// Commit the chosen AU parameter to the member's macro slot via the shared
    /// session mutator.
    func assignMemberMacro(_ parameter: AUParameterDescriptor, memberID: UUID, slotIndex: Int) {
        let descriptor = TrackMacroDescriptor(auParameter: parameter)
        _ = session.assignAUMacroToSlot(descriptor, to: memberID, slotIndex: slotIndex)
    }

    func memberMacroSlots(_ memberID: UUID) -> [MacroSlot] {
        let bindings = (memberTrack(memberID)?.macros ?? []).sorted { $0.slotIndex < $1.slotIndex }
        return (0..<8).map { slotIndex in
            MacroSlot(slotIndex: slotIndex, binding: bindings.first { $0.slotIndex == slotIndex })
        }
    }

    func memberMacroFallbackValues(_ memberID: UUID) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        let layers = session.store.layers
        for binding in memberTrack(memberID)?.macros ?? [] {
            let layerID = "macro-\(memberID.uuidString)-\(binding.id.uuidString)"
            if let layer = layers.first(where: { $0.id == layerID }),
               case let .scalar(v) = layer.defaults[memberID] {
                result[binding.id] = v
            } else {
                result[binding.id] = binding.descriptor.defaultValue
            }
        }
        return result
    }

    // MARK: Mixer mini-tab (member level + bus summary)

    /// Mixer mini-tab (AC21). The member's real level slider (writes via
    /// `setTrackMix`) plus the kit-bus output summary.
    @ViewBuilder
    func expandedMixerTab(_ row: DrumKitMatrixModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            kitPartLevelRow(row)
            if let model {
                kitBusOutputRow(model)
            }
        }
    }
}
