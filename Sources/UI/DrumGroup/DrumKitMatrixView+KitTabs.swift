import SwiftUI

// Kit-bus tab bodies for the kit matrix (AC23): the FX insert chain on the
// kit's own bus (+ its chooser sheet), the M1-M8 macros surface, and the
// mixer (bus output + per-part levels). Split out of DrumKitMatrixView.swift
// as an extension; zero behavior change.

extension DrumKitMatrixView {
    // MARK: - Kit FX tab (AC23: insert chain on the kit's own bus)

    /// FX tab: the insert chain on the kit's dedicated bus, so the inserts
    /// process every part together. Reuses the existing per-bus insert model
    /// (`MixerBusInsert`) + session mutations (`addMixerBusInsert` etc.).
    @ViewBuilder
    func kitFXTabBody(_ model: DrumKitMatrixModel) -> some View {
        if let bus = kitBus(model) {
            KitBusFXChainView(
                busID: bus.id,
                inserts: bus.inserts,
                accent: accent,
                onAddFX: { isPresentingKitFX = true },
                onRemove: { insertID in
                    session.removeMixerBusInsert(insertID, busID: bus.id)
                },
                onMove: { source, destination in
                    moveKitBusInserts(bus: bus, from: source, to: destination)
                },
                onSetBypassed: { insertID, bypassed in
                    session.updateMixerBusInsert(insertID, busID: bus.id) { insert in
                        insert.isEnabled = !bypassed
                    }
                }
            )
        } else {
            kitBusUnavailableState
        }
    }

    /// `List.onMove` gives index-based moves; the bus session API reorders by an
    /// explicit id list, so translate the move into the new ordering.
    func moveKitBusInserts(bus: MixerBus, from source: IndexSet, to destination: Int) {
        var ids = bus.inserts.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        session.reorderMixerBusInserts(ids, busID: bus.id)
    }

    var kitBusUnavailableState: some View {
        // Canon Rule 3: state title only — the instruction lives in the tooltip.
        Text("This kit is not on a dedicated bus")
            .studioText(.bodyEmphasis)
            .foregroundStyle(StudioTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.loose)
            .help("Route the kit to its own bus (Routing) to add kit-wide FX")
    }

