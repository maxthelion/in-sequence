import Foundation

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var pitches: [Int]
    var stepPattern: [Bool]
    var stepAccents: [Bool]
    var destination: Destination
    var groupID: TrackGroupID?
    var mix: TrackMixSettings
    var velocity: Int
    var gateLength: Int
    /// Per-track macro bindings. Capped at 8 (enforced by `Project.addAUMacro`).
    var macros: [TrackMacroBinding]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trackType
        case pitches
        case stepPattern
        case stepAccents
        case destination
        case groupID
        case mix
        case velocity
        case gateLength
        case macros
    }

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        trackType: .monoMelodic,
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        stepAccents: Array(repeating: false, count: 16),
        destination: .none,
        groupID: nil,
        mix: .default,
        velocity: 100,
        gateLength: 4,
        macros: []
    )

    init(
        id: UUID = UUID(),
        name: String,
        trackType: TrackType = .monoMelodic,
        pitches: [Int],
        stepPattern: [Bool],
        stepAccents: [Bool]? = nil,
        destination: Destination? = nil,
        groupID: TrackGroupID? = nil,
        mix: TrackMixSettings = .default,
        velocity: Int,
        gateLength: Int,
        macros: [TrackMacroBinding] = []
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.pitches = pitches
        self.stepPattern = stepPattern
        self.stepAccents = Self.normalizedAccents(stepAccents, stepCount: stepPattern.count)
        self.destination = destination ?? Project.defaultDestination(for: trackType)
        self.groupID = groupID
        self.mix = mix
        self.velocity = velocity
        self.gateLength = gateLength
        self.macros = macros
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
        pitches = try container.decode([Int].self, forKey: .pitches)
        stepPattern = try container.decode([Bool].self, forKey: .stepPattern)
        let decodedAccents = try container.decodeIfPresent([Bool].self, forKey: .stepAccents)
        stepAccents = Self.normalizedAccents(decodedAccents, stepCount: stepPattern.count)
        destination = try container.decode(Destination.self, forKey: .destination)
        groupID = try container.decodeIfPresent(TrackGroupID.self, forKey: .groupID)
        mix = try container.decodeIfPresent(TrackMixSettings.self, forKey: .mix) ?? .default
        velocity = try container.decode(Int.self, forKey: .velocity)
        gateLength = try container.decode(Int.self, forKey: .gateLength)
        // Legacy documents without macros decode as empty — no migration needed.
        macros = try container.decodeIfPresent([TrackMacroBinding].self, forKey: .macros) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackType, forKey: .trackType)
        try container.encode(pitches, forKey: .pitches)
        try container.encode(stepPattern, forKey: .stepPattern)
        try container.encode(stepAccents, forKey: .stepAccents)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encode(mix, forKey: .mix)
        try container.encode(velocity, forKey: .velocity)
        try container.encode(gateLength, forKey: .gateLength)
        try container.encode(macros, forKey: .macros)
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
}
