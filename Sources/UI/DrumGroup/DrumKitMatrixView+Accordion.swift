import SwiftUI

/// Pure routing decision for the drum-kit Sound mini-tab: does this member's
/// OWN destination render the AU instrument panel, or the sampler panel +
/// "Load AU…" affordance? Only a member's OWN `.auInstrument` shows the AU panel.
/// Pass the member's OWN (unresolved) destination, NOT the resolved one: an
/// `.inheritGroup` member of an AU kit RESOLVES to `.auInstrument`, but the
/// per-member AU panel (preset/remove keyed to the member's own host) must NOT be
/// shown for an inherited group AU — that member keeps the existing
/// sampler/placeholder path (shared-kit AU is an open product decision).
enum DrumKitSoundTabRouting {
    /// Which Sound-tab surface a member's OWN destination renders.
    enum Panel: Equatable {
        /// Own `.auInstrument`: the AU instrument panel (name + presets + remove).
        case au
        /// Own `.none`: a neutral "choose a sound source" chooser (Sample / AU) —
        /// distinct from a sampler that lost its sample (bug 20260629-101345).
        case chooser
        /// `.sample` (incl. missing-sample recovery) and `.inheritGroup`: the
        /// sampler panel.
        case sampler
    }

    static func panel(forOwnDestination ownDestination: Destination) -> Panel {
        switch ownDestination.withoutTransientState.kind {
        case .auInstrument:
            return .au
        case .none:
            return .chooser
        default:
            return .sampler
        }
    }

