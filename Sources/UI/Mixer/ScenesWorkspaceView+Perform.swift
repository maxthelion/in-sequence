import SwiftUI

extension ScenesWorkspaceView {
    @ViewBuilder
    var performView: some View {
        let selection = activeABSelection
        let sceneA = masterBus.scene(id: selection.sceneAID) ?? masterBus.activeScene
        let sceneB = masterBus.scene(id: selection.sceneBID)
            ?? masterBus.scenes.first { $0.id != sceneA.id }
            ?? MasterBusScene.sceneB
        StudioPanel(title: "Scenes Perform", eyebrow: "Runtime scene macro overrides", accent: StudioTheme.amber) {
            VStack(alignment: .leading, spacing: 16) {
                sharedCrossfader(selection, sceneA: sceneA, sceneB: sceneB)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        performSlot(title: "Slot A", scene: sceneA, isA: true)
                        performSlot(title: "Slot B", scene: sceneB, isA: false)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        performSlot(title: "Slot A", scene: sceneA, isA: true)
                        performSlot(title: "Slot B", scene: sceneB, isA: false)
                    }
                }
            }
        }
    }

    private func sharedCrossfader(
        _ selection: MasterBusABSelection,
        sceneA: MasterBusScene,
        sceneB: MasterBusScene
    ) -> some View {
        let value = engineController.masterBusPerformanceOverlay.crossfaderOverride ?? selection.crossfader
        return MasterCrossfaderView(
            sceneAName: sceneA.name,
            sceneBName: sceneB.name,
            value: value,
            hasLiveOverride: engineController.masterBusPerformanceOverlay.crossfaderOverride != nil,
            showsPersistenceActions: true,
            onChange: { engineController.setLiveMasterCrossfader($0) },
            onReset: { engineController.clearLiveMasterCrossfader() },
            onSave: { savedValue in
                session.setMasterCrossfader(savedValue)
                engineController.clearLiveMasterCrossfader()
            }
        )
    }

    private func performSlot(title: String, scene: MasterBusScene, isA: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.amber)
                    Text(scene.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                }
                Spacer()
                if engineController.hasMasterSceneMacroOverrides(sceneID: scene.id) {
                    Text("MODIFIED")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.amber)
                }
                Button {
                    scenePerformSlotPickerRequest = ScenePerformSlotPickerRequest(slot: isA ? .a : .b)
                } label: {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(StudioTheme.amber)
                .help("Choose scene")
            }

            performMacroSlots(scene)

            HStack(spacing: 8) {
                Button {
                    engineController.clearMasterSceneMacroOverrides(sceneID: scene.id)
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!engineController.hasMasterSceneMacroOverrides(sceneID: scene.id))

                Button {
                    let values = engineController.masterSceneMacroOverrides(sceneID: scene.id)
                    session.saveMasterScenePerformanceOverrides(values, to: scene.id)
                    engineController.clearMasterSceneMacroOverrides(sceneID: scene.id)
                } label: {
                    Label("Save to Scene", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.cyan)
                .disabled(!engineController.hasMasterSceneMacroOverrides(sceneID: scene.id))
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                    performMacroSlot(slotIndex, scene: scene)
                        .frame(width: 68)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
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
