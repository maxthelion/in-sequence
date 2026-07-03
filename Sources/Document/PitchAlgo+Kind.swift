import Foundation

enum PitchAlgoKind: String, CaseIterable, Identifiable, Sendable {
    case manual
    case pool
    case randomInScale
    case randomInChord
    case intervalProb
    case markov
    case fromClipPitches
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .pool:
            return "Pool"
        case .randomInScale:
            return "Scale"
        case .randomInChord:
            return "Chord"
        case .intervalProb:
            return "Intervals"
        case .markov:
            return "Markov"
        case .fromClipPitches:
            return "From Clip"
        case .external:
            return "External"
        }
    }

    func defaultAlgo(clipChoices: [ClipPoolEntry], current: PitchAlgo) -> PitchAlgo {
        switch self {
        case .manual:
            if case let .manual(pitches, pickMode) = current {
                return .manual(pitches: pitches, pickMode: pickMode)
            }
            return .manual(pitches: [60, 64, 67], pickMode: .sequential)
        case .pool:
            if case let .pool(root, scale, spread, selection, deviation) = current {
                return .pool(root: root, scale: scale, spread: spread, selection: selection, deviation: deviation)
            }
            return .pool(root: 60, scale: .major, spread: 12, selection: .balanced, deviation: .none)
        case .randomInScale:
            return .randomInScale(root: 60, scale: .major, spread: 12)
        case .randomInChord:
            return .randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12)
        case .intervalProb:
            return .intervalProb(root: 60, scale: .major, degreeWeights: Array(repeating: 0.5, count: 7))
        case .markov:
            return .markov(root: 60, scale: .major, styleID: .balanced, leap: 0.35, color: 0.2)
        case .fromClipPitches:
            if let clipID = clipChoices.first?.id {
                return .fromClipPitches(clipID: clipID, pickMode: .sequential)
            }
            return .manual(pitches: [60], pickMode: .sequential)
        case .external:
            return .external(port: "External MIDI", channel: 0, holdMode: .pool)
        }
    }
}

extension PitchAlgo {
    var kind: PitchAlgoKind {
        switch self {
        case .manual:
            return .manual
        case .pool:
            return .pool
        case .randomInScale:
            return .randomInScale
        case .randomInChord:
            return .randomInChord
        case .intervalProb:
            return .intervalProb
        case .markov:
            return .markov
        case .fromClipPitches:
            return .fromClipPitches
        case .external:
            return .external
        }
    }
}