    static func usesAUPanel(forOwnDestination ownDestination: Destination) -> Bool {
        panel(forOwnDestination: ownDestination) == .au
    }
}

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
        VStack(alignment: .leading, spacing: StudioTabWellGrammar.pillRowToWellGap) {
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
        .sheet(item: $expandedSoundAUTarget) { target in
            // Reuse the per-track AU instrument chooser. Selecting an AU swaps
            // the member's sampler sound for an AU instrument via the SAME
            // session mutation the per-track editor uses.
            AddDestinationSheet(
                trackHasGroup: memberTrack(target.memberID)?.groupID != nil,
                audioInstrumentChoices: engineController.availableAudioInstruments,
                sampleLibrary: AudioSampleLibrary.shared
            ) { destination in
                applyMemberSoundDestination(destination, memberID: target.memberID)
            }
            .presentationBackground(.clear)
        }
        .sheet(item: $expandedSoundPresetTarget) { target in
            // Reuse the per-track preset browser bound to the member's AU host.
            PresetBrowserSheet(
                auDisplayName: memberAudioInstrumentChoice(target.memberID).displayName,
                viewModel: makeMemberPresetBrowserViewModel(memberID: target.memberID)
            )
        }
    }

    /// Part-level section switcher — the D-pill grammar (locked 2026-07-02
    /// amendment: function-based, not nesting-based). The SAME
    /// StudioSectionPills shape/size grammar as the kit-level pills, hugging
    /// its content left-aligned flush to the sub-card edge (`fillsWidth:
    /// false`), carrying the ONE kit chrome accent (group colour) — never the
    /// inset-track value-selector style, "otherwise they look like the step
    /// layer, fill etc". The row sub-card around it stays neutral-outlined.
    var expandedRowTabBar: some View {
        StudioSectionPills(
            pills: DrumKitRowTab.allCases.map { tab in
                StudioSectionPill(
                    section: tab,
                    title: tab.title,
                    accessibilityIdentifier: "kit-row-tab-\(tab.rawValue)"
                )
            },
            selection: expandedRowTab,
            accent: accent,
            fillsWidth: false,
            accessibilityIdentifier: "kit-row-tabs",
            onSelect: { tab in
                expandedRowTab = tab
                postRenderedVisualState(isVisible: true)
            }
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
                    accent: accent,
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
                        .background(StudioTheme.subtleFill, in: Capsule())
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
                            .background(StudioTheme.subtleFill, in: Capsule())
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

    // MARK: Sound mini-tab (sampler + in-sampler filter OR AU instrument)

    /// Sound mini-tab (AC21). Branches on the member's RESOLVED destination kind:
    /// a sampler part shows `SamplerDestinationWidget` (mini sampler + in-sampler
    /// filter) plus a "Load AU…" affordance; an AU part shows the AU panel
    /// (instrument readout + preset browser + remove), reusing the per-track AU
    /// flow scoped to THIS member's id. An `.inheritGroup` part keeps its existing
    /// behaviour (shared-kit AU is an open product decision — not surfaced here).
    @ViewBuilder
    func expandedSoundTab(_ row: DrumKitMatrixModel.Row) -> some View {
        let memberID = row.memberID
        // Route on the member's OWN destination, not the resolved one: an
        // `.inheritGroup` member of an AU kit resolves to `.auInstrument`, but its
        // per-member AU panel must not be shown (its preset/remove are keyed to a
        // member host it doesn't own). Inherit members keep the sampler/placeholder.
        let ownDestination = memberTrack(memberID)?.destination ?? .none
        switch DrumKitSoundTabRouting.panel(forOwnDestination: ownDestination) {
        case .au:
            expandedSoundAUPanel(memberID: memberID)
        case .chooser:
            expandedSoundChooserPanel(memberID: memberID)
        case .sampler:
            expandedSoundSamplerPanel(memberID: memberID)
        }
    }

    /// Empty sound source state for a part with `.none` destination. Offers the
    /// two source choices as equal dashed add tiles — distinct from a sampler
    /// that lost its sample (which keeps its own recovery card).
    /// Choosing Sample assigns the first library sample so the sampler card opens
    /// populated; choosing AU opens the same instrument chooser as the per-track
    /// editor (bug 20260629-101345).
    @ViewBuilder
    func expandedSoundChooserPanel(memberID: UUID) -> some View {
        HStack(alignment: .top, spacing: StudioMetrics.Spacing.standard) {
            StudioAddCard(
                label: "Sample",
                accent: accent,
                minHeight: 92,
                help: "Add a sample sound source"
            ) {
                guard let first = AudioSampleLibrary.shared.samples.first else { return }
                applyMemberSoundDestination(
                    .sample(sampleID: first.id, settings: .default),
                    memberID: memberID
                )
            }
            .accessibilityIdentifier("kit-row-choose-sample")

            StudioAddCard(
                label: "AU Instrument",
                accent: accent,
                minHeight: 92,
                help: "Add an AU instrument sound source"
            ) {
                expandedSoundAUTarget = ExpandedSoundAUTarget(memberID: memberID)
            }
            .accessibilityIdentifier("kit-row-choose-au")
        }
        .padding(StudioMetrics.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Sampler sound source for the member: today's `SamplerDestinationWidget`
    /// (mini sampler + the in-sampler filter). Used for `.sample` (incl. the
    /// missing-sample recovery card) and `.inheritGroup`. A `.none` part routes
    /// to `expandedSoundChooserPanel` instead, so clearing the sample (X →
    /// `.none`) lands on the neutral chooser, not the sampler's missing-sample
    /// card.
    @ViewBuilder
    func expandedSoundSamplerPanel(memberID: UUID) -> some View {
        SamplerDestinationWidget(
            destination: Binding(
                get: { memberTrack(memberID)?.destination ?? .none },
                set: { session.setEditedDestination($0, for: memberID) }
            ),
            library: AudioSampleLibrary.shared,
            sampleEngine: engineController.sampleEngineSink,
            trackID: memberID,
            accent: accent,
            filterSettings: Binding(
                get: { memberTrack(memberID)?.filter ?? .init() },
                set: { session.setFilterSettings($0, for: memberID) }
            ),
            onManageMacros: {
                expandedRowTab = .macros
                postRenderedVisualState(isVisible: true)
            },
            // Clear the member part's sound through the normal undoable document
            // edit path (mirrors TrackDestinationEditor.clearDestination). The
            // `.none` change ramp-removes the live sample voice via
            // setEditedDestination -> .fullEngineApply -> syncSampleMixers; it does
            // NOT write a transient "empty" capture into the .seqai document.
            onRemove: {
                session.setEditedDestination(.none, for: memberID)
                postRenderedVisualState(isVisible: true)
            }
        )
    }

    /// AU instrument sound source for the member. Reuses the per-track AU flow
    /// (instrument name readout + a Presets button launching `PresetBrowserSheet`,
    /// preset load via `engineController.loadPreset(_, for: memberID)`, persistence
    /// via `session.writeStateBlob(_, target: .track(memberID))`) bound to THIS
    /// member's id, with an X to remove the AU (`setEditedDestination(.none)`).
    /// The per-track `filter` is intentionally NOT surfaced here — it stays stored
    /// on the part so toggling back to the sampler restores it.
    @ViewBuilder
    func expandedSoundAUPanel(memberID: UUID) -> some View {
        let choice = memberAudioInstrumentChoice(memberID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.displayName)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("AU instrument")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 12)

                StudioCircleIconButton(
                    systemName: "xmark",
                    size: StudioMetrics.ControlSize.medium,
                    help: "Remove this AU and return to the sampler"
                ) {
                    // Mirrors the Step-1 clear: ramps the AU host to silence via
                    // setEditedDestination → .fullEngineApply. The part's stored
                    // sampler filter is untouched and restored on the next sample.
                    session.setEditedDestination(.none, for: memberID)
                    postRenderedVisualState(isVisible: true)
                }
                .accessibilityIdentifier("kit-row-remove-au")
            }
            .padding(StudioMetrics.Spacing.standard)

            Divider()
                .overlay(StudioTheme.border.opacity(0.7))

            Button {
                engineController.prepareAudioUnit(for: memberID)
                expandedSoundPresetTarget = ExpandedSoundPresetTarget(memberID: memberID)
            } label: {
                HStack(spacing: 8) {
                    Text("Presets")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kit-row-au-presets")
            .padding(StudioMetrics.Spacing.comfortable)
        }
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// The AU instrument choice that names the member's current AU destination,
    /// mirroring TrackDestinationEditor.currentAudioInstrumentChoice.
    func memberAudioInstrumentChoice(_ memberID: UUID) -> AudioInstrumentChoice {
        // The member's OWN destination (the AU panel only shows for an own-AU
        // member), consistent with the routing decision in expandedSoundTab.
        if case let .auInstrument(componentID, _) = (memberTrack(memberID)?.destination ?? .none) {
            return AudioInstrumentChoice.defaultChoices.first(where: { $0.audioComponentID == componentID })
                ?? AudioInstrumentChoice(audioComponentID: componentID)
        }
        return .builtInSynth
    }

    /// Apply a "Load AU…" sheet selection to the member's own sound. Routes
    /// through the SAME session mutation the per-track editor uses; for an AU it
    /// also primes the AU host so the preset browser can read its list.
    func applyMemberSoundDestination(_ destination: Destination, memberID: UUID) {
        session.setEditedDestination(destination, for: memberID)
        if case .auInstrument = destination {
            engineController.prepareAudioUnit(for: memberID)
        }
        postRenderedVisualState(isVisible: true)
    }

    /// Preset-browser view model bound to the member's AU host. Reads/loads via
    /// the per-member EngineController APIs and persists the captured state blob
    /// to the member's own write target (`.track(memberID)`), scoped to the part's
    /// OWN AU (not an inherited group AU).
    func makeMemberPresetBrowserViewModel(memberID: UUID) -> PresetBrowserSheetViewModel {
        PresetBrowserSheetViewModel(
            read: { [engineController] in
                engineController.presetReadout(for: memberID)
            },
            load: { [engineController] descriptor in
                try engineController.loadPreset(descriptor, for: memberID)
            },
            commit: { [session] stateBlob in
                session.writeStateBlob(stateBlob, target: .track(memberID))
            }
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
        // Canon Rule 3: no explainer prose — the assign instruction lives in
        // the tooltip.
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
        .help("Drum-part macro defaults — tap an empty slot to assign an AU parameter")
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
