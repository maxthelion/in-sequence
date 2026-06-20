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
        let muteState = EngineController.effectiveMixerMuteState(tracks: tracks, buses: buses)

        // Solo state never injects a banner above the strips — that shifts
        // every column down. The solo affordance lives in the master column
        // header (fixed slot, no layout shift).
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: MixerWorkspaceLayout.laneSpacing) {
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

                // Busses are siblings of the track strips — same top edge,
                // same slot grid — never a separately-headed lower zone.
                ForEach(Array(buses.enumerated()), id: \.element.id) { index, bus in
                    MixerBusStrip(
                        bus: bus,
                        accent: Self.busAccent(for: bus, index: index),
                        routedTrackNames: MixerRoutingDisplayModel.affectedTrackNames(for: bus.id, tracks: tracks),
                        isEffectivelyMuted: muteState.mutedBusIDs.contains(bus.id),
                        isRenaming: renamingBusID == bus.id,
                        onBeginRename: {
                            renamingBusID = bus.id
                        },
                        onCancelRename: {
                            renamingBusID = nil
                        },
                        onCommitRename: { name in
                            session.renameMixerBus(bus.id, name: name)
                            renamingBusID = nil
                        },
                        onSetLevel: { session.setMixerBusLevel($0, busID: bus.id) },
                        onSetPan: { session.setMixerBusPan($0, busID: bus.id) },
                        onToggleMute: { session.setMixerBusMuted(!bus.mix.isMuted, busID: bus.id) },
                        onToggleSolo: { session.setMixerBusSoloed(!bus.mix.isSoloed, busID: bus.id) },
                        onDelete: { requestDelete(bus) }
                    )
                }

                // The one control for adding busses.
                MixerAddBusTile(onAddBus: addBus)

                trailingContent
            }
            .padding(StudioMetrics.Spacing.hairline)
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

    static func busAccent(for bus: MixerBus, index: Int) -> Color {
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
    @StateObject private var sendAControl = ThrottledMixValue()
    @StateObject private var sendBControl = ThrottledMixValue()

    var body: some View {
        StudioMixerStrip(
            accent: StudioTheme.cyan,
            isHighlighted: isSelected,
            dimsContent: isEffectivelyMuted && !track.mix.isMuted
        ) {
            // Configure is folded into the title: tapping the channel name
            // opens its editor — no separate Configure/edit button (bug 134440).
            MixerStripHeader(title: track.name, caption: destinationLabel, onTitleTap: onSelect)
        } processing: {
            sendsSection
        } levels: {
            MixerStripLevelsColumn(
                level: displayedLevel,
                isMuted: track.mix.isMuted,
                meterState: engineController.channelMeterPublisher(for: .track(track.id)).displayState,
                onBegin: { beginLevelDrag() },
                onChange: { updateLevel($0) },
                onEnd: { commitLevel() }
            )
        } pan: {
            StudioRotaryKnob(
                title: "PAN",
                value: displayedPan,
                range: -1...1,
                accent: StudioTheme.violet,
                size: 34,
                format: { StudioSlideControlModel.panLabel(for: $0) },
                onChange: { _ in commitPan() },
                onLiveChange: { updatePan($0) }
            )
            .frame(maxWidth: .infinity)
            .help("\(track.name) pan")
        } actions: {
            actionsRow
        } footer: {
            trackOutputSelector
        }
    }

    private var sendsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SENDS")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            // Send knobs sit closer together now the strip is narrower (bug
            // 134440): the A/B pair reads as one cluster, not two spread fields.
            HStack(spacing: 4) {
                ForEach(SendSlot.allCases, id: \.self) { slot in
                    sendKnob(slot)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Send knobs move in place — drag turns the rotary and drives the
    /// engine live; there is no popover slider.
    private func sendKnob(_ slot: SendSlot) -> some View {
        StudioRotaryKnob(
            title: slot.rawValue,
            value: displayedSend(slot),
            range: TrackMixSettings.sendRange,
            accent: slot.accent,
            size: 30,
            format: { MixerSendDisplayModel.percentLabel(for: $0) },
            onChange: { commitSend(slot, value: $0) },
            onLiveChange: { updateSend(slot, value: $0) }
        )
        .help("\(track.name) \(slot.title)")
        .accessibilityIdentifier("mixer-track-send-\(slot.rawValue.lowercased())-\(track.name)")
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            MixerStripActionButton(
                title: "",
                systemName: track.mix.isMuted ? "speaker.slash.fill" : "speaker.slash",
                accent: StudioTheme.amber,
                isActive: track.mix.isMuted,
                minWidth: 20
            ) {
                onToggleMute()
            }
            .help(track.mix.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel("\(track.name) mute")

            MixerStripActionButton(
                title: "",
                systemName: "headphones",
                accent: StudioTheme.amber,
                isActive: track.mix.isSoloed,
                minWidth: 20
            ) {
                onToggleSolo()
            }
            .help(track.mix.isSoloed ? "Unsolo" : "Solo")
            .accessibilityLabel("\(track.name) solo")
        }
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
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText)
                Text(isRoutingApplying ? "Applying..." : outputTitle)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRoutingApplying)
        .help("Output routing")
        .accessibilityLabel("\(track.name) output")
        .accessibilityValue(isRoutingApplying ? "Applying" : outputTitle)
    }

    private func sendControl(_ slot: SendSlot) -> ThrottledMixValue {
        slot == .a ? sendAControl : sendBControl
    }

    private func displayedSend(_ slot: SendSlot) -> Double {
        sendControl(slot).rendered(committed: MixerSendDisplayModel.clamped(track.mix[keyPath: slot.keyPath]))
    }

    private func updateSend(_ slot: SendSlot, value: Double) {
        let control = sendControl(slot)
        let clamped = MixerSendDisplayModel.clamped(value)
        if !control.isDragging {
            control.begin(with: MixerSendDisplayModel.clamped(track.mix[keyPath: slot.keyPath]))
        }
        guard control.update(clamped) else { return }
        var liveMix = track.mix
        liveMix[keyPath: slot.keyPath] = clamped
        onSetMix(liveMix)
    }

    private func commitSend(_ slot: SendSlot, value: Double) {
        let control = sendControl(slot)
        let clamped = MixerSendDisplayModel.clamped(value)
        _ = control.commit()
        var liveMix = track.mix
        liveMix[keyPath: slot.keyPath] = clamped
        onSetMix(liveMix)
    }

    private var displayedLevel: Double {
        levelControl.rendered(committed: track.mix.clampedLevel)
    }

    private var displayedPan: Double {
        panControl.rendered(committed: track.mix.clampedPan)
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
        onSetMix(liveMix)
    }

    private func commitLevel() {
        // commit() resets drag state; the final value was already written via updateLevel.
        _ = levelControl.commit()
    }

    private func updatePan(_ pan: Double) {
        let clamped = min(max(pan, -1), 1)
        if !panControl.isDragging {
            panControl.begin(with: track.mix.clampedPan)
        }
        guard panControl.update(clamped) else { return }
        var liveMix = track.mix
        liveMix.pan = clamped
        onSetMix(liveMix)
    }

    private func commitPan() {
        _ = panControl.commit()
    }
}

