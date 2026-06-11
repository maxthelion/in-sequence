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

struct AudioInputCapturePlan: Equatable, Sendable {
    var sampleRate: Double
    var channelCount: Int
    var maximumFrameCount: Int
}

struct AudioInputCaptureBufferPacket: Equatable, Sendable {
    var summary: AudioInputCaptureBufferSummary
    var captureWriterID: UUID?
    var copiedFrameCount: Int

    init(
        summary: AudioInputCaptureBufferSummary,
        captureWriterID: UUID? = nil,
        copiedFrameCount: Int = 0
    ) {
        self.summary = summary
        self.captureWriterID = captureWriterID
        self.copiedFrameCount = copiedFrameCount
    }
}

struct AudioInputCapturePCMCopyReceipt: Equatable, Sendable {
    var writerID: UUID
    var frameCount: Int
}

final class AudioInputCapturePCMWriter {
    let captureID = UUID()
    let trackID: UUID
    let sampleRate: Double
    let channelCount: Int
    let maximumFrameCount: Int
    private let capturedFrameCount = AtomicInt32(0)
    private let isActive = AtomicInt32(0)
    private let inFlightCopies = AtomicInt32(0)
    private var channels: [[Float]]

    init?(trackID: UUID, plan: AudioInputCapturePlan) {
        guard plan.sampleRate > 0,
              plan.channelCount > 0,
              plan.maximumFrameCount > 0
        else {
            return nil
        }

        self.trackID = trackID
        self.sampleRate = plan.sampleRate
        self.channelCount = plan.channelCount
        self.maximumFrameCount = plan.maximumFrameCount
        self.channels = (0..<plan.channelCount).map { _ in
            Array(repeating: 0, count: plan.maximumFrameCount)
        }
    }

    func copy(trackID: UUID, from buffer: AVAudioPCMBuffer) -> AudioInputCapturePCMCopyReceipt? {
        guard self.trackID == trackID,
              isActive.load() == 1
        else {
            return nil
        }

        inFlightCopies.increment()
        defer { inFlightCopies.decrement() }

        guard isActive.load() == 1,
              buffer.format.sampleRate == sampleRate,
              Int(buffer.format.channelCount) == channelCount,
              let sourceChannels = buffer.floatChannelData
        else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0,
              let destination = reserveDestinationRange(frameCount: frameCount)
        else {
            return nil
        }

        for channel in 0..<channelCount {
            for frame in 0..<destination.count {
                channels[channel][destination.start + frame] = sourceChannels[channel][frame]
            }
        }
        return AudioInputCapturePCMCopyReceipt(writerID: captureID, frameCount: destination.count)
    }

    func activate() {
        isActive.store(1)
    }

    func deactivate() {
        isActive.store(0)
    }

    func materializeCapturedPCM(frameCountLimit: Int? = nil) -> AudioInputCapturedPCM? {
        deactivate()
        waitForInFlightCopies()

        let copiedFrameCount = Int(capturedFrameCount.load())
        let frameCount = min(copiedFrameCount, max(0, frameCountLimit ?? copiedFrameCount))
        guard frameCount > 0 else { return nil }

        var copiedChannels: [[Float]] = []
        copiedChannels.reserveCapacity(channelCount)
        for channel in 0..<channelCount {
            copiedChannels.append(Array(channels[channel][0..<frameCount]))
        }
        return AudioInputCapturedPCM(sampleRate: sampleRate, channels: copiedChannels)
    }

    private func reserveDestinationRange(frameCount: Int) -> (start: Int, count: Int)? {
        while true {
            let currentFrameCount = capturedFrameCount.load()
            let availableFrameCount = Int32(maximumFrameCount) - currentFrameCount
            guard availableFrameCount > 0 else { return nil }

            let framesToCopy = min(Int32(frameCount), availableFrameCount)
            let nextFrameCount = currentFrameCount + framesToCopy
            if capturedFrameCount.compareAndSwap(expected: currentFrameCount, desired: nextFrameCount) {
                return (Int(currentFrameCount), Int(framesToCopy))
            }
        }
    }

