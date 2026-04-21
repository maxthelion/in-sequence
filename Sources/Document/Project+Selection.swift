import Foundation

extension Project {
    static let empty: Project = {
        let defaultTrack = StepSequenceTrack.default
        let ownedClip = makeOwnedClip(for: defaultTrack)
        let seedClipPool = [ownedClip]
        return Project(
            version: 1,
            tracks: [defaultTrack],
            trackGroups: [],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: seedClipPool,
            layers: PhraseLayerDefinition.defaultSet(for: [defaultTrack]),
            routes: [],
            patternBanks: [
                TrackPatternBank.default(for: defaultTrack, initialClipID: ownedClip.id)
            ],
            selectedTrackID: defaultTrack.id,
            phrases: [
                .default(
                    tracks: [defaultTrack],
                    layers: PhraseLayerDefinition.defaultSet(for: [defaultTrack]),
                    generatorPool: GeneratorPoolEntry.defaultPool,
                    clipPool: seedClipPool
                )
            ],
            selectedPhraseID: PhraseModel.default(
                tracks: [defaultTrack],
                layers: PhraseLayerDefinition.defaultSet(for: [defaultTrack]),
                generatorPool: GeneratorPoolEntry.defaultPool,
                clipPool: seedClipPool
            ).id
        )
    }()

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
