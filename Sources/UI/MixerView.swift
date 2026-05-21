import SwiftUI

enum MixerSendDisplayModel {
    static let activeThreshold = 0.005

    static func clamped(_ value: Double) -> Double {
        min(max(value, TrackMixSettings.sendRange.lowerBound), TrackMixSettings.sendRange.upperBound)
    }

    static func percentLabel(for value: Double) -> String {
        "\(Int((clamped(value) * 100).rounded()))%"
    }

    static func isNonZero(_ value: Double) -> Bool {
        clamped(value) > activeThreshold
    }
}

enum MixerRoutingDisplayModel {
    static func outputTitle(for track: StepSequenceTrack, buses: [MixerBus]) -> String {
        guard let busID = track.outputBusID,
              let bus = buses.first(where: { $0.id == busID })
        else {
            return "Master"
        }
        return bus.name
    }

    static func affectedTrackNames(for busID: UUID, tracks: [StepSequenceTrack]) -> [String] {
        tracks
            .filter { $0.outputBusID == busID }
            .map(\.name)
    }
}

struct MixerView<TrailingContent: View>: View {
    @Binding var document: SeqAIDocument
    var onEditTrack: ((UUID) -> Void)? = nil
    let trailingContent: TrailingContent
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var routingTrackIDs: Set<UUID> = []
    @State private var renamingBusID: UUID?
    @State private var deleteRequest: MixerBusDeleteRequest?

    init(
        document: Binding<SeqAIDocument>,
        onEditTrack: ((UUID) -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self._document = document
        self.onEditTrack = onEditTrack
        self.trailingContent = trailingContent()
    }

    var body: some View {
        let tracks = session.store.tracks
        let buses = session.store.buses
        let selectedTrackID = session.store.selectedTrackID
        let muteState = EngineController.effectiveMixerMuteState(for: session.store.exportToProject())

        VStack(alignment: .leading, spacing: 12) {
            if muteState.isSoloActive {
                MixerSoloBanner {
                    session.clearAllSolo()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(tracks, id: \.id) { track in
                        MixerChannelStrip(
                            track: track,
                            destinationLabel: destinationLabel(for: track),
                            outputTitle: MixerRoutingDisplayModel.outputTitle(for: track, buses: buses),
                            buses: buses,
                            isSelected: track.id == selectedTrackID,
                            isEffectivelyMuted: muteState.mutedTrackIDs.contains(track.id),
                            isRoutingApplying: routingTrackIDs.contains(track.id),
                            engineController: engineController,
                            onSelect: {
                                // Narrowed from .fullEngineApply: selection alone has no audible
                                // impact; .snapshotOnly is sufficient. The onEditTrack callback
                                // handles any editor-navigation side effects.
                                let trackID = track.id
                                session.setSelectedTrackID(trackID)
                                onEditTrack?(trackID)
                            },
                            onSetMix: { mix in
                                session.setTrackMix(trackID: track.id, mix: mix)
                            },
                            onToggleMute: {
                                // .fullEngineApply preserved: mute requires engine document-model rebuild.
                                session.toggleTrackMute(trackID: track.id)
                            },
                            onToggleSolo: {
                                session.setTrackSoloed(!track.mix.isSoloed, trackID: track.id)
                            },
                            onRoute: { busID in
                                applyRoute(trackID: track.id, busID: busID)
                            }
                        )
                    }

                    MixerBusZone(
                        buses: buses,
                        tracks: tracks,
                        mutedBusIDs: muteState.mutedBusIDs,
                        renamingBusID: $renamingBusID,
                        onAddBus: addBus,
                        onRenameBus: { busID, name in
                            session.renameMixerBus(busID, name: name)
                        },
                        onSetLevel: { busID, level in
                            session.setMixerBusLevel(level, busID: busID)
                        },
                        onSetPan: { busID, pan in
                            session.setMixerBusPan(pan, busID: busID)
                        },
                        onToggleMute: { bus in
                            session.setMixerBusMuted(!bus.mix.isMuted, busID: bus.id)
                        },
                        onToggleSolo: { bus in
                            session.setMixerBusSoloed(!bus.mix.isSoloed, busID: bus.id)
                        },
                        onDelete: requestDelete
                    )

                    trailingContent
                }
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            deleteRequest?.title ?? "Delete Bus",
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteRequest = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: deleteRequest
        ) { request in
            Button("Delete and Reroute to Master", role: .destructive) {
                session.deleteMixerBus(id: request.busID)
                deleteRequest = nil
            }
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: { request in
            Text(request.message)
        }
    }

    private func destinationLabel(for track: StepSequenceTrack) -> String {
        if case .inheritGroup = track.destination,
           let group = session.store.group(for: track.id),
           let sharedDestination = group.sharedDestination
        {
            return sharedDestination.kindLabel
        }
        return track.destination.kindLabel
    }

    private func addBus() {
        let busID = session.addMixerBus()
        renamingBusID = busID
    }

    private func applyRoute(trackID: UUID, busID: UUID?) {
        guard !routingTrackIDs.contains(trackID) else { return }
        routingTrackIDs.insert(trackID)
        session.setTrackOutputBus(trackID: trackID, busID: busID)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            routingTrackIDs.remove(trackID)
        }
    }

    private func requestDelete(_ bus: MixerBus) {
        let affectedNames = MixerRoutingDisplayModel.affectedTrackNames(for: bus.id, tracks: session.store.tracks)
        if affectedNames.isEmpty {
            session.deleteMixerBus(id: bus.id)
        } else {
            deleteRequest = MixerBusDeleteRequest(busID: bus.id, busName: bus.name, affectedTrackNames: affectedNames)
        }
    }
}

private struct MixerBusDeleteRequest: Identifiable {
    let id = UUID()
    let busID: UUID
    let busName: String
    let affectedTrackNames: [String]

    var title: String {
        "Delete \(busName)?"
    }

    var message: String {
        let names = affectedTrackNames.joined(separator: ", ")
        return "Tracks routed to this bus will be rerouted to Master: \(names)"
    }
}

private struct MixerSoloBanner: View {
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("SOLO ACTIVE", systemImage: "speaker.wave.2.fill")
                .studioText(.eyebrowBold)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.background)
            Spacer()
            Button("Clear Solo", action: onClear)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(StudioTheme.background)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .accessibilityIdentifier("mixer-solo-active-banner")
    }
}