/// Small, uniform strip header: every strip kind titles itself with the same
/// compact type so channel names read as one row.
struct MixerStripHeader<Leading: View>: View {
    let title: String
    var caption: String? = nil
    var accentDot: Color? = nil
    /// When set, the title block itself is the configure affordance — tapping
    /// the channel name opens its editor, so no separate Configure button is
    /// needed (bug 134440).
    var onTitleTap: (() -> Void)? = nil
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 7) {
            // Per-strip action affordance (e.g. the channel "edit" button)
            // sits to the left of the name instead of crowding the footer row.
            leading

            if let accentDot {
                Circle()
                    .fill(accentDot)
                    .frame(width: 9, height: 9)
            }
            titleBlock
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let onTitleTap {
            Button(action: onTitleTap) {
                titleLabel
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Configure \(title)")
            .accessibilityLabel("\(title) configure")
        } else {
            titleLabel
        }
    }

    private var titleLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
    }
}

extension MixerStripHeader where Leading == EmptyView {
    init(title: String, caption: String? = nil, accentDot: Color? = nil, onTitleTap: (() -> Void)? = nil) {
        self.init(title: title, caption: caption, accentDot: accentDot, onTitleTap: onTitleTap) { EmptyView() }
    }
}

/// The levels slot every strip shares: centered fader (with live meter
/// lanes) and the dB readout beneath, so faders and meters align row-for-row
/// across track, bus, send, and master columns.
struct MixerStripLevelsColumn: View {
    let level: Double
    let isMuted: Bool
    var meterState: MasterMeterDisplayState? = nil
    var isInteractive = true
    var valueLabel: String? = nil
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            VerticalLevelFader(
                level: level,
                isMuted: isMuted,
                meterState: meterState,
                isInteractive: isInteractive,
                onBegin: onBegin,
                onChange: onChange,
                onEnd: onEnd
            )
            .frame(
                width: StudioMixerStripMetrics.faderSize.width,
                height: StudioMixerStripMetrics.faderSize.height
            )

