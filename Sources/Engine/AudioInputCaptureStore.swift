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

struct AudioInputCapturedPCM: Equatable, Sendable {
    var sampleRate: Double
    var channels: [[Float]]

    var frameCount: Int {
        channels.first?.count ?? 0
    }

    var channelCount: Int {
        channels.count
    }
}

struct AudioInputCaptureBufferPacket: Equatable, Sendable {
    var summary: AudioInputCaptureBufferSummary
    var capturedPCM: AudioInputCapturedPCM?
}

final class AudioInputCaptureSummaryRing {
    private final class Slot {
        let sequence = AtomicInt32(0)
        var trackID = UUID()
        var packet = AudioInputCaptureBufferPacket(
            summary: AudioInputCaptureBufferSummary(liveLevel: .silent, monoPeak: 0, frameCount: 0),
            capturedPCM: nil
        )
    }

    private let slots: [Slot]
    private let capacity: Int32
    private let writeSequence = AtomicInt32(0)
    private var readSequence: Int32 = 0

    init(capacity: Int = 1024) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = Int32(resolvedCapacity)
        self.slots = (0..<resolvedCapacity).map { _ in Slot() }
    }

    func write(
        trackID: UUID,
        summary: AudioInputCaptureBufferSummary,
        capturedPCM: AudioInputCapturedPCM? = nil
    ) {
        let sequence = writeSequence.increment()
        let slot = slots[index(for: sequence)]
        slot.trackID = trackID
        slot.packet = AudioInputCaptureBufferPacket(summary: summary, capturedPCM: capturedPCM)
        slot.sequence.store(sequence)
    }

    func drain(_ consume: (UUID, AudioInputCaptureBufferPacket) -> Void) {
        let writeLimit = writeSequence.load()
        guard writeLimit > readSequence else { return }

        let earliestAvailableSequence = max(readSequence &+ 1, writeLimit &- capacity &+ 1)
        if earliestAvailableSequence > readSequence &+ 1 {
            readSequence = earliestAvailableSequence &- 1
        }

        var nextSequence = readSequence &+ 1
        while nextSequence <= writeLimit {
            let slot = slots[index(for: nextSequence)]
            let slotSequence = slot.sequence.load()
            guard slotSequence >= nextSequence else { break }

            if slotSequence > nextSequence {
                readSequence = slotSequence &- 1
                nextSequence = slotSequence
                continue
            }

            let trackID = slot.trackID
            let packet = slot.packet
            readSequence = nextSequence
            consume(trackID, packet)
            nextSequence = nextSequence &+ 1
        }
    }

    private func index(for sequence: Int32) -> Int {
        Int((sequence &- 1) % capacity)
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
        var capturedPCMChunks: [AudioInputCapturedPCM] = []
        var completedLoopPCM: AudioInputCapturedPCM?
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
            state.capturedPCMChunks.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.capturedFrameCount = 0
        }
    }

    func cancelCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.capturedPCMChunks.removeAll(keepingCapacity: true)
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
            state.completedLoopPCM = Self.concatenate(state.capturedPCMChunks)
            state.streamedWaveformBuckets = []
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.capturedPCMChunks.removeAll(keepingCapacity: true)
            state.capturedFrameCount = 0
        }
    }

    func replaceCompletedLoop(trackID: UUID, waveformBuckets: [Float]) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.capturedPCMChunks.removeAll(keepingCapacity: true)
            state.streamedWaveformBuckets = []
            state.completedWaveformBuckets = waveformBuckets.map(Self.clampedBucket)
            state.completedLoopPCM = nil
            state.capturedFrameCount = 0
            state.completedFrameCount = waveformBuckets.count
        }
    }

    func process(summary: AudioInputCaptureBufferSummary, trackID: UUID) -> AudioInputCaptureSnapshot {
        process(packet: AudioInputCaptureBufferPacket(summary: summary, capturedPCM: nil), trackID: trackID)
    }

    func process(packet: AudioInputCaptureBufferPacket, trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            let summary = packet.summary
            state.liveLevel = summary.liveLevel
            if state.isRecording, summary.hasFrames {
                state.capturedMagnitudes.append(summary.monoPeak)
                if let capturedPCM = packet.capturedPCM {
                    state.capturedPCMChunks.append(capturedPCM)
                }
                state.capturedFrameCount += summary.frameCount
                state.streamedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            }
        }
    }

    func isRecording(trackID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return states[trackID]?.isRecording == true
    }

    func completedLoopPlaybackBuffer(trackID: UUID) -> AVAudioPCMBuffer? {
        lock.lock()
        let pcm = states[trackID]?.completedLoopPCM
        lock.unlock()
        return pcm.flatMap(Self.makeBuffer)
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

    static func copyPCMForPlayback(from buffer: AVAudioPCMBuffer) -> AudioInputCapturedPCM? {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0,
              channelCount > 0,
              let sourceChannels = buffer.floatChannelData
        else {
            return nil
        }

        var copiedChannels: [[Float]] = []
        copiedChannels.reserveCapacity(channelCount)
        for channel in 0..<channelCount {
            copiedChannels.append(Array(UnsafeBufferPointer(start: sourceChannels[channel], count: frameCount)))
        }
        return AudioInputCapturedPCM(sampleRate: buffer.format.sampleRate, channels: copiedChannels)
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

    private static func concatenate(_ chunks: [AudioInputCapturedPCM]) -> AudioInputCapturedPCM? {
        guard let first = chunks.first,
              first.frameCount > 0,
              first.channelCount > 0
        else {
            return nil
        }

        let sampleRate = first.sampleRate
        let channelCount = first.channelCount
        var output = Array(repeating: [Float](), count: channelCount)
        for chunk in chunks
            where chunk.sampleRate == sampleRate && chunk.channelCount == channelCount
        {
            for channel in 0..<channelCount {
                output[channel].append(contentsOf: chunk.channels[channel])
            }
        }

        return AudioInputCapturedPCM(sampleRate: sampleRate, channels: output)
    }

    private static func makeBuffer(from pcm: AudioInputCapturedPCM) -> AVAudioPCMBuffer? {
        guard pcm.frameCount > 0,
              pcm.channelCount > 0,
              let format = AVAudioFormat(
                standardFormatWithSampleRate: pcm.sampleRate,
                channels: AVAudioChannelCount(pcm.channelCount)
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(pcm.frameCount)
              )
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(pcm.frameCount)
        guard let destinationChannels = buffer.floatChannelData else {
            return nil
        }
        for channel in 0..<pcm.channelCount {
            for frame in 0..<pcm.frameCount {
                destinationChannels[channel][frame] = pcm.channels[channel][frame]
            }
        }
        return buffer
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
