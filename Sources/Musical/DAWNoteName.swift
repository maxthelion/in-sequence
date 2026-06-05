import Foundation

enum DAWNoteName {
    private static let sharpNames = [
        "C", "C#", "D", "D#", "E", "F",
        "F#", "G", "G#", "A", "A#", "B",
    ]

    private static let naturalSemitones: [Character: Int] = [
        "C": 0,
        "D": 2,
        "E": 4,
        "F": 5,
        "G": 7,
        "A": 9,
        "B": 11,
    ]

    static func string(forMIDINote midiNote: Int) -> String? {
        guard (0...127).contains(midiNote) else { return nil }
        let octave = midiNote / 12 - 1
        let pitchClass = midiNote % 12
        return "\(sharpNames[pitchClass])\(octave)"
    }

    static func string(forNoteOffset noteOffset: Int) -> String? {
        string(forMIDINote: DrumKitNoteMap.baselineNote + noteOffset)
    }

    static func midiNote(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var index = trimmed.startIndex
        let letter = Character(String(trimmed[index]).uppercased())
        guard let naturalSemitone = naturalSemitones[letter] else { return nil }
        trimmed.formIndex(after: &index)

        var accidental = 0
        if index < trimmed.endIndex {
            let accidentalCharacter = trimmed[index]
            if accidentalCharacter == "#" {
                accidental = 1
                trimmed.formIndex(after: &index)
            } else if accidentalCharacter == "b" || accidentalCharacter == "B" {
                accidental = -1
                trimmed.formIndex(after: &index)
            }
        }

        guard index < trimmed.endIndex else { return nil }
        let octaveText = String(trimmed[index...])
        guard let octave = Int(octaveText) else { return nil }

        let midiNote = (octave + 1) * 12 + naturalSemitone + accidental
        guard (0...127).contains(midiNote) else { return nil }
        return midiNote
    }

    static func noteOffset(from input: String) -> Int? {
        midiNote(from: input).map { $0 - DrumKitNoteMap.baselineNote }
    }
}
