struct PitchContext: Equatable, Sendable {
    let lastPitch: Int?
    let scaleRoot: Int
    let scaleID: ScaleID
    let currentChord: Chord?
    let stepIndex: Int
}
