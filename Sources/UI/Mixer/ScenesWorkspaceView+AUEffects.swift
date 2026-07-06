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
                .tint(StudioTheme.transportAccent)

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

/// Draws the magnitude response shape of the native filter so the user can see
/// how type + cutoff + resonance reshape the signal. Approximate (visual only),
/// computed on a log-frequency axis from 20 Hz to 20 kHz.
struct SceneFilterCurveView: View {
    let mode: MasterFilterSettings.Mode
    let cutoffHz: Double
    let resonance: Double
    var accent: Color = StudioTheme.transportAccent

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 8
            let plot = CGRect(
                x: inset,
                y: inset,
                width: max(size.width - inset * 2, 1),
                height: max(size.height - inset * 2, 1)
            )

            // Cutoff guide line (vertical).
            let cutoffX = plot.minX + plot.width * CGFloat(normalizedLog(cutoffHz))
            var guideLine = Path()
            guideLine.move(to: CGPoint(x: cutoffX, y: plot.minY))
            guideLine.addLine(to: CGPoint(x: cutoffX, y: plot.maxY))
            context.stroke(guideLine, with: .color(accent.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Response curve.
            let steps = 80
            var path = Path()
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let magnitude = magnitudeDb(atFraction: fraction)
                let x = plot.minX + plot.width * CGFloat(fraction)
                let y = plot.maxY - plot.height * CGFloat(normalizedMagnitude(magnitude))
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // 0 (20 Hz) ... 1 (20 kHz) on a log scale.
    private func normalizedLog(_ hz: Double) -> Double {
        let clamped = min(max(hz, 20), 20_000)
        let lo = log10(20.0)
        let hi = log10(20_000.0)
        return (log10(clamped) - lo) / (hi - lo)
    }

    /// Approximate magnitude in dB at a normalized x position (log-frequency).
    private func magnitudeDb(atFraction fraction: Double) -> Double {
        let cutoffFraction = normalizedLog(cutoffHz)
        let delta = fraction - cutoffFraction
        // Resonance sharpens the transition and lifts the peak at cutoff.
        let q = 0.5 + resonance * 8
        let peak = resonance * 14
        let slope = 36.0 // dB/decade-ish visual rolloff

        switch mode {
        case .lowPass:
            let attenuation = delta > 0 ? -slope * delta * 4 : 0
            let bump = peakBump(delta: delta, width: 0.06 / q, height: peak)
            return attenuation + bump
        case .highPass:
            let attenuation = delta < 0 ? slope * delta * 4 : 0
            let bump = peakBump(delta: delta, width: 0.06 / q, height: peak)
            return attenuation + bump
        case .bandPass:
            let width = 0.14 / q
            return peakBump(delta: delta, width: width, height: 6 + peak) - 24 * (1 - bell(delta: delta, width: width))
        case .notch:
            let width = 0.1 / q
            return -(30 + peak) * bell(delta: delta, width: width)
        case .peak:
            let width = 0.12 / q
            return (8 + peak) * bell(delta: delta, width: width)
        }
    }

    private func bell(delta: Double, width: Double) -> Double {
        let w = max(width, 0.0001)
        return exp(-(delta * delta) / (2 * w * w))
    }

    private func peakBump(delta: Double, width: Double, height: Double) -> Double {
        guard height > 0 else { return 0 }
        return height * bell(delta: delta, width: width)
    }

    /// Map dB (-40 ... +18) into 0...1 plot height.
    private func normalizedMagnitude(_ db: Double) -> Double {
        let lo = -40.0
        let hi = 18.0
        return min(max((db - lo) / (hi - lo), 0), 1)
    }
}
