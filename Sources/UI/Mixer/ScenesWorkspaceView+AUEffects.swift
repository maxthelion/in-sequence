import AVFoundation
import SwiftUI

struct SceneAUMacroSlotPickerRequest: Identifiable, Equatable {
    let id = UUID()
    let sceneID: UUID
    let insertID: UUID
    let slotIndex: Int
}

extension ScenesWorkspaceView {
    @ViewBuilder
    func auEffectEditor(_ insert: MasterBusInsert, scene: MasterBusScene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    prepareAndOpenAUEffectWindow(insert, scene: scene)
                } label: {
                    Label("Open Plug-In", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.amber)

                Button {
                    engineController.prepareMasterAUEffect(insertID: insert.id)
                } label: {
                    Label("Refresh Parameters", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let params = engineController.masterAUEffectParameterReadout(insertID: insert.id) {
                Text("\(params.count) assignable AU parameters")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            } else {
                Label("Preparing AU parameters", systemImage: "slider.horizontal.3")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .onAppear {
                        engineController.prepareMasterAUEffect(insertID: insert.id)
                    }
            }
        }
    }

    @ViewBuilder
    func sceneAUMacroSlotPickerSheet(_ request: SceneAUMacroSlotPickerRequest) -> some View {
        let currentAddresses = currentAUMacroAddresses(sceneID: request.sceneID, insertID: request.insertID)
        SingleMacroSlotPickerSheet(
            slotIndex: request.slotIndex,
            currentBindingAddresses: currentAddresses,
            readParameters: {
                engineController.masterAUEffectParameterReadout(insertID: request.insertID)
            },
            onSelect: { parameter in
                assignAUMacro(parameter, request: request)
            }
        )
        .onAppear {
            engineController.prepareMasterAUEffect(insertID: request.insertID)
        }
    }

    private func assignAUMacro(_ parameter: AUParameterDescriptor, request: SceneAUMacroSlotPickerRequest) {
        guard let scene = masterBus.scene(id: request.sceneID) else { return }
        let existing = scene.macroBindings.first { $0.slotIndex == request.slotIndex }
        let target = MasterSceneMacroTarget.auParameter(
            insertID: request.insertID,
            address: parameter.address,
            identifier: parameter.identifier,
            displayName: parameter.displayName,
            minValue: parameter.minValue,
            maxValue: parameter.maxValue,
            defaultValue: parameter.defaultValue,
            unit: parameter.unit
        )
        let macro = MasterSceneMacroBinding(
            id: existing?.id ?? UUID(),
            slotIndex: request.slotIndex,
            target: target,
            authoredValue: parameter.defaultValue
        )
        session.upsertMasterSceneMacroBinding(macro, in: request.sceneID)
    }

    private func currentAUMacroAddresses(sceneID: UUID, insertID: UUID) -> Set<UInt64> {
        guard let scene = masterBus.scene(id: sceneID) else { return [] }
        return Set(scene.macroBindings.compactMap { binding in
            guard case let .auParameter(targetInsertID, address, _, _, _, _, _, _) = binding.target,
                  targetInsertID == insertID
            else {
                return nil
            }
            return address
        })
    }

    private func prepareAndOpenAUEffectWindow(_ insert: MasterBusInsert, scene: MasterBusScene) {
        let maxPollAttempts = 20
        let pollInterval = Duration.milliseconds(100)
        engineController.prepareMasterAUEffect(insertID: insert.id)

        Task { @MainActor in
            for _ in 0..<maxPollAttempts {
                if let audioUnit = engineController.currentMasterAUEffect(insertID: insert.id) {
                    openAUEffectWindow(audioUnit, insert: insert, scene: scene)
                    return
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    @MainActor
    private func openAUEffectWindow(_ audioUnit: AVAudioUnit, insert: MasterBusInsert, scene: MasterBusScene) {
        AUWindowHost.shared.open(
            for: .masterInsert(insert.id),
            presenter: audioUnit,
            title: "\(scene.name) - \(insert.name)"
        ) { stateBlob in
            session.setMasterAUEffectStateBlob(insert.id, in: scene.id, stateBlob: stateBlob)
        }
    }
}
