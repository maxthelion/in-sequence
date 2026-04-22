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
    let trackStates: [TrackPhrasePlaybackBuffer]
}
