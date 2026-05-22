import SwiftUI

struct ScenePerformDominance: Equatable {
    let isADominant: Bool
    let isBDominant: Bool

    init(effectiveCrossfader: Double) {
        isADominant = effectiveCrossfader < 0.5
        isBDominant = effectiveCrossfader > 0.5
    }
}

extension ScenesWorkspaceView {
    @ViewBuilder
    var performView: some View {
        let effectiveCrossfader = engineController.effectiveCrossfader
        let dominance = ScenePerformDominance(effectiveCrossfader: effectiveCrossfader)
        let selection = activeABSelection
        let sceneA = masterBus.scene(id: selection.sceneAID) ?? masterBus.activeScene
        let sceneB = masterBus.scene(id: selection.sceneBID)
            ?? masterBus.scenes.first { $0.id != sceneA.id }
            ?? MasterBusScene.sceneB
        StudioPanel(title: "Scenes Perform", eyebrow: "Runtime scene macro overrides", accent: StudioTheme.amber) {
            HStack(alignment: .top, spacing: 0) {
                performSlot(title: "Slot A", scene: sceneA, isA: true, isDominant: dominance.isADominant)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                crossfaderBridge(value: effectiveCrossfader)
                    .frame(width: 176)
                    .padding(.horizontal, 12)

                performSlot(title: "Slot B", scene: sceneB, isA: false, isDominant: dominance.isBDominant)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func crossfaderBridge(value: Double) -> some View {
        VStack(spacing: 10) {
            Text("\(Int((value * 100).rounded()))%")
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 56, alignment: .center)

            HStack(spacing: 8) {
                Text("A")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 14, alignment: .leading)

                ScenePerformCrossfaderTrack(value: value) { nextValue in
                    engineController.setLiveMasterCrossfader(nextValue)
                }
                .frame(height: 42)

                Text("B")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 14, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
    }

    private func performSlot(title: String, scene: MasterBusScene, isA: Bool, isDominant: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(isDominant ? Color.white.opacity(0.72) : StudioTheme.amber)
                    Text(scene.name)
                        .studioText(.title)
                        .foregroundStyle(isDominant ? Color.white : StudioTheme.text)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    scenePerformSlotPickerRequest = ScenePerformSlotPickerRequest(slot: isA ? .a : .b)
                } label: {
                    HStack(spacing: 5) {
                        Text("Choose")
                            .studioText(.micro)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(isDominant ? Color.white.opacity(0.72) : StudioTheme.mutedText)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Color.white.opacity(isDominant ? StudioOpacity.borderSubtle : StudioOpacity.subtleFill),
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(isDominant ? Color.white.opacity(0.16) : StudioTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Choose scene")
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(
                isDominant ? StudioTheme.background : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
            )
            .onTapGesture {
                engineController.setLiveMasterCrossfader(isA ? 0 : 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(scene.name), switch crossfader to Scene \(isA ? "A" : "B")")
            .accessibilityValue(isDominant ? "Active" : "Inactive")
            .accessibilityAction {
                engineController.setLiveMasterCrossfader(isA ? 0 : 1)
            }

            performMacroSlots(scene)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.hoverFill), lineWidth: 1)
        )
    }

    private func performMacroSlots(_ scene: MasterBusScene) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 68), spacing: 8),
                GridItem(.flexible(minimum: 68), spacing: 8)
            ],
            spacing: 10
        ) {
            ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                performMacroSlot(slotIndex, scene: scene)
            }
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func performMacroSlot(_ slotIndex: Int, scene: MasterBusScene) -> some View {
        let macro = scene.macroBindings.first { $0.slotIndex == slotIndex }
        return MacroSlotKnob(
            slotIndex: slotIndex,
            descriptor: macro.map {
                MacroSlotKnobDescriptor(displayName: $0.name, valueRange: $0.target.valueRange)
            },
            value: macro.map { resolvedMacroValue($0, scene: scene) },
            accent: StudioTheme.amber,
            onAssign: {
                sceneMacroTargetPickerRequest = SceneMacroTargetPickerRequest(sceneID: scene.id, slotIndex: slotIndex)
            },
            onChange: { value in
                guard let macro else { return }
                engineController.setMasterSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: value)
            }
        )
    }

    private func resolvedMacroValue(_ macro: MasterSceneMacroBinding, scene: MasterBusScene) -> Double {
        let authoredValue = macro.value(in: scene) ?? macro.target.valueRange.lowerBound
        return engineController.masterSceneMacroOverride(sceneID: scene.id, macroID: macro.id) ?? authoredValue
    }

    func scenePerformSlotPickerSheet(_ request: ScenePerformSlotPickerRequest) -> some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.slot.title)
                            .studioText(.title)
                            .foregroundStyle(StudioTheme.text)
                        Text("Choose Scene")
                            .studioText(.eyebrow)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    Spacer()
                    Button("Cancel") {
                        scenePerformSlotPickerRequest = nil
                    }
                    .buttonStyle(.bordered)
                    .tint(StudioTheme.amber)
                }

                ScrollView {
                    LazyVGrid(columns: scenePickerColumns, spacing: 12) {
                        ForEach(masterBus.scenes) { scene in
                            scenePickerCard(scene, request: request)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 560, minHeight: 430)
        .background(StudioTheme.stageFill)
    }

    private var scenePickerColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 104, maximum: 150), spacing: 12),
            count: 4
        )
    }

    private func scenePickerCard(_ scene: MasterBusScene, request: ScenePerformSlotPickerRequest) -> some View {
        let selected = selectedSceneID(for: request.slot) == scene.id
        return Button {
            setScene(scene.id, for: request.slot)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? StudioTheme.background : StudioTheme.text)
                        .frame(width: 26, height: 26)
                        .background(selected ? StudioTheme.amber : StudioTheme.amber.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudioTheme.amber)
                    }
                }

                Text(scene.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(scene.macroBindings.count) macros")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(selected ? StudioTheme.amber.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedSceneID(for slot: ScenePerformSlotPickerRequest.Slot) -> UUID {
        let selection = masterBus.abSelection ?? activeABSelection
        switch slot {
        case .a: return selection.sceneAID
        case .b: return selection.sceneBID
        }
    }

    private func setScene(_ sceneID: UUID, for slot: ScenePerformSlotPickerRequest.Slot) {
        engineController.clearMasterBusPerformanceOverlay()
        let current = masterBus.abSelection ?? activeABSelection
        switch slot {
        case .a:
            let sceneBID = current.sceneBID == sceneID ? current.sceneAID : current.sceneBID
            session.setMasterABMode(MasterBusABSelection(sceneAID: sceneID, sceneBID: sceneBID, crossfader: current.crossfader))
        case .b:
            let sceneAID = current.sceneAID == sceneID ? current.sceneBID : current.sceneAID
            session.setMasterABMode(MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneID, crossfader: current.crossfader))
        }
        scenePerformSlotPickerRequest = nil
    }
}

private struct ScenePerformCrossfaderTrack: View {
    let value: Double
    let onChange: (Double) -> Void

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let thumbX = width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StudioTheme.border.opacity(0.8))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(StudioTheme.amber.opacity(0.28))
                    .frame(width: thumbX, height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(StudioTheme.amber)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.65), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    .offset(x: min(max(thumbX - 14, 0), width - 28))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = min(max(drag.location.x, 0), width)
                        onChange(Double(x / width))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Scene crossfader")
        .accessibilityValue("\(Int((clampedValue * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onChange(min(clampedValue + 0.05, 1))
            case .decrement:
                onChange(max(clampedValue - 0.05, 0))
            @unknown default:
                break
            }
        }
    }
}
