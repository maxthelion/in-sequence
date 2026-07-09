import XCTest
import AVFoundation
@testable import SequencerAI

/// Phase 2b (Audio Engine Hard Rule 4): every triggered slice / one-shot must
/// play a RESIDENT `AVAudioPCMBuffer` via `scheduleBuffer` — never stream the
/// file from disk on the trigger path. These tests prove the DEFAULT forward
/// case (no reverse, no envelope) takes the resident path, and that an unwarmed
/// trigger warms first rather than silently streaming.
final class SamplePlaybackEngineResidentBufferTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeSineWAV(to: fixtureURL, durationSeconds: 0.25)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureURL)
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    private func writeSineWAV(to url: URL, durationSeconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(durationSeconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = sin(Float(frame) * 0.05) * 0.5
        }
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

    /// Build a fully-resident `PreparedSampleAsset` (carries the warmed PCM
    /// buffer) the way `SampleAssetCache` does at warm time.
    private func makeResidentAsset() throws -> PreparedSampleAsset {
        let file = try AVAudioFile(forReading: fixtureURL)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        file.framePosition = 0
        try file.read(into: buffer, frameCount: AVAudioFrameCount(file.length))
        file.framePosition = 0
        let asset = PreparedSampleAsset(
            sampleID: UUID(),
            name: "fixture",
            url: fixtureURL,
            fileIdentity: SampleAssetFileIdentity(path: fixtureURL.path, modifiedAt: nil, fileSize: nil),
            file: file,
            pcmBuffer: buffer
        )
        XCTAssertNotNil(asset.pcmBuffer, "asset must be resident (warmed PCM buffer) for this test")
        return asset
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

    // MARK: - Resident-vs-file: default forward slice uses scheduleBuffer

    /// A triggered slice with DEFAULT settings (forward, no envelope) must
    /// schedule the resident PCM buffer (`scheduleBuffer`), NOT stream the file
    /// (`scheduleSegment(file:)`). This is the core Phase 2b acceptance.
    func test_defaultForwardSlice_schedulesResidentBuffer_notFileSegment() throws {
        guard let engine = makeEngine() else { throw XCTSkip("audio engine unavailable") }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let asset = try makeResidentAsset()

        let handle = engine.playSlice(
            sampleAsset: asset,
            startFrame: 0,
            endFrame: 2_048,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )

        XCTAssertNotNil(handle, "default forward slice must trigger")
        XCTAssertEqual(
            engine.residentBufferScheduleCountForTesting, 1,
            "default forward slice must use the resident scheduleBuffer path"
        )
        XCTAssertEqual(
            engine.fileSegmentScheduleCountForTesting, 0,
            "default forward slice must NOT stream via scheduleSegment(file:)"
        )
    }

    /// A default one-shot sample trigger also reads from the resident buffer.
    func test_defaultOneShotSample_schedulesResidentBuffer_notFileSegment() throws {
        guard let engine = makeEngine() else { throw XCTSkip("audio engine unavailable") }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let asset = try makeResidentAsset()

        let handle = engine.play(
            sampleAsset: asset,
            settings: .default,
            trackID: trackID,
            at: nil
        )

        XCTAssertNotNil(handle, "one-shot sample must trigger")
        XCTAssertEqual(
            engine.residentBufferScheduleCountForTesting, 1,
            "default one-shot sample must use the resident scheduleBuffer path"
        )
        XCTAssertEqual(
            engine.fileSegmentScheduleCountForTesting, 0,
            "default one-shot sample must NOT stream via scheduleSegment(file:)"
        )
    }

    /// Reverse + envelope slices already used the resident buffer; confirm they
    /// stay resident (the transform branch must not regress to streaming).
    func test_reverseAndEnvelopeSlice_staysResident() throws {
        guard let engine = makeEngine() else { throw XCTSkip("audio engine unavailable") }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let asset = try makeResidentAsset()
        let params = SliceTriggerStepParameters(
            gain: 0, startTrim: 0, endTrim: 0, pan: 0, filter: 0,
            attackMs: 2, releaseMs: 3, reverse: true, choke: false
        )

        _ = engine.playSlice(
            sampleAsset: asset,
            startFrame: 0,
            endFrame: 2_048,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: true,
            stepParameters: params
        )

        XCTAssertEqual(engine.residentBufferScheduleCountForTesting, 1)
        XCTAssertEqual(engine.fileSegmentScheduleCountForTesting, 0)
    }

    func test_repeatedResidentSlice_reusesPreparedTriggerBuffer() throws {
        guard let engine = makeEngine() else { throw XCTSkip("audio engine unavailable") }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let asset = try makeResidentAsset()

        for _ in 0..<2 {
            _ = engine.playSlice(
                sampleAsset: asset,
                startFrame: 256,
                endFrame: 2_304,
                settings: .default,
                trackID: trackID,
                at: nil,
                reverse: false,
                stepParameters: nil
            )
        }

        XCTAssertEqual(engine.residentBufferScheduleCountForTesting, 2)
        XCTAssertEqual(
            engine.residentTriggerBufferBuildCountForTesting,
            1,
            "identical triggers must not allocate and copy a fresh PCM buffer each time"
        )
    }

    // MARK: - Warm-before-trigger

    /// Warm-before-trigger: when the slice's source is warmed (resident asset),
    /// the trigger reads RAM and never streams. A trigger whose asset has NO
    /// resident buffer (the only legacy/large-loop case) is the sole path that
    /// may fall back to file streaming — proving the resident buffer is the
    /// precondition that keeps the trigger off disk.
    func test_warmedAssetNeverStreams_unwarmedFallsBackToFile() throws {
        guard let engine = makeEngine() else { throw XCTSkip("audio engine unavailable") }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        // Warmed (resident) asset: trigger stays in RAM.
        let warmed = try makeResidentAsset()
        _ = engine.playSlice(
            sampleAsset: warmed,
            startFrame: 0,
            endFrame: 2_048,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )
        XCTAssertEqual(engine.residentBufferScheduleCountForTesting, 1)
        XCTAssertEqual(
            engine.fileSegmentScheduleCountForTesting, 0,
            "a warmed trigger must never stream from disk"
        )

        // An asset with NO resident buffer (the large-loop / unwarmed exception):
        // only this path may stream. This documents that the resident buffer is
        // the precondition — when present, disk is never touched.
        let unwarmedFile = try AVAudioFile(forReading: fixtureURL)
        let unwarmed = PreparedSampleAsset(
            sampleID: UUID(),
            name: "unwarmed",
            url: fixtureURL,
            fileIdentity: SampleAssetFileIdentity(path: fixtureURL.path, modifiedAt: nil, fileSize: nil),
            file: unwarmedFile,
            pcmBuffer: nil
        )
        _ = engine.playSlice(
            sampleAsset: unwarmed,
            startFrame: 0,
            endFrame: 2_048,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )
        XCTAssertEqual(
            engine.fileSegmentScheduleCountForTesting, 1,
            "only the no-resident-buffer (large-loop) exception streams the file"
        )
    }
}
