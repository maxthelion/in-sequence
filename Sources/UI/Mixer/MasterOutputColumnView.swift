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
        StudioMixerStrip(
            width: StudioMixerStripMetrics.masterWidth,
            accent: StudioTheme.amber
        ) {
            header
        } processing: {
            masterInsertSection
        } levels: {
            masterOutputSection
        } pan: {
            // The A/B blend is the master's side-to-side row, aligned with
            // the channel pan rows.
            StudioSlideControl(
                value: crossfaderValue,
                range: 0...1,
                fillStyle: .fromLeading,
                accent: StudioTheme.amber,
                leadingLabel: "A",
                trailingLabel: "B",
                help: "Scene A B blend",
                onChange: { engineController.setLiveMasterCrossfader($0) }
            )
        } actions: {
            clipActionsRow
        } footer: {
            Text("→ Output")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .sheet(isPresented: $isAddFXPresented) {
            addFXSheet
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixer-master-out-column")
    }

    private var isSoloActive: Bool {
        EngineController.effectiveMixerMuteState(
            tracks: session.store.tracks,
            buses: session.store.buses
        ).isSoloActive
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("MASTER OUT")
                .studioText(.eyebrowBold)
                .tracking(1.0)
                .foregroundStyle(StudioTheme.text)
            Spacer(minLength: 6)
            // Solo state surfaces here — a fixed header slot — never as a
            // banner that pushes the strip grid out of alignment.
            if isSoloActive {
                Button {
                    session.clearAllSolo()
                } label: {
                    Text("SOLO")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Clear solo")
                .accessibilityLabel("Clear solo")
                .accessibilityIdentifier("mixer-clear-solo")
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var masterInsertSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FX")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            ScrollView(showsIndicators: false) {
                MixerInsertChainView(
                    inserts: masterBus.masterInserts,
                    accent: StudioTheme.amber,
                    emptySlotCount: emptySlotCount,
                    maxAddAffordances: 1,
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
    }

    private var addFXSheet: some View {
        StudioModal(
            title: "Master Out FX",
            minWidth: 360,
            onClose: { isAddFXPresented = false }
        ) {
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
                    StudioEmptyListRow(message: "No AU effects found")
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
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
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
                .frame(
                    width: StudioMixerStripMetrics.masterFaderWidth,
                    height: StudioMixerStripMetrics.faderSize.height
                )

                outputScale
                    .frame(height: StudioMixerStripMetrics.faderSize.height)
            }

            Text(MasterOutputGainScale.dbLabel(forGain: displayedGain))
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
        }
        .frame(maxWidth: .infinity)
    }

    private var clipActionsRow: some View {
        HStack(spacing: 6) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

}

private struct MasterOutputFaderMeter: View {
    let gain: Double
    let meterState: MasterMeterDisplayState
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    private var thumbDiameter: CGFloat { 18 }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let position = MasterOutputGainScale.position(forGain: gain)
            let usableHeight = max(0, height - thumbDiameter)
            let thumbCenterY = thumbDiameter / 2 + (1 - CGFloat(position)) * usableHeight

            ZStack(alignment: .bottom) {
                // Live L/R meter lanes fill the trough.
                HStack(alignment: .bottom, spacing: 4) {
                    meterLane(peak: meterState.leftPeakDBFS)
                    Spacer(minLength: 26)
                    meterLane(peak: meterState.rightPeakDBFS)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                // The same draggable blue slide control as the channel faders.
                Capsule(style: .continuous)
                    .fill(StudioTheme.border.opacity(StudioOpacity.softStroke))
                    .frame(width: 4)
                    .padding(.vertical, thumbDiameter / 2)

                Capsule(style: .continuous)
                    .fill(StudioTheme.cyan)
                    .frame(width: 4, height: max(0, usableHeight * CGFloat(position)))
                    .offset(y: -thumbDiameter / 2)

                // Unity (0 dB) reference tick.
                Rectangle()
                    .fill(StudioTheme.amber)
                    .frame(width: 30, height: 2)
                    .offset(y: -usableHeight * MasterOutputGainScale.unityPosition - thumbDiameter / 2 + 1)

                Circle()
                    .fill(StudioTheme.cyan)
                    .overlay(Circle().stroke(StudioTheme.inset, lineWidth: 2))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(y: -(height - thumbCenterY) + thumbDiameter / 2)
            }
            .animation(.linear(duration: 0.05), value: meterState.leftPeakDBFS)
            .animation(.linear(duration: 0.05), value: meterState.rightPeakDBFS)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onBegin()
                        let travel = value.location.y - thumbDiameter / 2
                        let normalized = 1 - min(max(travel / max(usableHeight, 1), 0), 1)
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
                    .fill(StudioTheme.inset)

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
