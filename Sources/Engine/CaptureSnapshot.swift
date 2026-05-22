import Foundation

struct CaptureSnapshot: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let absoluteStep: Int
        let notes: [Note]
    }

    struct Note: Equatable, Hashable, Sendable {
        let pitch: Int
        let velocity: Int
        let lengthSteps: Int
        let voiceTag: VoiceTag?
        let sliceParameters: SliceTriggerStepParameters?

        init(
            pitch: Int,
            velocity: Int,
            lengthSteps: Int,
            voiceTag: VoiceTag?,
            sliceParameters: SliceTriggerStepParameters? = nil
        ) {
            self.pitch = pitch
            self.velocity = velocity
            self.lengthSteps = max(1, lengthSteps)
            self.voiceTag = voiceTag
            self.sliceParameters = sliceParameters
        }

        init(_ generatedNote: GeneratedNote) {
            self.init(
                pitch: generatedNote.pitch,
                velocity: generatedNote.velocity,
                lengthSteps: generatedNote.length,
                voiceTag: generatedNote.voiceTag,
                sliceParameters: generatedNote.sliceParameters
            )
        }
    }

    let maxSteps: Int
    let steps: [Step]

    var isEmpty: Bool { steps.isEmpty }

    init(maxSteps: Int = 256, steps: [Step] = []) {
        let resolvedMaxSteps = max(1, maxSteps)
        self.maxSteps = resolvedMaxSteps
        self.steps = Array(steps.suffix(resolvedMaxSteps))
    }
}
