import Foundation

extension Project {
    static let empty = Project(
        version: 1,
        tracks: [
            .default
        ],
        trackGroups: [],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [],
        layers: PhraseLayerDefinition.defaultSet(for: [.default]),
        routes: [],
        patternBanks: [
            TrackPatternBank.default(for: .default, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])
        ],
        selectedTrackID: StepSequenceTrack.default.id,
        phrases: [
            .default(
                tracks: [.default],
                layers: PhraseLayerDefinition.defaultSet(for: [.default]),
                generatorPool: GeneratorPoolEntry.defaultPool,
                clipPool: []
            )
        ],
        selectedPhraseID: PhraseModel.default(
            tracks: [.default],
            layers: PhraseLayerDefinition.defaultSet(for: [.default]),
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        ).id
    )

    var selectedTrackIndex: Int {
        tracks.firstIndex(where: { $0.id == selectedTrackID }) ?? 0
    }

    var selectedTrack: StepSequenceTrack {
        get {
            let fallback = StepSequenceTrack.default
            guard !tracks.isEmpty else {
                return fallback
            }
            return tracks[selectedTrackIndex]
        }
        set {
            guard !tracks.isEmpty else {
                tracks = [newValue]
                selectedTrackID = newValue.id
                return
            }
            tracks[selectedTrackIndex] = newValue
            selectedTrackID = newValue.id
        }
    }

    var selectedPhraseIndex: Int {
        phrases.firstIndex(where: { $0.id == selectedPhraseID }) ?? 0
    }

    var selectedPhrase: PhraseModel {
        get {
            let fallback = PhraseModel.default(
                tracks: tracks,
                layers: layers,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
            guard !phrases.isEmpty else {
                return fallback
            }
            return phrases[selectedPhraseIndex]
        }
        set {
            guard !phrases.isEmpty else {
                phrases = [newValue.synced(with: tracks, layers: layers)]
                selectedPhraseID = phrases[0].id
                return
            }
            phrases[selectedPhraseIndex] = newValue.synced(with: tracks, layers: layers)
            selectedPhraseID = phrases[selectedPhraseIndex].id
        }
    }

    mutating func selectTrack(id: UUID) {
        guard tracks.contains(where: { $0.id == id }) else {
            return
        }
        selectedTrackID = id
    }

    mutating func selectPhrase(id: UUID) {
        guard phrases.contains(where: { $0.id == id }) else {
            return
        }
        selectedPhraseID = id
    }
}
