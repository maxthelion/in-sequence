enum Chords {
    static let table: [ChordID: ChordDefinition] = [
        .majorTriad: ChordDefinition(id: .majorTriad, name: "Major Triad", intervals: [0, 4, 7]),
        .minorTriad: ChordDefinition(id: .minorTriad, name: "Minor Triad", intervals: [0, 3, 7]),
        .augmentedTriad: ChordDefinition(id: .augmentedTriad, name: "Augmented Triad", intervals: [0, 4, 8]),
        .diminishedTriad: ChordDefinition(id: .diminishedTriad, name: "Diminished Triad", intervals: [0, 3, 6]),
        .major7th: ChordDefinition(id: .major7th, name: "Major 7th", intervals: [0, 4, 7, 11]),
        .minor7th: ChordDefinition(id: .minor7th, name: "Minor 7th", intervals: [0, 3, 7, 10]),
        .dominant7th: ChordDefinition(id: .dominant7th, name: "Dominant 7th", intervals: [0, 4, 7, 10]),
        .diminished7th: ChordDefinition(id: .diminished7th, name: "Diminished 7th", intervals: [0, 3, 6, 9]),
        .augmented7th: ChordDefinition(id: .augmented7th, name: "Augmented 7th", intervals: [0, 4, 8, 10]),
        .halfDiminished7th: ChordDefinition(id: .halfDiminished7th, name: "Half-Diminished 7th", intervals: [0, 3, 6, 10]),
        .major6th: ChordDefinition(id: .major6th, name: "Major 6th", intervals: [0, 4, 7, 9]),
        .minor6th: ChordDefinition(id: .minor6th, name: "Minor 6th", intervals: [0, 3, 7, 9]),
        .major9th: ChordDefinition(id: .major9th, name: "Major 9th", intervals: [0, 4, 7, 11, 14]),
        .minor9th: ChordDefinition(id: .minor9th, name: "Minor 9th", intervals: [0, 3, 7, 10, 14]),
        .major11th: ChordDefinition(id: .major11th, name: "Major 11th", intervals: [0, 4, 7, 11, 14, 17]),
        .minor11th: ChordDefinition(id: .minor11th, name: "Minor 11th", intervals: [0, 3, 7, 10, 14, 17]),
    ]
}
