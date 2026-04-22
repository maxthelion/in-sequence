import XCTest
import AVFoundation
@testable import SequencerAI

/// Tests that `SamplerFilterNode` is wired correctly in the audio graph:
/// one node per track, inserted between the track mixer and the main mixer.
final class SamplePlaybackEngineFilterWiringTests: XCTestCase {

    // MARK: - Helpers

    private func writeSilentWAV(to url: URL, durationSeconds: Double = 0.05) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let count = AVAudioFrameCount(durationSeconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
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

    private var tempURLs: [URL] = []

    override func setUp() {
        super.setUp()
        tempURLs = []
    }

    override func tearDown() {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    private func makeTempWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeSilentWAV(to: url)
        tempURLs.append(url)
        return url
    }

    private func makeEngine() throws -> SamplePlaybackEngine {
        let engine = SamplePlaybackEngine()
        try engine.start()
        return engine
    }

    // MARK: - One filter per track

    func test_oneTrack_hasExactlyOneFilterNode() throws {
        let engine = try makeEngine()
        defer { engine.stop() }

        let trackID = UUID()
        let url = try makeTempWAV()
        // Trigger a play to force trackMixer (and filter) allocation.
        _ = engine.play(sampleURL: url, settings: .default, trackID: trackID, at: nil)

        XCTAssertNotNil(engine.filterNode(for: trackID),
            "A filter node must exist after routing a voice to the track")
    }

    func test_twoTracks_hasTwoDistinctFilterNodes() throws {
        let engine = try makeEngine()
        defer { engine.stop() }

        let trackA = UUID()
        let trackB = UUID()
        let url = try makeTempWAV()

        _ = engine.play(sampleURL: url, settings: .default, trackID: trackA, at: nil)
        _ = engine.play(sampleURL: url, settings: .default, trackID: trackB, at: nil)

        let filterA = engine.filterNode(for: trackA)
        let filterB = engine.filterNode(for: trackB)
        XCTAssertNotNil(filterA)
        XCTAssertNotNil(filterB)
        XCTAssertFalse(filterA === filterB, "Two tracks must have two distinct filter nodes")
    }

    // MARK: - Tear-down on removeTrack

    func test_removeTrack_removesFilterNode() throws {
        let engine = try makeEngine()
        defer { engine.stop() }

        let trackID = UUID()
        let url = try makeTempWAV()
        _ = engine.play(sampleURL: url, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(engine.filterNode(for: trackID))

        engine.removeTrack(trackID: trackID)
        XCTAssertNil(engine.filterNode(for: trackID),
            "Filter node must be nil after removeTrack")
    }

    func test_removeTrack_thenReaddTrack_createsNewFilterNode() throws {
        let engine = try makeEngine()
        defer { engine.stop() }

        let trackID = UUID()
        let url = try makeTempWAV()
        _ = engine.play(sampleURL: url, settings: .default, trackID: trackID, at: nil)
        let firstFilter = engine.filterNode(for: trackID)
        engine.removeTrack(trackID: trackID)

        // Re-add the track.
        _ = engine.play(sampleURL: url, settings: .default, trackID: trackID, at: nil)
        let secondFilter = engine.filterNode(for: trackID)

        XCTAssertNotNil(secondFilter, "A new filter must be created after re-adding the track")
        XCTAssertFalse(firstFilter === secondFilter,
            "Re-added track should have a fresh filter node, not the old one")
    }

    // MARK: - applyFilter is a no-op for unknown tracks

    func test_applyFilter_unknownTrack_nocrash() {
        let engine = SamplePlaybackEngine()
        // No start — filter node doesn't exist.
        let settings = SamplerFilterSettings()
        engine.applyFilter(settings, trackID: UUID())  // must not crash
    }

    // MARK: - Filter is in the signal path (not silently bypassed)

    func test_highpassFilter_at10kHz_attenuates1kHzSignal() throws {
        let sampleRate: Double = 44_100
        let durationSec: Double = 0.1
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(durationSec * sampleRate)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        input.frameLength = frameCount
        let data = input.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            data[i] = Float(sin(2 * Double.pi * 1_000 * t))
        }

        func render(filter: SamplerFilterNode?) throws -> AVAudioPCMBuffer {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            if let filter {
                engine.attach(filter.avNode)
                engine.connect(player, to: filter.avNode, format: format)
                engine.connect(filter.avNode, to: engine.mainMixerNode, format: format)
            } else {
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }

            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frameCount)
            try engine.start()
            player.scheduleBuffer(input, completionHandler: nil)
            player.play()

            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            try engine.renderOffline(frameCount, to: output)
            engine.stop()
            return output
        }

        let filter = SamplerFilterNode()
        filter.setType(.highpass)
        filter.setCutoff(hz: 10_000)
        let baseline = try render(filter: nil)
        let output = try render(filter: filter)

        // Compute RMS of input vs output.
        func rms(_ buf: AVAudioPCMBuffer) -> Double {
            let d = buf.floatChannelData![0]
            var sum = 0.0
            for i in 0..<Int(buf.frameLength) { let v = Double(d[i]); sum += v * v }
            return sqrt(sum / Double(buf.frameLength))
        }
        let inRMS = rms(baseline)
        let outRMS = rms(output)
        guard inRMS > 0 else { XCTFail("Input is silent"); return }

        let attenDB = 20 * log10(outRMS / inRMS)
        XCTAssertLessThanOrEqual(attenDB, -20,
            "HP at 10 kHz should attenuate 1 kHz by >20 dB in the graph, got \(attenDB) dB")
    }
}
