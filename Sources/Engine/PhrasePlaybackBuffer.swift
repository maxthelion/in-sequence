import Foundation

struct TrackPhrasePlaybackBuffer: Equatable, Sendable {
    let patternSlotIndex: [UInt8]
    let mute: [Bool]
    let fillEnabled: [Bool]
    let macroValues: [[Double]]
}

struct PhrasePlaybackBuffer: Equatable, Sendable {
    let phraseID: UUID
    let stepCount: Int
    let trackStates: [UUID: TrackPhrasePlaybackBuffer]

    func trackState(for trackID: UUID) -> TrackPhrasePlaybackBuffer? {
        trackStates[trackID]
    }
}
