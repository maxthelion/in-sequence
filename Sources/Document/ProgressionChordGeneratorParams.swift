import Foundation

enum ProgressionChordMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case major
    case minor

    var label: String {
        switch self {
        case .major:
            return "Major"
        case .minor:
            return "Minor"
        }
    }

    var scaleIntervals: [Int] {
        switch self {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11]
        case .minor:
            return [0, 2, 3, 5, 7, 8, 10]
        }
    }
}

enum ProgressionChordQuality: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case major
    case minor
    case minor7
    case dominant7
    case diminished

    var label: String {
        switch self {
        case .major:
            return "Major"
        case .minor:
            return "Minor"
        case .minor7:
            return "Minor 7"
        case .dominant7:
            return "Dominant 7"
        case .diminished:
            return "Diminished"
        }
    }

    var intervals: [Int] {
        switch self {
        case .major:
            return [0, 4, 7]
        case .minor:
            return [0, 3, 7]
        case .minor7:
            return [0, 3, 7, 10]
        case .dominant7:
            return [0, 4, 7, 10]
        case .diminished:
            return [0, 3, 6]
        }
    }

    var isMajorish: Bool {
        self == .major || self == .dominant7
    }
}

enum ProgressionChordVoicing: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case close
    case open
    case drop2
    case spread

    var label: String {
        switch self {
        case .close:
            return "Close"
        case .open:
            return "Open"
        case .drop2:
            return "Drop 2"
        case .spread:
            return "Spread"
        }
    }
}

enum ProgressionChordLength: Codable, Equatable, Hashable, Sendable {
    case untilNext
    case steps(Int)

    static let quickValues: [ProgressionChordLength] = [
        .untilNext,
        .steps(4),
        .steps(8),
        .steps(16),
    ]

    var label: String {
        switch self {
        case .untilNext:
            return "Until next"
        case let .steps(count):
            return "\(max(1, count)) steps"
        }
    }
}

struct ProgressionChord: Codable, Equatable, Hashable, Sendable {
    var position: Int
    var accidental: Int
    var quality: ProgressionChordQuality
    var inversion: Int
    var voicing: ProgressionChordVoicing
    var noteCount: Int
    var length: ProgressionChordLength

    static let minorOne = ProgressionChord(
        position: 0,
        accidental: 0,
        quality: .minor,
        inversion: 0,
        voicing: .close,
        noteCount: 3,
        length: .untilNext
    )

    var normalized: ProgressionChord {
        ProgressionChord(
            position: min(max(position, -14), 14),
            accidental: min(max(accidental, -2), 2),
            quality: quality,
            inversion: min(max(inversion, 0), 3),
            voicing: voicing,
            noteCount: min(max(noteCount, 2), 5),
            length: normalizedLength
        )
    }

    private var normalizedLength: ProgressionChordLength {
        switch length {
        case .untilNext:
            return .untilNext
        case let .steps(count):
            return .steps(min(max(count, 1), 128))
        }
    }
}

struct ProgressionChordGeneratorParams: Codable, Equatable, Hashable, Sendable {
    var rootMIDI: Int
    var mode: ProgressionChordMode
    var lengthSteps: Int
    var chords: [ProgressionChord?]
    var velocity: Int

    static let `default` = seeded(
        seed: .minorDescending,
        rootMIDI: 60,
        mode: .minor,
        lengthSteps: 64
    )

    var normalized: ProgressionChordGeneratorParams {
        let resolvedLength = min(max(lengthSteps, 16), 128)
        let normalizedChords = (0..<resolvedLength).map { index -> ProgressionChord? in
            guard chords.indices.contains(index) else { return nil }
            return chords[index]?.normalized
        }
        return ProgressionChordGeneratorParams(
            rootMIDI: min(max(rootMIDI, 0), 127),
            mode: mode,
            lengthSteps: resolvedLength,
            chords: normalizedChords,
            velocity: min(max(velocity, 1), 127)
        )
    }

    static func empty(rootMIDI: Int, mode: ProgressionChordMode, lengthSteps: Int) -> ProgressionChordGeneratorParams {
        let length = min(max(lengthSteps, 16), 128)
        return ProgressionChordGeneratorParams(
            rootMIDI: min(max(rootMIDI, 0), 127),
            mode: mode,
            lengthSteps: length,
            chords: Array(repeating: nil, count: length),
            velocity: 100
        )
    }

    static func seeded(
        seed: ProgressionChordSeed,
        rootMIDI: Int,
        mode: ProgressionChordMode,
        lengthSteps: Int
    ) -> ProgressionChordGeneratorParams {
        var params = empty(rootMIDI: rootMIDI, mode: mode, lengthSteps: lengthSteps)
        guard seed != .empty else { return params }
        let source = seed.chords(mode: mode)
        for (index, chord) in source.enumerated() {
            let step = index * 16
            if params.chords.indices.contains(step) {
                params.chords[step] = chord
            }
        }
        return params
    }

