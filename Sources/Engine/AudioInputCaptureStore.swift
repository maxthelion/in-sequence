import AVFoundation
import Foundation

struct AudioInputLevelSnapshot: Equatable, Sendable {
    static let silent = AudioInputLevelSnapshot(leftPeak: 0, rightPeak: 0)

    var leftPeak: Float
    var rightPeak: Float

    var peak: Float {
        max(leftPeak, rightPeak)
    }
}

struct AudioInputCaptureSnapshot: Equatable, Sendable {
    static let empty = AudioInputCaptureSnapshot(
        revision: 0,
        liveLevel: .silent,
        recordingProgress: 0,
        streamedWaveformBuckets: [],
        completedWaveformBuckets: [],
        capturedFrameCount: 0,
        completedFrameCount: 0
    )

    var revision: UInt64
    var liveLevel: AudioInputLevelSnapshot
    var recordingProgress: Double
    var streamedWaveformBuckets: [Float]
    var completedWaveformBuckets: [Float]
    var capturedFrameCount: Int
    var completedFrameCount: Int
}

struct AudioInputCaptureBufferSummary: Equatable, Sendable {
    var liveLevel: AudioInputLevelSnapshot
    var monoPeak: Float
    var frameCount: Int

    var hasFrames: Bool {
        frameCount > 0
    }
}

final class AudioInputCaptureStore {
    private struct CaptureState {
        var revision: UInt64 = 0
        var liveLevel = AudioInputLevelSnapshot.silent
        var recordingProgress: Double = 0
        var isRecording = false
        var capturedMagnitudes: [Float] = []
        var streamedWaveformBuckets: [Float] = []
        var completedWaveformBuckets: [Float] = []
        var capturedFrameCount = 0
        var completedFrameCount = 0
    }

    private let lock = NSLock()
    private let bucketCount: Int
    private var states: [UUID: CaptureState] = [:]

    init(bucketCount: Int = 64) {
        self.bucketCount = max(1, bucketCount)
    }

    func keepOnly(trackIDs: Set<UUID>) {
        lock.lock()
        states = states.filter { trackIDs.contains($0.key) }
        lock.unlock()
    }

    func prepareCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.recordingProgress = 0
            state.streamedWaveformBuckets = []
        }
    }

    func beginCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = true
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.capturedFrameCount = 0
        }
    }

    func cancelCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.capturedFrameCount = 0
        }
    }

    func updateProgress(trackID: UUID, progress: Double) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.recordingProgress = min(max(progress, 0), 1)
        }
    }

    func completeCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.completedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            state.completedFrameCount = state.capturedFrameCount
            state.streamedWaveformBuckets = []
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.capturedFrameCount = 0
        }
    }

    func replaceCompletedLoop(trackID: UUID, waveformBuckets: [Float]) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.completedWaveformBuckets = waveformBuckets.map(Self.clampedBucket)
            state.capturedFrameCount = 0
            state.completedFrameCount = waveformBuckets.count
        }
    }

    func process(summary: AudioInputCaptureBufferSummary, trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.liveLevel = summary.liveLevel
            if state.isRecording, summary.hasFrames {
                state.capturedMagnitudes.append(summary.monoPeak)
                state.capturedFrameCount += summary.frameCount
                state.streamedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            }
        }
    }

    static func summarize(buffer: AVAudioPCMBuffer) -> AudioInputCaptureBufferSummary {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0,
              let channels = buffer.floatChannelData
        else {
            return AudioInputCaptureBufferSummary(liveLevel: .silent, monoPeak: 0, frameCount: 0)
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            return AudioInputCaptureBufferSummary(liveLevel: .silent, monoPeak: 0, frameCount: 0)
        }

        var leftPeak: Float = 0
        var rightPeak: Float = 0
        var monoPeak: Float = 0

        for frame in 0..<frameCount {
            var frameMagnitude: Float = 0
            for channel in 0..<channelCount {
                let magnitude = abs(channels[channel][frame])
                frameMagnitude += magnitude
                if channel == 0 {
                    leftPeak = max(leftPeak, magnitude)
                } else if channel == 1 {
                    rightPeak = max(rightPeak, magnitude)
                }
            }
            monoPeak = max(monoPeak, frameMagnitude / Float(channelCount))
        }

        if channelCount == 1 {
            rightPeak = leftPeak
        }

        return AudioInputCaptureBufferSummary(
            liveLevel: AudioInputLevelSnapshot(
                leftPeak: clampedBucket(leftPeak),
                rightPeak: clampedBucket(rightPeak)
            ),
            monoPeak: clampedBucket(monoPeak),
            frameCount: frameCount
        )
    }

    private func withState(
        trackID: UUID,
        update: (inout CaptureState) -> Void
    ) -> AudioInputCaptureSnapshot {
        lock.lock()
        var state = states[trackID] ?? CaptureState()
        update(&state)
        state.revision &+= 1
        let output = snapshot(from: state)
        states[trackID] = state
        lock.unlock()
        return output
    }

    private func snapshot(from state: CaptureState) -> AudioInputCaptureSnapshot {
        AudioInputCaptureSnapshot(
            revision: state.revision,
            liveLevel: state.liveLevel,
            recordingProgress: state.recordingProgress,
            streamedWaveformBuckets: Array(state.streamedWaveformBuckets),
            completedWaveformBuckets: Array(state.completedWaveformBuckets),
            capturedFrameCount: state.capturedFrameCount,
            completedFrameCount: state.completedFrameCount
        )
    }

    private static func downsample(_ magnitudes: [Float], bucketCount: Int) -> [Float] {
        guard !magnitudes.isEmpty else {
            return []
        }

        var output = Array<Float>(repeating: 0, count: bucketCount)
        for bucket in 0..<bucketCount {
            let start = Int((Double(bucket) / Double(bucketCount)) * Double(magnitudes.count))
            let end = Int((Double(bucket + 1) / Double(bucketCount)) * Double(magnitudes.count))
            guard start < end else { continue }
            output[bucket] = magnitudes[start..<end].reduce(0) { max($0, clampedBucket($1)) }
        }
        return output
    }

    private static func clampedBucket(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