private struct MixerChannelStrip: View {
    private enum SendSlot: String, CaseIterable {
        case a = "A"
        case b = "B"

        var title: String {
            switch self {
            case .a: return "Send A"
            case .b: return "Send B"
            }
        }

        var keyPath: WritableKeyPath<TrackMixSettings, Double> {
            switch self {
            case .a: return \.sendA
            case .b: return \.sendB
            }
        }

        var accent: Color {
            switch self {
            case .a: return StudioTheme.cyan
            case .b: return StudioTheme.violet
            }
        }
    }

    let track: StepSequenceTrack
    let destinationLabel: String
    let outputTitle: String
    let buses: [MixerBus]
    let isSelected: Bool
    let isEffectivelyMuted: Bool
    let isRoutingApplying: Bool
    let engineController: EngineController
    let onSelect: () -> Void
    let onSetMix: (TrackMixSettings) -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onRoute: (UUID?) -> Void

    @StateObject private var levelControl = ThrottledMixValue()
    @StateObject private var panControl = ThrottledMixValue()
    @State private var activeSendEditor: SendSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Text(destinationLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .studioText(.micro)
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StudioTheme.cyan.opacity(StudioOpacity.softFill), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .center, spacing: 8) {
                        VerticalLevelFader(
                            level: displayedLevel,
                            isMuted: track.mix.isMuted,
                            onBegin: { beginLevelDrag() },
                            onChange: { updateLevel($0) },
                            onEnd: { commitLevel() }
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

                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { displayedPan },
                                    set: { updatePan($0) }
                                ),
                                in: -1...1,
                                onEditingChanged: handlePanEditingChanged
                            )
                            .tint(StudioTheme.violet)
                            .frame(width: 88)

