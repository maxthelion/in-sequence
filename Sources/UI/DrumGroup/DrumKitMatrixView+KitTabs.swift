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
        StudioPanel(title: "Kit FX", eyebrow: kitFXEyebrow(model), accent: accent) {
            if let bus = kitBus(model) {
                KitBusFXChainView(
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
    }

    func kitFXEyebrow(_ model: DrumKitMatrixModel) -> String {
        if let bus = kitBus(model) {
            return "Insert chain on \(bus.name) (whole kit)"
        }
        return "Kit bus unavailable"
    }

    /// `List.onMove` gives index-based moves; the bus session API reorders by an
    /// explicit id list, so translate the move into the new ordering.
    func moveKitBusInserts(bus: MixerBus, from source: IndexSet, to destination: Int) {
        var ids = bus.inserts.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        session.reorderMixerBusInserts(ids, busID: bus.id)
    }

    var kitBusUnavailableState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This kit is not on a dedicated bus")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
            Text("Route the kit to its own bus (Routing) to add kit-wide FX.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.loose)
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
                    kitFXOptionButton(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                        session.addMixerBusInsert(.filter(), busID: busID)
                        isPresentingKitFX = false
                    }
                    kitFXOptionButton(title: "Bitcrusher", systemName: "waveform.path.ecg") {
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

                if effects.isEmpty {
                    Text("No AU effects found")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(effects.prefix(AudioEffectChoice.menuDisplayLimit)) { effect in
                                kitFXOptionButton(title: effect.displayName, systemName: "slider.horizontal.3") {
                                    session.addMixerBusInsert(.auEffect(effect), busID: busID)
                                    isPresentingKitFX = false
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .scrollContentBackground(.hidden)
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

    func kitFXOptionButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kit Macros tab (AC23: M1–M8 across the kit / bus)

    /// Macros tab: a styled M1–M8 surface reusing `AUMacroSlotKnob`. It mirrors
    /// the originating part's macro bindings as a representative kit view.
    /// STUBBED: full cross-part / bus macro wiring (sweeping one parameter
    /// across every part at once) is a later slice; the knobs render the kit's
    /// default mappings but do not yet drive every part — see report.
    @ViewBuilder
    func kitMacrosTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Macros", eyebrow: "M1–M8 across the whole kit / its bus", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                kitNotYetFunctionalBadge("Kit-wide macro sweeps coming soon")

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
                .opacity(0.55)
                .allowsHitTesting(false)
            }
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
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
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

    /// Mixer tab: the kit bus output (→ its destination) and a per-part level
    /// row each (reusing `session.setTrackMix`). Send A/B and bus output
    /// routing are shown as the bus summary; full bus-strip editing is reachable
    /// from the global Mixer — see report for what is real vs summarized.
    @ViewBuilder
    func kitMixerTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Mixer", eyebrow: "Bus output + per-part levels", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                kitBusOutputRow(model)

                Text("PER-PART LEVELS")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.rows) { row in
                        kitPartLevelRow(row)
                    }
                }
            }
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

            Text(outputTitle)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(StudioOpacity.hoverFill), in: Capsule())

            Spacer(minLength: 0)

            kitSendBadge("A")
            kitSendBadge("B")
        }
    }

    /// Decorative Send A/B badge. The kit-bus send routing is not wired yet, so
    /// it reads as a dimmed "soon" affordance rather than a finished control.
    func kitSendBadge(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text("Send \(label)")
                .studioText(.label)
            Text("soon")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText.opacity(0.7))
        }
        .foregroundStyle(StudioTheme.mutedText.opacity(0.6))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(StudioOpacity.subtleFill * 0.6), in: Capsule())
        .overlay(
            Capsule().stroke(StudioTheme.border.opacity(0.6), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [3, 3]))
        )
        .help("Kit-bus sends are not yet functional")
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
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
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
