import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int
    var tracks: [StepSequenceTrack]
    var generatorPool: [GeneratorPoolEntry]
    var clipPool: [ClipPoolEntry]
    var routes: [Route]
    var patternBanks: [TrackPatternBank]
    var selectedTrackID: UUID
    var phrases: [PhraseModel]
    var selectedPhraseID: UUID

    private enum CodingKeys: String, CodingKey {
        case version
        case tracks
        case generatorPool
        case clipPool
        case routes
        case patternBanks
        case selectedTrackID
        case phrases
        case selectedPhraseID
        case primaryTrack
    }

    static let empty = SeqAIDocumentModel(
        version: 1,
        tracks: [
            .default
        ],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [],
        routes: [],
        patternBanks: [
            TrackPatternBank.default(for: .default, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])
        ],
        selectedTrackID: StepSequenceTrack.default.id,
        phrases: [
            .default(tracks: [.default], generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])
        ],
        selectedPhraseID: PhraseModel.default(tracks: [.default], generatorPool: GeneratorPoolEntry.defaultPool, clipPool: []).id
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
            let fallback = PhraseModel.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)
            guard !phrases.isEmpty else {
                return fallback
            }
            return phrases[selectedPhraseIndex]
        }
        set {
            guard !phrases.isEmpty else {
                phrases = [newValue.synced(with: tracks)]
                selectedPhraseID = phrases[0].id
                return
            }
            phrases[selectedPhraseIndex] = newValue.synced(with: tracks)
            selectedPhraseID = phrases[selectedPhraseIndex].id
        }
    }

    func patternBank(for trackID: UUID) -> TrackPatternBank {
        patternBanks.first(where: { $0.trackID == trackID })
            ?? TrackPatternBank.default(
                for: tracks.first(where: { $0.id == trackID }) ?? .default,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
    }

    func selectedPatternIndex(for trackID: UUID) -> Int {
        selectedPhrase.patternIndex(for: trackID)
    }

    func selectedPattern(for trackID: UUID) -> TrackPatternSlot {
        patternBank(for: trackID).slot(at: selectedPatternIndex(for: trackID))
    }

    func selectedSourceRef(for trackID: UUID) -> SourceRef {
        selectedPattern(for: trackID).sourceRef
    }

    func selectedSourceMode(for trackID: UUID) -> TrackSourceMode {
        selectedSourceRef(for: trackID).mode
    }

    func routesSourced(from trackID: UUID) -> [Route] {
        routes.filter { route in
            switch route.source {
            case let .track(sourceTrackID), let .chordGenerator(sourceTrackID):
                return sourceTrackID == trackID
            }
        }
    }

    func routesTargeting(_ trackID: UUID) -> [Route] {
        routes.filter { $0.destination.targetTrackID == trackID }
    }

    mutating func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        var phrase = selectedPhrase
        phrase.setPatternIndex(index, for: trackID)
        selectedPhrase = phrase
    }

    func makeDefaultRoute(from trackID: UUID) -> Route {
        if let targetTrack = tracks.first(where: { $0.id != trackID }) {
            return Route(source: .track(trackID), destination: .voicing(targetTrack.id))
        }

        return Route(
            source: .track(trackID),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
    }

    mutating func upsertRoute(_ route: Route) {
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.append(route)
        }
    }

    mutating func removeRoute(id: UUID) {
        routes.removeAll { $0.id == id }
    }

    mutating func setPatternSourceMode(_ mode: TrackSourceMode, for trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        var bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        let sourceRef = defaultSourceRef(
            for: mode,
            trackType: track.trackType
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: sourceRef),
            at: slotIndex
        )
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func setPatternName(_ name: String, for trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        var bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: name, sourceRef: slot.sourceRef),
            at: slotIndex
        )
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
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

    mutating func appendPhrase() {
        var nextPhrase = PhraseModel.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)
        nextPhrase.id = UUID()
        nextPhrase.name = Self.defaultPhraseName(for: phrases.count)
        phrases.append(nextPhrase.synced(with: tracks))
        selectedPhraseID = nextPhrase.id
    }

    mutating func duplicateSelectedPhrase() {
        guard !phrases.isEmpty else {
            return
        }

        var duplicate = selectedPhrase
        duplicate.id = UUID()
        duplicate.name = "\(selectedPhrase.name) Copy"
        let insertionIndex = min(selectedPhraseIndex + 1, phrases.count)
        phrases.insert(duplicate.synced(with: tracks), at: insertionIndex)
        selectedPhraseID = duplicate.id
    }

    mutating func removeSelectedPhrase() {
        guard phrases.count > 1 else {
            return
        }

        phrases.remove(at: selectedPhraseIndex)
        selectedPhraseID = phrases[min(selectedPhraseIndex, phrases.count - 1)].id
    }

    mutating func appendTrack() {
        let nextIndex = tracks.count + 1
        let nextTrack = StepSequenceTrack(
            name: "Track \(nextIndex)",
            pitches: StepSequenceTrack.default.pitches,
            stepPattern: StepSequenceTrack.default.stepPattern,
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
        tracks.append(nextTrack)
        patternBanks.append(
            TrackPatternBank.default(for: nextTrack, generatorPool: generatorPool, clipPool: clipPool)
        )
        selectedTrackID = nextTrack.id
        syncPhrasesWithTracks()
    }

    mutating func setSelectedTrackType(_ trackType: TrackType) {
        guard !tracks.isEmpty else {
            return
        }

        tracks[selectedTrackIndex].trackType = trackType
        patternBanks = patternBanks.map { bank in
            guard bank.trackID == selectedTrackID else {
                return bank
            }
            return TrackPatternBank.default(
                for: tracks[selectedTrackIndex],
                generatorPool: generatorPool,
                clipPool: clipPool
            )
        }
        syncPhrasesWithTracks()
    }

    mutating func removeSelectedTrack() {
        guard tracks.count > 1 else {
            return
        }

        tracks.remove(at: selectedTrackIndex)
        selectedTrackID = tracks[min(selectedTrackIndex, tracks.count - 1)].id
        syncPhrasesWithTracks()
    }

    init(version: Int, tracks: [StepSequenceTrack], selectedTrackID: UUID) {
        let defaultGeneratorPool = GeneratorPoolEntry.defaultPool
        let defaultClipPool: [ClipPoolEntry] = []
        let defaultPhrases = [PhraseModel.default(tracks: tracks, generatorPool: defaultGeneratorPool, clipPool: defaultClipPool)]
        self.init(
            version: version,
            tracks: tracks,
            generatorPool: defaultGeneratorPool,
            clipPool: defaultClipPool,
            patternBanks: Self.defaultPatternBanks(for: tracks, generatorPool: defaultGeneratorPool, clipPool: defaultClipPool),
            selectedTrackID: selectedTrackID,
            phrases: defaultPhrases,
            selectedPhraseID: defaultPhrases[0].id
        )
    }

    init(
        version: Int,
        tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = [],
        routes: [Route] = [],
        patternBanks: [TrackPatternBank] = [],
        selectedTrackID: UUID,
        phrases: [PhraseModel],
        selectedPhraseID: UUID
    ) {
        self.version = version
        self.tracks = tracks
        self.generatorPool = generatorPool
        self.clipPool = clipPool
        self.routes = routes
        self.patternBanks = patternBanks.isEmpty
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
        self.selectedTrackID = tracks.contains(where: { $0.id == selectedTrackID }) ? selectedTrackID : tracks[0].id
        self.phrases = phrases.isEmpty
            ? [.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)]
            : phrases.map { $0.synced(with: tracks) }
        self.selectedPhraseID = self.phrases.contains(where: { $0.id == selectedPhraseID }) ? selectedPhraseID : self.phrases[0].id
        syncPhrasesWithTracks()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)

        if let decodedTracks = try container.decodeIfPresent([StepSequenceTrack].self, forKey: .tracks),
           !decodedTracks.isEmpty
        {
            let resolvedTracks = decodedTracks
            let resolvedGeneratorPool = try container.decodeIfPresent([GeneratorPoolEntry].self, forKey: .generatorPool) ?? GeneratorPoolEntry.defaultPool
            let resolvedClipPool = try container.decodeIfPresent([ClipPoolEntry].self, forKey: .clipPool) ?? []
            let resolvedRoutes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
            var resolvedSelectedTrackID = try container.decodeIfPresent(UUID.self, forKey: .selectedTrackID) ?? resolvedTracks[0].id
            if !resolvedTracks.contains(where: { $0.id == resolvedSelectedTrackID }) {
                resolvedSelectedTrackID = resolvedTracks[0].id
            }
            let resolvedPhrases: [PhraseModel]
            if let decodedPhrases = try container.decodeIfPresent([PhraseModel].self, forKey: .phrases),
               !decodedPhrases.isEmpty
            {
                resolvedPhrases = decodedPhrases.map {
                    $0.synced(with: resolvedTracks)
                }
            } else {
                resolvedPhrases = [.default(tracks: resolvedTracks, generatorPool: resolvedGeneratorPool, clipPool: resolvedClipPool)]
            }
            let decodedPatternBanks = try container.decodeIfPresent([TrackPatternBank].self, forKey: .patternBanks) ?? []
            let migrated: (patternBanks: [TrackPatternBank], phrases: [PhraseModel])
            if decodedPatternBanks.isEmpty {
                migrated = Self.migrateLegacyPatternBanks(
                    tracks: resolvedTracks,
                    generatorPool: resolvedGeneratorPool,
                    clipPool: resolvedClipPool,
                    phrases: resolvedPhrases
                )
            } else {
                migrated = (
                    patternBanks: decodedPatternBanks.map { bank in
                        bank.synced(
                            track: resolvedTracks.first(where: { $0.id == bank.trackID }) ?? .default,
                            generatorPool: resolvedGeneratorPool,
                            clipPool: resolvedClipPool
                        )
                    },
                    phrases: resolvedPhrases.map { $0.synced(with: resolvedTracks) }
                )
            }
            var resolvedSelectedPhraseID = try container.decodeIfPresent(UUID.self, forKey: .selectedPhraseID) ?? resolvedPhrases[0].id
            if !migrated.phrases.contains(where: { $0.id == resolvedSelectedPhraseID }) {
                resolvedSelectedPhraseID = migrated.phrases[0].id
            }
            tracks = resolvedTracks
            generatorPool = resolvedGeneratorPool
            clipPool = resolvedClipPool
            routes = resolvedRoutes
            patternBanks = migrated.patternBanks
            selectedTrackID = resolvedSelectedTrackID
            phrases = migrated.phrases
            selectedPhraseID = resolvedSelectedPhraseID
            return
        }

        let fallbackTrack = try container.decodeIfPresent(StepSequenceTrack.self, forKey: .primaryTrack) ?? .default
        tracks = [fallbackTrack]
        generatorPool = GeneratorPoolEntry.defaultPool
        clipPool = []
        routes = []
        patternBanks = Self.defaultPatternBanks(for: tracks, generatorPool: generatorPool, clipPool: clipPool)
        selectedTrackID = fallbackTrack.id
        phrases = [.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)]
        selectedPhraseID = phrases[0].id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(generatorPool, forKey: .generatorPool)
        try container.encode(clipPool, forKey: .clipPool)
        try container.encode(routes, forKey: .routes)
        try container.encode(patternBanks, forKey: .patternBanks)
        try container.encode(selectedTrackID, forKey: .selectedTrackID)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(selectedPhraseID, forKey: .selectedPhraseID)
    }

    private mutating func syncPhrasesWithTracks() {
        if phrases.isEmpty {
            let fallback = PhraseModel.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)
            phrases = [fallback]
            selectedPhraseID = fallback.id
        } else {
            phrases = phrases.map { $0.synced(with: tracks) }
        }

        patternBanks = Self.syncPatternBanks(
            patternBanks,
            with: tracks,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        if !phrases.contains(where: { $0.id == selectedPhraseID }) {
            selectedPhraseID = phrases[0].id
        }
        if !tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = tracks[0].id
        }
    }

    private static func defaultPhraseName(for index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if alphabet.indices.contains(index) {
            return "Phrase \(alphabet[index])"
        }
        return "Phrase \(index + 1)"
    }

    private static func defaultPatternBanks(
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

    private static func migrateLegacyPatternBanks(
        tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry],
        phrases: [PhraseModel]
    ) -> (patternBanks: [TrackPatternBank], phrases: [PhraseModel]) {
        var patternBanks = defaultPatternBanks(for: tracks, generatorPool: generatorPool, clipPool: clipPool)
        var migratedPhrases = phrases.map { $0.synced(with: tracks) }

        for track in tracks {
            let legacyRefs = migratedPhrases.compactMap { phrase -> SourceRef? in
                phrase.legacySourceRefs.first(where: { $0.trackID == track.id })?.sourceRef.normalized(
                    trackType: track.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool
                )
            }

            guard !legacyRefs.isEmpty,
                  let bankIndex = patternBanks.firstIndex(where: { $0.trackID == track.id })
            else {
                continue
            }

            var uniqueRefs: [SourceRef] = []
            for sourceRef in legacyRefs where !uniqueRefs.contains(sourceRef) {
                uniqueRefs.append(sourceRef)
                if uniqueRefs.count == TrackPatternBank.slotCount {
                    break
                }
            }

            var bank = patternBanks[bankIndex]
            for (slotIndex, sourceRef) in uniqueRefs.enumerated() {
                let existingName = bank.slot(at: slotIndex).name
                bank.setSlot(
                    TrackPatternSlot(slotIndex: slotIndex, name: existingName, sourceRef: sourceRef),
                    at: slotIndex
                )
            }
            patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)

            for index in migratedPhrases.indices {
                let sourceRef = migratedPhrases[index].legacySourceRefs.first(where: { $0.trackID == track.id })?.sourceRef.normalized(
                    trackType: track.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool
                )
                let slotIndex = sourceRef.flatMap { ref in
                    patternBanks[bankIndex].slots.firstIndex(where: { $0.sourceRef == ref })
                } ?? 0
                migratedPhrases[index].setPatternIndex(slotIndex, for: track.id)
                migratedPhrases[index].legacySourceRefs = []
            }
        }

        return (patternBanks, migratedPhrases.map { $0.synced(with: tracks) })
    }

    private func defaultSourceRef(for mode: TrackSourceMode, trackType: TrackType) -> SourceRef {
        switch mode {
        case .generator:
            return .generator(generatorPool.first(where: { $0.trackType == trackType })?.id)
        case .clip:
            return .clip(clipPool.first(where: { $0.trackType == trackType })?.id)
        }
    }
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var pitches: [Int]
    var stepPattern: [Bool]
    var stepAccents: [Bool]
    var voicing: Voicing
    var mix: TrackMixSettings
    var velocity: Int
    var gateLength: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trackType
        case source
        case pitches
        case stepPattern
        case stepAccents
        case voicing
        case output
        case audioInstrument
        case mix
        case velocity
        case gateLength
    }

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        trackType: .monoMelodic,
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        stepAccents: Array(repeating: false, count: 16),
        voicing: .single(.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)),
        mix: .default,
        velocity: 100,
        gateLength: 4
    )

    init(
        id: UUID = UUID(),
        name: String,
        trackType: TrackType = .monoMelodic,
        pitches: [Int],
        stepPattern: [Bool],
        stepAccents: [Bool]? = nil,
        voicing: Voicing? = nil,
        output: TrackOutputDestination = .midiOut,
        audioInstrument: AudioInstrumentChoice = .builtInSynth,
        mix: TrackMixSettings = .default,
        velocity: Int,
        gateLength: Int
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.pitches = pitches
        self.stepPattern = stepPattern
        self.stepAccents = Self.normalizedAccents(stepAccents, stepCount: stepPattern.count)
        self.voicing = voicing ?? Self.legacyVoicing(
            output: output,
            audioInstrument: audioInstrument,
            trackType: trackType
        )
        self.mix = mix
        self.velocity = velocity
        self.gateLength = gateLength
    }

    var activeStepCount: Int {
        stepPattern.filter { $0 }.count
    }

    var accentedStepCount: Int {
        zip(stepPattern, stepAccents).filter { $0 && $1 }.count
    }

    mutating func cycleStep(at index: Int) {
        guard stepPattern.indices.contains(index),
              stepAccents.indices.contains(index)
        else {
            return
        }

        if !stepPattern[index] {
            stepPattern[index] = true
            stepAccents[index] = false
        } else if !stepAccents[index] {
            stepAccents[index] = true
        } else {
            stepPattern[index] = false
            stepAccents[index] = false
        }
    }

    mutating func accentDownbeats(groupSize: Int = 4) {
        guard groupSize > 0 else {
            return
        }

        stepAccents = stepPattern.enumerated().map { index, isEnabled in
            isEnabled && index % groupSize == 0
        }
    }

    mutating func clearAccents() {
        stepAccents = Array(repeating: false, count: stepPattern.count)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        if let decodedTrackType = try container.decodeIfPresent(TrackType.self, forKey: .trackType) {
            trackType = decodedTrackType
        } else {
            let legacySource = try container.decodeIfPresent(LegacyTrackSource.self, forKey: .source)
            trackType = legacySource?.trackType ?? .monoMelodic
        }
        pitches = try container.decode([Int].self, forKey: .pitches)
        stepPattern = try container.decode([Bool].self, forKey: .stepPattern)
        let decodedAccents = try container.decodeIfPresent([Bool].self, forKey: .stepAccents)
        stepAccents = Self.normalizedAccents(decodedAccents, stepCount: stepPattern.count)
        if let decodedVoicing = try container.decodeIfPresent(Voicing.self, forKey: .voicing) {
            voicing = decodedVoicing
        } else {
            let legacyOutput = try container.decodeIfPresent(TrackOutputDestination.self, forKey: .output) ?? .midiOut
            let legacyInstrument = try container.decodeIfPresent(AudioInstrumentChoice.self, forKey: .audioInstrument) ?? .builtInSynth
            voicing = Self.legacyVoicing(
                output: legacyOutput,
                audioInstrument: legacyInstrument,
                trackType: trackType
            )
        }
        mix = try container.decodeIfPresent(TrackMixSettings.self, forKey: .mix) ?? .default
        velocity = try container.decode(Int.self, forKey: .velocity)
        gateLength = try container.decode(Int.self, forKey: .gateLength)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackType, forKey: .trackType)
        try container.encode(pitches, forKey: .pitches)
        try container.encode(stepPattern, forKey: .stepPattern)
        try container.encode(stepAccents, forKey: .stepAccents)
        try container.encode(voicing, forKey: .voicing)
        try container.encode(mix, forKey: .mix)
        try container.encode(velocity, forKey: .velocity)
        try container.encode(gateLength, forKey: .gateLength)
    }

    var defaultDestination: Destination {
        voicing.defaultDestination
    }

    var output: TrackOutputDestination {
        get {
            switch defaultDestination {
            case .midi:
                return .midiOut
            case .auInstrument:
                return .auInstrument
            case .internalSampler:
                return .internalSampler
            case .inheritGroup, .none:
                return .none
            }
        }
        set {
            switch newValue {
            case .midiOut:
                let port: MIDIEndpointName?
                let channel: UInt8
                let noteOffset: Int
                if case let .midi(existingPort, existingChannel, existingOffset) = defaultDestination {
                    port = existingPort
                    channel = existingChannel
                    noteOffset = existingOffset
                } else {
                    port = .sequencerAIOut
                    channel = 0
                    noteOffset = 0
                }
                voicing.setDefault(.midi(port: port, channel: channel, noteOffset: noteOffset))
            case .auInstrument:
                voicing.setDefault(.auInstrument(componentID: audioInstrument.audioComponentID, stateBlob: nil))
            case .internalSampler:
                voicing.setDefault(Voicing.defaults(forType: trackType).defaultDestination)
            case .none:
                voicing.setDefault(.none)
            }
        }
    }

    var midiPortName: MIDIEndpointName? {
        if case let .midi(port, _, _) = defaultDestination {
            return port
        }
        return nil
    }

    var midiChannel: UInt8 {
        if case let .midi(_, channel, _) = defaultDestination {
            return channel
        }
        return 0
    }

    var midiNoteOffset: Int {
        if case let .midi(_, _, noteOffset) = defaultDestination {
            return noteOffset
        }
        return 0
    }

    mutating func setMIDIPort(_ port: MIDIEndpointName?) {
        voicing.setDefault(.midi(port: port, channel: midiChannel, noteOffset: midiNoteOffset))
    }

    mutating func setMIDIChannel(_ channel: UInt8) {
        voicing.setDefault(.midi(port: midiPortName, channel: channel, noteOffset: midiNoteOffset))
    }

    mutating func setMIDINoteOffset(_ noteOffset: Int) {
        voicing.setDefault(.midi(port: midiPortName, channel: midiChannel, noteOffset: noteOffset))
    }

    var audioInstrument: AudioInstrumentChoice {
        get {
            switch defaultDestination {
            case let .auInstrument(componentID, _):
                return AudioInstrumentChoice.defaultChoices.first(where: { $0.audioComponentID == componentID })
                    ?? AudioInstrumentChoice(audioComponentID: componentID)
            default:
                return .builtInSynth
            }
        }
        set {
            voicing.setDefault(.auInstrument(componentID: newValue.audioComponentID, stateBlob: nil))
        }
    }

    private static func normalizedAccents(_ accents: [Bool]?, stepCount: Int) -> [Bool] {
        let fallback = Array(repeating: false, count: stepCount)
        guard let accents else {
            return fallback
        }
        if accents.count == stepCount {
            return accents
        }
        return Array(accents.prefix(stepCount)) + Array(repeating: false, count: max(0, stepCount - accents.count))
    }

    private static func legacyVoicing(
        output: TrackOutputDestination,
        audioInstrument: AudioInstrumentChoice,
        trackType: TrackType
    ) -> Voicing {
        switch output {
        case .midiOut:
            return .single(.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
        case .auInstrument:
            return .single(.auInstrument(componentID: audioInstrument.audioComponentID, stateBlob: nil))
        case .internalSampler:
            return Voicing.defaults(forType: trackType)
        case .none:
            return .single(.none)
        }
    }
}

