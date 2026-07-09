import Foundation

enum NoteRepeatInterval: String, Codable, CaseIterable, Sendable {
    case oneQuarter = "1/4"
    case oneEighth = "1/8"
    case oneSixteenth = "1/16"
    case oneThirtySecond = "1/32"
    case oneSixtyFourth = "1/64"

    static let defaultValue: NoteRepeatInterval = .oneSixteenth

    /// Triggers fired within each 16th step (faster-than-step rates).
    var v1TriggerCountPerStep: Int {
        switch self {
        case .oneQuarter, .oneEighth, .oneSixteenth:
            return 1
        case .oneThirtySecond:
            return 2
        case .oneSixtyFourth:
            return 4
        }
    }

    /// Steps between triggers (slower-than-step rates). 1 = every step.
    var v1StepStride: Int {
        switch self {
        case .oneQuarter:
            return 4
        case .oneEighth:
            return 2
        case .oneSixteenth, .oneThirtySecond, .oneSixtyFourth:
            return 1
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = rawValue.flatMap(Self.init(rawValue:)) ?? Self.defaultValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    /// Drum-part tag ("kick", "snare", …) for drum-group members. The join key
    /// for kit/template matching. Nil for tracks outside drum groups (and for
    /// legacy documents, which never persisted tags).
    var voiceTag: VoiceTag?
    var pitches: [Int]
    var stepPattern: [Bool]
    var stepAccents: [Bool]
    var destination: Destination
    var groupID: TrackGroupID?
    var outputBusID: UUID?
    var mix: TrackMixSettings
    var velocity: Int
    var gateLength: Int
    /// Per-track macro bindings. Capped at 8 (enforced by `Project.addAUMacro`).
    var macros: [TrackMacroBinding]
    /// Per-track ordered FX insert chain. A new model concept (track-view IA):
    /// inserts previously lived only on buses / master / scenes. Ordered;
    /// each insert is independently bypassable. Defaults empty; legacy
    /// documents decode as empty.
    var fxInserts: [TrackFXInsert]
    /// Per-track filter settings. Lives here (not on Destination) so it survives
    /// sample swaps. Defaults are bypass-transparent.
    var filter: SamplerFilterSettings
    var recordBarLength: Int
    var inputChannel: AudioInputChannel
    var noteRepeatInterval: NoteRepeatInterval
    var chordPalette: ChordPalette

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trackType
        case voiceTag
        case pitches
        case stepPattern
        case stepAccents
        case destination
        case groupID
        case outputBusID
        case mix
        case velocity
        case gateLength
        case macros
        case fxInserts
        case filter
        case recordBarLength
        case inputChannel
        case noteRepeatInterval
        case chordPalette
    }

    static let allowedRecordBarLengths: Set<Int> = [1, 2, 4, 8]
    static let defaultRecordBarLength = 2
    static let defaultInputChannel = AudioInputChannel.stereo(firstChannel: 0)

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        trackType: .monoMelodic,
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        stepAccents: Array(repeating: false, count: 16),
        destination: Destination.none,
        groupID: nil,
        outputBusID: nil,
        mix: .default,
        velocity: 100,
        gateLength: 4,
        macros: [],
        fxInserts: [],
        filter: .init(),
        recordBarLength: Self.defaultRecordBarLength,
        inputChannel: Self.defaultInputChannel,
        noteRepeatInterval: NoteRepeatInterval.defaultValue,
        chordPalette: .default
    )

