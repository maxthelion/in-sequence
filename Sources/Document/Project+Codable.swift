import Foundation

extension Project {
    private enum CodingKeys: String, CodingKey {
        case version
        case tracks
        case trackGroups
        case generatorPool
        case clipPool
        case layers
        case routes
        case patternBanks
        case selectedTrackID
        case phrases
        case selectedPhraseID
    }

    init(version: Int, tracks: [StepSequenceTrack], selectedTrackID: UUID) {
        let defaultGeneratorPool = GeneratorPoolEntry.defaultPool
        let defaultClipPool: [ClipPoolEntry] = []
        let defaultLayers = PhraseLayerDefinition.defaultSet(for: tracks)
        let defaultPhrases = [
            PhraseModel.default(
                tracks: tracks,
                layers: defaultLayers,
                generatorPool: defaultGeneratorPool,
                clipPool: defaultClipPool
            )
        ]
        self.init(
            version: version,
            tracks: tracks,
            trackGroups: [],
            generatorPool: defaultGeneratorPool,
            clipPool: defaultClipPool,
            layers: defaultLayers,
            patternBanks: Self.defaultPatternBanks(for: tracks, generatorPool: defaultGeneratorPool, clipPool: defaultClipPool),
            selectedTrackID: selectedTrackID,
            phrases: defaultPhrases,
            selectedPhraseID: defaultPhrases[0].id
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolvedVersion = try container.decode(Int.self, forKey: .version)
        let resolvedTracks = try container.decode([StepSequenceTrack].self, forKey: .tracks)
        let resolvedTrackGroups = try container.decodeIfPresent([TrackGroup].self, forKey: .trackGroups) ?? []
        let resolvedGeneratorPool = try container.decodeIfPresent([GeneratorPoolEntry].self, forKey: .generatorPool) ?? GeneratorPoolEntry.defaultPool
        let resolvedClipPool = try container.decodeIfPresent([ClipPoolEntry].self, forKey: .clipPool) ?? []
        let resolvedLayers = (try container.decodeIfPresent([PhraseLayerDefinition].self, forKey: .layers) ?? PhraseLayerDefinition.defaultSet(for: resolvedTracks))
            .map { $0.synced(with: resolvedTracks) }
        let resolvedRoutes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        let decodedPatternBanks = try container.decodeIfPresent([TrackPatternBank].self, forKey: .patternBanks) ?? []
        let resolvedPatternBanks = decodedPatternBanks.isEmpty
            ? Self.defaultPatternBanks(for: resolvedTracks, generatorPool: resolvedGeneratorPool, clipPool: resolvedClipPool)
            : decodedPatternBanks.map { bank in
                bank.synced(
                    track: resolvedTracks.first(where: { $0.id == bank.trackID }) ?? .default,
                    generatorPool: resolvedGeneratorPool,
                    clipPool: resolvedClipPool
                )
            }
        let decodedPhrases = try container.decodeIfPresent([PhraseModel].self, forKey: .phrases) ?? []
        let resolvedPhrases = decodedPhrases.isEmpty
            ? [.default(tracks: resolvedTracks, layers: resolvedLayers, generatorPool: resolvedGeneratorPool, clipPool: resolvedClipPool)]
            : decodedPhrases.map { $0.synced(with: resolvedTracks, layers: resolvedLayers) }
        let decodedSelectedTrackID = try container.decodeIfPresent(UUID.self, forKey: .selectedTrackID)
        let resolvedSelectedTrackID: UUID
        if let decodedSelectedTrackID, resolvedTracks.contains(where: { $0.id == decodedSelectedTrackID }) {
            resolvedSelectedTrackID = decodedSelectedTrackID
        } else {
            resolvedSelectedTrackID = resolvedTracks[0].id
        }
        let decodedSelectedPhraseID = try container.decodeIfPresent(UUID.self, forKey: .selectedPhraseID)
        let resolvedSelectedPhraseID: UUID
        if let decodedSelectedPhraseID, resolvedPhrases.contains(where: { $0.id == decodedSelectedPhraseID }) {
            resolvedSelectedPhraseID = decodedSelectedPhraseID
        } else {
            resolvedSelectedPhraseID = resolvedPhrases[0].id
        }

        version = resolvedVersion
        tracks = resolvedTracks
        trackGroups = resolvedTrackGroups
        generatorPool = resolvedGeneratorPool
        clipPool = resolvedClipPool
        layers = resolvedLayers
        routes = resolvedRoutes
        patternBanks = resolvedPatternBanks
        selectedTrackID = resolvedSelectedTrackID
        phrases = resolvedPhrases
        selectedPhraseID = resolvedSelectedPhraseID
        syncPhrasesWithTracks()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(trackGroups, forKey: .trackGroups)
        try container.encode(generatorPool, forKey: .generatorPool)
        try container.encode(clipPool, forKey: .clipPool)
        try container.encode(layers, forKey: .layers)
        try container.encode(routes, forKey: .routes)
        try container.encode(patternBanks, forKey: .patternBanks)
        try container.encode(selectedTrackID, forKey: .selectedTrackID)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(selectedPhraseID, forKey: .selectedPhraseID)
    }

    mutating func syncPhrasesWithTracks() {
        layers = layers.map { $0.synced(with: tracks) }
        if phrases.isEmpty {
            let fallback = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: generatorPool, clipPool: clipPool)
            phrases = [fallback]
            selectedPhraseID = fallback.id
        } else {
            phrases = phrases.map { $0.synced(with: tracks, layers: layers) }
        }

        patternBanks = Self.syncPatternBanks(
            patternBanks,
            with: tracks,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        trackGroups = trackGroups.map { group in
            var synced = group
            synced.memberIDs = group.memberIDs.filter { memberID in
                tracks.contains(where: { $0.id == memberID })
            }
            synced.noteMapping = group.noteMapping.filter { memberID, _ in
                synced.memberIDs.contains(memberID)
            }
            return synced
        }
        if !phrases.contains(where: { $0.id == selectedPhraseID }) {
            selectedPhraseID = phrases[0].id
        }
        if !tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = tracks[0].id
        }
    }

    static func defaultPatternBanks(
        for tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> [TrackPatternBank] {
        tracks.map {
            TrackPatternBank.default(for: $0, generatorPool: generatorPool, clipPool: clipPool)
        }
    }

    private static func syncPatternBanks(
        _ patternBanks: [TrackPatternBank],
        with tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> [TrackPatternBank] {
        tracks.map { track in
            let existing = patternBanks.first(where: { $0.trackID == track.id })
                ?? TrackPatternBank.default(for: track, generatorPool: generatorPool, clipPool: clipPool)
            return existing.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        }
    }
}
