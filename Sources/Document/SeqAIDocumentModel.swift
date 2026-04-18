import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int
    var tracks: [StepSequenceTrack]
    var selectedTrackID: UUID

    private enum CodingKeys: String, CodingKey {
        case version
        case tracks
        case selectedTrackID
        case primaryTrack
    }

    static let empty = SeqAIDocumentModel(
        version: 1,
        tracks: [
            .default
        ],
        selectedTrackID: StepSequenceTrack.default.id
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

    mutating func selectTrack(id: UUID) {
        guard tracks.contains(where: { $0.id == id }) else {
            return
        }
        selectedTrackID = id
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
    }

    mutating func removeSelectedTrack() {
        guard tracks.count > 1 else {
            return
        }

        tracks.remove(at: selectedTrackIndex)
        selectedTrackID = tracks[min(selectedTrackIndex, tracks.count - 1)].id
    }

    init(version: Int, tracks: [StepSequenceTrack], selectedTrackID: UUID) {
        self.version = version
        self.tracks = tracks
        self.selectedTrackID = selectedTrackID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)

        if let decodedTracks = try container.decodeIfPresent([StepSequenceTrack].self, forKey: .tracks),
           !decodedTracks.isEmpty
        {
            tracks = decodedTracks
            selectedTrackID = try container.decodeIfPresent(UUID.self, forKey: .selectedTrackID) ?? decodedTracks[0].id
            if !tracks.contains(where: { $0.id == selectedTrackID }) {
                selectedTrackID = tracks[0].id
            }
            return
        }

        let fallbackTrack = try container.decodeIfPresent(StepSequenceTrack.self, forKey: .primaryTrack) ?? .default
        tracks = [fallbackTrack]
        selectedTrackID = fallbackTrack.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(selectedTrackID, forKey: .selectedTrackID)
    }
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var pitches: [Int]
    var stepPattern: [Bool]
    var stepAccents: [Bool]
    var velocity: Int
    var gateLength: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pitches
        case stepPattern
        case stepAccents
        case velocity
        case gateLength
    }

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        stepAccents: Array(repeating: false, count: 16),
        velocity: 100,
        gateLength: 4
    )

    init(
        id: UUID = UUID(),
        name: String,
        pitches: [Int],
        stepPattern: [Bool],
        stepAccents: [Bool]? = nil,
        velocity: Int,
        gateLength: Int
    ) {
        self.id = id
        self.name = name
        self.pitches = pitches
        self.stepPattern = stepPattern
        self.stepAccents = Self.normalizedAccents(stepAccents, stepCount: stepPattern.count)
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
        pitches = try container.decode([Int].self, forKey: .pitches)
        stepPattern = try container.decode([Bool].self, forKey: .stepPattern)
        let decodedAccents = try container.decodeIfPresent([Bool].self, forKey: .stepAccents)
        stepAccents = Self.normalizedAccents(decodedAccents, stepCount: stepPattern.count)
        velocity = try container.decode(Int.self, forKey: .velocity)
        gateLength = try container.decode(Int.self, forKey: .gateLength)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(pitches, forKey: .pitches)
        try container.encode(stepPattern, forKey: .stepPattern)
        try container.encode(stepAccents, forKey: .stepAccents)
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
