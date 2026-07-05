import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var isMasterOverlayPresented = false
    @State private var selectedSendInsertIDs: [SendBusID: UUID] = [:]
    @State private var sendInsertEditorRequest: SendInsertEditorRequest?
    @State private var addSendFXRequest: SendBusAddFXRequest?

    var body: some View {
        GeometryReader { proxy in
            let presentation = MasterOutputColumnLayout.presentation(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 18) {
                // The top-nav pill already names this page; the panel renders
                // no header of its own (ux-canon rule 1).
                StudioPanel(title: "Mixer", accent: StudioTheme.cyan, showsHeader: false) {
                    masterAwareMixer(presentation: presentation)
                }
            }
            .padding(StudioMetrics.Spacing.section)
            .onChange(of: presentation.usesCompactOverlay) {
                if !presentation.usesCompactOverlay {
                    isMasterOverlayPresented = false
                }
            }
        }
        .frame(minHeight: 920)
        .sheet(item: $addSendFXRequest) { request in
            addSendFXSheet(for: request.busID)
        }
        // The standard StudioModal FX editor sheet (bug 20260703-093500) —
        // never a floating mini-panel.
        .sheet(item: $sendInsertEditorRequest) { request in
            sendInsertEditorSheet(request)
        }
    }

    private func masterAwareMixer(presentation: MasterOutputColumnPresentation) -> some View {
        // Sends group next to the master, not among the channels: at full
        // width they sit as fixed siblings just before the master column;
        // in the compact presentation they trail the scrolling strips so
        // narrow windows stay usable.
        ZStack(alignment: .trailing) {
            HStack(alignment: .top, spacing: MixerWorkspaceLayout.laneSpacing) {
                MixerView(document: $document, onEditTrack: onSelectTrack) {
                    if presentation.usesCompactOverlay {
                        sendReturnStrips
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: MixerWorkspaceLayout.primaryMixerLaneHeight,
                    alignment: .topLeading
                )

                switch presentation {
                case .fullColumn:
                    sendReturnStrips
                    MasterOutputColumnView()
                case let .compactStrip(width):
                    MasterOutputCompactStrip(
                        width: width,
                        isExpanded: isMasterOverlayPresented,
                        meterState: engineController.masterMeterPublisher.displayState
                    ) {
                        isMasterOverlayPresented.toggle()
                    }
                }
            }

            if presentation.usesCompactOverlay, isMasterOverlayPresented {
                MasterOutputColumnView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }

    private var sendReturnStrips: some View {
        HStack(alignment: .top, spacing: MixerWorkspaceLayout.laneSpacing) {
            sendReturnStrip(sendBus(.sendA), accent: StudioTheme.cyan)
            sendReturnStrip(sendBus(.sendB), accent: StudioTheme.violet)
        }
        .accessibilityIdentifier("mixer-send-return-strips")
    }

    private func sendReturnStrip(_ sendBus: SendBusState, accent: Color) -> some View {
        let meterState = engineController.channelMeterPublisher(for: .send(sendBus.id)).displayState
        return StudioMixerStrip(
            width: MixerWorkspaceLayout.sendReturnStripWidth,
            accent: accent
        ) {
            MixerStripHeader(title: sendBus.name.uppercased(), accentDot: accent)
        } processing: {
            ScrollView(showsIndicators: false) {
                sendInsertList(sendBus, accent: accent)
            }
        } levels: {
            // The wet return has no user fader — the lane is a pure meter,
            // aligned with the channel faders either side of it.
            MixerStripLevelsColumn(
                level: 0,
                isMuted: false,
                meterState: meterState,
                isInteractive: false,
                valueLabel: meterValueLabel(for: meterState),
                onBegin: {},
                onChange: { _ in },
                onEnd: {}
            )
        } pan: {
            // No pan on the wet return — Color.clear (not EmptyView) keeps
            // the slot's height so actions/footers align across strips.
            Color.clear
        } actions: {
            // Each insert opens the standard FX editor sheet on tap (see
            // sendInsertRow); the only strip-level action is Add.
            if !sendBus.inserts.isEmpty {
                addSendFXButton(sendBus.id, accent: accent)
            }
        } footer: {
            Text("→ Master")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .accessibilityIdentifier("mixer-\(sendBus.id.rawValue)-return-strip")
    }

    private func meterValueLabel(for meterState: MasterMeterDisplayState) -> String {
        StudioLevelFormat.dBFSLabel(forPeak: max(meterState.leftPeakDBFS, meterState.rightPeakDBFS))
    }

    private func sendBus(_ busID: SendBusID) -> SendBusState {
        session.store.sendBus(id: busID)
    }

    private func sendInsertList(_ sendBus: SendBusState, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FX")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("\(sendBus.inserts.count)")
                    .studioText(.microEmphasis)
                    .foregroundStyle(accent)
            }

            if sendBus.inserts.isEmpty {
                // Bare plus tile — no descriptive text (matches the Scenes
                // +FX treatment from batch 1).
                Button {
                    addSendFXRequest = SendBusAddFXRequest(busID: sendBus.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(accent.opacity(StudioOpacity.softStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 5]))
                )
                .help("Add FX to \(sendBus.name)")
                .accessibilityLabel("Add FX to \(sendBus.name)")
            } else {
                VStack(spacing: 7) {
                    ForEach(sendBus.inserts) { insert in
                        sendInsertRow(insert, bus: sendBus, accent: accent)
                    }
                }
            }
        }
    }

    /// Name-only clickable row: the slim strip lists each insert as just its
    /// name; tapping opens the standard StudioModal FX editor sheet that holds
    /// enable/bypass, params, reorder and remove. No inline controls crammed
    /// into the ~96pt strip (bug 20260629-095947).
    private func sendInsertRow(_ insert: SendBusInsert, bus: SendBusState, accent: Color) -> some View {
        let isSelected = selectedSendInsertIDs[bus.id] == insert.id
        return Button {
            // One tap selects AND opens the editor (no separate "Edit FX" step).
            selectedSendInsertIDs[bus.id] = insert.id
            sendInsertEditorRequest = SendInsertEditorRequest(busID: bus.id, insertID: insert.id)
        } label: {
            // Name only — dot + chevron removed so the name gets the full strip
            // width (bug 20260629-140925); enabled state reads via text colour.
            Text(insert.name)
                .studioText(.label)
                .foregroundStyle(insert.isEnabled ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, StudioMetrics.Spacing.snug)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Colour identifies, it never floods (ux-canon rule 12):
                // selection reads from the accent outline, not a tinted row fill.
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(isSelected ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(insert.name)
    }

    /// The standard FX editor sheet for a send-return insert. Resolves the
    /// LIVE insert on every render so the sheet tracks edits; a concurrently
    /// removed insert renders nothing (Remove closes the sheet).
    @ViewBuilder
    private func sendInsertEditorSheet(_ request: SendInsertEditorRequest) -> some View {
        let bus = sendBus(request.busID)
        if let insert = bus.inserts.first(where: { $0.id == request.insertID }) {
            FXInsertEditorSheet(
                name: insert.name,
                kind: insert.kind,
                accent: sendAccent(for: request.busID),
                isEnabled: sendInsertBinding(insert.id, busID: bus.id, keyPath: \.isEnabled, fallback: insert.isEnabled),
                wet: sendInsertBinding(insert.id, busID: bus.id, keyPath: \.wetDry, fallback: insert.wetDry),
                canMoveUp: moveTargetIndex(for: insert, in: bus, by: -1) != nil,
                canMoveDown: moveTargetIndex(for: insert, in: bus, by: 1) != nil,
                onMove: { delta in move(insert, in: sendBus(request.busID), by: delta) },
                onRemove: {
                    session.removeSendBusInsert(insert.id, from: bus.id)
                    selectedSendInsertIDs[bus.id] = bus.inserts.first(where: { $0.id != insert.id })?.id
                    sendInsertEditorRequest = nil
                },
                onClose: { sendInsertEditorRequest = nil },
                mutateKind: { mutation in
                    session.updateSendBusInsert(insert.id, in: bus.id) { editing in
                        mutation(&editing.kind)
                    }
                }
            )
        }
    }

    /// The one chrome accent of each send strip (matches `sendReturnStrips`).
    private func sendAccent(for busID: SendBusID) -> Color {
        busID == .sendA ? StudioTheme.cyan : StudioTheme.violet
    }

    private func addSendFXButton(_ busID: SendBusID, accent: Color) -> some View {
        MixerStripActionButton(title: "Add", systemName: "plus", accent: accent, minWidth: 56) {
            addSendFXRequest = SendBusAddFXRequest(busID: busID)
        }
    }

    private func addSendFXSheet(for busID: SendBusID) -> some View {
        StudioModal(
            title: "\(busID.displayName) FX",
            minWidth: 360,
            onClose: { addSendFXRequest = nil }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    addSendFXChoice(title: "Filter", systemName: "line.3.horizontal.decrease.circle", busID: busID) {
                        .filter()
                    }
                    addSendFXChoice(title: "Bitcrusher", systemName: "waveform.path.ecg", busID: busID) {
                        .bitcrusher()
                    }
                }

                Divider()
                    .overlay(StudioTheme.border)

                Text("AU EFFECT")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                AUEffectPickerList(effects: engineController.availableAudioEffects) { effect in
                    addSendFXChoice(title: effect.displayName, systemName: "slider.horizontal.3", busID: busID) {
                        .auEffect(effect)
                    }
                }
            }
        }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
    }

    private func addSendFXChoice(
        title: String,
        systemName: String,
        busID: SendBusID,
        makeInsert: @escaping () -> SendBusInsert
    ) -> some View {
        Button {
            let insert = makeInsert()
            session.addSendBusInsert(insert, to: busID)
            selectedSendInsertIDs[busID] = insert.id
            addSendFXRequest = nil
        } label: {
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
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func sendInsertBinding<Value>(
        _ insertID: UUID,
        busID: SendBusID,
        keyPath: WritableKeyPath<SendBusInsert, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                sendBus(busID).inserts.first(where: { $0.id == insertID })?[keyPath: keyPath]
                    ?? fallback
            },
            set: { value in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    insert[keyPath: keyPath] = value
                }
            }
        )
    }

    private func move(_ insert: SendBusInsert, in bus: SendBusState, by delta: Int) {
        guard let next = moveTargetIndex(for: insert, in: bus, by: delta),
              let current = bus.inserts.firstIndex(where: { $0.id == insert.id })
        else { return }
        var ids = bus.inserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        session.reorderSendBusInserts(ids, in: bus.id)
    }

    private func moveTargetIndex(for insert: SendBusInsert, in bus: SendBusState, by delta: Int) -> Int? {
        guard let current = bus.inserts.firstIndex(where: { $0.id == insert.id }) else { return nil }
        let next = current + delta
        guard bus.inserts.indices.contains(next) else { return nil }
        return next
    }

}