                            Text(panLabel)
                                .studioText(.eyebrow)
                                .monospacedDigit()
                                .foregroundStyle(StudioTheme.text)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 4)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Sends")
                            .studioText(.eyebrow)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)
                        Spacer()
                        if let activeSendEditor {
                            Text("\(track.name) \(activeSendEditor.title) \(sendPercent(activeSendEditor))")
                                .studioText(.micro)
                                .monospacedDigit()
                                .foregroundStyle(activeSendEditor.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else {
                            Text("Post fader")
                                .studioText(.micro)
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(SendSlot.allCases, id: \.self) { slot in
                            SendAmountControl(
                                slot: slot.rawValue,
                                title: slot.title,
                                trackName: track.name,
                                value: sendValue(slot),
                                accent: slot.accent,
                                isEditing: Binding(
                                    get: { activeSendEditor == slot },
                                    set: { isPresented in
                                        activeSendEditor = isPresented ? slot : nil
                                    }
                                ),
                                onChange: { setSend(slot, value: $0) }
                            )
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                MixerStripActionButton(
                    title: track.mix.isMuted ? "Unmute" : "Mute",
                    accent: StudioTheme.amber,
                    isActive: track.mix.isMuted
                ) {
                    onToggleMute()
                }

                MixerStripActionButton(
                    title: track.mix.isSoloed ? "Unsolo" : "Solo",
                    accent: StudioTheme.amber,
                    isActive: track.mix.isSoloed
                ) {
                    onToggleSolo()
                }

                MixerStripActionButton(
                    title: "Edit",
                    systemName: "slider.horizontal.3",
                    accent: StudioTheme.cyan,
                    minWidth: 46,
                    action: onSelect
                )
            }

            trackOutputSelector

            Rectangle()
                .fill(StudioTheme.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Label("\(track.activeStepCount) active steps", systemImage: "square.grid.2x2")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Label("\(track.pitches.count) pitches", systemImage: "music.note")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(16)
        .frame(width: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel)
                .fill(StudioTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel)
                .stroke(isSelected ? StudioTheme.cyan : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
        )
        .opacity(isEffectivelyMuted && !track.mix.isMuted ? 0.58 : 1)
    }

    private var trackOutputSelector: some View {
        Menu {
            Button("Master") {
                onRoute(nil)
            }
            ForEach(buses) { bus in
                Button(bus.name) {
                    onRoute(bus.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                    Text(isRoutingApplying ? "Applying..." : outputTitle)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRoutingApplying)
        .accessibilityLabel("\(track.name) output")
        .accessibilityValue(isRoutingApplying ? "Applying" : outputTitle)
    }

    private func sendValue(_ slot: SendSlot) -> Double {
        track.mix[keyPath: slot.keyPath]
    }

    private func sendPercent(_ slot: SendSlot) -> String {
        MixerSendDisplayModel.percentLabel(for: sendValue(slot))
    }

    private func setSend(_ slot: SendSlot, value: Double) {
        var liveMix = track.mix
        liveMix[keyPath: slot.keyPath] = min(max(value, 0), 1)
        onSetMix(liveMix)
    }

    private var displayedLevel: Double {
        levelControl.rendered(committed: track.mix.clampedLevel)
    }

    private var displayedPan: Double {
        panControl.rendered(committed: track.mix.clampedPan)
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
            levelControl.begin(with: track.mix.clampedLevel)
        }
    }

    private func updateLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        if !levelControl.isDragging {
            levelControl.begin(with: track.mix.clampedLevel)
        }
        guard levelControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = clamped
        liveMix.pan = displayedPan
        onSetMix(liveMix)
    }

    private func commitLevel() {
        // commit() resets drag state; the final value was already written via updateLevel.
        _ = levelControl.commit()
    }

    private func handlePanEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !panControl.isDragging {
                panControl.begin(with: track.mix.clampedPan)
            }
        } else {
            commitPan()
        }
    }

    private func updatePan(_ pan: Double) {
        let clamped = min(max(pan, -1), 1)
        if !panControl.isDragging {
            panControl.begin(with: track.mix.clampedPan)
        }
        guard panControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.level = displayedLevel
        liveMix.pan = clamped
        onSetMix(liveMix)
    }

    private func commitPan() {
        // commit() resets drag state; the final value was already written via updatePan.
        _ = panControl.commit()
    }
}

private struct MixerBusZone: View {
    let buses: [MixerBus]
    let tracks: [StepSequenceTrack]
    let mutedBusIDs: Set<UUID>
    @Binding var renamingBusID: UUID?
    let onAddBus: () -> Void
    let onRenameBus: (UUID, String) -> Void
    let onSetLevel: (UUID, Double) -> Void
    let onSetPan: (UUID, Double) -> Void
    let onToggleMute: (MixerBus) -> Void
    let onToggleSolo: (MixerBus) -> Void
    let onDelete: (MixerBus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BUSSES")
                        .studioText(.eyebrowBold)
                        .tracking(1.0)
                        .foregroundStyle(StudioTheme.text)
                    Text("Fixed output -> Master")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                MixerStripActionButton(
                    title: "Add Bus",
                    systemName: "plus",
                    accent: StudioTheme.violet,
                    minWidth: 72,
                    action: onAddBus
                )
            }

            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(buses.enumerated()), id: \.element.id) { index, bus in
                    MixerBusStrip(
                        bus: bus,
                        accent: busAccent(for: bus, index: index),
                        routedTrackNames: MixerRoutingDisplayModel.affectedTrackNames(for: bus.id, tracks: tracks),
                        isEffectivelyMuted: mutedBusIDs.contains(bus.id),
                        isRenaming: renamingBusID == bus.id,
                        onBeginRename: {
                            renamingBusID = bus.id
                        },
                        onCancelRename: {
                            renamingBusID = nil
                        },
                        onCommitRename: { name in
                            onRenameBus(bus.id, name)
                            renamingBusID = nil
                        },
                        onSetLevel: { onSetLevel(bus.id, $0) },
                        onSetPan: { onSetPan(bus.id, $0) },
                        onToggleMute: { onToggleMute(bus) },
                        onToggleSolo: { onToggleSolo(bus) },
                        onDelete: { onDelete(bus) }
                    )
                }

                MixerAddBusTile(onAddBus: onAddBus)
            }
        }
        .padding(.vertical, 12)
        .frame(minWidth: 250, alignment: .topLeading)
        .accessibilityIdentifier("mixer-busses-zone")
    }

    private func busAccent(for bus: MixerBus, index: Int) -> Color {
        if let color = bus.color?.lowercased() {
            switch color {
            case "cyan", "blue": return StudioTheme.cyan
            case "amber", "yellow": return StudioTheme.amber
            case "green", "success": return StudioTheme.success
            case "violet", "purple": return StudioTheme.violet
            default: break
            }
        }
        return [StudioTheme.violet, StudioTheme.cyan, StudioTheme.amber, StudioTheme.success][index % 4]
    }
}

