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
                crossfader(selection)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        performSlot(title: "Slot A", scene: sceneA, selection: selection, isA: true)
                        performSlot(title: "Slot B", scene: sceneB, selection: selection, isA: false)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        performSlot(title: "Slot A", scene: sceneA, selection: selection, isA: true)
                        performSlot(title: "Slot B", scene: sceneB, selection: selection, isA: false)
                    }
                }
            }
        }
    }

    private func crossfader(_ selection: MasterBusABSelection) -> some View {
        let value = engineController.masterBusPerformanceOverlay.crossfaderOverride ?? selection.crossfader
        return HStack(spacing: 12) {
            Text("A")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.amber)
            Slider(
                value: Binding(
                    get: { engineController.masterBusPerformanceOverlay.crossfaderOverride ?? selection.crossfader },
                    set: { engineController.setLiveMasterCrossfader($0) }
                ),
                in: 0...1
            )
            .tint(StudioTheme.amber)
            Text("B")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.amber)

            Text("\(Int((value * 100).rounded()))%")
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 48, alignment: .trailing)

            Button {
                engineController.clearLiveMasterCrossfader()
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(engineController.masterBusPerformanceOverlay.crossfaderOverride == nil)

            Button {
                session.setMasterCrossfader(value)
                engineController.clearLiveMasterCrossfader()
            } label: {
                Label("Save Blend", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)
            .disabled(engineController.masterBusPerformanceOverlay.crossfaderOverride == nil)
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
    }

    private func performSlot(title: String, scene: MasterBusScene, selection: MasterBusABSelection, isA: Bool) -> some View {
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
            }

            Picker("Scene", selection: isA ? sceneABinding(selection) : sceneBBinding(selection)) {
                ForEach(masterBus.scenes) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }
            .pickerStyle(.menu)

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
}
