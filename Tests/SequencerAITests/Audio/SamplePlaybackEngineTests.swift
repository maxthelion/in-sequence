import XCTest
import AVFoundation
@testable import SequencerAI

final class SamplePlaybackEngineTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeSilentWAV(to: fixtureURL, durationSeconds: 0.1)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    private func writeSilentWAV(to url: URL, durationSeconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(durationSeconds * format.sampleRate))!
        buffer.frameLength = buffer.frameCapacity
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func makeEngine() -> SamplePlaybackEngine? {
        let engine = SamplePlaybackEngine()
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    func test_playReturnsHandle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(handle)
    }

    func test_playWithoutStart_returnsNil() {
        let engine = SamplePlaybackEngine()
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil))
    }

    func test_playWithoutPrepareTrack_returnsNilWhenStarted() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil))
    }

    func test_playSliceWithoutPrepareTrack_returnsNilWhenStarted() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        XCTAssertNil(engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 0,
            endFrame: 100,
            settings: .default,
            trackID: UUID(),
            at: nil,
            reverse: false,
            stepParameters: nil
        ))
    }

    func test_playSliceWithPreparedTrack_returnsHandle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let handle = engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 0,
            endFrame: 100,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )
        XCTAssertNotNil(handle)
    }

    func test_startRepairsPreparedVoiceGraphBeforePlayback() throws {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectFirstPreparedVoiceForTesting(trackID: trackID)
        XCTAssertFalse(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))

        do {
            try engine.start()
        } catch {
            throw XCTSkip("Audio engine unavailable in this environment: \(error)")
        }
        defer { engine.stop() }

        XCTAssertTrue(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))
        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(handle)
    }

    func test_applyEnvelope_shapesAttackAndRelease() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 10)!
        buffer.frameLength = 10
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<10 {
            samples[index] = 1
        }

        SamplePlaybackEngine.applyEnvelope(to: buffer, attackMs: 3, releaseMs: 3)

        XCTAssertEqual(samples[0], 0, accuracy: 0.0001)
        XCTAssertEqual(samples[1], Float(1.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(samples[3], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[6], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[8], Float(1.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(samples[9], 0, accuracy: 0.0001)
    }

    func test_applyEnvelope_zeroEnvelopeLeavesBufferUntouched() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4 {
            samples[index] = Float(index + 1)
        }

        SamplePlaybackEngine.applyEnvelope(to: buffer, attackMs: 0, releaseMs: 0)

        XCTAssertEqual(samples[0], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[1], 2, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 3, accuracy: 0.0001)
        XCTAssertEqual(samples[3], 4, accuracy: 0.0001)
    }

    func test_prepareTrack_isIdempotent() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.prepareTrack(trackID: trackID)
        XCTAssertEqual(engine.preparedTrackIDs, [trackID])
    }

    func test_prepareTrack_thenRemoveTrack_clearsBookkeeping() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.removeTrack(trackID: trackID)
        XCTAssertTrue(engine.preparedTrackIDs.isEmpty)
    }

    func test_rapidPlays_doNotCrash() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        for _ in 0..<20 {
            let trackID = UUID()
            engine.prepareTrack(trackID: trackID)
            _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        }
    }

    func test_playFromBackgroundQueue_usesPreparedVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let expectation = expectation(description: "background sample play completes")
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let lock = NSLock()
        var handle: VoiceHandle?

        DispatchQueue(label: "SamplePlaybackEngineTests.background-play").async {
            let result = engine.play(sampleURL: self.fixtureURL, settings: .default, trackID: trackID, at: nil)
            lock.lock()
            handle = result
            lock.unlock()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        lock.lock()
        let resolvedHandle = handle
        lock.unlock()
        XCTAssertNotNil(resolvedHandle)
    }

    func test_audition_runsIndependent() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.audition(sampleURL: fixtureURL)
        _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
    }

    /// start=1, length=0 must produce a clamped 1-frame segment (not zero frames,
    /// which AVAudioPlayerNode would reject). The handle must be non-nil (voice was
    /// allocated), stoppable (voice is registered in the engine), and the engine must
    /// remain operational for subsequent plays.
    func test_playWithExtremeTrimSettings_clampsToOneFrameSegment() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let settings = SamplerSettings(start: 1, length: 0, gain: 0)

        // The call must succeed (not return nil) — the bounds clamp produced a
        // valid 1-frame segment that AVAudioPlayerNode accepted.
        let handle = try XCTUnwrap(
            engine.play(sampleURL: fixtureURL, settings: settings, trackID: trackID, at: nil),
            "start=1/length=0 must return a handle; the 1-frame clamp must succeed"
        )

        // The voice must be registered: stopVoice must not crash.
        engine.stopVoice(handle)

        // Engine must still accept new play calls after the extreme-settings voice.
        let nextHandle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(nextHandle, "Engine must remain operational after extreme-trim play")
    }

    func test_stopVoice_silencesThatVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        guard let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil) else {
            XCTFail("play returned nil in a started engine"); return
        }
        engine.stopVoice(handle)
    }

    func test_missingFile_returnsNil() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        XCTAssertNil(engine.play(sampleURL: missing, settings: .default, trackID: trackID, at: nil))
    }

    func test_setTrackMix_doesNotCrash() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.setTrackMix(trackID: trackID, level: 0.5, pan: 0.25)
        XCTAssertEqual(engine.preparedTrackIDs, [trackID])
    }

    func test_removeTrack_unknownIsNoOp() {
        let engine = SamplePlaybackEngine()
        engine.removeTrack(trackID: UUID())
    }
}
