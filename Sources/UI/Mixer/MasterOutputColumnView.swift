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
            accent: StudioTheme.transportAccent
        ) {
            header
        } processing: {
            masterInsertSection
        } levels: {
            masterOutputSection
        } pan: {
            // The A/B blend is the master's side-to-side row, aligned with
            // the channel pan rows. Scene names sit above the slider (not as
            // end labels) so longer scene names stay readable.
            abBlendControl
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
                        .background(StudioTheme.transportAccent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Clear solo")
                .accessibilityLabel("Clear solo")
                .accessibilityIdentifier("mixer-clear-solo")
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var abBlendControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            sceneLabelsRow

            StudioSlideControl(
                value: crossfaderValue,
                range: 0...1,
                fillStyle: .fromLeading,
                accent: StudioTheme.transportAccent,
                help: "Scene A B blend",
                onChange: { engineController.setLiveMasterCrossfader($0) }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("master-crossfader")
    }

    private var sceneLabelsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            sceneBlendEndpoint(label: "Scene A", name: sceneA.name, alignment: .leading)
            Spacer(minLength: 6)
            sceneBlendEndpoint(label: "Scene B", name: sceneB.name, alignment: .trailing)
        }
    }

    private func sceneBlendEndpoint(label: String, name: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .studioText(.microEmphasis)
                .foregroundStyle(StudioTheme.transportAccent)
                .lineLimit(1)
            Text(name)
                .studioText(.micro)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
                    accent: StudioTheme.transportAccent,
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
                    StudioFXOptionRow(title: "Filter", systemImage: "line.3.horizontal.decrease.circle") {
                        session.addMasterOutputInsert(.filter())
                        isAddFXPresented = false
                    }
                    StudioFXOptionRow(title: "Bitcrusher", systemImage: "waveform.path.ecg") {
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

                AUEffectPickerList(effects: engineController.availableAudioEffects) { effect in
                    StudioFXOptionRow(title: effect.displayName, systemImage: "slider.horizontal.3") {
                        session.addMasterOutputInsert(.auEffect(effect))
                        isAddFXPresented = false
                    }
                }
        }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
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
                    .background(StudioTheme.danger, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)) // ux-canon-allow: latched CLIP is a true danger state
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
                .background(StudioTheme.danger, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)) // ux-canon-allow: clear action belongs to the latched CLIP danger state
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
                    .foregroundStyle(label == "0" ? StudioTheme.transportAccent : StudioTheme.mutedText)
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
                    Spacer(minLength: 16)
                    meterLane(peak: meterState.rightPeakDBFS)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                // The same draggable blue slide control as the channel faders.
                Capsule(style: .continuous)
                    .fill(StudioTheme.borderSoftFill)
                    .frame(width: 4)
                    .padding(.vertical, thumbDiameter / 2)

                Capsule(style: .continuous)
                    .fill(StudioTheme.transportAccent)
                    .frame(width: 4, height: max(0, usableHeight * CGFloat(position)))
                    .offset(y: -thumbDiameter / 2)

                // Unity (0 dB) reference tick.
                Rectangle()
                    .fill(StudioTheme.transportAccent)
                    .frame(width: 30, height: 2)
                    .offset(y: -usableHeight * MasterOutputGainScale.unityPosition - thumbDiameter / 2 + 1)

                Circle()
                    .fill(StudioTheme.transportAccent)
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

                MasterMeterLevelScale.meterGradient
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
}
