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
        let normalized = Self.normalize(
            tracks: tracks,
            generatorPool: generatorPool,
            clipPool: clipPool,
            layers: layers.isEmpty ? nil : layers,
            patternBanks: patternBanks.isEmpty ? nil : patternBanks,
            phrases: phrases.isEmpty ? nil : phrases,
            selectedTrackID: selectedTrackID,
            selectedPhraseID: selectedPhraseID
        )

        self.version = version
        self.tracks = tracks
        self.trackGroups = trackGroups
        self.generatorPool = generatorPool
        self.clipPool = clipPool
        self.layers = normalized.layers
        self.routes = routes
        self.patternBanks = normalized.patternBanks
        self.selectedTrackID = normalized.selectedTrackID
        self.phrases = normalized.phrases
        self.selectedPhraseID = normalized.selectedPhraseID
        syncPhrasesWithTracks()
    }
}
