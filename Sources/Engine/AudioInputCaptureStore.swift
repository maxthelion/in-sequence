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
        liveLevel: .silent,
        recordingProgress: 0,
        streamedWaveformBuckets: [],
        completedWaveformBuckets: [],
        capturedFrameCount: 0,
        completedFrameCount: 0
    )

    var liveLevel: AudioInputLevelSnapshot
    var recordingProgress: Double
    var streamedWaveformBuckets: [Float]
    var completedWaveformBuckets: [Float]
    var capturedFrameCount: Int
    var completedFrameCount: Int
}

final class AudioInputCaptureStore {
    private struct CaptureState {
        var liveLevel = AudioInputLevelSnapshot.silent
        var recordingProgress: Double = 0
        var isRecording = false
        var capturedMagnitudes: [Float] = []
        var streamedWaveformBuckets: [Float] = []
        var completedWaveformBuckets: [Float] = []
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
            return snapshot(from: state)
        }
    }

    func beginCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = true
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            return snapshot(from: state)
        }
    }

    func cancelCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            return snapshot(from: state)
        }
    }

    func updateProgress(trackID: UUID, progress: Double) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.recordingProgress = min(max(progress, 0), 1)
            return snapshot(from: state)
        }
    }

    func completeCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.completedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            state.completedFrameCount = state.capturedMagnitudes.count
            state.streamedWaveformBuckets = []
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            return snapshot(from: state)
        }
    }

    func replaceCompletedLoop(trackID: UUID, waveformBuckets: [Float]) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.completedWaveformBuckets = waveformBuckets.map(Self.clampedBucket)
            state.completedFrameCount = waveformBuckets.count
            return snapshot(from: state)
        }
    }

    func process(buffer: AVAudioPCMBuffer, trackID: UUID) -> AudioInputCaptureSnapshot {
        let level = Self.levelSnapshot(buffer: buffer)
        let magnitudes = Self.monoMagnitudes(buffer: buffer)

        return withState(trackID: trackID) { state in
            state.liveLevel = level
            if state.isRecording, !magnitudes.isEmpty {
                state.capturedMagnitudes.append(contentsOf: magnitudes)
                state.streamedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            }
            return snapshot(from: state)
        }
    }

    private func withState(
        trackID: UUID,
        update: (inout CaptureState) -> AudioInputCaptureSnapshot
    ) -> AudioInputCaptureSnapshot {
        lock.lock()
        var state = states[trackID] ?? CaptureState()
        let output = update(&state)
        states[trackID] = state
        lock.unlock()
        return output
    }

    private func snapshot(from state: CaptureState) -> AudioInputCaptureSnapshot {
        AudioInputCaptureSnapshot(
            liveLevel: state.liveLevel,
            recordingProgress: state.recordingProgress,
            streamedWaveformBuckets: Array(state.streamedWaveformBuckets),
            completedWaveformBuckets: Array(state.completedWaveformBuckets),
            capturedFrameCount: state.capturedMagnitudes.count,
            completedFrameCount: state.completedFrameCount
        )
    }

    private static func levelSnapshot(buffer: AVAudioPCMBuffer) -> AudioInputLevelSnapshot {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0,
              let channels = buffer.floatChannelData
        else {
            return .silent
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return .silent }

        let left = peakAmplitude(channel: channels[0], frameCount: frameCount)
        let right = channelCount > 1
            ? peakAmplitude(channel: channels[1], frameCount: frameCount)
            : left
        return AudioInputLevelSnapshot(leftPeak: left, rightPeak: right)
    }

    private static func monoMagnitudes(buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0,
              let channels = buffer.floatChannelData
        else {
            return []
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return [] }

        var output = Array<Float>(repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += abs(channels[channel][frame])
            }
            output[frame] = min(sum / Float(channelCount), 1)
        }
        return output
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

    private static func peakAmplitude(channel: UnsafePointer<Float>, frameCount: Int) -> Float {
        var peak: Float = 0
        for frame in 0..<frameCount {
            peak = max(peak, abs(channel[frame]))
        }
        return clampedBucket(peak)
    }

    private static func clampedBucket(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
