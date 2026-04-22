import Foundation

final class MacroCoordinator {
    func snapshot(
        upcomingGlobalStep: UInt64,
        project: Project,
        phraseID: UUID
    ) -> LayerSnapshot {
        guard let phrase = project.phrases.first(where: { $0.id == phraseID }) else {
            return .empty
        }

        assert(phrase.stepCount > 0, "Phrase stepCount must be positive for coordinator evaluation.")
        let stepInPhrase = Int(upcomingGlobalStep % UInt64(max(1, phrase.stepCount)))
        let muteLayer = project.layers.first(where: { $0.target == .mute })
        let fillLayer = project.layers.first(where: { $0.target == .macroRow("fill-flag") })

        var mute: [UUID: Bool] = [:]
        var fillEnabled: [UUID: Bool] = [:]
        for track in project.tracks {
            if let muteLayer,
               case let .bool(isMuted) = phrase.resolvedValue(for: muteLayer, trackID: track.id, stepIndex: stepInPhrase),
               isMuted {
                mute[track.id] = true
            }

            if let fillLayer,
               case let .bool(isEnabled) = phrase.resolvedValue(for: fillLayer, trackID: track.id, stepIndex: stepInPhrase),
               isEnabled {
                fillEnabled[track.id] = true
            }
        }

        // Resolve macro values from .macroParam phrase layers.
        let macroValues = resolveMacroValues(
            in: phrase,
            stepInPhrase: stepInPhrase,
            project: project
        )

        return LayerSnapshot(
            mute: mute,
            fillEnabled: fillEnabled,
            macroValues: macroValues
        )
    }

    // MARK: - Macro resolution

    /// Walk all `.macroParam` layers and resolve a value per (track, binding) pair.
    ///
    /// Resolution order (clip lane override is applied in EngineController's prepare
    /// step where the active clip is known):
    ///   1. descriptor.defaultValue (lowest priority)
    ///   2. phrase snapshot value (this method)
    ///   3. clip macro lane override (applied in EngineController — not here)
    private func resolveMacroValues(
        in phrase: PhraseModel,
        stepInPhrase: Int,
        project: Project
    ) -> [UUID: [UUID: Double]] {
        var result: [UUID: [UUID: Double]] = [:]

        let macroParamLayers = project.layers.filter {
            if case .macroParam = $0.target { return true }
            return false
        }

        for layer in macroParamLayers {
            guard case let .macroParam(trackID, bindingID) = layer.target else {
                continue
            }

            let resolved = phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepInPhrase)
            let doubleValue = scalarDouble(from: resolved, layer: layer)
            result[trackID, default: [:]][bindingID] = doubleValue
        }

        return result
    }

    /// Coerce a `PhraseCellValue` to `Double` for macro dispatch.
    ///
    /// - `.scalar(x)` → x (clamped to layer range)
    /// - `.bool(b)` → 0.0 / layer.maxValue (log assertion in debug; bool on scalar descriptor is unusual)
    /// - `.index(i)` → Double(i) (clamped)
    private func scalarDouble(from value: PhraseCellValue, layer: PhraseLayerDefinition) -> Double {
        switch value {
        case let .scalar(x):
            return min(max(x, layer.minValue), layer.maxValue)
        case let .bool(b):
            assert(layer.valueType == .boolean, "Bool cell value on non-boolean macro layer \(layer.id) — coercing to 0/1")
            return b ? layer.maxValue : layer.minValue
        case let .index(i):
            return min(max(Double(i), layer.minValue), layer.maxValue)
        }
    }
}