private enum LegacyTrackSource: String, Codable {
    case manualMono
    case clip
    case template
    case midiIn
    case drumRack
    case sliceLoop

    var trackType: TrackType {
        switch self {
        case .manualMono, .clip, .template, .midiIn:
            return .monoMelodic
        case .drumRack:
            return .monoMelodic
        case .sliceLoop:
            return .slice
        }
    }
}

enum TrackType: String, Codable, CaseIterable, Equatable, Sendable {
    case monoMelodic
    case polyMelodic
    case slice

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case "monoMelodic":
            self = .monoMelodic
        case "polyMelodic":
            self = .polyMelodic
        case "slice":
            self = .slice
        case "instrument":
            self = .monoMelodic
        case "drumRack":
            self = .monoMelodic
        case "sliceLoop":
            self = .slice
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown TrackType: \(raw)"
            )
        }
    }

    var label: String {
        switch self {
        case .monoMelodic:
            return "Mono"
        case .polyMelodic:
            return "Poly"
        case .slice:
            return "Slice"
        }
    }

    var shortLabel: String {
        switch self {
        case .monoMelodic:
            return "Mono"
        case .polyMelodic:
            return "Poly"
        case .slice:
            return "Slice"
        }
    }
}

enum TrackOutputDestination: String, Codable, CaseIterable, Equatable, Sendable {
    case midiOut
    case auInstrument
    case internalSampler
    case none

    var label: String {
        switch self {
        case .midiOut:
            return "Virtual MIDI Out"
        case .auInstrument:
            return "AU Instrument"
        case .internalSampler:
            return "Internal Sampler"
        case .none:
            return "No Default Output"
        }
    }
}

struct TrackMixSettings: Codable, Equatable, Sendable {
    var level: Double
    var pan: Double
    var isMuted: Bool

    static let `default` = TrackMixSettings(level: 0.8, pan: 0, isMuted: false)

    var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var clampedPan: Double {
        min(max(pan, -1), 1)
    }
}