    init(
        id: UUID = UUID(),
        name: String,
        trackType: TrackType = .monoMelodic,
        voiceTag: VoiceTag? = nil,
        pitches: [Int],
        stepPattern: [Bool],
        stepAccents: [Bool]? = nil,
        destination: Destination? = nil,
        groupID: TrackGroupID? = nil,
        outputBusID: UUID? = nil,
        mix: TrackMixSettings = .default,
        velocity: Int,
        gateLength: Int,
        macros: [TrackMacroBinding] = [],
        fxInserts: [TrackFXInsert] = [],
        filter: SamplerFilterSettings = .init(),
        recordBarLength: Int = Self.defaultRecordBarLength,
        inputChannel: AudioInputChannel = Self.defaultInputChannel,
        noteRepeatInterval: NoteRepeatInterval = NoteRepeatInterval.defaultValue,
        chordPalette: ChordPalette = .default
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.voiceTag = voiceTag
        self.pitches = pitches
        self.stepPattern = stepPattern
        self.stepAccents = Self.normalizedAccents(stepAccents, stepCount: stepPattern.count)
        self.destination = destination ?? Project.defaultDestination(for: trackType)
        self.groupID = groupID
        self.outputBusID = outputBusID
        self.mix = mix
        self.velocity = velocity
        self.gateLength = gateLength
        self.macros = Self.normalizedMacros(macros)
        self.fxInserts = TrackFXInsert.normalizedChain(fxInserts)
        self.filter = filter
        self.recordBarLength = Self.normalizedRecordBarLength(recordBarLength)
        self.inputChannel = inputChannel
        self.noteRepeatInterval = noteRepeatInterval
        self.chordPalette = chordPalette.normalized
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
        trackType = try container.decode(TrackType.self, forKey: .trackType)
        // Legacy documents without voiceTag decode as nil — no migration needed.
        voiceTag = try container.decodeIfPresent(VoiceTag.self, forKey: .voiceTag)
        pitches = try container.decode([Int].self, forKey: .pitches)
        stepPattern = try container.decode([Bool].self, forKey: .stepPattern)
        let decodedAccents = try container.decodeIfPresent([Bool].self, forKey: .stepAccents)
        stepAccents = Self.normalizedAccents(decodedAccents, stepCount: stepPattern.count)
        destination = try container.decode(Destination.self, forKey: .destination)
        groupID = try container.decodeIfPresent(TrackGroupID.self, forKey: .groupID)
        outputBusID = try container.decodeIfPresent(UUID.self, forKey: .outputBusID)
        mix = try container.decodeIfPresent(TrackMixSettings.self, forKey: .mix) ?? .default
        velocity = try container.decode(Int.self, forKey: .velocity)
        gateLength = try container.decode(Int.self, forKey: .gateLength)
        // Legacy documents without macros decode as empty — no migration needed.
        // normalizedMacros assigns sequential slotIndex values to legacy bindings that
        // were stored without slotIndex (all decode to 0 via decodeIfPresent fallback).
        macros = Self.normalizedMacros(
            try container.decodeIfPresent([TrackMacroBinding].self, forKey: .macros) ?? []
        )
        // Legacy documents without an FX chain decode as an empty chain.
        fxInserts = TrackFXInsert.normalizedChain(
            try container.decodeIfPresent([TrackFXInsert].self, forKey: .fxInserts) ?? []
        )
        // Legacy documents without filter decode with bypass-transparent defaults.
        filter = try container.decodeIfPresent(SamplerFilterSettings.self, forKey: .filter) ?? .init()
        let decodedRecordBarLength = try container.decodeIfPresent(Int.self, forKey: .recordBarLength)
        recordBarLength = Self.normalizedRecordBarLength(decodedRecordBarLength ?? Self.defaultRecordBarLength)
        inputChannel = (try? container.decodeIfPresent(AudioInputChannel.self, forKey: .inputChannel)) ?? Self.defaultInputChannel
        noteRepeatInterval = (try? container.decodeIfPresent(NoteRepeatInterval.self, forKey: .noteRepeatInterval)) ?? .defaultValue
        chordPalette = ((try? container.decodeIfPresent(ChordPalette.self, forKey: .chordPalette)) ?? nil)?.normalized ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackType, forKey: .trackType)
        try container.encodeIfPresent(voiceTag, forKey: .voiceTag)
        try container.encode(pitches, forKey: .pitches)
        try container.encode(stepPattern, forKey: .stepPattern)
        try container.encode(stepAccents, forKey: .stepAccents)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encodeIfPresent(outputBusID, forKey: .outputBusID)
        try container.encode(mix, forKey: .mix)
        try container.encode(velocity, forKey: .velocity)
        try container.encode(gateLength, forKey: .gateLength)
        try container.encode(macros, forKey: .macros)
        try container.encode(fxInserts, forKey: .fxInserts)
        try container.encode(filter, forKey: .filter)
        if trackType == .audioInput {
            try container.encode(recordBarLength, forKey: .recordBarLength)
            try container.encode(inputChannel, forKey: .inputChannel)
        }
        try container.encode(noteRepeatInterval, forKey: .noteRepeatInterval)
        if trackType == .chord {
            try container.encode(chordPalette.normalized, forKey: .chordPalette)
        }
    }

    var defaultDestination: Destination {
        destination.withoutTransientState
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
        destination = .midi(port: port, channel: midiChannel, noteOffset: midiNoteOffset)
    }

    mutating func setMIDIChannel(_ channel: UInt8) {
        destination = .midi(port: midiPortName, channel: channel, noteOffset: midiNoteOffset)
    }

    mutating func setMIDINoteOffset(_ noteOffset: Int) {
        destination = .midi(port: midiPortName, channel: midiChannel, noteOffset: noteOffset)
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

    static func normalizedRecordBarLength(_ recordBarLength: Int) -> Int {
        allowedRecordBarLengths.contains(recordBarLength) ? recordBarLength : defaultRecordBarLength
    }

    /// Normalise macro bindings so slotIndex values are valid (0-7) and unique.
    /// Legacy documents store bindings without slotIndex — all decode to 0.
    /// When multiple bindings share the same slotIndex, sequential slots are assigned.
    private static func normalizedMacros(_ macros: [TrackMacroBinding]) -> [TrackMacroBinding] {
        guard !macros.isEmpty else {
            return []
        }

        // Legacy path: all bindings have slotIndex == 0 and there's more than one.
        if macros.count > 1, macros.allSatisfy({ $0.slotIndex == 0 }) {
            return Array(
                macros
                    .prefix(8)
                    .enumerated()
                    .map { index, binding in
                        binding.withSlotIndex(index)
                    }
            )
        }

        var normalized: [TrackMacroBinding] = []
        var occupiedSlots = Set<Int>()

        for binding in macros.prefix(8) {
            let requestedSlot = binding.slotIndex
            if (0..<8).contains(requestedSlot), !occupiedSlots.contains(requestedSlot) {
                normalized.append(binding.withSlotIndex(requestedSlot))
                occupiedSlots.insert(requestedSlot)
                continue
            }

            guard let fallbackSlot = (0..<8).first(where: { !occupiedSlots.contains($0) }) else {
                continue
            }
            normalized.append(binding.withSlotIndex(fallbackSlot))
            occupiedSlots.insert(fallbackSlot)
        }

        return normalized.sorted { lhs, rhs in
            if lhs.slotIndex != rhs.slotIndex {
                return lhs.slotIndex < rhs.slotIndex
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
