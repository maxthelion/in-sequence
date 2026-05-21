import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var isMasterOverlayPresented = false
    @State private var selectedSendInsertIDs: [SendBusID: UUID] = [:]
    @State private var addSendFXRequest: SendBusAddFXRequest?

    var body: some View {
        GeometryReader { proxy in
            let presentation = MasterOutputColumnLayout.presentation(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: "Mixer", eyebrow: "Track strips active now", accent: StudioTheme.cyan) {
                    masterAwareMixer(presentation: presentation)
                }

                StudioPanel(title: "Voice Routes", eyebrow: "Future drum and sliced-loop mixer coverage", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Tagged Voices", detail: "Drum and slice tracks")
                        StudioPlaceholderTile(title: "Per-Voice Treatment", detail: "Mute, bus, FX, and gain")
                    }
                }
            }
            .padding(20)
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
    }

    private func masterAwareMixer(presentation: MasterOutputColumnPresentation) -> some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    MixerView(document: $document, onEditTrack: onSelectTrack)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: MixerWorkspaceLayout.primaryMixerLaneHeight,
                            alignment: .topLeading
                        )

                    switch presentation {
                    case let .fullColumn(width):
                        Color.clear
                            .frame(width: width)
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

                sendBusDetails
                    .padding(.trailing, sendBusTrailingReserve(for: presentation))
            }

            if case .fullColumn = presentation {
                MasterOutputColumnView()
                    .zIndex(1)
            }

            if presentation.usesCompactOverlay, isMasterOverlayPresented {
                MasterOutputColumnView()
                    .shadow(color: .black.opacity(0.35), radius: 18, x: -8, y: 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }

    private func sendBusTrailingReserve(for presentation: MasterOutputColumnPresentation) -> CGFloat {
        switch presentation {
        case let .fullColumn(width):
            width + 14
        case .compactStrip:
            0
        }
    }

    private var sendBusDetails: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                sendBusDetail(sendBus(.sendA), accent: StudioTheme.cyan)
                sendBusDetail(sendBus(.sendB), accent: StudioTheme.violet)
            }

            VStack(alignment: .leading, spacing: 12) {
                sendBusDetail(sendBus(.sendA), accent: StudioTheme.cyan)
                sendBusDetail(sendBus(.sendB), accent: StudioTheme.violet)
            }
        }
        .accessibilityIdentifier("mixer-send-bus-detail-surface")
    }

    private func sendBus(_ busID: SendBusID) -> SendBusState {
        session.store.sendBus(id: busID)
    }

    private func sendBusDetail(_ sendBus: SendBusState, accent: Color) -> some View {
        let selectedInsert = selectedInsert(in: sendBus)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sendBus.name.uppercased())
                        .studioText(.eyebrowBold)
                        .tracking(1.0)
                        .foregroundStyle(StudioTheme.text)
                    Text("Automatic wet return")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                if !sendBus.inserts.isEmpty {
                    addSendFXButton(sendBus.id, accent: accent)
                }
            }

            if sendBus.inserts.isEmpty {
                sendInsertList(sendBus, accent: accent)
                    .frame(maxWidth: 360, alignment: .topLeading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        sendInsertList(sendBus, accent: accent)
                            .frame(minWidth: 280, maxWidth: 360, alignment: .topLeading)
                        sendInsertEditor(selectedInsert, bus: sendBus, accent: accent)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sendInsertList(sendBus, accent: accent)
                        sendInsertEditor(selectedInsert, bus: sendBus, accent: accent)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixer-\(sendBus.id.rawValue)-detail")
    }

    private func sendInsertList(_ sendBus: SendBusState, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INSERTS")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("\(sendBus.inserts.count)")
                    .studioText(.microEmphasis)
                    .foregroundStyle(accent)
            }

            if sendBus.inserts.isEmpty {
                Button {
                    addSendFXRequest = SendBusAddFXRequest(busID: sendBus.id)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Empty Chain", systemImage: "plus")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                        Text("Add an insert to \(sendBus.name)")
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(10)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(accent.opacity(StudioOpacity.softStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                )
            } else {
                VStack(spacing: 7) {
                    ForEach(sendBus.inserts) { insert in
                        sendInsertRow(insert, bus: sendBus, accent: accent)
                    }
                }
            }
        }
    }

    private func sendInsertRow(_ insert: SendBusInsert, bus: SendBusState, accent: Color) -> some View {
        let isSelected = selectedInsert(in: bus)?.id == insert.id
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: insertIconName(for: insert.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 24, height: 24)
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

                Spacer(minLength: 4)

                Toggle("Enabled", isOn: sendInsertBinding(insert.id, busID: bus.id, keyPath: \.isEnabled, fallback: insert.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(StudioTheme.success)
            }

            HStack(spacing: 6) {
                Text(insert.isEnabled ? "Enabled" : "Bypassed")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(insert.isEnabled ? StudioTheme.success : StudioTheme.mutedText)

                Spacer()

                insertMoveButton(insert, bus: bus, systemName: "arrow.up", delta: -1)
                insertMoveButton(insert, bus: bus, systemName: "arrow.down", delta: 1)

                Button(role: .destructive) {
                    session.removeSendBusInsert(insert.id, from: bus.id)
                    selectedSendInsertIDs[bus.id] = bus.inserts.first(where: { $0.id != insert.id })?.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Remove insert")
            }
        }
        .padding(9)
        .background(isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(isSelected ? accent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .onTapGesture {
            selectedSendInsertIDs[bus.id] = insert.id
        }
    }

    @ViewBuilder
    private func sendInsertEditor(_ insert: SendBusInsert?, bus: SendBusState, accent: Color) -> some View {
        if let insert {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("EDIT")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer()
                    Text(insert.name)
                        .studioText(.microEmphasis)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }

                sendSliderRow(
                    title: "Wet",
                    value: sendInsertBinding(insert.id, busID: bus.id, keyPath: \.wetDry, fallback: insert.wetDry),
                    range: 0...1,
                    label: "\(Int((insert.wetDry * 100).rounded()))%",
                    accent: accent
                )

                sendKindEditor(insert, busID: bus.id, accent: accent)
            }
            .padding(8)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        } else {
            StudioPlaceholderTile(title: "No Insert Selected", detail: "Add FX to shape the wet return", accent: accent)
        }
    }

    @ViewBuilder
    private func sendKindEditor(_ insert: SendBusInsert, busID: SendBusID, accent: Color) -> some View {
        switch insert.kind {
        case let .nativeFilter(settings):
            Picker("Mode", selection: sendFilterModeBinding(insertID: insert.id, busID: busID, settings: settings)) {
                Text("Low Pass").tag(MasterFilterSettings.Mode.lowPass)
                Text("High Pass").tag(MasterFilterSettings.Mode.highPass)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            sendSliderRow(
                title: "Cutoff",
                value: sendFilterCutoffBinding(insertID: insert.id, busID: busID, settings: settings),
                range: 20...20_000,
                label: "\(Int(settings.cutoffHz.rounded())) Hz",
                accent: accent
            )
            sendSliderRow(
                title: "Res",
                value: sendFilterResonanceBinding(insertID: insert.id, busID: busID, settings: settings),
                range: 0...1,
                label: String(format: "%.2f", settings.resonance),
                accent: accent
            )

        case let .nativeBitcrusher(settings):
            Stepper("Bits: \(settings.bitDepth)", value: sendBitDepthBinding(insertID: insert.id, busID: busID, settings: settings), in: 4...16)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)
                .controlSize(.small)
            sendSliderRow(
                title: "Rate",
                value: sendBitRateBinding(insertID: insert.id, busID: busID, settings: settings),
                range: 0.05...1,
                label: "\(Int((settings.sampleRateScale * 100).rounded()))%",
                accent: accent
            )
            sendSliderRow(
                title: "Drive",
                value: sendBitDriveBinding(insertID: insert.id, busID: busID, settings: settings),
                range: 0...1,
                label: "\(Int((settings.drive * 100).rounded()))%",
                accent: accent
            )

        case .auEffect:
            Label("AU Effect", systemImage: "slider.horizontal.3")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private func sendSliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range)
                .tint(accent)
            Text(label)
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private func addSendFXButton(_ busID: SendBusID, accent: Color) -> some View {
        Button {
            addSendFXRequest = SendBusAddFXRequest(busID: busID)
        } label: {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(accent)
    }

    private func addSendFXSheet(for busID: SendBusID) -> some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(busID.displayName) FX")
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    Button("Done") {
                        addSendFXRequest = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(busID == .sendA ? StudioTheme.cyan : StudioTheme.violet)
                }

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

                let effects = engineController.availableAudioEffects
                if effects.isEmpty {
                    Text("No AU effects found")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(effects.prefix(16)) { effect in
                                addSendFXChoice(title: effect.displayName, systemName: "slider.horizontal.3", busID: busID) {
                                    .auEffect(effect)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(18)
            .frame(width: 360)
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
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func selectedInsert(in sendBus: SendBusState) -> SendBusInsert? {
        guard let selectedID = selectedSendInsertIDs[sendBus.id] else {
            return sendBus.inserts.first
        }
        return sendBus.inserts.first(where: { $0.id == selectedID }) ?? sendBus.inserts.first
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

    private func sendFilterModeBinding(insertID: UUID, busID: SendBusID, settings: MasterFilterSettings) -> Binding<MasterFilterSettings.Mode> {
        Binding(
            get: { sendFilterSettings(insertID, busID: busID)?.mode ?? settings.mode },
            set: { mode in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.mode = mode
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func sendFilterCutoffBinding(insertID: UUID, busID: SendBusID, settings: MasterFilterSettings) -> Binding<Double> {
        Binding(
            get: { sendFilterSettings(insertID, busID: busID)?.cutoffHz ?? settings.cutoffHz },
            set: { cutoff in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.cutoffHz = cutoff
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func sendFilterResonanceBinding(insertID: UUID, busID: SendBusID, settings: MasterFilterSettings) -> Binding<Double> {
        Binding(
            get: { sendFilterSettings(insertID, busID: busID)?.resonance ?? settings.resonance },
            set: { resonance in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.resonance = resonance
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func sendBitDepthBinding(insertID: UUID, busID: SendBusID, settings: MasterBitcrusherSettings) -> Binding<Int> {
        Binding(
            get: { sendBitcrusherSettings(insertID, busID: busID)?.bitDepth ?? settings.bitDepth },
            set: { bitDepth in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.bitDepth = bitDepth
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func sendBitRateBinding(insertID: UUID, busID: SendBusID, settings: MasterBitcrusherSettings) -> Binding<Double> {
        Binding(
            get: { sendBitcrusherSettings(insertID, busID: busID)?.sampleRateScale ?? settings.sampleRateScale },
            set: { value in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.sampleRateScale = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func sendBitDriveBinding(insertID: UUID, busID: SendBusID, settings: MasterBitcrusherSettings) -> Binding<Double> {
        Binding(
            get: { sendBitcrusherSettings(insertID, busID: busID)?.drive ?? settings.drive },
            set: { value in
                session.updateSendBusInsert(insertID, in: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func sendFilterSettings(_ insertID: UUID, busID: SendBusID) -> MasterFilterSettings? {
        guard let insert = sendBus(busID).inserts.first(where: { $0.id == insertID }),
              case let .nativeFilter(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func sendBitcrusherSettings(_ insertID: UUID, busID: SendBusID) -> MasterBitcrusherSettings? {
        guard let insert = sendBus(busID).inserts.first(where: { $0.id == insertID }),
              case let .nativeBitcrusher(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func insertMoveButton(_ insert: SendBusInsert, bus: SendBusState, systemName: String, delta: Int) -> some View {
        Button {
            move(insert, in: bus, by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(moveTargetIndex(for: insert, in: bus, by: delta) == nil)
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

    private func insertIconName(for kind: MasterBusInsertKind) -> String {
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

private enum MixerWorkspaceLayout {
    static let primaryMixerLaneHeight: CGFloat = 580
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
                    .stroke(StudioTheme.amber.opacity(0.7), lineWidth: 1)
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
                .fill(Color.white.opacity(0.06))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .fill(state.isClipLatched ? Color.red : StudioTheme.success)
                        .frame(height: max(4, height * peak))
                }
        }
    }
}
