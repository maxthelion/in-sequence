import Foundation

typealias VoiceTag = String

enum GeneratorParams: Codable, Equatable, Sendable {
    case mono(step: StepAlgo, pitch: PitchAlgo, shape: NoteShape)
    case poly(step: StepAlgo, pitches: [PitchAlgo], shape: NoteShape)
    case drum(steps: [VoiceTag: StepAlgo], shape: NoteShape)
    case template(templateID: UUID)
    case slice(step: StepAlgo, sliceIndexes: [Int])

    static let defaultMono = GeneratorParams.mono(
        step: .manual(pattern: Array(repeating: false, count: 16)),
        pitch: .manual(pitches: [60, 62, 64, 67], pickMode: .random),
        shape: .default
    )

    static let defaultDrumKit = GeneratorParams.drum(
        steps: [
            "kick": .manual(pattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]),
            "snare": .manual(pattern: [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]),
            "hat": .euclidean(pulses: 8, steps: 16, offset: 0),
        ],
        shape: .default
    )
}