            // Bold-flat pass: level values read in the accent colour.
            Text(valueLabel ?? StudioLevelFormat.dBLabel(forLinear: level))
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.cyan)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MixerAddBusTile: View {
    let onAddBus: () -> Void

    var body: some View {
        StudioAddCard(label: "Add Bus", minHeight: StudioMixerStripMetrics.stripHeight - 2 * StudioMetrics.Spacing.comfortable, action: onAddBus)
            .frame(width: MixerWorkspaceLayout.addBusTileWidth)
            .accessibilityIdentifier("mixer-add-bus-tile")
    }
}

struct MixerInsertChainView: View {
    let inserts: [MasterBusInsert]
    let accent: Color
    let emptySlotCount: Int
    var maxAddAffordances: Int = .max
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
                ForEach(0..<emptySlotCount, id: \.self) { index in
                    if index < maxAddAffordances {
                        emptyInsertSlot
                    } else {
                        inertEmptySlot
                    }
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
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 22, height: 22)
                    .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

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
        .padding(StudioMetrics.Spacing.snug)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
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
        .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.75), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [4, 4]))
        )
    }

    private var inertEmptySlot: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
            .fill(StudioTheme.inset)
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.45), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [4, 4]))
            )
            .accessibilityHidden(true)
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

/// Fader and live meter in one lane, the channel-strip miniature of the
/// master fader-meter: thin L/R gradient meter lanes behind a translucent
/// level fill with a cap. Render with `isInteractive: false` for strips
/// whose level is not user-adjustable (send returns) — the lane then reads
/// as a pure meter.
struct VerticalLevelFader: View {
    let level: Double
    let isMuted: Bool
    var meterState: MasterMeterDisplayState? = nil
    var isInteractive = true
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let usableHeight = max(0, height - thumbDiameter)
            // The thumb travels within the trough; its centre maps the level.
            let thumbCenterY = thumbDiameter / 2 + (1 - clampedLevel) * usableHeight

            ZStack(alignment: .bottom) {
                // The trough carries the live L/R meter lanes — prominent,
                // like the master fader, so channels read levels too.
                if let meterState {
                    HStack(alignment: .bottom, spacing: 4) {
                        meterLane(peak: meterState.leftPeakDBFS, height: height)
                        meterLane(peak: meterState.rightPeakDBFS, height: height)
                    }
                    .animation(.linear(duration: 0.05), value: meterState.leftPeakDBFS)
                    .animation(.linear(duration: 0.05), value: meterState.rightPeakDBFS)
                } else {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .fill(StudioTheme.inset)
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                                .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: StudioMetrics.borderWidth)
                        )
                }

                if isInteractive {
                    // The draggable blue slide control, vertical: a thin
                    // accent rail with a round thumb at the level position.
                    Capsule(style: .continuous)
                        .fill(StudioTheme.border.opacity(StudioOpacity.softStroke))
                        .frame(width: 4)
                        .padding(.vertical, thumbDiameter / 2)

                    Capsule(style: .continuous)
                        .fill(isMuted ? Color.white.opacity(StudioOpacity.selectedFill) : StudioTheme.cyan)
                        .frame(width: 4, height: max(0, usableHeight * clampedLevel))
                        .offset(y: -thumbDiameter / 2)

                    Circle()
                        .fill(isMuted ? Color.white.opacity(0.85) : StudioTheme.cyan)
                        .overlay(
                            Circle().stroke(StudioTheme.inset, lineWidth: 2)
                        )
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        // Position the thumb centre; ZStack is bottom-aligned
                        // so offset up from the bottom edge.
                        .offset(y: -(height - thumbCenterY) + thumbDiameter / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                isInteractive
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onBegin()
                            let travel = value.location.y - thumbDiameter / 2
                            let normalized = 1 - min(max(travel / max(usableHeight, 1), 0), 1)
                            onChange(normalized)
                        }
                        .onEnded { _ in
                            onEnd()
                        }
                    : nil
            )
        }
    }

    private var thumbDiameter: CGFloat { 16 }

    private func meterLane(peak: Double, height: CGFloat) -> some View {
        let normalizedPeak = MasterMeterLevelScale.normalized(peak)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                .fill(StudioTheme.inset)
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: StudioMetrics.borderWidth)
                )

            MasterMeterLevelScale.meterGradient
                .mask {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: height * normalizedPeak)
                    }
                }
                .opacity(normalizedPeak > 0 ? 0.95 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var clampedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }
}