    private func waitForInFlightCopies() {
        while inFlightCopies.load() > 0 {
            Thread.sleep(forTimeInterval: 0)
        }
    }
}

final class AudioInputCapturePCMWriterSlot {
    private let pointerBits = AtomicInt64(0)
    private let inFlightReaders = AtomicInt32(0)
    private var retainedWriter: AudioInputCapturePCMWriter?

    func install(_ writer: AudioInputCapturePCMWriter?) {
        pointerBits.store(Self.pointerBits(for: writer))
        waitForInFlightReaders()
        retainedWriter = writer
    }

    func copy(trackID: UUID, from buffer: AVAudioPCMBuffer) -> AudioInputCapturePCMCopyReceipt? {
        inFlightReaders.increment()
        defer { inFlightReaders.decrement() }

        guard let writer = writer() else { return nil }
        return writer.copy(trackID: trackID, from: buffer)
    }

    private func writer() -> AudioInputCapturePCMWriter? {
        let bits = pointerBits.load()
        guard bits != 0,
              let rawPointer = UnsafeRawPointer(bitPattern: Int(bits))
        else {
            return nil
        }

        return Unmanaged<AudioInputCapturePCMWriter>
            .fromOpaque(rawPointer)
            .takeUnretainedValue()
    }

    private func waitForInFlightReaders() {
        while inFlightReaders.load() > 0 {
            Thread.sleep(forTimeInterval: 0)
        }
    }

    private static func pointerBits(for writer: AudioInputCapturePCMWriter?) -> Int64 {
        guard let writer else { return 0 }
        return Int64(Int(bitPattern: Unmanaged.passUnretained(writer).toOpaque()))
    }
}

final class AudioInputCaptureSummaryRing {
    private final class Slot {
        let sequence = AtomicInt32(0)
        var trackID = UUID()
        var packet = AudioInputCaptureBufferPacket(
            summary: AudioInputCaptureBufferSummary(liveLevel: .silent, monoPeak: 0, frameCount: 0)
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

    func write(trackID: UUID, packet: AudioInputCaptureBufferPacket) {
        let sequence = writeSequence.increment()
        let slot = slots[index(for: sequence)]
        // Two-phase seqlock write: publish a sentinel (the negated sequence)
        // BEFORE touching the payload. Without it, a lapping writer mid
        // payload-write leaves the slot's previous (valid) sequence visible,
        // so a reader's post-copy re-check passes on a torn copy (R3).
        slot.sequence.store(0 &- sequence)
        slot.trackID = trackID
        slot.packet = packet
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
            // Seqlock re-check: a writer may have lapped this slot while we
            // copied trackID/packet. The lapping writer publishes a negative
            // sentinel BEFORE its payload write (see `write`), so a torn
            // copy can never re-check clean. On mismatch drop the copy and
            // loop — the sentinel breaks out (retry next drain) and a
            // completed lap jumps the read cursor forward.
            guard slot.sequence.load() == nextSequence else {
                continue
            }
            readSequence = nextSequence
            consume(trackID, packet)
            nextSequence = nextSequence &+ 1
        }
    }

    private func index(for sequence: Int32) -> Int {
        Int((sequence &- 1) % capacity)
    }

    // MARK: - Test hooks (seqlock contract)

    /// Performs the first phase of a write (sentinel + payload) WITHOUT
    /// publishing the final sequence — models a writer paused mid-write so
    /// tests can pin that readers never consume a torn slot. Returns the
    /// claimed sequence for `completeTornWriteForTesting`.
    @discardableResult
    func beginTornWriteForTesting(trackID: UUID, packet: AudioInputCaptureBufferPacket) -> Int32 {
        let sequence = writeSequence.increment()
        let slot = slots[index(for: sequence)]
        slot.sequence.store(0 &- sequence)
        slot.trackID = trackID
        slot.packet = packet
        return sequence
    }

