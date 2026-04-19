enum Scales {
    static let table: [ScaleID: Scale] = [
        .chromatic: Scale(id: .chromatic, name: "Chromatic", intervals: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
        .major: Scale(id: .major, name: "Major", intervals: [0, 2, 4, 5, 7, 9, 11]),
        .naturalMinor: Scale(id: .naturalMinor, name: "Natural Minor", intervals: [0, 2, 3, 5, 7, 8, 10]),
        .harmonicMinor: Scale(id: .harmonicMinor, name: "Harmonic Minor", intervals: [0, 2, 3, 5, 7, 8, 11]),
        .melodicMinor: Scale(id: .melodicMinor, name: "Melodic Minor", intervals: [0, 2, 3, 5, 7, 9, 11]),
        .majorPentatonic: Scale(id: .majorPentatonic, name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9]),
        .minorPentatonic: Scale(id: .minorPentatonic, name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10]),
        .blues: Scale(id: .blues, name: "Blues", intervals: [0, 3, 5, 6, 7, 10]),
        .dorian: Scale(id: .dorian, name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10]),
        .phrygian: Scale(id: .phrygian, name: "Phrygian", intervals: [0, 1, 3, 5, 7, 8, 10]),
        .lydian: Scale(id: .lydian, name: "Lydian", intervals: [0, 2, 4, 6, 7, 9, 11]),
        .mixolydian: Scale(id: .mixolydian, name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10]),
        .locrian: Scale(id: .locrian, name: "Locrian", intervals: [0, 1, 3, 5, 6, 8, 10]),
        .wholeTone: Scale(id: .wholeTone, name: "Whole Tone", intervals: [0, 2, 4, 6, 8, 10]),
        .diminished: Scale(id: .diminished, name: "Diminished", intervals: [0, 2, 3, 5, 6, 8, 9, 11]),
        .augmented: Scale(id: .augmented, name: "Augmented", intervals: [0, 3, 4, 7, 8, 11]),
        .gypsy: Scale(id: .gypsy, name: "Gypsy", intervals: [0, 2, 3, 6, 7, 8, 11]),
        .hungarianMinor: Scale(id: .hungarianMinor, name: "Hungarian Minor", intervals: [0, 2, 3, 6, 7, 8, 11]),
        .akebono: Scale(id: .akebono, name: "Akebono", intervals: [0, 2, 3, 7, 8]),
    ]
}
