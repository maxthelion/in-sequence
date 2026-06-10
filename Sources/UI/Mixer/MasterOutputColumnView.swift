import SwiftUI

struct MasterOutputColumnView: View {
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @StateObject private var gainControl = ThrottledMixValue()
    @State private var isAddFXPresented = false

    private var masterBus: MasterBusState { session.store.masterBus }
    private var selection: MasterBusABSelection { masterBus.abSelection ?? fallbackSelection }
    private var liveCrossfader: Double? { engineController.masterBusPerformanceOverlay.crossfaderOverride }
    private var crossfaderValue: Double { liveCrossfader ?? selection.crossfader }
    private var sceneA: MasterBusScene { masterBus.scene(id: selection.sceneAID) ?? masterBus.activeScene }
    private var sceneB: MasterBusScene {
        masterBus.scene(id: selection.sceneBID)
            ?? masterBus.scenes.first { $0.id != sceneA.id }
            ?? MasterBusScene.sceneB
    }
    private var meterState: MasterMeterDisplayState {
        engineController.masterMeterPublisher.displayState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MasterCrossfaderView(
                sceneAName: sceneA.name,
                sceneBName: sceneB.name,
                value: crossfaderValue,
                hasLiveOverride: liveCrossfader != nil,
                showsPersistenceActions: false,
                onChange: { engineController.setLiveMasterCrossfader($0) }
            )
            section("FX") {
                masterInsertSection
            }
            section("Output") {
                masterOutputSection
            }
        }
        .padding(12)
        .frame(width: MasterOutputColumnLayout.fullColumnWidth, alignment: .topLeading)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.amber.opacity(0.7), lineWidth: 1)
        )
        .sheet(isPresented: $isAddFXPresented) {
            addFXSheet
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixer-master-out-column")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MASTER OUT")
                    .studioText(.eyebrowBold)
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)
            }
            Spacer(minLength: 6)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            content()
        }
        .padding(.top, 2)
    }

    private var masterInsertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After Scene A/B mix")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)

            MixerInsertChainView(
                inserts: masterBus.masterInserts,
                accent: StudioTheme.amber,
                emptySlotCount: emptySlotCount,
                addLabel: "Add FX",
                addAction: { isAddFXPresented = true },
                updateInsert: { insertID, edit in
                    session.updateMasterOutputInsert(insertID, edit: edit)
                },
                removeInsert: { insertID in
                    session.removeMasterOutputInsert(insertID)
                },
                reorderInserts: { ids in
                    session.reorderMasterOutputInserts(ids)
                }
            )
        }
    }

    private func masterInsertRow(_ insert: MasterBusInsert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: iconName(for: insert.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 22, height: 22)
                    .background(StudioTheme.amber.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

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
                    session.removeMasterOutputInsert(insert.id)
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
        Button {
            isAddFXPresented = true
        } label: {
            Label("Add FX", systemImage: "plus")
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
        .accessibilityLabel("Add master output FX")
    }

    private var addFXSheet: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Master Out FX")
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    StudioModalCloseButton {
                        isAddFXPresented = false
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    addFXButton(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                        session.addMasterOutputInsert(.filter())
                        isAddFXPresented = false
                    }
                    addFXButton(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                        session.addMasterOutputInsert(.bitcrusher())
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
                                addFXButton(title: effect.displayName, systemName: "slider.horizontal.3") {
                                    session.addMasterOutputInsert(.auEffect(effect))
                                    isAddFXPresented = false
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

    private var masterOutputSection: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                MasterOutputFaderMeter(
                    gain: displayedGain,
                    meterState: meterState,
                    onBegin: beginGainDrag,
                    onChange: updateGain,
                    onEnd: commitGain
                )
                .frame(width: 72, height: 178)

                outputScale
                    .frame(height: 178)
            }

            HStack(spacing: 8) {
                Text(MasterOutputGainScale.dbLabel(forGain: displayedGain))
                    .studioText(.eyebrowBold)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)

                Spacer(minLength: 4)

                if meterState.isClipLatched {
                    Text("CLIP")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }

                if meterState.isClearClipActionable {
                    clearClipButton
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
    }

    private var clearClipButton: some View {
        Button {
            engineController.masterMeterPublisher.clearClip()
        } label: {
            Text("CLR")
                .studioText(.eyebrowBold)
                .tracking(0.4)
                .monospaced()
                .foregroundStyle(StudioTheme.background)
                .frame(
                    minWidth: MasterOutputClearClipControlMetrics.minWidth,
                    minHeight: MasterOutputClearClipControlMetrics.minHeight
                )
                .background(Color.red, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .accessibilityLabel("Clear master output clip")
        .accessibilityIdentifier("master-meter-clear-clip")
    }

    private var outputScale: some View {
        VStack {
            ForEach(["+6", "0", "-6", "-12", "-18", "-24", "-36", "-inf"], id: \.self) { label in
                Text(label)
                    .studioText(.micro)
                    .monospacedDigit()
                    .foregroundStyle(label == "0" ? StudioTheme.amber : StudioTheme.mutedText)
                if label != "-inf" {
                    Spacer(minLength: 1)
                }
            }
        }
    }

    private var displayedGain: Double {
        gainControl.rendered(committed: masterBus.masterOutputGain)
    }

    private var emptySlotCount: Int {
        max(0, 2 - masterBus.masterInserts.count)
    }

    private var fallbackSelection: MasterBusABSelection {
        let scenes = masterBus.scenes
        return MasterBusABSelection(
            sceneAID: scenes.first?.id ?? MasterBusScene.sceneAID,
            sceneBID: scenes.dropFirst().first?.id ?? scenes.first?.id ?? MasterBusScene.sceneBID
        )
    }

    private func beginGainDrag() {
        if !gainControl.isDragging {
            gainControl.begin(with: masterBus.masterOutputGain)
        }
    }

    private func updateGain(_ gain: Double) {
        let range = MasterBusState.masterOutputGainRange
        let clamped = min(max(gain, range.lowerBound), range.upperBound)
        if !gainControl.isDragging {
            gainControl.begin(with: masterBus.masterOutputGain)
        }
        guard gainControl.update(clamped) else { return }
        engineController.setLiveMasterOutputGain(clamped)
    }

    private func commitGain() {
        guard let finalGain = gainControl.commit() else {
            engineController.clearLiveMasterOutputGain()
            return
        }
        session.setMasterOutputGain(finalGain)
    }

    private func insertEnabledBinding(_ insert: MasterBusInsert) -> Binding<Bool> {
        Binding(
            get: {
                masterBus.masterInserts.first(where: { $0.id == insert.id })?.isEnabled ?? insert.isEnabled
            },
            set: { isEnabled in
                session.updateMasterOutputInsert(insert.id) { updated in
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
              let current = masterBus.masterInserts.firstIndex(where: { $0.id == insert.id })
        else { return }
        var ids = masterBus.masterInserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        session.reorderMasterOutputInserts(ids)
    }

    private func moveTargetIndex(for insert: MasterBusInsert, by delta: Int) -> Int? {
        guard let current = masterBus.masterInserts.firstIndex(where: { $0.id == insert.id }) else { return nil }
        let next = current + delta
        guard masterBus.masterInserts.indices.contains(next) else { return nil }
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

private struct MasterOutputFaderMeter: View {
    let gain: Double
    let meterState: MasterMeterDisplayState
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let position = MasterOutputGainScale.position(forGain: gain)
            let filledHeight = max(8, height * position)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                HStack(alignment: .bottom, spacing: 4) {
                    meterLane(peak: meterState.leftPeakDBFS)
                    Spacer(minLength: 26)
                    meterLane(peak: meterState.rightPeakDBFS)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(StudioTheme.cyan.opacity(0.48))
                    .frame(width: 30, height: filledHeight)

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.cyan.opacity(0.85), lineWidth: 1)
                    .frame(width: 30)

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(StudioTheme.cyan.opacity(0.34))
                    .frame(width: 30, height: filledHeight)

                Rectangle()
                    .fill(StudioTheme.amber.opacity(0.85))
                    .frame(width: 58, height: 2)
                    .offset(y: -height * MasterOutputGainScale.unityPosition + 1)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StudioTheme.text)
                    .frame(width: 42, height: 6)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: -filledHeight + 10)
            }
            .animation(.linear(duration: 0.05), value: meterState.leftPeakDBFS)
            .animation(.linear(duration: 0.05), value: meterState.rightPeakDBFS)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        let normalized = 1 - min(max(value.location.y / max(height, 1), 0), 1)
                        onChange(MasterOutputGainScale.gain(forPosition: normalized))
                    }
                    .onEnded { _ in
                        onEnd()
                    }
            )
        }
        .accessibilityIdentifier("master-output-fader-meter")
    }

    private func meterLane(peak: Double) -> some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let normalizedPeak = MasterMeterLevelScale.normalized(peak)
            let peakHeight = height * normalizedPeak

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                meterGradient
                    .frame(height: height)
                    .mask {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .frame(height: peakHeight)
                        }
                    }
                    .opacity(normalizedPeak > 0 ? 0.95 : 0)
            }
        }
        .frame(width: 10)
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: StudioTheme.success, location: 0),
                .init(color: StudioTheme.success, location: MasterMeterLevelScale.normalized(MasterMeterLevelScale.warningDBFS)),
                .init(color: StudioTheme.amber, location: MasterMeterLevelScale.normalized(MasterMeterLevelScale.warningDBFS)),
                .init(color: StudioTheme.amber, location: MasterMeterLevelScale.normalized(MasterMeterLevelScale.dangerDBFS)),
                .init(color: Color.red, location: MasterMeterLevelScale.normalized(MasterMeterLevelScale.dangerDBFS)),
                .init(color: Color.red, location: 1)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
