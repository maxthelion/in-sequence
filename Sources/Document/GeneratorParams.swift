import Foundation

typealias VoiceTag = String
let defaultVoiceTag: VoiceTag = "default"

enum GeneratorParams: Codable, Equatable, Hashable, Sendable {
    case mono(trigger: TriggerStageNode, pitch: PitchStageNode, shape: NoteShape)
    case poly(trigger: TriggerStageNode, pitches: [PitchStageNode], shape: NoteShape)
    case drum(triggers: [VoiceTag: TriggerStageNode], shape: NoteShape)
    case template(templateID: UUID)
    case slice(trigger: TriggerStageNode, sliceIndexes: [Int])

    static let defaultMono = GeneratorParams.mono(
        trigger: .native(.defaultMono),
        pitch: .native(.defaultMono),
        shape: .default
    )

    static let defaultDrumKit = GeneratorParams.drum(
        triggers: [
            "kick": .native(
                .init(
                    algo: .manual(pattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]),
                    basePitch: Int(DrumKitNoteMap.note(for: "kick"))
                )
            ),
            "snare": .native(
                .init(
                    algo: .manual(pattern: [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]),
                    basePitch: Int(DrumKitNoteMap.note(for: "snare"))
                )
            ),
            "hat": .native(
                .init(
                    algo: .euclidean(pulses: 8, steps: 16, offset: 0),
                    basePitch: Int(DrumKitNoteMap.note(for: "hat-closed"))
                )
            ),
        ],
        shape: .default
    )
}