    func completeTornWriteForTesting(sequence: Int32) {
        slots[index(for: sequence)].sequence.store(sequence)
    }

    func slotSequenceForTesting(claimedSequence sequence: Int32) -> Int32 {
        slots[index(for: sequence)].sequence.load()
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
        var pcmWriter: AudioInputCapturePCMWriter?
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
        for (trackID, state) in states where !trackIDs.contains(trackID) {
            state.pcmWriter?.deactivate()
        }
        states = states.filter { trackIDs.contains($0.key) }
        lock.unlock()
    }

    func prepareCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.recordingProgress = 0
            state.streamedWaveformBuckets = []
        }
    }

    func beginCapture(trackID: UUID, plan: AudioInputCapturePlan? = nil) -> AudioInputCaptureSnapshot {
        beginCapture(
            trackID: trackID,
            writer: plan.flatMap { AudioInputCapturePCMWriter(trackID: trackID, plan: $0) }
        )
    }

    func beginCapture(
        trackID: UUID,
        writer: AudioInputCapturePCMWriter?
    ) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.pcmWriter?.deactivate()
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.pcmWriter = writer
            state.streamedWaveformBuckets = []
            state.capturedFrameCount = 0
            writer?.activate()
            state.isRecording = true
        }
    }

    func cancelCapture(trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 0
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.pcmWriter?.deactivate()
            state.pcmWriter = nil
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
            state.completedLoopPCM = state.pcmWriter?.materializeCapturedPCM(frameCountLimit: state.capturedFrameCount)
            state.streamedWaveformBuckets = []
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.pcmWriter = nil
            state.capturedFrameCount = 0
        }
    }

    func replaceCompletedLoop(trackID: UUID, waveformBuckets: [Float]) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            state.isRecording = false
            state.recordingProgress = 1
            state.capturedMagnitudes.removeAll(keepingCapacity: true)
            state.pcmWriter?.deactivate()
            state.pcmWriter = nil
            state.streamedWaveformBuckets = []
            state.completedWaveformBuckets = waveformBuckets.map(Self.clampedBucket)
            state.completedLoopPCM = nil
            state.capturedFrameCount = 0
            state.completedFrameCount = waveformBuckets.count
        }
    }

    func process(summary: AudioInputCaptureBufferSummary, trackID: UUID) -> AudioInputCaptureSnapshot {
        process(packet: AudioInputCaptureBufferPacket(summary: summary), trackID: trackID)
    }

    func process(packet: AudioInputCaptureBufferPacket, trackID: UUID) -> AudioInputCaptureSnapshot {
        withState(trackID: trackID) { state in
            let summary = packet.summary
            state.liveLevel = summary.liveLevel
            let copiedFrameCount = max(0, packet.copiedFrameCount)
            let matchesActiveWriter = state.pcmWriter?.captureID == packet.captureWriterID
            if state.isRecording, summary.hasFrames, matchesActiveWriter, copiedFrameCount > 0 {
                state.capturedMagnitudes.append(summary.monoPeak)
                state.capturedFrameCount += min(summary.frameCount, copiedFrameCount)
                state.streamedWaveformBuckets = Self.downsample(state.capturedMagnitudes, bucketCount: bucketCount)
            }
        }
    }

    func pcmWriterForActiveCapture(trackID: UUID) -> AudioInputCapturePCMWriter? {
        lock.lock()
        let pcmWriter = states[trackID]?.isRecording == true
            ? states[trackID]?.pcmWriter
            : nil
        lock.unlock()
        return pcmWriter
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

    /// The raw PCM of the last completed capture, if it is still resident.
    /// Value-typed (COW), so callers can hand it to a background writer
    /// without copying or retaining store internals.
    func completedLoopPCM(trackID: UUID) -> AudioInputCapturedPCM? {
        lock.lock()
        let pcm = states[trackID]?.completedLoopPCM
        lock.unlock()
        return pcm
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