    func chord(at stepIndex: Int) -> ProgressionChord? {
        let params = normalized
        guard !params.chords.isEmpty else { return nil }
        return params.chords[positiveModulo(stepIndex, params.lengthSteps)]
    }

    func generatedNotes(at stepIndex: Int) -> [GeneratedNote] {
        let params = normalized
        guard let chord = params.chord(at: stepIndex) else {
            return []
        }
        let length = params.resolvedLength(forChordAt: stepIndex, chord: chord)
        return params.pitches(for: chord).map { pitch in
            GeneratedNote(pitch: pitch, velocity: params.velocity, length: length, voiceTag: nil)
        }
    }

    func resolvedLength(forChordAt stepIndex: Int, chord: ProgressionChord) -> Int {
        let params = normalized
        switch chord.length {
        case let .steps(count):
            return min(max(count, 1), params.lengthSteps)
        case .untilNext:
            let normalizedStep = positiveModulo(stepIndex, params.lengthSteps)
            for offset in 1...params.lengthSteps {
                let candidate = (normalizedStep + offset) % params.lengthSteps
                if params.chords.indices.contains(candidate), params.chords[candidate] != nil {
                    return offset
                }
            }
            return params.lengthSteps
        }
    }

    func pitches(for chord: ProgressionChord) -> [Int] {
        let params = normalized
        let normalizedChord = chord.normalized
        let scale = params.mode.scaleIntervals
        let degree = positiveModulo(normalizedChord.position, scale.count)
        let octave = Int(floor(Double(normalizedChord.position) / Double(scale.count))) * 12
        let root = params.rootMIDI + scale[degree] + octave + normalizedChord.accidental
        var notes = normalizedChord.quality.intervals.map { root + $0 }
        for _ in 0..<normalizedChord.inversion where !notes.isEmpty {
            notes.append(notes.removeFirst() + 12)
        }
        switch normalizedChord.voicing {
        case .close:
            break
        case .open:
            notes = notes.enumerated().map { index, pitch in index % 2 == 1 ? pitch + 12 : pitch }
        case .drop2:
            if notes.count > 2 {
                notes[notes.count - 2] -= 12
            }
        case .spread:
            notes = notes.enumerated().map { index, pitch in pitch + index * 12 }
        }
        let source = notes
        while notes.count < normalizedChord.noteCount, !source.isEmpty {
            let sourceIndex = notes.count % source.count
            let octave = (notes.count / source.count) * 12
            notes.append(source[sourceIndex] + octave)
        }
        return Array(notes.prefix(normalizedChord.noteCount)).map { min(max($0, 0), 127) }
    }

    func roman(for chord: ProgressionChord) -> String {
        let major = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let minor = ["i", "ii", "iii", "iv", "v", "vi", "vii"]
        let degree = positiveModulo(chord.position, 7)
        var label = chord.quality.isMajorish ? major[degree] : minor[degree]
        if chord.accidental > 0 {
            label = String(repeating: "#", count: chord.accidental) + label
        } else if chord.accidental < 0 {
            label = String(repeating: "b", count: abs(chord.accidental)) + label
        }
        if chord.quality == .diminished {
            label += "dim"
        } else if chord.quality == .minor7 || chord.quality == .dominant7 {
            label += "7"
        }
        return label
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        ((value % modulus) + modulus) % modulus
    }
}

enum ProgressionChordSeed: String, CaseIterable, Identifiable, Sendable {
    case minorDescending
    case popMajor
    case jazzTurnaround
    case empty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minorDescending:
            return "i - VII - VI - VII"
        case .popMajor:
            return "I - V - vi - IV"
        case .jazzTurnaround:
            return "ii - V - I - VI"
        case .empty:
            return "Empty"
        }
    }

    func chords(mode: ProgressionChordMode) -> [ProgressionChord] {
        switch self {
        case .minorDescending:
            return [
                ProgressionChord(position: 0, accidental: 0, quality: mode == .major ? .major : .minor, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 6, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 5, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 6, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
            ]
        case .popMajor:
            return [
                ProgressionChord(position: 0, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 4, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 5, accidental: 0, quality: .minor, inversion: 0, voicing: .open, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 3, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
            ]
        case .jazzTurnaround:
            return [
                ProgressionChord(position: 1, accidental: 0, quality: .minor7, inversion: 0, voicing: .close, noteCount: 4, length: .untilNext),
                ProgressionChord(position: 4, accidental: 0, quality: .dominant7, inversion: 0, voicing: .drop2, noteCount: 4, length: .untilNext),
                ProgressionChord(position: 0, accidental: 0, quality: .major, inversion: 0, voicing: .close, noteCount: 3, length: .untilNext),
                ProgressionChord(position: 5, accidental: 0, quality: .major, inversion: 0, voicing: .open, noteCount: 3, length: .untilNext),
            ]
        case .empty:
            return []
        }
    }
}
