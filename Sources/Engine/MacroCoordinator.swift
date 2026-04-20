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
        guard let muteLayer = project.layers.first(where: { $0.target == .mute }) else {
            return .empty
        }

        var mute: [UUID: Bool] = [:]
        for track in project.tracks {
            if case let .bool(isMuted) = phrase.resolvedValue(for: muteLayer, trackID: track.id, stepIndex: stepInPhrase),
               isMuted {
                mute[track.id] = true
            }
        }

        return LayerSnapshot(mute: mute)
    }
}