private struct MixerAddBusTile: View {
    let onAddBus: () -> Void

    var body: some View {
        Button(action: onAddBus) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                Text("Add Bus")
                    .studioText(.labelBold)
            }
            .foregroundStyle(StudioTheme.text)
            .frame(width: 150, height: 170)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mixer-add-bus-tile")
    }
}

struct MixerInsertChainView: View {
    let inserts: [MasterBusInsert]
    let accent: Color
    let emptySlotCount: Int
    let addLabel: String
    let addAction: () -> Void
    let updateInsert: (UUID, (inout MasterBusInsert) -> Void) -> Void
    let removeInsert: (UUID) -> Void
    let reorderInserts: ([UUID]) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if inserts.count > 3 {
                ScrollView {
                    insertRows
                }
                .frame(maxHeight: 138)
            } else {
                insertRows
                ForEach(0..<emptySlotCount, id: \.self) { _ in
                    emptyInsertSlot
                }
            }
        }
    }

    private var insertRows: some View {
        VStack(spacing: 6) {
            ForEach(inserts) { insert in
                insertRow(insert)
            }
        }
    }

    private func insertRow(_ insert: MasterBusInsert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: iconName(for: insert.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(insert.name)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Text(insert.kind.summary)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                Toggle("Enabled", isOn: insertEnabledBinding(insert))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(StudioTheme.success)

                Spacer(minLength: 2)

                insertMoveButton(insert, systemName: "arrow.up", delta: -1)
                insertMoveButton(insert, systemName: "arrow.down", delta: 1)

                Button(role: .destructive) {
                    removeInsert(insert.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Remove insert")
            }
        }
        .padding(8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var emptyInsertSlot: some View {
        Button(action: addAction) {
            Label(addLabel, systemImage: "plus")
                .studioText(.micro)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.text)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func insertEnabledBinding(_ insert: MasterBusInsert) -> Binding<Bool> {
        Binding(
            get: {
                inserts.first(where: { $0.id == insert.id })?.isEnabled ?? insert.isEnabled
            },
            set: { isEnabled in
                updateInsert(insert.id) { updated in
                    updated.isEnabled = isEnabled
                }
            }
        )
    }

    private func insertMoveButton(_ insert: MasterBusInsert, systemName: String, delta: Int) -> some View {
        Button {
            move(insert, by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(moveTargetIndex(for: insert, by: delta) == nil)
    }

    private func move(_ insert: MasterBusInsert, by delta: Int) {
        guard let next = moveTargetIndex(for: insert, by: delta),
              let current = inserts.firstIndex(where: { $0.id == insert.id })
        else { return }
        var ids = inserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        reorderInserts(ids)
    }

    private func moveTargetIndex(for insert: MasterBusInsert, by delta: Int) -> Int? {
        guard let current = inserts.firstIndex(where: { $0.id == insert.id }) else { return nil }
        let next = current + delta
        guard inserts.indices.contains(next) else { return nil }
        return next
    }

    private func iconName(for kind: MasterBusInsertKind) -> String {
        switch kind {
        case .nativeFilter:
            return "line.3.horizontal.decrease.circle"
        case .nativeBitcrusher:
            return "waveform.path.ecg"
        case .auEffect:
            return "slider.horizontal.3"
        }
    }
}

private struct SendAmountControl: View {
    let slot: String
    let title: String
    let trackName: String
    let value: Double
    let accent: Color
    @Binding var isEditing: Bool
    let onChange: (Double) -> Void

    private var clampedValue: Double {
        MixerSendDisplayModel.clamped(value)
    }

    private var percentLabel: String {
        MixerSendDisplayModel.percentLabel(for: clampedValue)
    }

    private var isActive: Bool {
        MixerSendDisplayModel.isNonZero(clampedValue)
    }

    var body: some View {
        Button {
            isEditing = true
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(isActive ? StudioOpacity.softStroke : StudioOpacity.borderFaint), lineWidth: 3)

                    Circle()
                        .trim(from: 0, to: clampedValue)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(slot)
                        .studioText(.labelBold)
                        .foregroundStyle(isActive ? StudioTheme.text : StudioTheme.mutedText)
                }
                .frame(width: 34, height: 34)

                Text(percentLabel)
                    .studioText(.micro)
                    .monospacedDigit()
                    .foregroundStyle(isActive ? StudioTheme.text : StudioTheme.mutedText)
                    .frame(width: 42)
            }
            .frame(width: 48, height: 58)
            .background(
                (isEditing ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(isActive ? StudioOpacity.subtleFill : 0.018)),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isEditing || isActive ? accent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(trackName) \(title)")
        .accessibilityLabel("\(trackName) \(title)")
        .accessibilityValue(percentLabel)
        .accessibilityIdentifier("mixer-track-send-\(slot.lowercased())-\(trackName)")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(title)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    Text(percentLabel)
                        .studioText(.eyebrowBold)
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }

                Text(trackName)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)

                Slider(
                    value: Binding(
                        get: { clampedValue },
                        set: onChange
                    ),
                    in: TrackMixSettings.sendRange,
                    onEditingChanged: { editing in
                        if editing {
                            isEditing = true
                        }
                    }
                )
                .tint(accent)

                Text("Automatic wet return to main mix")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(16)
            .frame(width: 280)
            .background(StudioTheme.stageFill)
        }
    }
}

struct VerticalLevelFader: View {
    let level: Double
    let isMuted: Bool
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let filledHeight = max(12, height * clampedLevel)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(isMuted ? Color.white.opacity(StudioOpacity.selectedFill) : StudioTheme.cyan)
                    .frame(height: filledHeight)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.selectedFill))
                    .frame(width: 16, height: 4)
                    .offset(y: -filledHeight + 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        let normalized = 1 - min(max(value.location.y / max(height, 1), 0), 1)
                        onChange(normalized)
                    }
                    .onEnded { _ in
                        onEnd()
                    }
            )
        }
    }

    private var clampedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }
}
