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

            if scene.macroBindings.isEmpty {
                StudioPlaceholderTile(title: "No Scene Macros", detail: "Assign macros in Browse/Edit.", accent: StudioTheme.amber)
            } else {
                VStack(spacing: 10) {
                    ForEach(scene.macroBindings) { macro in
                        performMacroRow(macro, scene: scene)
                    }
                }
            }

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

    private func performMacroRow(_ macro: MasterSceneMacroBinding, scene: MasterBusScene) -> some View {
        let authoredValue = macro.value(in: scene) ?? macro.target.valueRange.lowerBound
        let resolvedValue = engineController.masterSceneMacroOverride(sceneID: scene.id, macroID: macro.id) ?? authoredValue
        return HStack(spacing: 10) {
            Text(macro.name)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)
                .frame(width: 116, alignment: .leading)
                .lineLimit(1)
            Slider(
                value: Binding(
                    get: {
                        engineController.masterSceneMacroOverride(sceneID: scene.id, macroID: macro.id) ?? authoredValue
                    },
                    set: { value in
                        engineController.setMasterSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: value)
                    }
                ),
                in: macro.target.valueRange
            )
            .tint(StudioTheme.amber)
            Text(valueLabel(resolvedValue, target: macro.target))
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 76, alignment: .trailing)
        }
    }

    private func valueLabel(_ value: Double, target: MasterSceneMacroTarget) -> String {
        switch target {
        case .filterCutoff:
            return "\(Int(value.rounded())) Hz"
        case .outputGain:
            return String(format: "%.2f", value)
        default:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}
