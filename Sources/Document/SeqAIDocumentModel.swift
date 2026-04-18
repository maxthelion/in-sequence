import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int
    var tracks: [StepSequenceTrack]
    var generatorPool: [GeneratorPoolEntry]
    var clipPool: [ClipPoolEntry]
    var selectedTrackID: UUID
    var phrases: [PhraseModel]
    var selectedPhraseID: UUID

    private enum CodingKeys: String, CodingKey {
        case version
        case tracks
        case generatorPool
        case clipPool
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
                phrases = [newValue.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool)]
                selectedPhraseID = phrases[0].id
                return
            }
            phrases[selectedPhraseIndex] = newValue.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool)
            selectedPhraseID = phrases[selectedPhraseIndex].id
        }
    }

    func selectedSourceRef(for trackID: UUID) -> SourceRef {
        selectedPhrase.sourceRef(for: trackID)
    }

    func selectedSourceMode(for trackID: UUID) -> TrackSourceMode {
        selectedPhrase.sourceMode(for: trackID)
    }

    mutating func setSelectedPhraseSourceMode(_ mode: TrackSourceMode, for trackID: UUID) {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return
        }

        var phrase = selectedPhrase
        phrase.setSourceMode(
            mode,
            for: trackID,
            trackType: track.trackType,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        selectedPhrase = phrase
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
        phrases.append(nextPhrase.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool))
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
        phrases.insert(duplicate.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool), at: insertionIndex)
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
        selectedTrackID = nextTrack.id
        syncPhrasesWithTracks()
    }

    mutating func setSelectedTrackType(_ trackType: TrackType) {
        guard !tracks.isEmpty else {
            return
        }

        tracks[selectedTrackIndex].trackType = trackType
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
        selectedTrackID: UUID,
        phrases: [PhraseModel],
        selectedPhraseID: UUID
    ) {
        self.version = version
        self.tracks = tracks
        self.generatorPool = generatorPool
        self.clipPool = clipPool
        self.selectedTrackID = selectedTrackID
        self.phrases = phrases.isEmpty
            ? [.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)]
            : phrases.map { $0.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool) }
        self.selectedPhraseID = self.phrases.contains(where: { $0.id == selectedPhraseID }) ? selectedPhraseID : self.phrases[0].id
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
            var resolvedSelectedTrackID = try container.decodeIfPresent(UUID.self, forKey: .selectedTrackID) ?? resolvedTracks[0].id
            if !resolvedTracks.contains(where: { $0.id == resolvedSelectedTrackID }) {
                resolvedSelectedTrackID = resolvedTracks[0].id
            }
            let resolvedPhrases: [PhraseModel]
            if let decodedPhrases = try container.decodeIfPresent([PhraseModel].self, forKey: .phrases),
               !decodedPhrases.isEmpty
            {
                resolvedPhrases = decodedPhrases.map {
                    $0.synced(with: resolvedTracks, generatorPool: resolvedGeneratorPool, clipPool: resolvedClipPool)
                }
            } else {
                resolvedPhrases = [.default(tracks: resolvedTracks, generatorPool: resolvedGeneratorPool, clipPool: resolvedClipPool)]
            }
            var resolvedSelectedPhraseID = try container.decodeIfPresent(UUID.self, forKey: .selectedPhraseID) ?? resolvedPhrases[0].id
            if !resolvedPhrases.contains(where: { $0.id == resolvedSelectedPhraseID }) {
                resolvedSelectedPhraseID = resolvedPhrases[0].id
            }
            tracks = resolvedTracks
            generatorPool = resolvedGeneratorPool
            clipPool = resolvedClipPool
            selectedTrackID = resolvedSelectedTrackID
            phrases = resolvedPhrases
            selectedPhraseID = resolvedSelectedPhraseID
            return
        }

        let fallbackTrack = try container.decodeIfPresent(StepSequenceTrack.self, forKey: .primaryTrack) ?? .default
        tracks = [fallbackTrack]
        generatorPool = GeneratorPoolEntry.defaultPool
        clipPool = []
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
        try container.encode(selectedTrackID, forKey: .selectedTrackID)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(selectedPhraseID, forKey: .selectedPhraseID)
    }

    private mutating func syncPhrasesWithTracks() {
        if phrases.isEmpty {
            let fallback = PhraseModel.default(tracks: tracks, generatorPool: generatorPool, clipPool: clipPool)
            phrases = [fallback]
            selectedPhraseID = fallback.id
            return
        }

        phrases = phrases.map { $0.synced(with: tracks, generatorPool: generatorPool, clipPool: clipPool) }
        if !phrases.contains(where: { $0.id == selectedPhraseID }) {
            selectedPhraseID = phrases[0].id
        }
    }

    private static func defaultPhraseName(for index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if alphabet.indices.contains(index) {
            return "Phrase \(alphabet[index])"
        }
        return "Phrase \(index + 1)"
    }
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var pitches: [Int]
    var stepPattern: [Bool]
    var stepAccents: [Bool]
    var output: TrackOutputDestination
    var audioInstrument: AudioInstrumentChoice
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
        case output
        case audioInstrument
        case mix
        case velocity
        case gateLength
    }

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        trackType: .instrument,
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        stepAccents: Array(repeating: false, count: 16),
        output: .midiOut,
        audioInstrument: .builtInSynth,
        mix: .default,
        velocity: 100,
        gateLength: 4
    )

    init(
        id: UUID = UUID(),
        name: String,
        trackType: TrackType = .instrument,
        pitches: [Int],
        stepPattern: [Bool],
        stepAccents: [Bool]? = nil,
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
        self.output = output
        self.audioInstrument = audioInstrument
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
            trackType = legacySource?.trackType ?? .instrument
        }
        pitches = try container.decode([Int].self, forKey: .pitches)
        stepPattern = try container.decode([Bool].self, forKey: .stepPattern)
        let decodedAccents = try container.decodeIfPresent([Bool].self, forKey: .stepAccents)
        stepAccents = Self.normalizedAccents(decodedAccents, stepCount: stepPattern.count)
        output = try container.decodeIfPresent(TrackOutputDestination.self, forKey: .output) ?? .midiOut
        audioInstrument = try container.decodeIfPresent(AudioInstrumentChoice.self, forKey: .audioInstrument) ?? .builtInSynth
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
        try container.encode(output, forKey: .output)
        try container.encode(audioInstrument, forKey: .audioInstrument)
        try container.encode(mix, forKey: .mix)
        try container.encode(velocity, forKey: .velocity)
        try container.encode(gateLength, forKey: .gateLength)
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
            return .instrument
        case .drumRack:
            return .drumRack
        case .sliceLoop:
            return .sliceLoop
        }
    }
}

enum TrackType: String, Codable, CaseIterable, Equatable, Sendable {
    case instrument
    case drumRack
    case sliceLoop

    var label: String {
        switch self {
        case .instrument:
            return "Instrument"
        case .drumRack:
            return "Drum Rack"
        case .sliceLoop:
            return "Slice Loop"
        }
    }

    var shortLabel: String {
        switch self {
        case .instrument:
            return "Inst"
        case .drumRack:
            return "Drum"
        case .sliceLoop:
            return "Slice"
        }
    }
}

enum TrackOutputDestination: String, Codable, CaseIterable, Equatable, Sendable {
    case midiOut
    case auInstrument

    var label: String {
        switch self {
        case .midiOut:
            return "Virtual MIDI Out"
        case .auInstrument:
            return "Built-in AU Synth"
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
