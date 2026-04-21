import Foundation

struct PreviewRNG: RandomNumberGenerator {
    private var state: UInt64 = 0x5EEDC0DE

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}

func previewSteps(for params: GeneratorParams, clipChoices: [ClipPoolEntry], count: Int = 16) -> [[String]] {
    previewSteps(for: params.generatedSourcePipeline, clipChoices: clipChoices, count: count)
}

func previewSteps(for pipeline: GeneratedSourcePipeline, clipChoices: [ClipPoolEntry], count: Int = 16) -> [[String]] {
    GeneratedSourceEvaluator.previewNotes(
        for: pipeline,
        clipChoices: clipChoices,
        count: count
    ).map { notes in
        notes.map { note in
            if let voiceTag = note.voiceTag {
                return voiceTag
            }
            return "\(note.pitch)"
        }
    }
}
