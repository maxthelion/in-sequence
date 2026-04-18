import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int
    var tracks: [StepSequenceTrack]
    var selectedTrackID: UUID

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
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var pitches: [Int]
    var stepPattern: [Bool]
    var velocity: Int
    var gateLength: Int

    static let `default` = StepSequenceTrack(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Main Track",
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        velocity: 100,
        gateLength: 4
    )

    init(
        id: UUID = UUID(),
        name: String,
        pitches: [Int],
        stepPattern: [Bool],
        velocity: Int,
        gateLength: Int
    ) {
        self.id = id
        self.name = name
        self.pitches = pitches
        self.stepPattern = stepPattern
        self.velocity = velocity
        self.gateLength = gateLength
    }
}