enum MixerWorkspaceLayout {
    static let primaryMixerLaneHeight: CGFloat = 580
    static let laneSpacing: CGFloat = 10
    static let busStripWidth: CGFloat = StudioMixerStripMetrics.stripWidth
    static let addBusTileWidth: CGFloat = 116
    static let sendReturnStripWidth: CGFloat = StudioMixerStripMetrics.stripWidth
}

struct MixerStripActionButton: View {
    let title: String
    var systemName: String?
    var accent: Color = StudioTheme.cyan
    var isActive = false
    var minWidth: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .studioText(.microEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isActive ? StudioTheme.background : StudioTheme.text)
            .frame(minWidth: minWidth, minHeight: 26)
            .padding(.horizontal, 7)
            // Colour identifies, it never floods (ux-canon rule 12): an
            // engaged action chip is fully solid accent with dark text.
            .background(
                (isActive ? accent : Color.white.opacity(StudioOpacity.subtleFill)),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isActive ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MasterOutputCompactStrip: View {
    let width: CGFloat
    let isExpanded: Bool
    let meterState: MasterMeterDisplayState
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.right" : "slider.vertical.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)

                Text("MSTR")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: 24)

                CompactMasterMeter(state: meterState)
                    .frame(width: 12, height: 110)

                if meterState.isClipLatched {
                    Text("CLIP")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(Color.red)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 24)
                }
            }
            .frame(width: width)
            .frame(minHeight: 300)
            .padding(.vertical, 10)
            .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.amber.opacity(0.7), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Master Out")
        .accessibilityIdentifier("mixer-master-out-compact-strip")
    }
}

private struct SendBusAddFXRequest: Identifiable {
    let busID: SendBusID
    var id: SendBusID { busID }
}

/// Sheet-presentation token for the one send-return insert being edited.
private struct SendInsertEditorRequest: Identifiable {
    let busID: SendBusID
    let insertID: UUID
    var id: UUID { insertID }
}

private struct CompactMasterMeter: View {
    let state: MasterMeterDisplayState

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let peak = max(
                MasterMeterLevelScale.normalized(state.leftPeakDBFS),
                MasterMeterLevelScale.normalized(state.rightPeakDBFS)
            )
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .fill(StudioTheme.inset)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .fill(state.isClipLatched ? Color.red : StudioTheme.success)
                        .frame(height: max(4, height * peak))
                }
        }
    }
}
