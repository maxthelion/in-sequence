import SwiftUI

struct MasterOutputColumnView: View {
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @StateObject private var gainControl = ThrottledMixValue()

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
    private var dominant: MasterOutputDominantScene {
        MasterOutputSceneSelector.dominantScene(in: masterBus, selection: selection, liveCrossfader: liveCrossfader)
    }
    private var dominantScene: MasterBusScene {
        masterBus.scene(id: dominant.id) ?? masterBus.activeScene
    }
    private var meterState: MasterMeterDisplayState {
        engineController.masterMeterPublisher.displayState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section("Crossfader") {
                MasterCrossfaderView(
                    sceneAName: sceneA.name,
                    sceneBName: sceneB.name,
                    value: crossfaderValue,
                    hasLiveOverride: liveCrossfader != nil,
                    showsPersistenceActions: false,
                    onChange: { engineController.setLiveMasterCrossfader($0) }
                )
            }
            section("Inserts") {
                masterInsertSection
            }
            section("Fader") {
                masterFaderSection
            }
            section("Meter") {
                masterMeterSection
            }
        }
        .padding(12)
        .frame(width: MasterOutputColumnLayout.fullColumnWidth, alignment: .topLeading)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.amber.opacity(0.7), lineWidth: 1)
        )
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
                Text("Scene \(dominant.slotLabel)")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)
            }
            Spacer(minLength: 6)
            if meterState.isClipLatched {
                Text("CLIP")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            }
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
            HStack(spacing: 8) {
                Text(dominantScene.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                addInsertMenu
            }

            VStack(spacing: 6) {
                ForEach(dominantScene.inserts) { insert in
                    masterInsertRow(insert)
                }

                ForEach(0..<emptySlotCount, id: \.self) { _ in
                    emptyInsertSlot
                }
            }
        }
    }

    private var addInsertMenu: some View {
        Menu {
            Button {
                session.addMasterBusInsert(.filter(), to: dominantScene.id)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }

            Button {
                session.addMasterBusInsert(.bitcrusher(), to: dominantScene.id)
            } label: {
                Label("Bitcrusher", systemImage: "waveform.path.ecg")
            }

            let effects = engineController.availableAudioEffects
            if effects.isEmpty {
                Button("No AU effects found") {}
                    .disabled(true)
            } else {
                Menu("AU Effect") {
                    ForEach(effects.prefix(16)) { effect in
                        Button(effect.displayName) {
                            session.addMasterBusInsert(.auEffect(effect), to: dominantScene.id)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.success)
        .help("Add insert")
        .accessibilityLabel("Add master insert")
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
                    session.removeMasterBusInsert(insert.id, from: dominantScene.id)
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
        Text("- empty slot -")
            .studioText(.micro)
            .tracking(0.8)
            .foregroundStyle(StudioTheme.mutedText)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }

    private var masterFaderSection: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                MasterOutputFader(
                    gain: displayedGain,
                    onBegin: beginGainDrag,
                    onChange: updateGain,
                    onEnd: commitGain
                )
                .frame(width: 42, height: 178)

                faderScale
                    .frame(height: 178)
            }

            Text(MasterOutputGainScale.dbLabel(forGain: displayedGain))
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(maxWidth: .infinity)
        }
    }

    private var faderScale: some View {
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

    private var masterMeterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                DualMasterMeterView(state: meterState)
                    .frame(width: 54, height: 156)
                meterScale
                    .frame(height: 156)
            }

            HStack(spacing: 6) {
                if meterState.isClipLatched {
                    Text("CLIP")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }

                if meterState.isClearClipActionable {
                    Button("CLR") {
                        engineController.masterMeterPublisher.clearClip()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(StudioTheme.amber)
                    .accessibilityIdentifier("master-meter-clear-clip")
                }
            }
            .frame(minHeight: 24, alignment: .leading)
        }
    }

    private var meterScale: some View {
        VStack {
            ForEach(["0", "-6", "-12", "-18", "-24", "-36", "-inf"], id: \.self) { label in
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
        max(0, 2 - dominantScene.inserts.count)
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
        session.setMasterOutputGain(clamped)
    }

    private func commitGain() {
        _ = gainControl.commit()
    }

    private func insertEnabledBinding(_ insert: MasterBusInsert) -> Binding<Bool> {
        Binding(
            get: {
                dominantScene.inserts.first(where: { $0.id == insert.id })?.isEnabled ?? insert.isEnabled
            },
            set: { isEnabled in
                session.updateMasterBusInsert(insert.id, in: dominantScene.id) { updated in
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
              let current = dominantScene.inserts.firstIndex(where: { $0.id == insert.id })
        else { return }
        var ids = dominantScene.inserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        session.reorderMasterBusInserts(ids, in: dominantScene.id)
    }

    private func moveTargetIndex(for insert: MasterBusInsert, by delta: Int) -> Int? {
        guard let current = dominantScene.inserts.firstIndex(where: { $0.id == insert.id }) else { return nil }
        let next = current + delta
        guard dominantScene.inserts.indices.contains(next) else { return nil }
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

private struct MasterOutputFader: View {
    let gain: Double
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

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(StudioTheme.cyan)
                    .frame(height: filledHeight)

                Rectangle()
                    .fill(StudioTheme.amber.opacity(0.8))
                    .frame(height: 2)
                    .offset(y: -height * MasterOutputGainScale.unityPosition + 1)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.selectedFill))
                    .frame(width: 30, height: 5)
                    .offset(y: -filledHeight + 10)
            }
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
        .accessibilityIdentifier("master-output-gain-fader")
    }
}

private struct DualMasterMeterView: View {
    let state: MasterMeterDisplayState

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            meterLane(peak: state.leftPeakDBFS, hold: state.leftPeakHoldDBFS, label: "L")
            meterLane(peak: state.rightPeakDBFS, hold: state.rightPeakHoldDBFS, label: "R")
        }
        .accessibilityIdentifier("master-output-meter")
    }

    private func meterLane(peak: Double, hold: Double, label: String) -> some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let height = proxy.size.height
                let peakHeight = height * MasterMeterLevelScale.normalized(peak)
                let holdOffset = height * (1 - MasterMeterLevelScale.normalized(hold))

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    VStack(spacing: 0) {
                        Rectangle().fill(StudioTheme.amber).frame(height: peakHeight * 0.12)
                        Rectangle().fill(StudioTheme.amber.opacity(0.78)).frame(height: peakHeight * 0.24)
                        Rectangle().fill(StudioTheme.success).frame(height: max(0, peakHeight * 0.64))
                    }

                    Rectangle()
                        .fill(StudioTheme.text)
                        .frame(height: 2)
                        .offset(y: -holdOffset + 1)
                        .opacity(hold.isFinite ? 0.9 : 0)
                }
            }

            Text(label)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}
