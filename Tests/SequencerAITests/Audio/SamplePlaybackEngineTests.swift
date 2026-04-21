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
        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil)
        XCTAssertNotNil(handle)
    }

    func test_playWithoutStart_returnsNil() {
        let engine = SamplePlaybackEngine()
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil))
    }

    func test_rapidPlays_doNotCrash() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        for _ in 0..<20 {
            _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil)
        }
    }

    func test_audition_runsIndependent() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        engine.audition(sampleURL: fixtureURL)
        _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil)
    }

    func test_stopVoice_silencesThatVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        guard let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil) else {
            XCTFail("play returned nil in a started engine"); return
        }
        engine.stopVoice(handle)
    }

    func test_missingFile_returnsNil() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        XCTAssertNil(engine.play(sampleURL: missing, settings: .default, trackID: UUID(), at: nil))
    }

    func test_setTrackMix_doesNotCrash() {
        let engine = SamplePlaybackEngine()
        engine.setTrackMix(trackID: UUID(), level: 0.5, pan: 0.25)
    }

    func test_removeTrack_unknownIsNoOp() {
        let engine = SamplePlaybackEngine()
        engine.removeTrack(trackID: UUID())
    }
}
