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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text("-> Master")
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Delete bus")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("INSERTS")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                MixerInsertChainView(
                    inserts: bus.inserts,
                    accent: accent,
                    emptySlotCount: max(0, 3 - bus.inserts.count),
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
                .frame(height: 146, alignment: .topLeading)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .center, spacing: 8) {
                    VerticalLevelFader(
                        level: displayedLevel,
                        isMuted: bus.mix.isMuted || isEffectivelyMuted,
                        onBegin: beginLevelDrag,
                        onChange: updateLevel,
                        onEnd: commitLevel
                    )
                    .frame(width: 36, height: 150)

                    Text("\(Int((displayedLevel * 100).rounded()))%")
                        .studioText(.eyebrow)
                        .monospacedDigit()
                        .foregroundStyle(StudioTheme.text)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pan")
                        .studioText(.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    Slider(value: Binding(get: { displayedPan }, set: updatePan), in: -1...1, onEditingChanged: handlePanEditingChanged)
                        .tint(accent)
                        .frame(width: 88)
                    Text(panLabel)
                        .studioText(.eyebrow)
                        .monospacedDigit()
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 88, alignment: .trailing)
                }
                .padding(.bottom, 4)
            }

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

            VStack(alignment: .leading, spacing: 5) {
                if isRenaming {
                    TextField("Bus name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                } else {
                    Button(action: onBeginRename) {
                        Text(bus.name)
                            .studioText(.title)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Rename bus")
                }

                Text(routedSummary)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(StudioMetrics.Spacing.roomy)
        .frame(width: MixerWorkspaceLayout.busStripWidth, alignment: .topLeading)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(bus.mix.isSoloed ? StudioTheme.amber : accent.opacity(StudioOpacity.accentStroke), lineWidth: bus.mix.isSoloed ? 2 : 1)
        )
        .opacity(isEffectivelyMuted && !bus.mix.isMuted ? 0.58 : 1)
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

    private var routedSummary: String {
        if routedTrackNames.isEmpty {
            return "No tracks routed"
        }
        return "\(routedTrackNames.count) routed: \(routedTrackNames.joined(separator: ", "))"
    }

    private var displayedLevel: Double {
        levelControl.rendered(committed: bus.mix.clampedLevel)
    }

    private var displayedPan: Double {
        panControl.rendered(committed: bus.mix.clampedPan)
    }

    private var panLabel: String {
        let value = displayedPan
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

    private func handlePanEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !panControl.isDragging {
                panControl.begin(with: bus.mix.clampedPan)
            }
        } else {
            commitPan()
        }
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
