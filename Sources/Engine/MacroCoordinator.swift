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

        return LayerSnapshot(mute: mute, fillEnabled: fillEnabled)
    }
}
