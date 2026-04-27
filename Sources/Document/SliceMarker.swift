import Foundation

struct SliceMarker: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var startFrame: Int64
    var endFrame: Int64
    var gain: Double
    var reverse: Bool
    var microTimingSteps: Double
    var tag: String

    init(
        id: UUID = UUID(),
        startFrame: Int64,
        endFrame: Int64,
        gain: Double = 0,
        reverse: Bool = false,
        microTimingSteps: Double = 0,
        tag: String = ""
    ) {
        self.id = id
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.gain = gain
        self.reverse = reverse
        self.microTimingSteps = microTimingSteps
        self.tag = tag
    }

    var clampedGain: Double {
        min(max(gain, -60), 12)
    }

    var clampedMicroTimingSteps: Double {
        min(max(microTimingSteps, -0.5), 0.5)
    }

    func normalized(sampleLengthFrames: Int64) -> SliceMarker? {
        let sampleLength = max(0, sampleLengthFrames)
        let start = min(max(startFrame, 0), sampleLength)
        let end = min(max(endFrame, start), sampleLength)
        guard sampleLength == 0 || end > start else {
            return nil
        }

        return SliceMarker(
            id: id,
            startFrame: start,
            endFrame: end,
            gain: clampedGain,
            reverse: reverse,
            microTimingSteps: clampedMicroTimingSteps,
            tag: tag
        )
    }
}
