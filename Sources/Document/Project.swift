import Foundation

struct Project: Codable, Equatable {
    enum DestinationWriteTarget: Equatable, Sendable {
        case track(UUID)
        case group(TrackGroupID)
    }

    var version: Int
    var tracks: [StepSequenceTrack]
    var trackGroups: [TrackGroup]
    var generatorPool: [GeneratorPoolEntry]
    var clipPool: [ClipPoolEntry]
    var layers: [PhraseLayerDefinition]
    var routes: [Route]
    var patternBanks: [TrackPatternBank]
    var selectedTrackID: UUID
    var phrases: [PhraseModel]
    var selectedPhraseID: UUID

    init(
        version: Int,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup] = [],
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = [],
        layers: [PhraseLayerDefinition] = [],
        routes: [Route] = [],
        patternBanks: [TrackPatternBank] = [],
        selectedTrackID: UUID,
        phrases: [PhraseModel],
        selectedPhraseID: UUID
    ) {
        let resolvedLayers = layers.isEmpty
            ? PhraseLayerDefinition.defaultSet(for: tracks)
            : layers.map { $0.synced(with: tracks) }
        let resolvedPatternBanks = patternBanks.isEmpty
            ? Self.defaultPatternBanks(for: tracks, generatorPool: generatorPool, clipPool: clipPool)
            : patternBanks
                .filter { bank in tracks.contains(where: { $0.id == bank.trackID }) }
                .map { bank in
                    bank.synced(
                        track: tracks.first(where: { $0.id == bank.trackID }) ?? .default,
                        generatorPool: generatorPool,
                        clipPool: clipPool
                    )
                }
        let resolvedSelectedTrackID = tracks.contains(where: { $0.id == selectedTrackID }) ? selectedTrackID : tracks[0].id
        let resolvedPhrases = phrases.isEmpty
            ? [.default(tracks: tracks, layers: resolvedLayers, generatorPool: generatorPool, clipPool: clipPool)]
            : phrases.map { $0.synced(with: tracks, layers: resolvedLayers) }
        let resolvedSelectedPhraseID = resolvedPhrases.contains(where: { $0.id == selectedPhraseID }) ? selectedPhraseID : resolvedPhrases[0].id

        self.version = version
        self.tracks = tracks
        self.trackGroups = trackGroups
        self.generatorPool = generatorPool
        self.clipPool = clipPool
        self.layers = resolvedLayers
        self.routes = routes
        self.patternBanks = resolvedPatternBanks
        self.selectedTrackID = resolvedSelectedTrackID
        self.phrases = resolvedPhrases
        self.selectedPhraseID = resolvedSelectedPhraseID
        syncPhrasesWithTracks()
    }
}