    /// "+ FX" picker for the kit bus, mirroring the per-track Add FX sheet but
    /// committing a `MixerBusInsert` to the kit's bus (AC23).
    @ViewBuilder
    var kitFXChooserSheet: some View {
        if let model, let bus = kitBus(model) {
            let effects = engineController.availableAudioEffects
            let busID = bus.id
            StudioModal(
                title: "Add Kit FX",
                accent: accent,
                minWidth: 360,
                onClose: { isPresentingKitFX = false }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    kitFXOptionRow(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                        session.addMixerBusInsert(.filter(), busID: busID)
                        isPresentingKitFX = false
                    }
                    kitFXOptionRow(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                        session.addMixerBusInsert(.bitcrusher(), busID: busID)
                        isPresentingKitFX = false
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
                        session.addMixerBusInsert(.auEffect(effect), busID: busID)
                        isPresentingKitFX = false
                    }
                }
            }
            .presentationBackground(.clear)
            .environment(\.colorScheme, .dark)
        } else {
            Text("Kit bus unavailable")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .padding(StudioMetrics.Spacing.page)
                .background(StudioTheme.stageFill)
        }
    }

    /// Kit add-FX picker row. Routes through the shared `StudioFXOptionRow`,
    /// passing the kit's accent-tinted icon, no reserved icon column, the
    /// `.badge` corner radius, and the full-opacity border that this sheet uses.
    func kitFXOptionRow(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        StudioFXOptionRow(
            title: title,
            systemImage: systemName,
            iconColor: accent,
            iconColumnWidth: nil,
            cornerRadius: StudioMetrics.CornerRadius.badge,
            borderColor: StudioTheme.border,
            action: action
        )
    }

    // MARK: - Kit Macros tab (AC23: M1–M8 across the kit / bus)

    /// Macros tab: a styled M1–M8 surface reusing `AUMacroSlotKnob`. It mirrors
    /// the originating part's macro bindings as a representative kit view.
    /// STUBBED: full cross-part / bus macro wiring (sweeping one parameter
    /// across every part at once) is a later slice; the knobs render the kit's
    /// default mappings but do not yet drive every part — see report.
    @ViewBuilder
    func kitMacrosTabBody(_ model: DrumKitMatrixModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let slots = kitMacroSlots(model)
            LazyVGrid(columns: Self.macroColumns, alignment: .leading, spacing: 14) {
                ForEach(slots) { slot in
                    AUMacroSlotKnob(
                        slotIndex: slot.slotIndex,
                        binding: slot.binding,
                        value: nil,
                        onAssign: {},
                        onChange: { _ in }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Small "not yet functional" affordance for stubbed kit surfaces. Reads as
    /// a preview rather than a finished control, without building the feature.
    func kitNotYetFunctionalBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .studioText(.micro)
        }
        .foregroundStyle(StudioTheme.mutedText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(StudioTheme.subtleFill, in: Capsule())
        .overlay(
            Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    static let macroColumns = Array(
        repeating: GridItem(.flexible(), spacing: 14),
        count: 4
    )

    /// Eight slots (M1–M8) seeded from the originating part's macro bindings so
    /// the kit view reflects the seeded drum-part defaults (M1 start / M2 len /
    /// M3 cutoff). Unbound slots render as assignable knobs.
    func kitMacroSlots(_ model: DrumKitMatrixModel) -> [MacroSlot] {
        let originating = session.store.tracks.first { $0.id == model.originatingPartID }
        let bindings = originating?.macros ?? []
        return (0..<8).map { slotIndex in
            MacroSlot(
                slotIndex: slotIndex,
                binding: bindings.first { $0.slotIndex == slotIndex }
            )
        }
    }

    // MARK: - Kit Mixer tab (AC23: bus output + sends + per-part levels)

    /// Mixer tab: the kit bus output (→ its destination) plus scene routing.
    /// This mirrors the normal-track mixer grammar without presenting unwired
    /// Send A/B placeholders as finished controls.
    /// Per-part levels live on each member's accordion mixer mini-tab, not here.
    /// Full bus-strip editing is reachable from the global Mixer.
    @ViewBuilder
    func kitMixerTabBody(_ model: DrumKitMatrixModel) -> some View {
        HStack(alignment: .top, spacing: 20) {
            kitBusOutputRow(model)
            kitSceneMembershipSelector(model)
            Spacer(minLength: 0)
        }
    }

    func kitBusOutputRow(_ model: DrumKitMatrixModel) -> some View {
        let bus = kitBus(model)
        let outputTitle = bus.map { "→ \($0.name) → Master" } ?? "→ Master"
        return HStack(spacing: 10) {
            Text("BUS OUTPUT")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            // Colour identifies, it never floods (ux-canon rule 12): the bus
            // route is real state, carried by a SOLID accent badge with a dark
            // glyph — never a translucent accent wash.
            Text(outputTitle)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent, in: Capsule())

            Spacer(minLength: 0)
        }
    }

    func kitSceneMembershipSelector(_ model: DrumKitMatrixModel) -> some View {
        let selectedMembership = kitSceneMembership(model)
        return VStack(alignment: .leading, spacing: 6) {
            Text("SCENE")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 6) {
                ForEach(TrackMixSettings.SceneMembership.allCases, id: \.self) { membership in
                    let isSelected = selectedMembership == membership
                    Button {
                        commitKitSceneMembership(membership, model: model)
                    } label: {
                        Text(membership.shortLabel)
                            .studioText(.labelBold)
                            .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                            .frame(minWidth: 38)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                isSelected ? accent : StudioTheme.subtleFill,
                                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                                    .stroke(isSelected ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(membership.label)
                }
            }
            .help("\(model.groupName) scene membership")
            .accessibilityIdentifier("kit-routing-scene-membership")
            .accessibilityLabel("\(model.groupName) scene membership")
            .accessibilityValue(selectedMembership?.label ?? "Mixed")
        }
    }

    func kitSceneMembership(_ model: DrumKitMatrixModel) -> TrackMixSettings.SceneMembership? {
        let tracksByID = Dictionary(uniqueKeysWithValues: session.store.tracks.map { ($0.id, $0) })
        let memberships = Set(model.rows.compactMap { row in
            tracksByID[row.memberID]?.mix.sceneMembership
        })
        return memberships.count == 1 ? memberships.first : nil
    }

    func commitKitSceneMembership(_ membership: TrackMixSettings.SceneMembership, model: DrumKitMatrixModel) {
        let memberIDs = Set(model.rows.map(\.memberID))
        for track in session.store.tracks where memberIDs.contains(track.id) {
            var mix = track.mix
            mix.sceneMembership = membership
            session.setTrackMix(trackID: track.id, mix: mix)
        }
    }

    func kitPartLevelRow(_ row: DrumKitMatrixModel.Row) -> some View {
        let track = session.store.tracks.first { $0.id == row.memberID }
        let level = track?.mix.level ?? 0
        let percent = Int((level * 100).rounded())
        return HStack(spacing: 12) {
            Text(row.partName)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Slider(
                value: kitPartLevelBinding(memberID: row.memberID, track: track),
                in: 0...1
            )
            .tint(accent)

            Text("\(percent)%")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    func kitPartLevelBinding(memberID: UUID, track: StepSequenceTrack?) -> Binding<Double> {
        Binding(
            get: { track?.mix.level ?? 0 },
            set: { newValue in
                guard var mix = session.store.tracks.first(where: { $0.id == memberID })?.mix else { return }
                mix.level = newValue
                session.setTrackMix(trackID: memberID, mix: mix)
            }
        )
    }
}
