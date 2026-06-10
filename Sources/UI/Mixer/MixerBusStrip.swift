import SwiftUI

struct MixerBusStrip: View {
    let bus: MixerBus
    let accent: Color
    let routedTrackNames: [String]
    let isEffectivelyMuted: Bool
    let isRenaming: Bool
    let onBeginRename: () -> Void
    let onCancelRename: () -> Void
    let onCommitRename: (String) -> Void
    let onSetLevel: (Double) -> Void
    let onSetPan: (Double) -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onDelete: () -> Void

    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @StateObject private var levelControl = ThrottledMixValue()
    @StateObject private var panControl = ThrottledMixValue()
    @State private var draftName = ""
    @State private var isAddFXPresented = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        StudioMixerStrip(
            width: MixerWorkspaceLayout.busStripWidth,
            accent: accent,
            isHighlighted: bus.mix.isSoloed,
            highlightAccent: StudioTheme.amber,
            dimsContent: isEffectivelyMuted && !bus.mix.isMuted
        ) {
            headerSlot
        } processing: {
            processingSlot
        } levels: {
            levelsSlot
        } actions: {
            actionsSlot
        } footer: {
            footerSlot
        }
        .sheet(isPresented: $isAddFXPresented) {
            addFXSheet
        }
        .onAppear {
            draftName = bus.name
            if isRenaming {
                isNameFocused = true
            }
        }
        .onChange(of: bus.name) {
            if !isRenaming {
                draftName = bus.name
            }
        }
        .onChange(of: isRenaming) {
            draftName = bus.name
            isNameFocused = isRenaming
        }
        .onChange(of: isNameFocused) {
            if !isNameFocused && isRenaming {
                commitRename()
            }
        }
        .accessibilityIdentifier("mixer-bus-strip-\(bus.id.uuidString)")
    }

    private var headerSlot: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)

            if isRenaming {
                TextField("Bus name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Button(action: onBeginRename) {
                    Text(bus.name)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Rename bus")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Delete bus")
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var processingSlot: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INSERTS")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            ScrollView(showsIndicators: false) {
                MixerInsertChainView(
                    inserts: bus.inserts,
                    accent: accent,
                    emptySlotCount: max(0, 2 - bus.inserts.count),
                    maxAddAffordances: 1,
                    addLabel: "Add FX",
                    addAction: { isAddFXPresented = true },
                    updateInsert: { insertID, edit in
                        session.updateMixerBusInsert(insertID, busID: bus.id, edit: edit)
                    },
                    removeInsert: { insertID in
                        session.removeMixerBusInsert(insertID, busID: bus.id)
                    },
                    reorderInserts: { ids in
                        session.reorderMixerBusInserts(ids, busID: bus.id)
                    }
                )
            }
        }
    }

    private var levelsSlot: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .center, spacing: 6) {
                VerticalLevelFader(
                    level: displayedLevel,
                    isMuted: bus.mix.isMuted || isEffectivelyMuted,
                    onBegin: beginLevelDrag,
                    onChange: updateLevel,
                    onEnd: commitLevel
                )
                .frame(
                    width: StudioMixerStripMetrics.faderSize.width,
                    height: StudioMixerStripMetrics.faderSize.height
                )

                Text(StudioLevelFormat.dBLabel(forLinear: displayedLevel))
                    .studioText(.eyebrow)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
            }

            StudioRotaryKnob(
                title: "Pan",
                value: displayedPan,
                range: -1...1,
                accent: accent,
                format: { panLabel(for: $0) },
                onChange: { pan in
                    updatePan(pan)
                    commitPan()
                }
            )
        }
    }

    private var actionsSlot: some View {
        HStack(spacing: 8) {
            MixerStripActionButton(
                title: bus.mix.isMuted ? "Unmute" : "Mute",
                accent: StudioTheme.amber,
                isActive: bus.mix.isMuted,
                action: onToggleMute
            )

            MixerStripActionButton(
                title: bus.mix.isSoloed ? "Unsolo" : "Solo",
                accent: StudioTheme.amber,
                isActive: bus.mix.isSoloed,
                action: onToggleSolo
            )
        }
    }

    private var footerSlot: some View {
        Text(routedSummary)
            .studioText(.micro)
            .foregroundStyle(StudioTheme.mutedText)
            .lineLimit(2)
    }

    private var routedSummary: String {
        "→ Master · \(routedTrackNames.count) routed"
    }

    private var displayedLevel: Double {
        levelControl.rendered(committed: bus.mix.clampedLevel)
    }

    private var displayedPan: Double {
        panControl.rendered(committed: bus.mix.clampedPan)
    }

    private func panLabel(for value: Double) -> String {
        if value < -0.05 {
            return "L\(Int(abs(value) * 100))"
        }
        if value > 0.05 {
            return "R\(Int(value * 100))"
        }
        return "C"
    }

    private func beginLevelDrag() {
        if !levelControl.isDragging {
            levelControl.begin(with: bus.mix.clampedLevel)
        }
    }

    private func updateLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        if !levelControl.isDragging {
            levelControl.begin(with: bus.mix.clampedLevel)
        }
        guard levelControl.update(clamped) else { return }
        onSetLevel(clamped)
    }

    private func commitLevel() {
        _ = levelControl.commit()
    }

    private func updatePan(_ pan: Double) {
        let clamped = min(max(pan, -1), 1)
        if !panControl.isDragging {
            panControl.begin(with: bus.mix.clampedPan)
        }
        guard panControl.update(clamped) else { return }
        onSetPan(clamped)
    }

    private func commitPan() {
        _ = panControl.commit()
    }

    private func commitRename() {
        onCommitRename(draftName)
    }

    private func cancelRename() {
        draftName = bus.name
        onCancelRename()
    }

    private var addFXSheet: some View {
        StudioModal(
            title: "\(bus.name) FX",
            minWidth: 360,
            onClose: { isAddFXPresented = false }
        ) {
                VStack(alignment: .leading, spacing: 8) {
                    addFXButton(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                        session.addMixerBusInsert(.filter(), busID: bus.id)
                        isAddFXPresented = false
                    }
                    addFXButton(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                        session.addMixerBusInsert(.bitcrusher(), busID: bus.id)
                        isAddFXPresented = false
                    }
                }

                Divider()
                    .overlay(StudioTheme.border)

                Text("AU Effect")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                let effects = engineController.availableAudioEffects
                if effects.isEmpty {
                    StudioEmptyListRow(message: "No AU effects found")
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(effects.prefix(16)) { effect in
                                addFXButton(title: effect.displayName, systemName: "slider.horizontal.3") {
                                    session.addMixerBusInsert(.auEffect(effect), busID: bus.id)
                                    isAddFXPresented = false
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
    }

    private func addFXButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .studioText(.labelBold)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }
}
