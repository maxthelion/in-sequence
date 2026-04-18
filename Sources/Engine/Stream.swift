import Foundation

struct NoteEvent: Equatable, Sendable {
    let pitch: UInt8
    let velocity: UInt8
    let length: UInt16
    let gate: Bool
    let voiceTag: String?
}

struct Chord: Equatable, Sendable {
    let root: UInt8
    let chordType: String
    let scale: String
}

enum EventKind: Equatable, Sendable {
    case fillFlag
    case barTick
    case custom(String)
}

enum Stream: Equatable, Sendable {
    case notes([NoteEvent])
    case scalar(Double)
    case chord(Chord)
    case event(EventKind)
    case gate(Bool)
    case stepIndex(Int)
}
